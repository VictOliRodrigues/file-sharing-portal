class AddShareLinkToDownloads < ActiveRecord::Migration[8.1]
  def change
    # Set when the file was fetched through a public share link rather than by
    # a signed-in user.
    add_reference :downloads, :share_link, null: true, foreign_key: true
  end
end
