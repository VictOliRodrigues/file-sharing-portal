# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_19_220100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "downloads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.bigint "share_link_id"
    t.bigint "stored_file_id", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_downloads_on_created_at"
    t.index ["share_link_id"], name: "index_downloads_on_share_link_id"
    t.index ["stored_file_id"], name: "index_downloads_on_stored_file_id"
    t.index ["user_id"], name: "index_downloads_on_user_id"
  end

  create_table "folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.bigint "parent_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_folders_on_owner_and_root_name", unique: true, where: "((parent_id IS NULL) AND (deleted_at IS NULL))"
    t.index "user_id, parent_id, lower((name)::text)", name: "index_folders_on_owner_parent_and_name", unique: true, where: "((parent_id IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["user_id", "deleted_at"], name: "index_folders_on_user_id_and_deleted_at"
    t.index ["user_id"], name: "index_folders_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "share_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0, null: false
    t.integer "download_limit"
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.string "password_digest"
    t.datetime "revoked_at"
    t.bigint "shareable_id", null: false
    t.string "shareable_type", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shareable_type", "shareable_id"], name: "index_share_links_on_shareable"
    t.index ["token"], name: "index_share_links_on_token", unique: true
    t.index ["user_id", "created_at"], name: "index_share_links_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_share_links_on_user_id"
  end

  create_table "stored_files", force: :cascade do |t|
    t.bigint "byte_size", default: 0, null: false
    t.string "content_type", default: "application/octet-stream", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "download_count", default: 0, null: false
    t.bigint "folder_id"
    t.datetime "last_downloaded_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["content_type"], name: "index_stored_files_on_content_type"
    t.index ["deleted_at"], name: "index_stored_files_on_deleted_at"
    t.index ["folder_id", "deleted_at"], name: "index_stored_files_on_folder_id_and_deleted_at"
    t.index ["folder_id"], name: "index_stored_files_on_folder_id"
    t.index ["user_id", "created_at"], name: "index_stored_files_on_user_id_and_created_at"
    t.index ["user_id", "deleted_at"], name: "index_stored_files_on_user_id_and_deleted_at"
    t.index ["user_id"], name: "index_stored_files_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "email_address", null: false
    t.datetime "last_signed_in_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.bigint "storage_quota_bytes"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "downloads", "share_links"
  add_foreign_key "downloads", "stored_files"
  add_foreign_key "downloads", "users"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "share_links", "users"
  add_foreign_key "stored_files", "folders"
  add_foreign_key "stored_files", "users"
end
