# A public link that gives access to one file or one folder without an account.
#
# The token is the only credential, so it is generated from a cryptographically
# secure source and is long enough that guessing is not feasible. A link can
# additionally be protected by a password, an expiry date and a download limit,
# and it can be revoked at any time.
class ShareLink < ApplicationRecord
  # Length of the generated token in base58 characters, which is well over 200
  # bits of entropy.
  TOKEN_LENGTH = 48

  # Reasons a link may refuse to serve anything. Exposed so the public pages can
  # explain what happened without leaking whether the token ever existed.
  UNAVAILABLE_REASONS = %i[revoked expired limit_reached].freeze

  belongs_to :user
  belongs_to :shareable, polymorphic: true

  has_many :downloads, dependent: :nullify

  # A password is entirely optional, so the built-in presence validations are
  # switched off and length is checked explicitly instead.
  has_secure_password :password, validations: false

  before_validation :generate_token, on: :create

  validates :token, presence: true, uniqueness: true, length: { maximum: 64 }
  validates :download_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :password, length: { minimum: 6, maximum: 72 }, allow_nil: true
  validate  :shareable_must_belong_to_the_creator
  validate  :expiry_must_be_in_the_future, on: :create
  validate  :expiry_must_be_within_the_server_limit

  scope :active,  -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }

  def to_param
    token
  end

  # --- Availability --------------------------------------------------------

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def limit_reached?
    download_limit.present? && download_count >= download_limit
  end

  def available?
    unavailable_reason.nil?
  end

  def unavailable_reason
    return :revoked if revoked?
    return :expired if expired?
    return :limit_reached if limit_reached?

    nil
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def password_protected?
    password_digest.present?
  end

  def remaining_downloads
    return nil if download_limit.nil?

    [ download_limit - download_count, 0 ].max
  end

  # --- Contents ------------------------------------------------------------

  def file_share?
    shareable_type == "StoredFile"
  end

  def folder_share?
    shareable_type == "Folder"
  end

  # The single guard against traversal out of a shared folder. Every public
  # request resolves its target through this method, so a recipient can never
  # reach a record that is not inside what was actually shared.
  def contains?(record)
    return false if record.nil?
    return false if record.respond_to?(:deleted?) && record.deleted?
    return false if record.user_id != user_id

    case record
    when StoredFile
      return record.id == shareable_id if file_share?

      record.folder_id.present? && shared_folder_ids.include?(record.folder_id)
    when Folder
      folder_share? && shared_folder_ids.include?(record.id)
    else
      false
    end
  end

  def files_in(folder)
    return StoredFile.none unless folder_share? && contains?(folder)

    user.stored_files.kept.in_folder(folder).ordered
  end

  def folders_in(folder)
    return Folder.none unless folder_share? && contains?(folder)

    user.folders.kept.where(parent_id: folder.id).ordered
  end

  # --- Accounting ----------------------------------------------------------

  def record_download!(stored_file, ip_address: nil)
    transaction do
      stored_file.downloads.create!(share_link: self, ip_address: ip_address, created_at: Time.current)
      stored_file.update_columns(
        download_count: stored_file.download_count + 1,
        last_downloaded_at: Time.current
      )
      update_columns(
        download_count: download_count + 1,
        last_accessed_at: Time.current
      )
    end
  end

  def touch_access!
    update_column(:last_accessed_at, Time.current)
  end

  private
    def shared_folder_ids
      @shared_folder_ids ||= folder_share? ? shareable.self_and_descendant_ids : []
    end

    def generate_token
      self.token ||= self.class.generate_unique_secure_token(length: TOKEN_LENGTH)
    end

    def shareable_must_belong_to_the_creator
      return if shareable.nil?

      if shareable.user_id != user_id
        errors.add(:shareable, "does not exist")
      elsif shareable.respond_to?(:deleted?) && shareable.deleted?
        errors.add(:shareable, "is in the trash")
      end
    end

    def expiry_must_be_in_the_future
      return if expires_at.blank?
      return if expires_at > Time.current

      errors.add(:expires_at, "must be in the future")
    end

    def expiry_must_be_within_the_server_limit
      maximum_days = Rails.application.config.x.portal.max_share_link_days.to_i
      return if maximum_days.zero?

      if expires_at.blank?
        errors.add(:expires_at, "is required on this server")
      elsif expires_at > maximum_days.days.from_now
        errors.add(:expires_at, "cannot be more than #{maximum_days} days from now")
      end
    end
end
