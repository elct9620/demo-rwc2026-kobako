class Chat < ApplicationRecord
  acts_as_chat

  # Each message LINE delivers opens a chat, so there is one question in it.
  def question
    messages.find_by(role: "user")&.content
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
