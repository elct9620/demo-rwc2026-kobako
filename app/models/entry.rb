# One row is one thing worth showing on a card: an event, a talk recording, or
# a post from the community's page. All three live in one table because reading
# is a single query across the lot — what separates them is a column value, not
# a class.
class Entry < ApplicationRecord
  # The whole of the vocabulary. A fetcher writes one of these three and the
  # unique index is scoped by it, so a name absent here is a row nothing can
  # find again.
  enum :source, { kktix: "kktix", youtube: "youtube", facebook: "facebook" }
end
