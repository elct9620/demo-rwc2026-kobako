require "test_helper"

class LineWebhookTest < ActionDispatch::IntegrationTest
  CHANNEL_SECRET = "channel-secret-for-tests"
  CHANNEL_ENV = {
    "LINE_CHANNEL_SECRET" => CHANNEL_SECRET,
    "LINE_CHANNEL_ACCESS_TOKEN" => "channel-access-token-for-tests"
  }.freeze
  REPLY_URL = "https://api.line.me/v2/bot/message/reply"
  LOADING_URL = "https://api.line.me/v2/bot/chat/loading/start"
  WRITER_URL = "https://api.openai.com/v1/chat/completions"
  USER_ID = "Udeadbeefdeadbeefdeadbeefdeadbeef"
  JSON_TYPE = { "Content-Type" => "application/json" }.freeze
  SCRIPT = <<~MRUBY
    Flex.with do
      alt_text "Brown Cafe"
      bubble do
        body layout: :vertical, spacing: :md do
          text "10:00 - 23:00", wrap: true, color: "#666666", size: :sm
        end
      end
    end
  MRUBY

  setup do
    @environment = ENV.to_h.slice(*CHANNEL_ENV.keys)
    ENV.update(CHANNEL_ENV)
    # Both are read once at boot, so a test puts them where the app kept them
    # rather than in the environment they were read from. The address is pinned
    # to OpenAI's own because that is what the stub below answers: a gateway
    # belongs to a deployment, and a machine that has one configured is not a
    # machine whose tests should fail.
    @writer_config = [ RubyLLM.config.openai_api_key, RubyLLM.config.openai_api_base ]
    RubyLLM.config.openai_api_key = "openai-api-key-for-tests"
    RubyLLM.config.openai_api_base = nil
    @writer = stub_request(:post, WRITER_URL).to_return(
      status: 200,
      body: written(SCRIPT),
      headers: JSON_TYPE
    )
    @reply = stub_request(:post, REPLY_URL).to_return(
      status: 200,
      body: { sentMessages: [ { id: "461230966842064897", quoteToken: "IStG5h1Tz7b..." } ] }.to_json,
      headers: JSON_TYPE
    )
    @loading = stub_request(:post, LOADING_URL).to_return(status: 202)
  end

  # The channel values live in the process, so this file leaves them as it
  # found them rather than for whatever runs next.
  teardown do
    CHANNEL_ENV.each_key { |key| ENV.delete(key) }
    ENV.update(@environment)
    RubyLLM.config.openai_api_key, RubyLLM.config.openai_api_base = @writer_config
  end

  # The whole of the wiring, walked once: the writer asks for entries, the app
  # runs the query against the table, and what comes back travels into the next
  # request. Asserting on that second request is what proves the card is
  # written from the community's own posts rather than from what a model
  # remembers.
  test "an answer is written from what the tool read out of the table" do
    meetup = entries(:august_meetup)
    stub_request(:post, WRITER_URL).to_return(
      { status: 200, body: asked_for(:search_entries, query: "小聚"), headers: JSON_TYPE },
      { status: 200, body: written(card_naming(meetup.title)), headers: JSON_TYPE }
    )

    deliver(text_event(text: "最近有什麼小聚"))

    assert_requested :post, WRITER_URL, times: 2
    assert_requested(:post, WRITER_URL) { |request| request.body.include?(meetup.title) }
    assert_requested(:post, REPLY_URL) do |request|
      JSON.parse(request.body)["messages"].first["altText"] == meetup.title
    end
  end

  test "a message is answered with the card the sandbox assembled" do
    deliver(text_event)

    assert_response :ok
    assert_requested @writer
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "flex" && message["altText"] == "Brown Cafe"
    end
  end

  # A gateway in front of the model words its own errors its own way, and
  # ruby_llm raises while parsing them rather than raising one of its own — a
  # failure in no shape this app can name. It still has to reach the sender.
  test "an error worded the gateway's own way is still answered" do
    stub_request(:post, WRITER_URL).to_return(
      status: 401,
      body: { success: false, error: [ { code: 2009, message: "Unauthorized" } ], name: "AiGatewayError" }.to_json,
      headers: JSON_TYPE
    )

    deliver(text_event)

    assert_response :ok
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "text" && message["text"].include?("could not be written")
    end
  end

  # The writer is an ordinary outside service. When it cannot answer, the
  # sender still gets something — a job that dies holding the reply token
  # leaves them watching an animation that never resolves.
  test "a layout that could not be written is still answered" do
    stub_request(:post, WRITER_URL).to_return(status: 500)

    deliver(text_event)

    assert_response :ok
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "text" && message["text"].include?("could not be written")
    end
  end

  test "the sender is shown a loading animation while the answer is prepared" do
    deliver(text_event)

    assert_requested(:post, LOADING_URL) do |request|
      JSON.parse(request.body)["chatId"] == USER_ID
    end
  end

  # A group names the member who spoke, not a chat the animation can be drawn
  # in, so the answer arrives without one rather than in someone's own chat.
  test "a message from a group is answered with no loading animation" do
    deliver(group_event)

    assert_requested @reply
    assert_not_requested @loading
  end

  test "a script the sandbox stopped is explained to whoever asked" do
    stopped = LineFlex::Failure.new(reason: :timeout, message: "guest exceeded its deadline")

    LineFlex.stub(:render, stopped) { deliver(text_event) }

    assert_response :ok
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "text" && message["text"].include?("timeout")
    end
  end

  test "a delivery signed with the wrong key is refused before anything is parsed" do
    deliver(text_event, signature: "not-the-signature")

    assert_response :bad_request
    assert_not_requested @reply
  end

  # Anything that is not LINE may leave the header off entirely, and a boundary
  # that rejects has to answer that the same way it answers a wrong one.
  test "a delivery carrying no signature at all is refused the same way" do
    deliver(text_event, signature: nil)

    assert_response :bad_request
    assert_not_requested @reply
  end

  private

  # The content type is what LINE sends, so a delivery here carries it too.
  # Passing nil leaves the header off, which is not the same as sending a
  # wrong one and is the reason both are stated above.
  #
  # The answer leaves from a job, so running whatever the delivery enqueued is
  # part of delivering it — without that, every assertion below would be about
  # a request that reached LINE only in the tests that expected it to.
  def deliver(body, signature: signature_for(body))
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["X-Line-Signature"] = signature if signature

    perform_enqueued_jobs { post "/webhook", params: body, headers: headers }
  end

  # An assistant turn that calls a tool instead of answering. What the writer
  # asks for is its own decision in production, so a test that wants the loop
  # walked has to make that decision for it.
  def asked_for(tool, **arguments)
    {
      id: "chatcmpl-for-tests",
      model: "gpt-5-mini",
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: nil,
            tool_calls: [
              {
                id: "call-for-tests",
                type: "function",
                function: { name: tool.to_s, arguments: arguments.to_json }
              }
            ]
          },
          finish_reason: "tool_calls"
        }
      ]
    }.to_json
  end

  def card_naming(title)
    <<~MRUBY
      Flex.with do
        alt_text "#{title}"
        bubble do
          body layout: :vertical do
            text "#{title}", wrap: true
          end
        end
      end
    MRUBY
  end

  # A schema is in force, so the fields come back as JSON inside the
  # assistant's message rather than as prose around it.
  def written(script)
    {
      id: "chatcmpl-for-tests",
      model: "gpt-5-mini",
      choices: [
        { index: 0, message: { role: "assistant", content: { script: script }.to_json }, finish_reason: "stop" }
      ]
    }.to_json
  end

  def signature_for(body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", CHANNEL_SECRET, body))
  end

  def group_event
    text_event(source: { type: "group", groupId: "Cdeadbeefdeadbeefdeadbeefdeadbeef", userId: USER_ID })
  end

  def text_event(source: { type: "user", userId: USER_ID }, text: "cafe")
    {
      destination: USER_ID,
      events: [
        {
          type: "message",
          mode: "active",
          timestamp: 1_700_000_000_000,
          source: source,
          webhookEventId: "01FZ74A0TDDPYRVKNK77XKC3ZR",
          deliveryContext: { isRedelivery: false },
          replyToken: "reply-token",
          message: {
            type: "text",
            id: "14353798921116",
            text: text,
            quoteToken: "q3Plxr4AgKd...4qtSf9scFUsdBdXQ"
          }
        }
      ]
    }.to_json
  end
end
