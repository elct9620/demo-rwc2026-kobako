# Where the answer is written, run and sent. Asking an LLM for the layout and
# running it takes as long as it takes, so it happens here rather than in the
# request LINE is waiting on.
#
# Nothing is retried. A reply token is spent once and expires about a minute
# after the webhook, so a second attempt would answer with a token LINE has
# already refused — a run that failed has nothing left to reply with.
class AnswerMessageJob < ApplicationJob
  # A reply token authorises one message to one person, and the text beside it
  # is what that person wrote. Active Job prints a job's arguments verbatim and
  # config.filter_parameters does not reach them, so these stay out of the log
  # entirely rather than travelling to wherever it is read.
  self.log_arguments = false

  # Long enough to cover the writing, which is the part that takes seconds.
  # LINE accepts 5 to 60, the animation clears the moment the reply arrives,
  # and a wait it stops covering is one the sender spends watching nothing.
  LOADING_SECONDS = 20

  # +text+ is what the message asked for, and it is what the layout is written
  # from. It travels with the token so that arrival needs no second look at the
  # webhook.
  #
  # +chat_id+ is nil for a delivery with no one-on-one chat to draw in.
  def perform(reply_token:, text:, chat_id: nil)
    show_loading(chat_id)

    reply(reply_token, message_for(card_for(text)))
  end

  private

  # Everything outside this app happens in here, and every way it can go wrong
  # ends the same: the job is not retried, so an exception leaving this method
  # is a sender left watching an animation that never resolves. That is why the
  # rescue is as wide as it is — a missing key raises outside RubyLLM::Error,
  # and a gateway wording its errors differently than ruby_llm expects makes
  # ruby_llm raise while parsing the error itself. The log keeps the detail;
  # the chat gets a sentence.
  #
  # The script is untrusted the moment it comes back — nothing here reads it
  # before the sandbox does.
  def card_for(text)
    LineFlex.render(FlexMessageAgent.create!.ask(text).content.fetch("script"))
  rescue StandardError => e
    logger.error("The layout could not be written: #{e.class}: #{e.message}")
    :unwritten
  end

  # LINE's own answer to a reply that takes a moment. It is decoration on the
  # way to the card, so a refusal is not worth failing the answer over — and
  # the SDK hands one back as a status rather than raising it.
  def show_loading(chat_id)
    return if chat_id.nil?

    client.show_loading_animation(
      show_loading_animation_request: Line::Bot::V2::MessagingApi::ShowLoadingAnimationRequest.new(
        chat_id: chat_id,
        loading_seconds: LOADING_SECONDS
      )
    )
  end

  # Three outcomes, and the two that are not a card read differently on
  # purpose. A script the sandbox stopped is the point of the demo, so its
  # reason goes back to whoever triggered it. A layout that was never written
  # is an outside service having a bad day, and its detail belongs in the log.
  def message_for(result)
    case result
    when :unwritten
      Line::Bot::V2::MessagingApi::TextMessage.new(text: "The layout could not be written.")
    when LineFlex::Failure
      Line::Bot::V2::MessagingApi::TextMessage.new(text: "The script did not finish: #{result.reason}")
    else
      Line::Bot::V2::MessagingApi::FlexMessage.create(result)
    end
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
