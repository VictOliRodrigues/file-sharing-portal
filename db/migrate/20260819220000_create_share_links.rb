class CreateShareLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :share_links do |t|
      # The account that created the link and is accountable for it.
      t.references :user, null: false, foreign_key: true
      # Either a StoredFile or a Folder.
      t.references :shareable, null: false, polymorphic: true
      # The only credential a recipient needs. Unguessable and unique.
      t.string   :token, null: false
      # Optional second factor for the link.
      t.string   :password_digest
      t.datetime :expires_at
      t.integer  :download_limit
      t.integer  :download_count, null: false, default: 0
      t.datetime :last_accessed_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :share_links, :token, unique: true
    add_index :share_links, [ :user_id, :created_at ]
  end
end
