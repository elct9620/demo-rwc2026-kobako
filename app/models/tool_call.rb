class ToolCall < ApplicationRecord
  acts_as_tool_call

  # A check carries the version being checked, so this is where the writing
  # shows its work: a script the sandbox turned down never reaches a message,
  # and its only trace is the call that asked about it. What the writer looked
  # up stays off the card — the card is about the layout, not the material.
  after_create_commit -> { message.chat.broadcast_script }, if: -> { name == LayoutCheckTool.new.name }
end
