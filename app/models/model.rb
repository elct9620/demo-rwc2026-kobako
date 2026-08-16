# The model a chat was answered by. A Chat belongs to one of these and RubyLLM
# creates the row it needs on the way in, so this table is what makes chat
# records storable at all rather than a registry anyone here maintains.
class Model < ApplicationRecord
  acts_as_model
end
