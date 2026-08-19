class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]

  # Shown to everybody, whether or not the address is registered.
  CONFIRMATION_NOTICE = "If that email address is registered, password reset " \
                        "instructions have been sent to it.".freeze

  def new
  end

  def create
    if (user = User.active.find_by(email_address: params[:email_address]))
      PasswordsMailer.reset(user).deliver_later
    end

    # The same response either way, so the form cannot enumerate accounts.
    redirect_to sign_in_path, notice: CONFIRMATION_NOTICE
  end

  def edit
  end

  def update
    if @user.update(password_params)
      # Changing the password invalidates every outstanding reset token, and
      # every other signed-in device is signed out as a precaution.
      @user.sessions.destroy_all
      redirect_to sign_in_path, notice: "Your password has been reset. Please sign in."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_token_for!(:password_reset, params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: "That password reset link is invalid or has expired."
    end

    def password_params
      params.expect(user: [ :password, :password_confirmation ])
    end
end
