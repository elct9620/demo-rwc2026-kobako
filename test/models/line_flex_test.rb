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
end
