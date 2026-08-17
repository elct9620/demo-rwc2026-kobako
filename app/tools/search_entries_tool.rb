# What the writer reads before it lays anything out. Without it the card is
# written from whatever the model remembers, which for a local community is
# nothing — this is the difference between an answer and a guess.
class SearchEntriesTool < RubyLLM::Tool
  description <<~TEXT
    Search the community's events, talk recordings and page posts by keyword.
    Answers at most #{LineFlex::MAX_BUBBLES} entries as JSON, most recent
    first, or a sentence saying nothing matched.
  TEXT

  param :query, desc: "Words to look for in an entry's title or summary."
  param :source, desc: "Limit to one source: #{Entry.sources.keys.join(", ")}.", required: false
  param :from, desc: "Only entries published on or after this date, as YYYY-MM-DD.", required: false
  param :to, desc: "Only entries published on or before this date, as YYYY-MM-DD.", required: false

  def execute(query:, source: nil, from: nil, to: nil)
    return unknown_source(source) if source.present? && !Entry.sources.key?(source)

    entries = Entry.matching(query)
    entries = entries.where(source: source) if source.present?
    # A bare date means the whole of that day where the community keeps it, so
    # both ends are widened before they are compared against a timestamp.
    # Read as ISO rather than parsed loosely: Date.parse reads "next tuesday"
    # as a date, which would answer confidently from a question nobody asked.
    entries = entries.where(published_at: Date.iso8601(from).beginning_of_day..) if from.present?
    entries = entries.where(published_at: ..Date.iso8601(to).end_of_day) if to.present?
    entries = entries.order(published_at: :desc).limit(LineFlex::MAX_BUBBLES)

    entries.any? ? entries.to_json : "Nothing the community posted matches that."
  rescue Date::Error
    "A date has to be written as YYYY-MM-DD."
  end

  private

  # The same shape the sandbox answers a name it does not lend: say what is
  # wrong and hand back the whole of what is allowed, so the next call can be
  # right rather than another guess.
  def unknown_source(source)
    "There is no source called #{source}. The three are: #{Entry.sources.keys.join(", ")}."
  end
end
