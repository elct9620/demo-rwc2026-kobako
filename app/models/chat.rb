class Chat < ApplicationRecord
  acts_as_chat

  # Each message LINE delivers opens a chat, so there is one question in it.
  def question
    messages.find_by(role: "user")&.content
  end

  # The block a card's script lives in. A replace swaps the whole element, so
  # the partial's root has to carry the id the broadcast aims at — naming it
  # here is what keeps those two the same id.
  def script_id
    ActionView::RecordIdentifier.dom_id(self, :script)
  end

  # What the block holds, rather than what is happening to it. A word about
  # the writing goes stale the moment a run stops without saying so, and
  # nothing here would ever come back to correct it — a card left calling
  # itself checked is worse than one that only ever claimed to hold a draft.
  # What did happen is said by the job, in the sentence the sender was given.
  def state
    answer ? "Answer" : "Draft"
  end

  def broadcast_card
    broadcast_prepend_to :chats
  end

  def broadcast_script
    broadcast_state(state)
  end

  # Sent where it happens rather than through a job. Every version replaces
  # the same block, and Solid Queue runs three threads — a broadcast that
  # arrives out of order would leave the card showing a version the writer has
  # already moved past.
  def broadcast_state(state)
    broadcast_replace_to :chats, target: script_id, partial: "chats/script",
                                 locals: { chat: self, state: state }
  end

  # The one version this chat is showing: the answer once it is settled, and
  # until then the draft it last ran through the sandbox. A card carries a
  # single script, so reloading the page and watching it arrive show the same
  # thing.
  def script
    answer || draft
  end

  # Structured output is not text, so it lands in +content_raw+ where the
  # column for prose stays empty. That is also what tells the settled answer
  # apart from the turns that only called a tool, which fill neither.
  def answer
    messages.where.not(content_raw: nil).last&.content_raw&.dig("script")
  end

  # What the writer last handed the sandbox to check. It is an argument to the
  # tool call rather than anything the model said, so this is the only place a
  # version that was rejected is written down.
  def draft
    ToolCall.where(message: messages, name: LayoutCheckTool.new.name).last&.arguments&.dig("script")
  end
end
