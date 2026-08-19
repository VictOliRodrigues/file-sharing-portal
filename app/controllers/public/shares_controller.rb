# The only part of the portal reachable without an account.
#
# Everything is resolved through the share link itself: the link decides what
# exists, and ShareLink#contains? is the single gate that stops a recipient from
# walking out of the shared folder into the rest of the owner's drive.
class Public::SharesController < ApplicationController
  include ShareLinkAccess

  layout "public"

  # The password form has to stay reachable while the link is still locked.
  skip_before_action :require_unlocked_link, only: %i[locked unlock]

  def show
    @share_link.touch_access!

    if @share_link.file_share?
      @stored_file = @share_link.shareable
      render :file
    else
      @folder = @share_link.shareable
      render_folder
    end
  end

  # Browsing a subfolder of a shared folder.
  def folder
    @folder = shared_folder(params[:folder_id])
    return render_unavailable if @folder.nil?

    render_folder
  end

  def locked
  end

  def unlock
    if @share_link.password_protected? &&
       @share_link.authenticate_password(params[:password].to_s)
      unlocked_share_link_ids << @share_link.id
      redirect_to share_path(@share_link.token)
    else
      redirect_to locked_share_path(@share_link.token), alert: "Incorrect password."
    end
  end

  private
    def render_folder
      @folders = @share_link.folders_in(@folder)
      @stored_files = @share_link.files_in(@folder)
      @breadcrumbs = folder_breadcrumbs(@folder)

      render :folder
    end

    # Ancestors are trimmed at the shared root, so a recipient never learns
    # about the folders above whatever was shared with them.
    def folder_breadcrumbs(folder)
      root = @share_link.shareable
      folder.breadcrumbs.drop_while { |crumb| crumb.id != root.id }
    end
end
