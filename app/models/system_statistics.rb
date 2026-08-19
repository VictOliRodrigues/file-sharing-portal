# Deployment-wide numbers for the administration dashboard.
#
# Every value is a plain aggregate query. Nothing here is cached, because the
# page is only ever seen by administrators.
class SystemStatistics
  TOP_USERS_LIMIT = 10
  RECENT_WINDOW = 30.days

  def users_count      = User.count
  def active_users     = User.active.count
  def disabled_users   = User.disabled.count
  def administrators   = User.administrators.count

  def files_count      = StoredFile.kept.count
  def trashed_files    = StoredFile.discarded.count
  def folders_count    = Folder.kept.count

  def storage_used     = StoredFile.sum(:byte_size)
  def storage_in_trash = StoredFile.discarded.sum(:byte_size)

  # What the object store actually holds, including blobs that are still
  # waiting to be purged.
  def blob_storage_used = ActiveStorage::Blob.sum(:byte_size)

  def share_links_count  = ShareLink.count
  def active_share_links = ShareLink.active.reject(&:expired?).reject(&:limit_reached?).size
  def revoked_share_links = ShareLink.revoked.count

  def downloads_count = Download.count

  def share_downloads_count
    Download.where.not(share_link_id: nil).count
  end

  def recent_downloads_count
    Download.where(created_at: RECENT_WINDOW.ago..).count
  end

  def recent_uploads_count
    StoredFile.where(created_at: RECENT_WINDOW.ago..).count
  end

  def new_users_count
    User.where(created_at: RECENT_WINDOW.ago..).count
  end

  # Accounts using the most storage, largest first.
  def top_users_by_storage
    StoredFile
      .group(:user_id)
      .order(Arel.sql("SUM(byte_size) DESC"))
      .limit(TOP_USERS_LIMIT)
      .sum(:byte_size)
      .filter_map { |user_id, bytes| [ users_by_id[user_id], bytes ] if users_by_id[user_id] }
  end

  def files_by_category
    StoredFile.kept.group(:content_type).sum(:byte_size).each_with_object(Hash.new(0)) do |(type, bytes), totals|
      totals[category_for(type)] += bytes
    end
  end

  private
    def users_by_id
      @users_by_id ||= User.all.index_by(&:id)
    end

    def category_for(content_type)
      StoredFile::CATEGORIES.each do |name, prefixes|
        return name if prefixes.any? { |prefix| content_type.to_s.start_with?(prefix) }
      end
      "other"
    end
end
