require "test_helper"

class SearchEntriesToolTest < ActiveSupport::TestCase
  # The question the tool exists to answer: one that names no words to search
  # for. "Is there a video" is a source and nothing else, and a tool that
  # insisted on a keyword would answer it with whatever the model guessed.
  test "a source alone answers without any words to search for" do
    answer = JSON.parse(SearchEntriesTool.new.execute(source: "youtube"))

    assert_equal [ "在 WASM 沙箱裡跑 mruby" ], answer["entries"].pluck("title")
  end

  # An answer usually reaches across the three, so asking with nothing at all
  # has to bring back all three rather than nothing.
  test "no filter at all answers the whole record" do
    answer = JSON.parse(SearchEntriesTool.new.execute)

    assert_equal Entry.count, answer["matched"]
    assert_equal Entry.sources.keys.sort, answer["entries"].pluck("source").uniq.sort
  end

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

  # A post with neither a title nor any text is the shape an absent keyword
  # would lose: LIKE '%%' is NULL against a NULL column, so a filter that
  # matched on nothing would quietly drop it.
  test "an entry with nothing to search is still among what an empty filter answers" do
    Entry.create!(
      source: "facebook",
      external_id: "166417243936_900000000000002",
      url: "https://www.facebook.com/166417243936/posts/photo",
      published_at: 1.day.ago
    )

    answer = JSON.parse(SearchEntriesTool.new.execute(source: "facebook"))

    assert_equal 2, answer["matched"]
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

  # Read as its default instead, a direction nobody recognises would answer
  # confidently in the opposite order.
  test "an order that does not exist comes back with the two that do" do
    answer = SearchEntriesTool.new.execute(order: "ascending")

    SearchEntriesTool::ORDERS.each_key { |order| assert_includes answer, order }
  end

  # What is coming up is a date and a direction rather than a tool of its own.
  test "reading forwards from today answers what has not happened yet" do
    answer = JSON.parse(SearchEntriesTool.new.execute(from: Date.current.iso8601, order: "oldest"))

    assert_equal [ "Ruby Taiwan 八月小聚" ], answer["entries"].pluck("title")
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

  # Nothing matched is a count of none rather than a sentence: a sentence is
  # something a writer can mistake for content and lay out as a card.
  test "a filter that matches nothing answers a count of none" do
    answer = JSON.parse(SearchEntriesTool.new.execute(query: "量子力學讀書會"))

    assert_equal 0, answer["matched"]
    assert_empty answer["entries"]
  end

  # What did not fit has to be visible, or a truncated list reads as the whole
  # record and gets answered as if it were.
  test "more matching than fit says how many matched" do
    (SearchEntriesTool::DEFAULT_LIMIT + 5).times do |index|
      Entry.create!(
        source: "youtube",
        external_id: "talk-#{index}",
        title: "Ruby 議程 #{index}",
        url: "https://www.youtube.com/watch?v=talk-#{index}",
        published_at: index.days.ago
      )
    end

    answer = JSON.parse(SearchEntriesTool.new.execute(query: "Ruby 議程"))

    assert_equal SearchEntriesTool::DEFAULT_LIMIT + 5, answer["matched"]
    assert_equal SearchEntriesTool::DEFAULT_LIMIT, answer["entries"].size
  end

  # The budget is what the writer can read, so asking past it is answered with
  # the budget rather than refused.
  test "asking for more than the budget answers the budget" do
    (SearchEntriesTool::MAX_LIMIT + 1).times do |index|
      Entry.create!(
        source: "youtube",
        external_id: "session-#{index}",
        title: "議程 #{index}",
        url: "https://www.youtube.com/watch?v=session-#{index}",
        published_at: index.hours.ago
      )
    end

    answer = JSON.parse(SearchEntriesTool.new.execute(query: "議程", limit: 500))

    assert_equal SearchEntriesTool::MAX_LIMIT, answer["entries"].size
  end

  # The Flex DSL lends no uri action, so a link is a string nobody can tap.
  # Sending it anyway spends the writer's context on something it cannot use.
  test "the link is not among what the writer is told" do
    answer = SearchEntriesTool.new.execute(query: "八月小聚")

    assert_not_includes answer, "rubytaiwan.kktix.cc/events"
  end
end
