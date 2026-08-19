class ApplicationController < ActionController::Base
  include Authentication
  include Authorization

  # Reject requests from browsers that cannot run the front-end.
  allow_browser versions: :modern

  # Cross-site request forgery protection. Rails enables this by default for
  # non-GET requests; raising instead of silently resetting the session makes
  # failures visible rather than confusing.
  protect_from_forgery with: :exception

  before_action :set_current_request_details

  # Never reveal whether a record exists when the visitor may not see it.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private
    def set_current_request_details
      Current.ip_address = request.remote_ip
      Current.user_agent = request.user_agent
    end

    def render_not_found
      respond_to do |format|
        format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
        format.any  { head :not_found }
      end
    end
end
