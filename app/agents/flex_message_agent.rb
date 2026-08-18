# Writes the layout script from whatever the sender asked for. What comes back
# is untrusted like any other script: the vocabulary in the instructions
# describes the boundary so the writer can aim at it, and the sandbox is what
# holds it.
class FlexMessageAgent < RubyLLM::Agent
  # The model is named rather than looked up, because it comes from the
  # environment and may well be one the registry ruby_llm ships has never heard
  # of. Naming the provider is what lets that lookup be skipped.
  model RubyLLM.config.default_model, provider: :openai, assume_model_exists: true

  # Every message opens its own chat. Nothing ties one sender's messages
  # together, so what is kept is a record of exchanges rather than a
  # conversation.
  chat_model Chat

  # app/prompts/flex_message_agent/instructions.txt.erb
  instructions

  # In the order they are reached for: filter what the community actually
  # posted, then check the layout written from it.
  tools SearchEntriesTool, LayoutCheckTool

  # Wanting this alongside the tools is what pins the model to an older
  # generation; the initializer says why.
  thinking effort: "medium"

  # The script is the whole answer, and the field ahead of it is what has to be
  # settled before one can be written. Structured output is produced in the
  # order the fields are declared, so asking for the reasoning first is what
  # stops a card being laid out before the material it answers from has been
  # read. Fields are also what keep prose, apologies and code fences out of
  # what the sandbox is handed.
  schema do
    string :reasoning, description: "What the asker most likely wants, what the search returned, and why the card is arranged as it is. Written in English whatever language the question came in — the card is what is answered in the asker's, and this is read beside it rather than by them."
    string :script, description: "The layout script, ready to evaluate exactly as it stands."
  end
end
