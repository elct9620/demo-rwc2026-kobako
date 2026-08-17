require "test_helper"

class SearchEntriesToolTest < ActiveSupport::TestCase
  test "an entry is found by what its title says" do
    answer = SearchEntriesTool.new.execute(query: "八月小聚")

    assert_includes answer, "Ruby Taiwan 八月小聚"
  end

  # Facebook carries no title, so a post is only ever reachable through its
  # text. A search that read titles alone would leave a third of the table
  # unfindable.
  test "a post with no title is found by what its text says" do
    answer = SearchEntriesTool.new.execute(query: "現場")

    assert_includes answer, "七月小聚的現場"
  end

  test "a source narrows the answer to that source alone" do
    answer = SearchEntriesTool.new.execute(query: "Ruby", source: "kktix")

    assert_includes answer, "RubyConf Taiwan 春季場"
    assert_not_includes answer, "在 WASM 沙箱裡跑 mruby"
  end

  test "a source that does not exist comes back with the three that do" do
    answer = SearchEntriesTool.new.execute(query: "Ruby", source: "twitter")

    Entry.sources.each_key { |source| assert_includes answer, source }
  end

  # The dates the writer sends are the community's dates. Stored at 17:00 UTC
  # this event is already the 21st in Taipei, and asking for the 21st has to
  # find it — read in UTC the same query would answer nothing.
  test "a date is read in the zone the community keeps" do
    Entry.create!(
      source: "kktix",
      external_id: "tag:rubytaiwan.kktix.cc,2005:Event/999999",
      title: "深夜場",
      url: "https://rubytaiwan.kktix.cc/events/late-night",
      published_at: Time.utc(2026, 8, 20, 17)
    )

    answer = SearchEntriesTool.new.execute(query: "深夜場", from: "2026-08-21")

    assert_includes answer, "深夜場"
  end

  test "a date in no shape the tool reads is said to be so" do
    answer = SearchEntriesTool.new.execute(query: "Ruby", from: "next tuesday")

    assert_includes answer, "YYYY-MM-DD"
  end

  # Nothing found is an answer the brief has a card for, so it has to read
  # differently from a list of none.
  test "a search that matches nothing says so in words" do
    answer = SearchEntriesTool.new.execute(query: "量子力學讀書會")

    assert_includes answer, "Nothing"
  end

  # A carousel holds twelve bubbles, so a thirteenth entry is one the answer
  # could never show — and context the writer pays for either way.
  test "no more entries come back than a carousel could show" do
    (LineFlex::MAX_BUBBLES + 1).times do |index|
      Entry.create!(
        source: "youtube",
        external_id: "talk-#{index}",
        title: "Ruby 議程 #{index}",
        url: "https://www.youtube.com/watch?v=talk-#{index}",
        published_at: index.days.ago
      )
    end

    answer = JSON.parse(SearchEntriesTool.new.execute(query: "Ruby 議程"))

    assert_equal LineFlex::MAX_BUBBLES, answer.size
  end

  # The Flex DSL lends no uri action, so a link is a string nobody can tap.
  # Sending it anyway spends the writer's context on something it cannot use.
  test "the link is not among what the writer is told" do
    answer = SearchEntriesTool.new.execute(query: "八月小聚")

    assert_not_includes answer, "rubytaiwan.kktix.cc/events"
  end
end
