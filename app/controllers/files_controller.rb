class FilesController < ApplicationController
  before_action :set_stored_file, only: %i[show update destroy]
  before_action :set_discarded_file, only: %i[restore purge]

  def index
    @stored_files = owned_files.kept.ordered
  end

  def new
    @stored_file = current_user.stored_files.new
  end

  def show
    @downloads = @stored_file.downloads.recent.limit(10)
  end

  def create
    uploads = Array(params[:files]).reject(&:blank?)

    if uploads.empty?
      redirect_to new_file_path, alert: "Choose at least one file to upload."
      return
    end

    stored, rejected = store(uploads)

    if rejected.empty?
      redirect_to files_path, notice: "#{helpers.pluralize(stored.size, "file")} uploaded."
    elsif stored.any?
      redirect_to files_path,
                  alert: "Uploaded #{stored.size} of #{uploads.size} files. #{rejected.join(' ')}"
    else
      redirect_to new_file_path, alert: rejected.join(" ")
    end
  end

  def update
    if @stored_file.update(rename_params)
      redirect_back_or_to file_path(@stored_file), notice: "File renamed."
    else
      redirect_back_or_to file_path(@stored_file),
                          alert: @stored_file.errors.full_messages.to_sentence
    end
  end

  def destroy
    @stored_file.discard!
    redirect_back_or_to files_path, notice: "#{@stored_file.name} moved to the trash."
  end

  def restore
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

    def rename_params
      # Only the display name may be changed here; size, type and owner are
      # derived from the stored blob.
      params.expect(stored_file: [ :name ])
    end

    def store(uploads)
      stored = []
      rejected = []

      uploads.each do |upload|
        stored_file = current_user.stored_files.new
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
