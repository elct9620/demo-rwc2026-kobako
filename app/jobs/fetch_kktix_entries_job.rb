# The community's events, as KKTIX lists them.
class FetchKktixEntriesJob < ApplicationJob
  include FetchesSource

  # The feed answers 100 entries at once, past and future mixed, and mints a
  # fresh ETag on every request — so there is no cheap way to ask it for only
  # what is new. Reading all of it daily is affordable precisely because the
  # unique index throws away what is already here.
  FEED_URL = "https://rubytaiwan.kktix.cc/events.atom?locale=zh-TW"

  def perform
    body = body_of(FEED_URL)
    return if body.nil?

    store(Nokogiri::XML(body).css("entry").filter_map { |entry| row_for(entry) })
  end

  private

  def row_for(entry)
    title = entry.at_css("> title")&.text
    summary = entry.at_css("> summary")&.text
    return if title.blank? && summary.blank?

    {
      source: "kktix",
      external_id: entry.at_css("> id").text,
      title: title,
      summary: summary,
      url: entry.at_css("> link")["href"],
      # This feed's `published` is when the event starts rather than when it
      # was listed, which is the date worth showing on a card either way.
      published_at: entry.at_css("> published").text,
      # Where and when to turn up exists only as this line of free text, and
      # only on this source.
      metadata: { schedule: entry.at_css("> content")&.text }
    }
  end
end
