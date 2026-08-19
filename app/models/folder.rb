# A folder in a user's drive.
#
# Folders form a tree per user. A folder with no parent sits at the root. The
# tree is only ever traversed within the owner's own records, so one account can
# never reach another account's structure.
class Folder < ApplicationRecord
  # Guard against pathological nesting, which would otherwise make breadcrumb
  # rendering and recursive deletes expensive.
  MAX_DEPTH = 20

  belongs_to :user
  belongs_to :parent, class_name: "Folder", optional: true

  has_many :children, class_name: "Folder", foreign_key: :parent_id, dependent: :destroy,
           inverse_of: :parent
  has_many :stored_files, dependent: :nullify

  normalizes :name, with: ->(value) { SafeFilename.call(value) }

  validates :name, presence: true, length: { maximum: 255 }
  validate :parent_must_belong_to_the_same_user
  validate :parent_must_not_create_a_cycle
  validate :depth_must_be_within_the_limit
  validate :name_must_be_unique_among_siblings

  scope :kept,      -> { where(deleted_at: nil) }
  scope :discarded, -> { where.not(deleted_at: nil) }
  scope :roots,     -> { where(parent_id: nil) }
  scope :ordered,   -> { order(Arel.sql("LOWER(name) ASC")) }

  # --- Tree ----------------------------------------------------------------

  # The folder itself plus every folder underneath it, resolved in one query.
  def self_and_descendant_ids
    return [ id ] if new_record?

    self.class.connection.select_values(
      self.class.sanitize_sql_array([ <<~SQL.squish, id, user_id ])
        WITH RECURSIVE tree AS (
          SELECT id FROM folders WHERE id = ?
          UNION ALL
          SELECT folders.id FROM folders JOIN tree ON folders.parent_id = tree.id
        )
        SELECT tree.id FROM tree
        JOIN folders ON folders.id = tree.id
        WHERE folders.user_id = ?
      SQL
    ).map(&:to_i)
  end

  def descendant_ids
    self_and_descendant_ids - [ id ]
  end

  # Root first, this folder last.
  def ancestors
    chain = []
    node = parent
    depth = 0

    while node && depth < MAX_DEPTH
      chain.unshift(node)
      node = node.parent
      depth += 1
    end

    chain
  end

  def breadcrumbs
    ancestors + [ self ]
  end

  def depth
    ancestors.size
  end

  def root?
    parent_id.nil?
  end

  # --- Soft delete ---------------------------------------------------------

  def deleted?
    deleted_at.present?
  end

  # Deleting a folder deletes everything inside it in one operation. The shared
  # timestamp is what makes an exact restore possible later.
  def discard!(timestamp = Time.current)
    ids = self_and_descendant_ids

    transaction do
      StoredFile.where(folder_id: ids, deleted_at: nil).update_all(deleted_at: timestamp)
      self.class.where(id: ids, deleted_at: nil).update_all(deleted_at: timestamp, updated_at: timestamp)
    end

    reload
  end

  # Restores exactly what was removed by the matching discard!, leaving records
  # that had already been deleted beforehand in the trash.
  def undiscard!
    timestamp = deleted_at
    return if timestamp.nil?

    ids = self_and_descendant_ids

    transaction do
      # A folder whose parent is still in the trash comes back to the root, so
      # that restoring can never leave an unreachable record behind.
      update_columns(parent_id: nil) if parent && parent.deleted?

      StoredFile.where(folder_id: ids, deleted_at: timestamp).update_all(deleted_at: nil)
      self.class.where(id: ids, deleted_at: timestamp).update_all(deleted_at: nil, updated_at: Time.current)
    end

    reload
  end

  # Removes the folder, everything below it and the stored bytes for good.
  def purge!
    ids = self_and_descendant_ids

    transaction do
      StoredFile.where(folder_id: ids).find_each(&:purge!)
      self.class.where(id: ids).delete_all
    end
  end

  # --- Contents ------------------------------------------------------------

  def total_byte_size
    StoredFile.where(folder_id: self_and_descendant_ids).kept.sum(:byte_size)
  end

  def to_s
    name
  end

  private
    def parent_must_belong_to_the_same_user
      return if parent.nil?
      return if parent.user_id == user_id

      errors.add(:parent, "does not exist")
    end

    def parent_must_not_create_a_cycle
      return if parent.nil? || new_record?

      if parent_id == id
        errors.add(:parent, "cannot be the folder itself")
      elsif self_and_descendant_ids.include?(parent_id)
        errors.add(:parent, "cannot be a folder inside this one")
      end
    end

    def depth_must_be_within_the_limit
      return if parent.nil?
      return if parent.depth + 1 < MAX_DEPTH

      errors.add(:base, "Folders cannot be nested more than #{MAX_DEPTH} levels deep")
    end

    def name_must_be_unique_among_siblings
      return if name.blank? || user_id.nil?

      duplicate = self.class.kept
        .where(user_id: user_id, parent_id: parent_id)
        .where("LOWER(name) = ?", name.downcase)
        .where.not(id: id)
        .exists?

      errors.add(:name, "is already used in this folder") if duplicate
    end
end
