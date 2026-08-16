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
  config.default_model = ENV.fetch("OPENAI_MODEL", "gpt-5.6-luna")

  # A reply token expires about a minute after the webhook, and the job holding
  # it is not retried. RubyLLM would rather wait five minutes and try three
  # times, which is a card that arrives after the only thing that could deliver
  # it is gone.
  config.request_timeout = 20
  config.max_retries = 1
end
