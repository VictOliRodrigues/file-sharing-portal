# Resolves a public share link and everything reachable through it.
#
# Included by every controller that serves a share link, so that the rules for
# availability, password unlocking and containment are defined in exactly one
# place.
module ShareLinkAccess
  extend ActiveSupport::Concern

  included do
    allow_unauthenticated_access

    before_action :set_share_link
    before_action :require_available_link
    before_action :require_unlocked_link
  end

  private
    def set_share_link
      @share_link = ShareLink.find_by(token: params[:token])

      # An unknown, revoked or expired token all produce the same response, so
      # a probe can never confirm that a token exists.
      render_unavailable if @share_link.nil?
    end

    def require_available_link
      render_unavailable unless @share_link.available?
    end

    def require_unlocked_link
      return unless @share_link.password_protected?
      return if unlocked_share_link_ids.include?(@share_link.id)

      redirect_to locked_share_path(@share_link.token)
    end

    def unlocked_share_link_ids
      session[:unlocked_share_links] ||= []
    end

    # Resolves a folder inside the share, or nil when the folder is outside it.
    def shared_folder(id)
      folder = Folder.find_by(id: id)
      @share_link.contains?(folder) ? folder : nil
    end

    # Resolves a file inside the share, or nil when the file is outside it.
    def shared_file(id)
      stored_file = StoredFile.find_by(id: id)
      @share_link.contains?(stored_file) ? stored_file : nil
    end

    def render_unavailable
      render "public/shares/unavailable", status: :not_found, layout: "public"
    end
end
