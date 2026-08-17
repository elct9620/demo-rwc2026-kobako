# What the writer reads before it lays anything out. Without it the card is
# written from whatever the model remembers, which for a local community is
# nothing — this is the difference between an answer and a guess.
#
# Every filter is optional because a question rarely names one. "What has been
# happening" is a date range with nothing else in it, and "is there a video" is
# a source with no keyword — neither has words to search for, and a tool that
# demanded them would answer nothing to both.
class SearchEntriesTool < RubyLLM::Tool
  # How much of the record one call hands over, and the most it will hand over
  # when asked for more. This is a reading budget, not a display ceiling: the
  # card is written from what these rows say rather than printed from them, so
  # what fits in a carousel has no say in what is worth reading.
  DEFAULT_LIMIT = 10
  MAX_LIMIT = 50

  # Which end of the range the limit cuts from. Asking what is coming up is
  # this and a `from` — a direction rather than a tool of its own.
  ORDERS = { "newest" => :desc, "oldest" => :asc }.freeze

  description <<~TEXT
    Filter what the community has posted — events, talk recordings and page
    posts — and answer the rows as JSON alongside how many matched in total.

    Every filter is optional, and with none of them the whole record comes back
    newest first. One question is often answered from more than one source, so
    leave `source` out unless the question is about that source alone.

    When `matched` is larger than the rows returned, ask again with a larger
    `limit` or a narrower filter rather than assuming the rest is nothing.
  TEXT

  param :query, desc: "Words to look for in an entry's title or summary. Omit to filter without searching.", required: false
  param :source, desc: "Limit to one source: #{Entry.sources.keys.join(", ")}.", required: false
  param :from, desc: "Only entries published on or after this date, as YYYY-MM-DD.", required: false
  param :to, desc: "Only entries published on or before this date, as YYYY-MM-DD.", required: false
  param :order, desc: "#{ORDERS.keys.join(" or ")} first. Defaults to newest.", required: false
  param :limit, type: "integer", desc: "How many rows to return, at most #{MAX_LIMIT}. Defaults to #{DEFAULT_LIMIT}.", required: false

  def execute(query: nil, source: nil, from: nil, to: nil, order: nil, limit: nil)
    return unknown(:source, source, Entry.sources.keys) if source.present? && !Entry.sources.key?(source)
    return unknown(:order, order, ORDERS.keys) if order.present? && !ORDERS.key?(order)

    entries = filter(query:, source:, from:, to:)
    rows = entries.order(published_at: ORDERS.fetch(order, :desc)).limit(clamp(limit))

    { matched: entries.count, entries: rows }.to_json
  rescue Date::Error
    "A date has to be written as YYYY-MM-DD."
  end

  private

  def filter(query:, source:, from:, to:)
    entries = Entry.all
    # An absent keyword drops the condition rather than matching on nothing:
    # LIKE '%%' is NULL against a NULL column, which would silently lose every
    # post carrying neither a title nor any text.
    entries = entries.matching(query) if query.present?
    entries = entries.where(source: source) if source.present?
    # A bare date means the whole of that day where the community keeps it, so
    # both ends are widened before they are compared against a timestamp.
    # Read as ISO rather than parsed loosely: Date.parse reads "next tuesday"
    # as a date, which would answer confidently from a question nobody asked.
    entries = entries.where(published_at: Date.iso8601(from).beginning_of_day..) if from.present?
    entries = entries.where(published_at: ..Date.iso8601(to).end_of_day) if to.present?
    entries
  end

  def clamp(limit) = limit.nil? ? DEFAULT_LIMIT : limit.to_i.clamp(1, MAX_LIMIT)

  # The same shape the sandbox answers a name it does not lend: say what is
  # wrong and hand back the whole of what is allowed, so the next call can be
  # right rather than another guess. A value read as its default instead would
  # answer confidently in an order nobody asked for.
  def unknown(param, value, allowed)
    "There is no #{param} called #{value}. The ones there are: #{allowed.join(", ")}."
  end
end
