require "test_helper"

class LineWebhookTest < ActionDispatch::IntegrationTest
  CHANNEL_SECRET = "channel-secret-for-tests"
  REPLY_URL = "https://api.line.me/v2/bot/message/reply"

  setup do
    ENV["LINE_CHANNEL_SECRET"] = CHANNEL_SECRET
    ENV["LINE_CHANNEL_ACCESS_TOKEN"] = "channel-access-token-for-tests"
    @reply = stub_request(:post, REPLY_URL).to_return(
      status: 200,
      body: { sentMessages: [ { id: "461230966842064897", quoteToken: "IStG5h1Tz7b..." } ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  test "a message is answered with the card the sandbox assembled" do
    deliver(text_event)

    assert_response :ok
    assert_requested(:post, REPLY_URL) do |request|
      message = JSON.parse(request.body)["messages"].first
      message["type"] == "flex" && message["altText"] == "Brown Cafe"
    end
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

  test "an unsigned delivery is refused before anything is parsed" do
    deliver(text_event, signature: "not-the-signature")

    assert_response :bad_request
    assert_not_requested @reply
  end

  private

  # The content type is what LINE sends, so a delivery here carries it too.
  def deliver(body, signature: nil)
    post "/webhook",
         params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Line-Signature" => signature || signature_for(body)
         }
  end

  def signature_for(body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", CHANNEL_SECRET, body))
  end

  def text_event
    {
      destination: "Udeadbeefdeadbeefdeadbeefdeadbeef",
      events: [
        {
          type: "message",
          mode: "active",
          timestamp: 1_700_000_000_000,
          source: { type: "user", userId: "Udeadbeefdeadbeefdeadbeefdeadbeef" },
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
