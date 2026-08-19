class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  require_signed_out
  before_action :ensure_registration_enabled

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    # The very first account to be created owns the deployment. Every later
    # sign up is an ordinary user.
    @user.admin = true if User.none?

    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Welcome to #{portal_name}, #{@user.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.expect(user: [ :name, :email_address, :password, :password_confirmation ])
    end

    def ensure_registration_enabled
      return if Rails.application.config.x.portal.registration_enabled
      # Always allow the deployment to bootstrap its first administrator.
      return if User.none?

      redirect_to sign_in_path, alert: "Registration is disabled on this server."
    end

    def portal_name
      Rails.application.config.x.portal.app_name
    end
end
