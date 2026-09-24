class Message < ApplicationRecord
  acts_as_message

  # The question is what opens a card. Nothing before it is worth showing —
  # the brief the writer is handed is the same on every chat, and the chat
  # record itself does not say what was asked.
  after_create_commit -> { chat.broadcast_card }, if: -> { role == "user" }

  # Every writer turn arrives as an update: the row is created empty and filled
  # once the model has finished, in the same commit as the tool calls it made.
  # So this is where both a version sent to the sandbox and the settled answer
  # reach the page — a check carries the version being checked, and a script
  # the sandbox turned down never reaches a message, so the call that asked
  # about it is its only trace. What the writer looked up stays off the card —
  # the card is about the layout, not the material.
  after_update_commit -> { chat.broadcast_script }, if: -> { role == "assistant" && (content.present? || checked?) }

  private

  def checked?
    tool_calls.each_value.any? { |call| call.name == LayoutCheckTool.new.name }
  end
end
