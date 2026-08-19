class CreateStoredFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :stored_files do |t|
      t.references :user, null: false, foreign_key: true
      # Display name. Always the sanitized form of the name supplied by the
      # client; the name is never used to build a storage path.
      t.string   :name, null: false
      # Denormalized from the Active Storage blob so listings, search and the
      # dashboard do not have to join the blob tables.
      t.bigint   :byte_size, null: false, default: 0
      t.string   :content_type, null: false, default: "application/octet-stream"
      # Soft delete. Deleted files move to the trash and can be restored until
      # they are purged.
      t.datetime :deleted_at
      t.integer  :download_count, null: false, default: 0
      t.datetime :last_downloaded_at

      t.timestamps
    end

    add_index :stored_files, [ :user_id, :deleted_at ]
    add_index :stored_files, [ :user_id, :created_at ]
    add_index :stored_files, :content_type
    add_index :stored_files, :deleted_at
  end
end
