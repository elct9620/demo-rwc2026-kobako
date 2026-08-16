# RubyLLM's 1.x default mixes the deprecated acts_as API into every model and
# announces it on every boot. This demo takes the association-based API, which
# is also what the persisted chat records are declared against, and starts
# quiet.
RubyLLM.configure do |config|
  config.use_new_acts_as = true
end
