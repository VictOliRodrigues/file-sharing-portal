# Cookie based session authentication.
#
# The browser stores only the session record's id, inside a signed HttpOnly
# cookie. Every request looks the session up again, which means revoking a
# session (sign out, password change, account disabled) takes effect at once.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    # Marks actions that visitors may reach without signing in.
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Marks actions that must only ever be reached by signed-out visitors, such
    # as the sign in and sign up forms.
    def require_signed_out(**options)
      before_action :redirect_if_authenticated, **options
    end
  end

  private
    def authenticated?
      resume_session.present?
    end

    def current_user
      Current.user
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      session_id = cookies.signed[:session_id]
      return nil if session_id.blank?

      session = Session.includes(:user).find_by(id: session_id)

      # A session that outlived its user, or whose user has been suspended, is
      # not a valid session.
      if session.nil? || session.user.disabled?
        terminate_session
        return nil
      end

      session
    end

    def request_authentication
      # HEAD is routed like GET, so treat both as a navigation worth resuming.
      session[:return_to_after_authenticating] = request.url if request.get? || request.head?
      redirect_to sign_in_path, alert: "Please sign in to continue."
    end

    def redirect_if_authenticated
      redirect_to root_path if resume_session
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_path
    end

    def start_new_session_for(user)
      # Rotate the Rails session on privilege change to defeat session fixation.
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to

      user.sessions.create!(
        user_agent: request.user_agent.to_s.truncate(255),
        ip_address: request.remote_ip
      ).tap do |new_session|
        Current.session = new_session
        user.update_column(:last_signed_in_at, Time.current)
        cookies.signed.permanent[:session_id] = {
          value: new_session.id,
          httponly: true,
          same_site: :lax,
          secure: request.ssl?
        }
      end
    end

    def terminate_session
      Current.session&.destroy
      Current.session = nil
      cookies.delete(:session_id)
    end
end
