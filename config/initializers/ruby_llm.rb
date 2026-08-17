# RubyLLM's 1.x default mixes the deprecated acts_as API into every model and
# announces it on every boot. This demo takes the association-based API, which
# is also what the persisted chat records are declared against, and starts
# quiet.
RubyLLM.configure do |config|
  config.use_new_acts_as = true

  # Absent here, the answer never comes and the sender is told so. Naming it at
  # boot instead would take the whole app down for a credential only one path
  # needs.
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)

  # A Cloudflare AI Gateway speaks OpenAI's own API, so it is the address that
  # changes and nothing else. The address carries an account and a gateway id,
  # which belong to whoever deploys this rather than to the code — unset, this
  # talks to OpenAI directly, which is what a laptop with a plain key wants.
  config.openai_api_base = ENV.fetch("OPENAI_API_BASE", nil)

  # The model is written down so the demo answers the same way twice, and
  # overridable so trying another one is not a commit.
  #
  # It sits a generation back because the writer needs tools and reasoning at
  # once, and from gpt-5.4 onwards that pair only travels on OpenAI's Responses
  # API — which ruby_llm does not speak yet.
  config.default_model = ENV.fetch("OPENAI_MODEL", "gpt-5-mini")

  # Sized for the writing rather than for the reply token. An answer is three
  # calls now — choose the tools, lay out what they returned, check it — and a
  # cap that fits the whole exchange into one of them cuts off the middle call,
  # which is the one that does the work. LINE says to reply as soon as possible
  # and that beyond a minute is not guaranteed; that is a limit to answer to
  # where the reply leaves, not one to enforce by refusing to finish thinking.
  config.request_timeout = 120

  # One retry, for a gateway having a moment. A second would only repeat a slow
  # call at its new length.
  config.max_retries = 1
end
