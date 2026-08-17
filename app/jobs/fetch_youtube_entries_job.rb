# Talk recordings, from the channel's own RSS.
class FetchYoutubeEntriesJob < ApplicationJob
  include FetchesSource

  # The feed answers the latest 15 and has no pages, so anything older than
  # that is only here if a previous run already caught it — which is what makes
  # a daily run worth having rather than a one-off import.
  FEED_URL = "https://www.youtube.com/feeds/videos.xml?channel_id=UC5YyLQH-M9_tSXIKv29bstg"

  def perform
    body = body_of(FEED_URL)
    return if body.nil?

    store(Nokogiri::XML(body).css("entry").filter_map { |entry| row_for(entry) })
  end

  private

  def row_for(entry)
    title = entry.at_css("> title")&.text
    summary = entry.at_css("media|description")&.text
    return if title.blank? && summary.blank?

    {
      source: "youtube",
      external_id: entry.at_css("yt|videoId").text,
      title: title,
      summary: summary,
      url: entry.at_css("> link")["href"],
      # The only source whose thumbnail survives being written down: the URL
      # carries no signature and no expiry, so it still resolves months later.
      thumbnail_url: entry.at_css("media|thumbnail")&.[]("url"),
      published_at: entry.at_css("> published").text
    }
  end
end
