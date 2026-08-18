class Message < ApplicationRecord
  acts_as_message

  # The question is what opens a card. Nothing before it is worth showing —
  # the brief the writer is handed is the same on every chat, and the chat
  # record itself does not say what was asked.
  after_create_commit -> { chat.broadcast_card }, if: -> { role == "user" }

  # The settled answer arrives as an update: the row is created empty and
  # filled once the model has finished. Structured output lands in
  # +content_raw+, which is what a turn that only called a tool leaves blank.
  after_update_commit -> { chat.broadcast_script }, if: -> { content_raw.present? }
end
