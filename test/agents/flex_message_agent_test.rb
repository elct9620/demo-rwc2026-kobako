require "test_helper"

class FlexMessageAgentTest < ActiveSupport::TestCase
  setup do
    @instructions = FlexMessageAgent.render_prompt("instructions", chat: nil, inputs: {}, locals: {})
    @vocabulary = FlexMessageAgent.render_prompt("vocabulary", chat: nil, inputs: {}, locals: {})
  end

  # The vocabulary is one contract in two directions: the ceiling the sandbox
  # enforces, and what the writer is given to aim at. A verb that lands in one
  # and not the other is the drift this catches — and it is the signature that
  # is looked for, because a name the writer cannot tell how to call is a name
  # it will call the way it remembers.
  test "the writer is given a signature for every verb the sandbox lends" do
    LineFlex::VERBS.each { |verb| assert_match(/^\s*def (self\.)?#{verb}:/, @vocabulary, verb.to_s) }
  end

  # The brief hands the contract over rather than restating it, so there is one
  # place a verb is described and no second one to fall out of step.
  test "the brief hands over the whole vocabulary" do
    assert_includes @instructions, @vocabulary.strip
  end

  # A tool's name is derived from its class, and the brief calls it by that
  # name. A rename reaching one and not the other leaves the writer asking for
  # something that is not there.
  test "the writer is given the name of every tool it is handed" do
    FlexMessageAgent.tools.each { |tool| assert_includes @instructions, tool.new.name }
  end

  # Twelve is the builder's ceiling on a carousel, so it is also the most a
  # single answer can show. A writer told a larger number would lay out entries
  # the sandbox then refuses to assemble.
  test "the writer is told how many bubbles one answer holds" do
    assert_includes @instructions, LineFlex::MAX_BUBBLES.to_s
  end

  # The model's own sense of the date is whenever it was trained. Every
  # question about what is coming up is answered against this line instead.
  test "the writer is told what day it is where the community is" do
    assert_includes @instructions, Date.current.iso8601
  end

  # The brief teaches by example — a card to imitate, and a card to copy when
  # there is nothing to lay out. Each is a script like any other, and one the
  # sandbox has to accept: an example it would stop is a lesson in how to fail.
  test "every card the writer is shown is one the sandbox assembles" do
    examples = @instructions.scan(/```ruby\n(.*?)```/m).flatten

    assert_operator examples.size, :>, 1
    examples.each do |example|
      assert_not_instance_of LineFlex::Failure, LineFlex.render(example), example
    end
  end
end
