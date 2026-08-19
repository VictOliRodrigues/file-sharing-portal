class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :name, null: false
      t.string   :email_address, null: false
      t.string   :password_digest, null: false
      t.boolean  :admin, null: false, default: false
      # Set when an administrator suspends the account. Disabled users keep
      # their data but can no longer authenticate.
      t.datetime :disabled_at
      # Per-user storage limit in bytes. NULL falls back to the deployment-wide
      # default, 0 means unlimited.
      t.bigint   :storage_quota_bytes
      t.datetime :last_signed_in_at

      t.timestamps
    end

    add_index :users, :email_address, unique: true
  end
end
