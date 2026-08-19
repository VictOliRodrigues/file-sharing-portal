class DashboardController < ApplicationController
  RECENT_LIMIT = 8

  def show
    files = current_user.stored_files

    @total_files = files.kept.count
    @trashed_files = files.discarded.count
    @storage_used = current_user.storage_used
    @storage_quota = current_user.storage_quota

    @recent_uploads = files.kept.recent.limit(RECENT_LIMIT)
    @recent_downloads = Download
      .joins(:stored_file)
      .where(stored_files: { user_id: current_user.id })
      .includes(:stored_file, :user)
      .recent
      .limit(RECENT_LIMIT)
  end
end
