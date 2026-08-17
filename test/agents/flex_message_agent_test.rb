require "test_helper"

class FlexMessageAgentTest < ActiveSupport::TestCase
  setup do
    @instructions = FlexMessageAgent.render_prompt("instructions", chat: nil, inputs: {}, locals: {})
  end

  # The vocabulary is one contract in two directions: the ceiling the sandbox
  # enforces, and the list the writer is given to aim at. A verb that lands in
  # one and not the other is the drift this catches.
  test "the writer is given every verb the sandbox lends" do
    LineFlex::VERBS.each { |verb| assert_includes @instructions, verb.to_s }
  end

  # A tool's name is derived from its class, and the brief calls it by that
  # name. A rename reaching one and not the other leaves the writer asking for
  # something that is not there.
  test "the writer is given the name of every tool it is handed" do
    FlexMessageAgent.tools.each { |tool| assert_includes @instructions, tool.new.name }
  end

  # The model's own sense of the date is whenever it was trained. Every
  # question about what is coming up is answered against this line instead.
  test "the writer is told what day it is where the community is" do
    assert_includes @instructions, Date.current.iso8601
  end
end
