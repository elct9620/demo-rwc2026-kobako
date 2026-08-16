# Writes the layout script from whatever the sender asked for. What comes back
# is untrusted like any other script: the vocabulary in the instructions
# describes the boundary so the writer can aim at it, and the sandbox is what
# holds it.
class FlexMessageAgent < RubyLLM::Agent
  # The model is named rather than looked up. It is newer than the registry
  # ruby_llm ships with, and naming the provider is what lets that lookup be
  # skipped — the row stored for it is minted from this rather than fetched.
  model RubyLLM.config.default_model, provider: :openai, assume_model_exists: true

  # Every message opens its own chat. Nothing ties one sender's messages
  # together, so what is kept is a record of exchanges rather than a
  # conversation.
  chat_model Chat

  # app/prompts/flex_message_agent/instructions.txt.erb
  instructions

  tools LayoutCheckTool

  # One field, because the whole answer is the script. Structured output is
  # what keeps prose, apologies and code fences out of what the sandbox is
  # handed.
  schema do
    string :script, description: "The layout script, ready to evaluate exactly as it stands."
  end
end
