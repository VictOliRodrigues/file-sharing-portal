# Coarse grained authorization helpers.
#
# Record level authorization is not done with a policy layer: every query is
# scoped through the signed-in user's associations instead, so a record that
# does not belong to the current user simply cannot be loaded. This concern only
# covers the administrator area.
module Authorization
  extend ActiveSupport::Concern

  # Raised when a signed-in user tries to reach something they may not touch.
  class NotAuthorized < StandardError; end

  included do
    helper_method :administrator?
    rescue_from NotAuthorized, with: :deny_access
  end

  private
    def administrator?
      current_user&.admin?
    end

    def require_administrator
      raise NotAuthorized unless administrator?
    end

    def deny_access
      respond_to do |format|
        format.html { redirect_to root_path, alert: "You are not allowed to do that." }
        format.any  { head :forbidden }
      end
    end
end
