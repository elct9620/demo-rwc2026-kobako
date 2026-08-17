# Answers one message the way the job would, but from a terminal and without
# LINE — printing the script that was written and whether the sandbox built a
# card from it. What it proves is the half no test can reach: that the gateway
# answers, the key is accepted, and the model of the day still writes something
# the sandbox will run. Worth doing before the talk and after a deploy.
#
#   set -a && source .env.production && set +a
#   bin/rails runner script/answer_once.rb
#
# It spends a real request. The credentials never reach the output — a failure
# is reported by class and message with both of them redacted.

QUESTION = ENV.fetch("QUESTION", "Ruby Taiwan 辦過哪些活動？")

def redact(text)
  [ ENV["OPENAI_API_KEY"], ENV["OPENAI_API_BASE"] ]
    .reject(&:blank?)
    .reduce(text.to_s) { |redacted, secret| redacted.gsub(secret, "[redacted]") }
end

begin
  chat = FlexMessageAgent.create!
  script = chat.ask(QUESTION).content.fetch("script")
  card = LineFlex.render(script)

  puts script
  puts
  puts "model:   #{chat.model_id}"
  puts "tools:   #{chat.messages.flat_map { |message| message.tool_calls.map(&:name) }.tally}"
  puts "card:    #{card.is_a?(LineFlex::Failure) ? "not built — #{card.reason}: #{card.message}" : "#{card[:type]} / #{card[:alt_text]}"}"
rescue StandardError => e
  abort "failed: #{e.class}: #{redact(e.message)}"
end
