# Posts from the community's page — the record of what an event was actually
# like, which neither the event listing nor the recording carries.
class FetchFacebookEntriesJob < ApplicationJob
  include FetchesSource

  # Pinned, because a call without a version falls to the oldest one Meta still
  # serves rather than the newest.
  GRAPH_VERSION = "v25.0"

  # `full_picture` is deliberately not asked for. It answers a signed CDN URL
  # that expires about four days out, and nothing here revisits a row once it
  # is written — so a thumbnail kept from this source would be a broken image
  # by the time anyone saw it.
  FIELDS = "id,message,created_time,permalink_url"

  def perform
    body = body_of(posts_url, "Authorization" => "Bearer #{ENV.fetch("FB_PAGE_TOKEN")}")
    return if body.nil?

    store(JSON.parse(body).fetch("data", []).filter_map { |post| row_for(post) })
  end

  private

  # The token travels in a header rather than the query string, so it stays out
  # of anything that records a URL.
  #
  # Meta expires *data access* on its own 90-day clock, separately from the
  # token, and the current window closes on 2026-11-15. Nothing announces it:
  # the call simply starts failing, which is why the log line matters here more
  # than on the other two sources.
  def posts_url
    "https://graph.facebook.com/#{GRAPH_VERSION}/#{ENV.fetch("FB_PAGE_ID")}/posts?fields=#{FIELDS}"
  end

  def row_for(post)
    message = post["message"]
    # A post that is only a photo carries no text, and this source has no
    # title to fall back on — there would be nothing to put on a card.
    return if message.blank?

    {
      source: "facebook",
      external_id: post.fetch("id"),
      summary: message,
      url: post.fetch("permalink_url"),
      published_at: post.fetch("created_time")
    }
  end
end
