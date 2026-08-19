class AddFolderToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    # A null folder means the file sits at the root of the owner's drive.
    add_reference :stored_files, :folder, null: true, foreign_key: true
    add_index :stored_files, [ :folder_id, :deleted_at ]
  end
end
