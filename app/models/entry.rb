# One row is one thing worth showing on a card: an event, a talk recording, or
# a post from the community's page. All three live in one table because reading
# is a single query across the lot — what separates them is a column value, not
# a class.
class Entry < ApplicationRecord
  # The whole of the vocabulary. A fetcher writes one of these three and the
  # unique index is scoped by it, so a name absent here is a row nothing can
  # find again.
  enum :source, { kktix: "kktix", youtube: "youtube", facebook: "facebook" }

  # A search runs over both columns because a card is written from both: a
  # Facebook post has no title at all, and a KKTIX event says what it is about
  # only in its summary.
  scope :matching, ->(text) {
    where("title LIKE :text OR summary LIKE :text", text: "%#{sanitize_sql_like(text.to_s)}%")
  }

  # What the writer is told about an entry. The link is left out on purpose:
  # the vocabulary lends no uri action, so a URL on a card is a string nobody
  # can tap. Empty fields are dropped rather than sent as null — a source that
  # cannot fill a column has nothing to say about it.
  def as_json(*)
    {
      source: source,
      title: title,
      summary: summary,
      # Where and when to turn up exists only as this line of free text, and
      # only on KKTIX.
      schedule: metadata["schedule"],
      published_at: published_at.iso8601,
      thumbnail_url: thumbnail_url
    }.compact
  end
end
