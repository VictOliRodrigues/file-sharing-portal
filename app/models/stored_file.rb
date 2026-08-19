# A file uploaded by a user.
#
# The bytes live in Active Storage; this record holds the metadata the portal
# needs to list, search, authorize and account for them. Size and content type
# are denormalized from the blob so that listings and the dashboard never have
# to join the Active Storage tables.
class StoredFile < ApplicationRecord
  DEFAULT_CONTENT_TYPE = "application/octet-stream".freeze

  # Coarse grouping used by the type filter in search.
  CATEGORIES = {
    "image"    => %w[image/],
    "video"    => %w[video/],
    "audio"    => %w[audio/],
    "document" => %w[
      application/pdf application/msword application/vnd. application/rtf
      application/json application/xml text/
    ],
    "archive"  => %w[
      application/zip application/x-tar application/gzip application/x-bzip2
      application/x-7z-compressed application/vnd.rar application/x-rar-compressed
    ]
  }.freeze

  belongs_to :user

  has_one_attached :attachment
  has_many :downloads, dependent: :destroy

  before_validation :apply_attachment_metadata

  validates :name, presence: true, length: { maximum: 255 }
  validates :content_type, presence: true, length: { maximum: 255 }
  validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
  validate  :name_must_not_contain_a_path
  validate  :attachment_must_be_present
  validate  :attachment_within_size_limit
  validate  :attachment_type_must_be_allowed
  validate  :owner_must_be_within_quota, on: :create

  scope :kept,      -> { where(deleted_at: nil) }
  scope :discarded, -> { where.not(deleted_at: nil) }
  scope :recent,    -> { order(created_at: :desc) }
  scope :ordered,   -> { order(Arel.sql("LOWER(name) ASC")) }

  scope :named_like, ->(term) {
    next all if term.blank?
    where("stored_files.name ILIKE ?", "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  scope :of_category, ->(category) {
    prefixes = CATEGORIES[category.to_s]
    next all if prefixes.blank?

    conditions = prefixes.map { "content_type LIKE ?" }.join(" OR ")
    where(conditions, *prefixes.map { |prefix| "#{sanitize_sql_like(prefix)}%" })
  }

  # --- Soft delete ---------------------------------------------------------

  def deleted?
    deleted_at.present?
  end

  def discard!
    update!(deleted_at: Time.current)
  end

  def undiscard!
    update!(deleted_at: nil)
  end

  # Removes the record and the stored bytes for good.
  def purge!
    attachment.purge
    destroy!
  end

  # --- Presentation --------------------------------------------------------

  def category
    CATEGORIES.each do |name, prefixes|
      return name if prefixes.any? { |prefix| content_type.start_with?(prefix) }
    end
    "other"
  end

  def previewable_image?
    Rails.application.config.active_storage.content_types_allowed_inline.include?(content_type)
  end

  def extension
    File.extname(name).delete_prefix(".").downcase.presence
  end

  # --- Download accounting -------------------------------------------------

  def record_download!(user: nil, ip_address: nil)
    transaction do
      downloads.create!(user: user, ip_address: ip_address, created_at: Time.current)
      update_columns(
        download_count: download_count + 1,
        last_downloaded_at: Time.current
      )
    end
  end

  private
    # Copies the trustworthy metadata off the blob. The content type comes from
    # Active Storage, which sniffs the actual bytes with Marcel rather than
    # believing the type declared by the client. The name is re-sanitized on
    # every save, so a rename cannot smuggle a path in either.
    def apply_attachment_metadata
      return unless attachment.attached?

      blob = attachment.blob
      self.byte_size = blob.byte_size.to_i
      self.content_type = blob.content_type.presence || DEFAULT_CONTENT_TYPE
      self.name = SafeFilename.call(name.presence || blob.filename.to_s)
    end

    # Belt and braces: nothing that reached this point should still contain a
    # separator, but a stored name is echoed back in download headers.
    def name_must_not_contain_a_path
      return if name.blank?
      return unless name.include?(SafeFilename::SEPARATOR) || name.include?(SafeFilename::BACKSLASH)

      errors.add(:name, "cannot contain a path separator")
    end

    def attachment_must_be_present
      errors.add(:attachment, "must be provided") unless attachment.attached?
    end

    def attachment_within_size_limit
      return unless attachment.attached?

      limit = Rails.application.config.x.portal.max_upload_size
      return if limit.to_i.zero? || byte_size.to_i <= limit

      errors.add(:attachment, "is larger than the #{ActiveSupport::NumberHelper.number_to_human_size(limit)} limit")
    end

    def attachment_type_must_be_allowed
      return unless attachment.attached?
      return if UploadPolicy.allows?(name: name, content_type: content_type)

      errors.add(:attachment, "type is not accepted by this server")
    end

    def owner_must_be_within_quota
      return unless attachment.attached?
      return if user.nil?

      quota = user.storage_quota
      return if quota.nil?
      return if user.storage_used + byte_size.to_i <= quota

      errors.add(:base, "Storage quota exceeded. Delete some files and try again.")
    end
end
