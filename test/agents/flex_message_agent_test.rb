require "test_helper"

class FlexMessageAgentTest < ActiveSupport::TestCase
  # The vocabulary is one contract in two directions: the ceiling the sandbox
  # enforces, and the list the writer is given to aim at. A verb that lands in
  # one and not the other is the drift this catches.
  test "the writer is given every verb the sandbox lends" do
    instructions = FlexMessageAgent.render_prompt("instructions", chat: nil, inputs: {}, locals: {})

    LineFlex::VERBS.each { |verb| assert_includes instructions, verb.to_s }
  end
end
