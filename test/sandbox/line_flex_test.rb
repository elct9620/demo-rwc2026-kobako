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
            icon "https://example.com/clock.png", size: :sm
            text "10:00 - 23:00", wrap: true, color: "#666666", size: :sm
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
    assert_equal "Brown Cafe", message[:alt_text]
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

  # Carousel#bubble hands back the mutated contents Array rather than the child
  # it made, which is the one case Node#method_missing reaches into. Several
  # entries on one answer is what the verb is for, so this is the path that
  # carries it.
  # Read with the test below, this pair is what pins MAX_BUBBLES to what the
  # builder actually does rather than to what it was believed to do: the last
  # carousel it accepts, and the first it refuses.
  test "a carousel of every bubble LINE holds crosses the boundary intact" do
    message = LineFlex.render(carousel_of(LineFlex::MAX_BUBBLES))

    assert_equal "carousel", message[:contents][:type]
    assert_equal LineFlex::MAX_BUBBLES, message[:contents][:contents].size
  end

  # The builder's own limits are host exceptions raised inside a Service call.
  # Whether it refuses a thirteenth bubble is its business; what belongs here is
  # that its refusal arrives as a value, and as a different one from a name the
  # sandbox does not lend — those two send the writer to fix different things.
  test "a carousel past what LINE holds comes back as a value" do
    result = LineFlex.render(carousel_of(LineFlex::MAX_BUBBLES + 1))

    assert_instance_of LineFlex::Failure, result
    assert_equal :service, result.reason
  end

  # The builder assigns one slot for both verbs, so the second container wins
  # and the first is gone without a word — a whole carousel dropped from an
  # answer that still assembles and still checks green. This is the one refusal
  # the boundary makes on its own behalf, which is why it is pinned here.
  test "a second container at the root comes back as a value" do
    result = LineFlex.render(<<~MRUBY)
      Flex.with do
        alt_text "Sessions"
        carousel do
          bubble { body(layout: :vertical) { text "第 1 場" } }
        end
        bubble { body(layout: :vertical) { text "共 15 場" } }
      end
    MRUBY

    assert_instance_of LineFlex::Failure, result
    assert_match(/one container/, result.message)
  end

  test "a button with nothing to do comes back as a value" do
    result = LineFlex.render(<<~MRUBY)
      Flex.with do
        alt_text "Sessions"
        bubble do
          footer layout: :vertical do
            button style: :link
          end
        end
      end
    MRUBY

    assert_instance_of LineFlex::Failure, result
    assert_equal :service, result.reason
  end

  private

  def carousel_of(count)
    bubbles = Array.new(count) { |index| %(bubble { body(layout: :vertical) { text "第 #{index} 場" } }) }

    <<~MRUBY
      Flex.with do
        alt_text "Sessions"
        carousel do
          #{bubbles.join("\n    ")}
        end
      end
    MRUBY
  end
end
