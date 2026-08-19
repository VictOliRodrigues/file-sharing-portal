# One recorded download of a file.
#
# `user` is null when the file was fetched through a public share link, in
# which case `share_link` identifies the link that was used.
class Download < ApplicationRecord
  belongs_to :stored_file
  belongs_to :user, optional: true

  scope :recent, -> { order(created_at: :desc) }

  def anonymous?
    user_id.nil?
  end
end
