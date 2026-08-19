class ShareLinksController < ApplicationController
  before_action :set_share_link, only: %i[show destroy]

  def index
    @share_links = current_user.share_links
      .includes(:shareable)
      .recent
  end

  def show
  end

  def create
    @share_link = current_user.share_links.new(share_link_params)
    @share_link.shareable = find_shareable

    if @share_link.shareable.nil?
      redirect_back_or_to files_path, alert: "Choose something to share."
    elsif @share_link.save
      redirect_to share_link_path(@share_link), notice: "Share link created."
    else
      redirect_back_or_to files_path, alert: @share_link.errors.full_messages.to_sentence
    end
  end

  # Revoking keeps the record so the owner can still see that the link existed
  # and how often it was used.
  def destroy
    @share_link.revoke!
    redirect_to share_links_path, notice: "Share link revoked."
  end

  private
    def set_share_link
      @share_link = current_user.share_links.find_by!(token: params[:id])
    end

    def share_link_params
      # Every restriction is optional, so a request that omits the whole
      # share_link key is treated as a link with no restrictions.
      raw = params[:share_link] || ActionController::Parameters.new
      permitted = raw.permit(:expires_at, :download_limit, :password)

      permitted[:password] = permitted[:password].presence
      permitted[:download_limit] = permitted[:download_limit].presence
      permitted[:expires_at] = permitted[:expires_at].presence
      permitted
    end

    # Resolved through the owner's own records, so a share link can never be
    # created for somebody else's file or folder.
    def find_shareable
      if params[:stored_file_id].present?
        current_user.stored_files.kept.find_by(id: params[:stored_file_id])
      elsif params[:folder_id].present?
        current_user.folders.kept.find_by(id: params[:folder_id])
      end
    end
end
