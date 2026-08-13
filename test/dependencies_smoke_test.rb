require "test_helper"

# Two of the demo's gems reach outside plain Ruby to work: kobako loads a native
# extension and a wasm guest, and line-message-builder has to emit a payload
# LINE will accept. A failure here is an installation problem rather than a
# change in what the demo does.
class DependenciesSmokeTest < ActiveSupport::TestCase
  test "the sandbox evaluates guest code and hands back its value" do
    execution = Kobako::Sandbox.new.eval("1 + 2")

    assert_equal 3, execution.value
  end

  test "the builder emits a Flex message" do
    messages = Line::Message::Builder.with do
      flex alt_text: "Hello" do
        bubble do
          body do
            text "Hello"
          end
        end
      end
    end.build

    assert_equal "flex", messages.first[:type]
  end
end
