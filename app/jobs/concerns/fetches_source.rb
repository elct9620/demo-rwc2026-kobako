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

    logger.error("#{self.class.name}: the source answered #{response.code}")
    nil
  end

  # Rows already in the table are skipped rather than compared: what a feed
  # says about an event or a video does not change once it is published, and
  # what does change — how many seats are left — is not kept here.
  def store(rows)
    Entry.insert_all(rows, unique_by: [ :source, :external_id ]) if rows.any?
  end
end
