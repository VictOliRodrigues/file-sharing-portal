class SearchesController < ApplicationController
  def show
    # Resolved through the signed-in user's own folders, so the filter can
    # never point at somebody else's tree.
    @folder = current_user.folders.kept.find_by(id: params[:folder_id])

    @search = FileSearch.new(
      user: current_user,
      term: params[:q],
      folder: @folder,
      category: params[:type]
    )

    @stored_files = @search.files
    @folders = @search.folders
    @folder_options = current_user.folders.kept.ordered
  end
end
