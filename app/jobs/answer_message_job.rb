# Where the answer is written, run and sent. Asking an LLM for the layout and
# running it takes as long as it takes, so it happens here rather than in the
# request LINE is waiting on.
#
# The job is never retried. A reply token is spent by a reply that reached
# someone, so running the whole thing again would answer with a token already
# used — and the writing it would repeat costs a minute nobody is waiting
# through twice.
#
# A reply LINE refused is the exception, because nothing was delivered and so
# nothing was spent. It is answered once more, with a sentence instead of a
# card, and that second answer is not retried either.
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

    refusal = reply(reply_token, message_for(result))
    refused(reply_token, refusal) if refusal
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

    @chat&.broadcast_failure(sentence) if sentence
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

  # A card the sandbox assembled can still break a rule that lives only at LINE,
  # and that is the one failure this path reaches with everything else already
  # done: the script is written down, the page is showing it as the answer, and
  # the sender has watched an animation resolve into nothing.
  #
  # The token is spent by a reply that was *delivered*, and a body LINE refused
  # on validation delivered nothing — so the same token still carries a sentence
  # saying so. LINE does not put that in writing, which is why the second reply
  # is sent for its own sake and its own refusal only reaches the log: the page
  # has been told either way.
  def refused(token, refusal)
    @chat&.broadcast_failure(refusal)
    reply(token, Line::Bot::V2::MessagingApi::TextMessage.new(text: refusal))
  end

  # Answers with the refusal LINE gave, or nil when the reply went out.
  def reply(token, message)
    body, status, _headers = client.reply_message_with_http_info(
      reply_message_request: Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
        reply_token: token,
        messages: [ message ]
      )
    )
    return if status == 200

    # A refused reply arrives as a status code; the SDK does not raise for it.
    sentence = "LINE would not show the card: #{refusal(body)}"
    logger.error("#{sentence} (#{status})")
    sentence
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
