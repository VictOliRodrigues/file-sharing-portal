class User < ApplicationRecord
  # Minimum accepted password length. Long passphrases are preferred over
  # composition rules, which mostly push people towards predictable patterns.
  MINIMUM_PASSWORD_LENGTH = 12

  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :stored_files, dependent: :destroy
  has_many :downloads, dependent: :nullify
  has_many :share_links, dependent: :destroy

  normalizes :email_address, with: ->(value) { value.to_s.strip.downcase }
  normalizes :name, with: ->(value) { value.to_s.strip }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email_address,
            presence: true,
            length: { maximum: 255 },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  validates :storage_quota_bytes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(disabled_at: nil) }
  scope :disabled, -> { where.not(disabled_at: nil) }
  scope :administrators, -> { where(admin: true) }
  scope :ordered, -> { order(:name) }

  # Password reset tokens are derived from the current password digest, so a
  # token stops working as soon as the password changes or another reset is
  # completed. They are single use in practice and short lived.
  generates_token_for :password_reset, expires_in: 30.minutes do
    password_salt&.last(10)
  end

  def disabled?
    disabled_at.present?
  end

  def active?
    !disabled?
  end

  def disable!
    transaction do
      update!(disabled_at: Time.current)
      # Revoke every signed-in session immediately.
      sessions.destroy_all
    end
  end

  def enable!
    update!(disabled_at: nil)
  end

  # Effective quota in bytes, or nil when the account has no limit.
  def storage_quota
    quota = storage_quota_bytes || Rails.application.config.x.portal.default_storage_quota
    quota.to_i.zero? ? nil : quota.to_i
  end

  # Bytes currently occupied by this account. Files in the trash are counted,
  # because their bytes are still stored until they are purged.
  def storage_used
    stored_files.sum(:byte_size)
  end

  def storage_used_percentage
    quota = storage_quota
    return nil if quota.nil? || quota.zero?

    [ (storage_used.to_f / quota * 100).round, 100 ].min
  end

  def to_s
    name
  end
end
