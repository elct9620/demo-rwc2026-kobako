# Fills the page with cards so the appearance can be looked at, without a LINE
# delivery and without spending a request on the writer. What it builds is the
# record a finished run leaves behind, in each of the two states a card is ever
# in: a draft the sandbox has checked, and the answer a chat settled on.
#
#   bin/rails runner script/preview_cards.rb
#   bin/dev                                    # then open http://localhost:3000
#
# It replaces whatever is already there, because a stage is worth more clean
# than cumulative — which is also why it refuses to run anywhere but here.

abort "preview data replaces every chat; development only" unless Rails.env.development?

# Nothing below reaches a provider: the writing has already happened and what is
# being built is the record of it. Opening a chat still resolves one, so it is
# handed a placeholder no request will ever carry.
RubyLLM.config.openai_api_key ||= "preview-makes-no-request"

ANSWERED = <<~MRUBY
  Flex.with do
    alt_text "八月小聚：Ruby on Rails 的下一步"
    bubble do
      body layout: :vertical, spacing: :md do
        text "八月小聚", weight: :bold, size: :lg, wrap: true
        text "Ruby on Rails 的下一步", size: :sm, color: "#7A7A7A", wrap: true
        box layout: :baseline, spacing: :sm do
          text "8/23 (六) 14:00", size: :sm, flex: 0
        end
      end
    end
  end
MRUBY

DRAFTED = <<~MRUBY
  # The carousel the writer is still measuring against the ceiling
  Flex.with do
    alt_text "近期的三場活動"
    carousel do
      3.times do |index|
        bubble do
          body layout: :vertical do
            text "活動 \#{index + 1}", weight: :bold, wrap: true
          end
        end
      end
    end
  end
MRUBY

Chat.destroy_all

def opened(question)
  chat = Chat.create!
  chat.messages.create!(role: "user", content: question)
  chat
end

# A chat whose only trace of the writing is the call that asked the sandbox
# about a version. Nothing has been settled, so the card reads as a draft.
drafted = opened("最近有哪些活動")
drafted.messages.create!(role: "assistant").tool_calls.create!(
  tool_call_id: "preview-layout-check", name: LayoutCheckTool.new.name,
  arguments: { "script" => DRAFTED }
)

# A chat that settled. Structured output lands in content_raw, which is what
# tells the answer apart from the turns that only called a tool.
opened("下一場小聚是什麼時候").messages.create!(
  role: "assistant", content_raw: { "script" => ANSWERED }
)

puts "#{Chat.count} chats — #{Chat.order(:created_at).map(&:state).join(", ")}"
