namespace :portal do
  desc "Permanently delete trashed files and folders older than TRASH_RETENTION_DAYS"
  task purge_trash: :environment do
    days = ENV.fetch("TRASH_RETENTION_DAYS", "30").to_i

    if days <= 0
      puts "TRASH_RETENTION_DAYS is #{days}; nothing is purged automatically."
      next
    end

    cutoff = days.days.ago

    folders = Folder.discarded.where(deleted_at: ...cutoff)
    files = StoredFile.discarded.where(deleted_at: ...cutoff)

    folder_count = folders.count
    file_count = files.count

    # Folders first: purging a folder also purges the files inside it.
    folders.find_each(&:purge!)
    StoredFile.discarded.where(deleted_at: ...cutoff).find_each(&:purge!)

    puts "Purged #{folder_count} folders and up to #{file_count} files deleted before #{cutoff}."
  end

  desc "Remove Active Storage blobs that are no longer attached to anything"
  task purge_orphan_blobs: :environment do
    count = ActiveStorage::Blob.unattached.count
    ActiveStorage::Blob.unattached.find_each(&:purge)

    puts "Purged #{count} unattached blobs."
  end

  desc "Print deployment usage statistics"
  task stats: :environment do
    statistics = SystemStatistics.new

    puts "Users:        #{statistics.users_count} " \
         "(#{statistics.active_users} active, #{statistics.disabled_users} disabled)"
    puts "Files:        #{statistics.files_count} (#{statistics.trashed_files} in trash)"
    puts "Folders:      #{statistics.folders_count}"
    puts "Storage:      #{ActiveSupport::NumberHelper.number_to_human_size(statistics.storage_used)}"
    puts "Share links:  #{statistics.share_links_count} (#{statistics.active_share_links} active)"
    puts "Downloads:    #{statistics.downloads_count}"
  end
end
