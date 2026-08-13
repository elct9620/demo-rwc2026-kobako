require "test_helper"

class LineFlexTest < ActiveSupport::TestCase
  CARD = <<~MRUBY
    Flex.with do
      alt_text "Brown Cafe"
      bubble do
        hero_image "https://example.com/cafe.png", size: :full, aspect_ratio: "20:13", aspect_mode: :cover
        body layout: :vertical, spacing: :md do
          text do
            span "Brown Cafe", weight: :bold, size: :xl
          end
          box layout: :baseline, spacing: :sm do
            text "Time", color: "#aaaaaa", size: :sm, flex: 1
            text "10:00 - 23:00", wrap: true, color: "#666666", size: :sm, flex: 5
          end
        end
        footer layout: :vertical do
          button style: :link, height: :sm do
            message "CALL", label: "CALL"
          end
        end
      end
    end
  MRUBY

  test "an untrusted script assembles a Flex Message through the sandbox" do
    message = LineFlex.render(CARD)

    assert_equal "flex", message[:type]
    assert_equal "Brown Cafe", message[:altText]
    assert_equal "bubble", message[:contents][:type]
  end

  # Base#context is a public method on every builder node, and its return value
  # would cross back as a live Handle into the context chain. Nothing but VERBS
  # decides that this name is unreachable.
  test "a verb outside the vocabulary never reaches the builder" do
    result = LineFlex.render("Flex.with { context }")

    assert_equal :no_service, result.reason
  end

  test "a script that never returns comes back as a value" do
    result = LineFlex.render("while true; end")

    assert_equal :timeout, result.reason
  end
end
