class Profile::SessionsController < ApplicationController
  def index
    @sessions = current_user.sessions.ordered
  end

  def destroy
    # Scoped to the current user, so one account can never revoke another's session.
    session_record = current_user.sessions.find(params[:id])
    current = session_record.id == Current.session.id
    session_record.destroy

    if current
      cookies.delete(:session_id)
      redirect_to sign_in_path, notice: "You have been signed out."
    else
      redirect_to profile_sessions_path, notice: "That session has been signed out."
    end
  end
end
