require "test_helper"

class LineWebhookTest < ActionDispatch::IntegrationTest
  CHANNEL_SECRET = "channel-secret-for-tests"
  CHANNEL_ENV = {
    "LINE_CHANNEL_SECRET" => CHANNEL_SECRET,
    "LINE_CHANNEL_ACCESS_TOKEN" => "channel-access-token-for-tests"
  }.freeze
  REPLY_URL = "https://api.line.me/v2/bot/message/reply"
  LOADING_URL = "https://api.line.me/v2/bot/chat/loading/start"
  USER_ID = "Udeadbeefdeadbeefdeadbeefdeadbeef"

  setup do
    @environment = ENV.to_h.slice(*CHANNEL_ENV.keys)
    ENV.update(CHANNEL_ENV)
    @reply = stub_request(:post, REPLY_URL).to_return(
      status: 200,
      body: { sentMessages: [ { id: "461230966842064897", quoteToken: "IStG5h1Tz7b..." } ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    @loading = stub_request(:post, LOADING_URL).to_return(status: 202)
  end

  # The channel values live in the process, so this file leaves them as it
  # found them rather than for whatever runs next.
  teardown do
    CHANNEL_ENV.each_key { |key| ENV.delete(key) }
    ENV.update(@environment)
  end

  test "a message is answered with the card the sandbox assembled" do
    deliver(text_event)

    assert_response :ok
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "flex" && message["altText"] == "Brown Cafe"
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

  def signature_for(body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", CHANNEL_SECRET, body))
  end

  def group_event
    text_event(source: { type: "group", groupId: "Cdeadbeefdeadbeefdeadbeefdeadbeef", userId: USER_ID })
  end

  def text_event(source: { type: "user", userId: USER_ID })
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
            text: "cafe",
            quoteToken: "q3Plxr4AgKd...4qtSf9scFUsdBdXQ"
          }
        }
      ]
    }.to_json
  end
end
