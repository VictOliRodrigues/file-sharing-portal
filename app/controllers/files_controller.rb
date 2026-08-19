class FilesController < ApplicationController
  before_action :set_stored_file, only: %i[show update destroy]
  before_action :set_discarded_file, only: %i[restore purge]

  # The root of the drive: folders and files that have no parent.
  def index
    @folder = nil
    @folders = current_user.folders.kept.roots.ordered
    @stored_files = owned_files.kept.in_folder(nil).ordered
    @breadcrumbs = []
    @move_targets = current_user.folders.kept.ordered

    render "folders/browse"
  end

  def new
    @folder = find_optional_folder(params[:folder_id])
    @stored_file = owned_files.new
  end

  def show
    @downloads = @stored_file.downloads.recent.limit(10)
    @move_targets = current_user.folders.kept.ordered
  end

  def create
    folder = find_optional_folder(params[:folder_id])
    uploads = Array(params[:files]).reject(&:blank?)
    destination = folder ? folder_path(folder) : files_path

    if uploads.empty?
      redirect_to new_file_path(folder_id: folder&.id), alert: "Choose at least one file to upload."
      return
    end

    stored, rejected = store(uploads, folder)

    if rejected.empty?
      redirect_to destination, notice: "#{helpers.pluralize(stored.size, "file")} uploaded."
    elsif stored.any?
      redirect_to destination,
                  alert: "Uploaded #{stored.size} of #{uploads.size} files. #{rejected.join(' ')}"
    else
      redirect_to new_file_path(folder_id: folder&.id), alert: rejected.join(" ")
    end
  end

  # Handles both renaming and moving between folders.
  def update
    if @stored_file.update(file_params)
      redirect_back_or_to file_path(@stored_file), notice: "File updated."
    else
      redirect_back_or_to file_path(@stored_file),
                          alert: @stored_file.errors.full_messages.to_sentence
    end
  end

  def destroy
    folder = @stored_file.folder
    @stored_file.discard!

    redirect_back_or_to(folder ? folder_path(folder) : files_path,
                        notice: "#{@stored_file.name} moved to the trash.")
  end

  def restore
    # A file whose folder is still in the trash comes back to the root so that
    # it can never end up somewhere the owner cannot reach.
    @stored_file.folder = nil if @stored_file.folder&.deleted?
    @stored_file.undiscard!

    redirect_to trash_path, notice: "#{@stored_file.name} restored."
  end

  def purge
    name = @stored_file.name
    @stored_file.purge!
    redirect_to trash_path, notice: "#{name} deleted permanently."
  end

  private
    # Every lookup goes through the signed-in user's own files, so a record that
    # belongs to somebody else raises RecordNotFound and is answered with a 404.
    def owned_files
      current_user.stored_files
    end

    def set_stored_file
      @stored_file = owned_files.kept.find(params[:id])
    end

    def set_discarded_file
      @stored_file = owned_files.discarded.find(params[:id])
    end

    def find_optional_folder(id)
      return nil if id.blank?

      current_user.folders.kept.find(id)
    end

    def file_params
      # Size, type and owner are derived from the stored blob and can never be
      # set from a form. A folder_id outside the owner's tree fails validation.
      params.expect(stored_file: [ :name, :folder_id ])
    end

    def store(uploads, folder)
      stored = []
      rejected = []

      uploads.each do |upload|
        stored_file = owned_files.new(folder: folder)
        stored_file.attachment.attach(upload)

        if stored_file.save
          stored << stored_file
        else
          rejected << "#{SafeFilename.call(upload.original_filename)}: " \
                      "#{stored_file.errors.full_messages.to_sentence}."
        end
      end

      [ stored, rejected ]
    end
end
