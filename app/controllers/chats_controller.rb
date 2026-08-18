# The demo's only screen. Each message LINE delivers opens a chat of its own,
# so a chat is one question and the card written to answer it — newest first,
# because the one being written is the one worth watching.
class ChatsController < ApplicationController
  # A window rather than a record. What is worth showing is what is being
  # written now and the few before it, and a window is also what clears the
  # half-written cards a failed run leaves behind: they are pushed out by
  # whatever is asked next rather than needing anyone to delete them.
  SHOWN = 5

  def index
    @chats = Chat.order(created_at: :desc).limit(SHOWN)
  end
end
