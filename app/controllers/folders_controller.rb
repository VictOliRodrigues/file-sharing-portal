class FoldersController < ApplicationController
  before_action :set_folder, only: %i[show update destroy]
  before_action :set_discarded_folder, only: %i[restore purge]

  # Browses one folder: its subfolders first, then its files.
  def show
    @folders = owned_folders.kept.where(parent_id: @folder.id).ordered
    @stored_files = current_user.stored_files.kept.in_folder(@folder).ordered
    @breadcrumbs = @folder.breadcrumbs
    @move_targets = move_targets(excluding: @folder)

    render "folders/browse"
  end

  def create
    @folder = owned_folders.new(folder_params)

    if @folder.save
      redirect_to folder_path(@folder), notice: "Folder created."
    else
      redirect_back_or_to files_path, alert: @folder.errors.full_messages.to_sentence
    end
  end

  def update
    if @folder.update(folder_params)
      redirect_to folder_path(@folder), notice: "Folder updated."
    else
      redirect_back_or_to folder_path(@folder), alert: @folder.errors.full_messages.to_sentence
    end
  end

  def destroy
    parent = @folder.parent
    @folder.discard!

    redirect_to parent ? folder_path(parent) : files_path,
                notice: "#{@folder.name} and its contents were moved to the trash."
  end

  def restore
    @folder.undiscard!
    redirect_to trash_path, notice: "#{@folder.name} restored."
  end

  def purge
    name = @folder.name
    @folder.purge!
    redirect_to trash_path, notice: "#{name} and its contents were deleted permanently."
  end

  private
    def owned_folders
      current_user.folders
    end

    def set_folder
      @folder = owned_folders.kept.find(params[:id])
    end

    def set_discarded_folder
      @folder = owned_folders.discarded.find(params[:id])
    end

    def folder_params
      # parent_id is validated against the owner's own tree in the model.
      params.expect(folder: [ :name, :parent_id ])
    end

    # Folders the given record may be moved into: everything the user owns,
    # minus the folder itself and its own descendants.
    def move_targets(excluding: nil)
      scope = owned_folders.kept.ordered
      scope = scope.where.not(id: excluding.self_and_descendant_ids) if excluding

      scope
    end
end
