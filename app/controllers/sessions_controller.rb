class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  require_signed_out only: %i[new create]

  def new
  end

  def create
    user = User.authenticate_by(email_address: params[:email_address], password: params[:password])

    if user.nil?
      # Deliberately identical for unknown accounts and wrong passwords so the
      # form cannot be used to discover which addresses are registered.
      redirect_to sign_in_path, alert: "Incorrect email address or password."
    elsif user.disabled?
      # Safe to be specific: the correct password has already been supplied.
      redirect_to sign_in_path, alert: "This account has been disabled. Contact an administrator."
    else
      start_new_session_for(user)
      redirect_to after_authentication_url, notice: "Welcome back, #{user.name}."
    end
  end

  def destroy
    terminate_session
    redirect_to sign_in_path, notice: "You have been signed out."
  end
end
