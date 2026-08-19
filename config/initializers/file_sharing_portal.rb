# frozen_string_literal: true

# Application settings that a self-hosted operator may want to tune without
# touching code. Everything here is read from the environment so the same
# container image can be reused across deployments.
#
# See .env.example for the full list of supported variables.
Rails.application.config.x.portal = ActiveSupport::OrderedOptions.new.tap do |portal|
  # Maximum size of a single upload, in bytes.
  portal.max_upload_size = ENV.fetch("MAX_UPLOAD_SIZE_MB", "512").to_i.megabytes

  # Per-user storage quota, in bytes. Zero means "unlimited".
  portal.default_storage_quota = ENV.fetch("DEFAULT_STORAGE_QUOTA_MB", "0").to_i.megabytes

  # When disabled, only an administrator can create new accounts.
  portal.registration_enabled = ActiveModel::Type::Boolean.new.cast(
    ENV.fetch("ALLOW_REGISTRATION", "true")
  )

  # Maximum lifetime of a share link, in days. Zero means "never expires".
  portal.max_share_link_days = ENV.fetch("MAX_SHARE_LINK_DAYS", "0").to_i

  # Human-facing application name, shown in the UI and in emails.
  portal.app_name = ENV.fetch("APP_NAME", "File Sharing Portal")

  # Canonical host used to build absolute URLs in emails and share links.
  portal.host = ENV["APP_HOST"].presence
end
