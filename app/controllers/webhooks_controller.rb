# Where the sandbox's output leaves the app. LINE signs every delivery, so a
# request arriving without that signature is refused rather than parsed — a
# boundary that rejects, where the sandbox's contains.
class WebhooksController < ApplicationController
  # LINE has no session to carry a CSRF token; the signature is what
  # authenticates the request.
  skip_forgery_protection

  # The layout a generator will eventually write. Fixed for now, so the path it
  # travels is the only thing this exercises.
  SCRIPT = <<~MRUBY
    Flex.with do
      alt_text "Brown Cafe"
      bubble do
        body layout: :vertical, spacing: :md do
          text do
            span "Brown Cafe", weight: :bold, size: :xl
          end
          box layout: :baseline, spacing: :sm do
            text "Time", color: "#aaaaaa", size: :sm, flex: 1
            text "10:00 - 23:00", wrap: true, color: "#666666", size: :sm, flex: 5
          end
        end
        footer layout: :vertical do
          button style: :link, height: :sm do
            message "CALL", label: "CALL"
          end
        end
      end
    end
  MRUBY

  def create
    parser.parse(body: request.body.read, signature: request.headers["X-Line-Signature"])
          .each { |event| answer(event) }

    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end

  private

  def answer(event)
    return unless event.is_a?(Line::Bot::V2::Webhook::MessageEvent)
    return unless event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)

    reply(event.reply_token, message_for(LineFlex.render(SCRIPT)))
  end

  def message_for(result)
    return Line::Bot::V2::MessagingApi::FlexMessage.create(result) unless result.is_a?(LineFlex::Failure)

    # A script the sandbox stopped is the thing worth showing, so the reason
    # goes back to whoever triggered it rather than into a log nobody reads.
    Line::Bot::V2::MessagingApi::TextMessage.new(text: "The script did not finish: #{result.reason}")
  end

  def reply(token, message)
    _body, status, _headers = client.reply_message_with_http_info(
      reply_message_request: Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
        reply_token: token,
        messages: [ message ]
      )
    )

    # A refused reply arrives as a status code; the SDK does not raise for it.
    logger.error("LINE refused the reply with #{status}") unless status == 200
  end

  def client
    @client ||= Line::Bot::V2::MessagingApi::ApiClient.new(
      channel_access_token: ENV.fetch("LINE_CHANNEL_ACCESS_TOKEN")
    )
  end

  def parser
    @parser ||= Line::Bot::V2::WebhookParser.new(channel_secret: ENV.fetch("LINE_CHANNEL_SECRET"))
  end
end
