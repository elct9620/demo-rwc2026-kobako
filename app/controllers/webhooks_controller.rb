# Where a delivery from LINE arrives. LINE signs every delivery, so a request
# arriving without that signature is refused rather than parsed — a boundary
# that rejects, where the sandbox's contains.
#
# Answering is handed to a job, so the webhook is not held open while the
# layout is written and run.
class WebhooksController < ApplicationController
  # LINE has no session to carry a CSRF token; the signature is what
  # authenticates the request.
  skip_forgery_protection

  def create
    # The signature covers the bytes LINE posted, and #raw_post is the reading
    # that rewinds — #body hands back whatever position an earlier reader left.
    #
    # A caller that is not LINE may send no signature at all. #to_s makes that
    # an empty one, so it is refused by the same comparison as a wrong one
    # rather than raising on its way into the digest.
    parser.parse(body: request.raw_post, signature: request.headers["X-Line-Signature"].to_s)
          .each { |event| answer(event) }

    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end

  private

  def answer(event)
    return unless event.is_a?(Line::Bot::V2::Webhook::MessageEvent)
    return unless event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)

    AnswerMessageJob.perform_later(reply_token: event.reply_token, text: event.message.text)
  end

  def parser
    @parser ||= Line::Bot::V2::WebhookParser.new(channel_secret: ENV.fetch("LINE_CHANNEL_SECRET"))
  end
end
