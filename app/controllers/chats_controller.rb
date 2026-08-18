# The demo's only screen. Each message LINE delivers opens a chat of its own,
# so a chat is one question and the card written to answer it — newest first,
# because the one being written is the one worth watching.
class ChatsController < ApplicationController
  def index
    @chats = Chat.order(created_at: :desc)
  end
end
