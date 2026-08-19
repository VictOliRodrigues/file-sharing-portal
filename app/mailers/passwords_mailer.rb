class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @token = user.generate_token_for(:password_reset)
    @portal_name = Rails.application.config.x.portal.app_name

    mail subject: "Reset your #{@portal_name} password", to: user.email_address
  end
end
