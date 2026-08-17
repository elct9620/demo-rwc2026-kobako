require "net/http"

# What the three source jobs share: one GET, and a line in the log when the
# answer was not 200.
#
# Nothing here retries and nothing alerts, so that line is the only trace a
# source leaves when it stops answering — a table that quietly stopped growing
# looks exactly like a community that stopped posting. The URL is never part of
# it, because one of the three carries its credential there.
module FetchesSource
  extend ActiveSupport::Concern

  private

  def body_of(url, headers = nil)
    response = Net::HTTP.get_response(URI(url), headers)
    return response.body if response.is_a?(Net::HTTPSuccess)

    # The status alone does not say what to do about it. Meta answers 400 for a
    # page whose data access has lapsed, and only the body distinguishes that —
    # "Session has expired" — from a request this app got wrong; the first needs
    # a person to re-authorise the page and no amount of retrying will do.
    #
    # Truncated, because a source answering with an error page should not fill
    # the log with it. Safe to keep at all because no URL here carries a
    # credential: the one token in play travels in a header.
    logger.error("#{self.class.name}: the source answered #{response.code} — #{response.body.to_s.squish.truncate(200)}")
    nil
  end

  # Rows already in the table are skipped rather than compared: what a feed
  # says about an event or a video does not change once it is published, and
  # what does change — how many seats are left — is not kept here.
  #
  # An answer nothing could be read out of is worth a line of its own. None of
  # the three is ever legitimately empty, so a source that starts serving a
  # login wall or a challenge page under a 200 would otherwise pass as quietly
  # as a source that simply had no news.
  def store(rows)
    return logger.error("#{self.class.name}: the answer held no entries") if rows.empty?

    Entry.insert_all(rows, unique_by: [ :source, :external_id ])
  end
end
