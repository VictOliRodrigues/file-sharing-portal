class CreateDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :downloads do |t|
      t.references :stored_file, null: false, foreign_key: true
      # Null when the file was fetched through a public share link.
      t.references :user, null: true, foreign_key: true
      t.string     :ip_address

      t.datetime :created_at, null: false
    end

    add_index :downloads, :created_at
  end
end
