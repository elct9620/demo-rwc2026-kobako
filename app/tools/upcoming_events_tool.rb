# The one question a keyword cannot ask. "What is coming up" is a comparison
# against now, and nothing in an entry's own words says whether it has happened
# yet — so the writer is given a way to ask for it directly rather than
# guessing at search terms.
class UpcomingEventsTool < RubyLLM::Tool
  description <<~TEXT
    List the events that have not happened yet, soonest first, as JSON.
    Answers at most #{LineFlex::MAX_BUBBLES} entries, or a sentence saying
    there are none.
  TEXT

  def execute
    entries = Entry.upcoming.limit(LineFlex::MAX_BUBBLES)

    entries.any? ? entries.to_json : "The community has nothing scheduled at the moment."
  end
end
