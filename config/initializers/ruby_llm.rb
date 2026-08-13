# RubyLLM's 1.x default mixes the deprecated acts_as API into every model and
# announces it on every boot. This demo persists no conversations, so it takes
# the association-based API and starts quiet.
RubyLLM.configure do |config|
  config.use_new_acts_as = true
end
