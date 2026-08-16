# Where the sandbox's output leaves the app. Writing the layout and running it
# takes as long as it takes, so it happens here rather than in the request LINE
# is waiting on.
#
# Nothing is retried. A reply token is spent once and expires about a minute
# after the webhook, so a second attempt would answer with a token LINE has
# already refused — a run that failed has nothing left to reply with.
class AnswerMessageJob < ApplicationJob
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

  # +text+ is what the message asked for, and it is what the generator will
  # write the script from. It travels with the token so that arrival needs no
  # second look at the webhook.
  def perform(reply_token:, text:)
    reply(reply_token, message_for(LineFlex.render(SCRIPT)))
  end

  private

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
end
