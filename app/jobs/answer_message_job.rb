# Where the answer is written, run and sent. Asking an LLM for the layout and
# running it takes as long as it takes, so it happens here rather than in the
# request LINE is waiting on.
#
# Nothing is retried. A reply token is spent once, so a second attempt would
# answer with a token LINE has already refused — a run that failed has nothing
# left to reply with.
class AnswerMessageJob < ApplicationJob
  # A reply token authorises one message to one person, and the text beside it
  # is what that person wrote. Active Job prints a job's arguments verbatim and
  # config.filter_parameters does not reach them, so these stay out of the log
  # entirely rather than travelling to wherever it is read.
  self.log_arguments = false

  # The most LINE accepts. Three calls to the writer and a sandbox run take
  # most of a minute between them, and the animation clears the moment the
  # reply arrives — so the only thing a smaller number buys is a stretch at the
  # end the sender spends watching nothing.
  LOADING_SECONDS = 60

  # +text+ is what the message asked for, and it is what the layout is written
  # from. It travels with the token so that arrival needs no second look at the
  # webhook.
  #
  # +chat_id+ is nil for a delivery with no one-on-one chat to draw in.
  def perform(reply_token:, text:, chat_id: nil)
    show_loading(chat_id)

    result = card_for(text)
    announce(result)

    reply(reply_token, message_for(result))
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
    @chat = FlexMessageAgent.create!
    LineFlex.render(@chat.ask(text).content.fetch("script"))
  rescue StandardError => e
    logger.error("The layout could not be written: #{e.class}: #{e.message}")
    :unwritten
  end

  # The page has followed every version the writer produced, and this is the
  # only way it hears that none of them became a card: a run that ends without
  # one writes nothing down, so the page would be left holding a draft and no
  # account of why it stopped being one. Whoever is watching is told what the
  # sender was told, in the same words.
  def announce(result)
    sentence = sentence_for(result)

    @chat&.broadcast_state(sentence) if sentence
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
  #
  # A card answers with nothing here, because there is no sentence to say
  # about one that worked.
  def sentence_for(result)
    case result
    when :unwritten
      "The layout could not be written."
    when LineFlex::Failure
      "The script did not finish: #{result.reason}"
    end
  end

  def message_for(result)
    sentence = sentence_for(result)
    return Line::Bot::V2::MessagingApi::FlexMessage.create(result) if sentence.nil?

    Line::Bot::V2::MessagingApi::TextMessage.new(text: sentence)
  end

  def reply(token, message)
    body, status, _headers = client.reply_message_with_http_info(
      reply_message_request: Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
        reply_token: token,
        messages: [ message ]
      )
    )

    # A refused reply arrives as a status code; the SDK does not raise for it.
    logger.error("LINE refused the reply with #{status} — #{refusal(body)}") unless status == 200
  end

  # LINE says which property it refused and why, and this is the only place
  # that ever hears it: a card the sandbox assembled can still break a rule
  # that lives only at LINE, and then nothing else on this path knows anything
  # happened. Without the detail, every refusal reads the same and the script
  # has to be dug out of the chat to find out which line was wrong.
  def refusal(body)
    return "no reason given" unless body.respond_to?(:message)

    faults = Array(body.details).map { |detail| "#{detail.property}: #{detail.message}" }
    [ body.message, *faults ].compact_blank.join(" | ")
  end

  def client
    @client ||= Line::Bot::V2::MessagingApi::ApiClient.new(
      channel_access_token: ENV.fetch("LINE_CHANNEL_ACCESS_TOKEN")
    )
  end
end
