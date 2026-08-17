require "test_helper"

class UpcomingEventsToolTest < ActiveSupport::TestCase
  # KKTIX's published_at is when the event starts, so what separates an event
  # someone can still attend from a record of one is a comparison against now.
  test "an event already held is not among what is coming up" do
    answer = UpcomingEventsTool.new.execute

    assert_includes answer, "Ruby Taiwan 八月小聚"
    assert_not_includes answer, "RubyConf Taiwan 春季場"
  end

  test "the soonest event comes first" do
    Entry.create!(
      source: "kktix",
      external_id: "tag:rubytaiwan.kktix.cc,2005:Event/888888",
      title: "明天的場次",
      url: "https://rubytaiwan.kktix.cc/events/tomorrow",
      published_at: 1.day.from_now
    )

    answer = JSON.parse(UpcomingEventsTool.new.execute)

    assert_equal "明天的場次", answer.first["title"]
  end

  test "an empty calendar is said in words rather than as no entries" do
    Entry.upcoming.delete_all

    answer = UpcomingEventsTool.new.execute

    assert_includes answer, "nothing scheduled"
  end
end
