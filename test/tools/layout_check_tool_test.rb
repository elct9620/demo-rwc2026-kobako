require "test_helper"

class LayoutCheckToolTest < ActiveSupport::TestCase
  OUTSIDE_THE_VOCABULARY = "Flex.with { context }"
  CARD = <<~MRUBY
    Flex.with do
      alt_text "Brown Cafe"
      bubble do
        body layout: :vertical do
          text "10:00 - 23:00"
        end
      end
    end
  MRUBY

  test "a script that assembles a card comes back as assembled" do
    answer = LayoutCheckTool.new.execute(script: CARD)

    assert_includes answer, "assembled"
  end

  # The one failure the writer can actually repair, so the answer carries what
  # it needs to repair it with.
  test "a name outside the vocabulary comes back with the vocabulary" do
    answer = LayoutCheckTool.new.execute(script: OUTSIDE_THE_VOCABULARY)

    LineFlex::VERBS.each { |verb| assert_includes answer, verb.to_s }
  end

  test "a script that never returns is told what it may not do" do
    answer = LayoutCheckTool.new.execute(script: "while true; end")

    assert_includes answer, "loop"
  end

  # The ceiling is a deadline, so it has to stop the run rather than only say
  # something about it.
  test "the sandbox stops running once the attempts are spent" do
    tool = LayoutCheckTool.new
    LayoutCheckTool::ATTEMPTS.times { tool.execute(script: OUTSIDE_THE_VOCABULARY) }

    answer = LineFlex.stub(:render, ->(*) { flunk "the sandbox ran after the attempts were spent" }) do
      tool.execute(script: OUTSIDE_THE_VOCABULARY)
    end

    assert_includes answer, "best script"
  end
end
