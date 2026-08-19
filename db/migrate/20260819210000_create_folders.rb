class CreateFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :folders do |t|
      t.references :user, null: false, foreign_key: true
      # Self referential: a null parent means the folder sits at the root of
      # the owner's drive.
      t.references :parent, null: true, foreign_key: { to_table: :folders }
      t.string     :name, null: false
      t.datetime   :deleted_at

      t.timestamps
    end

    # Folder names are unique per parent, case insensitively. Two indexes are
    # needed because PostgreSQL treats NULL parent_id values as distinct, which
    # would let duplicates through at the root.
    add_index :folders, "user_id, parent_id, lower(name)",
              unique: true, where: "parent_id IS NOT NULL AND deleted_at IS NULL",
              name: "index_folders_on_owner_parent_and_name"
    add_index :folders, "user_id, lower(name)",
              unique: true, where: "parent_id IS NULL AND deleted_at IS NULL",
              name: "index_folders_on_owner_and_root_name"

    add_index :folders, [ :user_id, :deleted_at ]
  end
end
