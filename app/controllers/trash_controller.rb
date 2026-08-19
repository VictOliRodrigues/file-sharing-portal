class TrashController < ApplicationController
  def show
    @stored_files = current_user.stored_files.discarded.order(deleted_at: :desc)
    # Only the topmost deleted folder of each branch is listed: restoring it
    # brings everything underneath it back in one go.
    @folders = current_user.folders.discarded.order(deleted_at: :desc).reject do |folder|
      folder.parent&.deleted?
    end
    # Files that went to the trash together with a folder are represented by
    # that folder, so they are not listed twice.
    deleted_folder_ids = current_user.folders.discarded.pluck(:id)
    @stored_files = @stored_files.reject do |stored_file|
      stored_file.folder_id.in?(deleted_folder_ids) &&
        stored_file.deleted_at == stored_file.folder&.deleted_at
    end
  end
end
