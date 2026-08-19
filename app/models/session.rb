# A signed-in browser session.
#
# The browser only ever holds the session's id in a signed, HttpOnly cookie.
# Deleting the row signs the user out everywhere that session was used, which is
# what makes "disable user" and "sign out all devices" effective immediately.
class Session < ApplicationRecord
  belongs_to :user

  scope :ordered, -> { order(created_at: :desc) }
end
