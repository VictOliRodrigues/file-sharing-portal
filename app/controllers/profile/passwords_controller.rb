class Profile::PasswordsController < ApplicationController
  def update
    @user = current_user

    unless @user.authenticate(params.dig(:user, :current_password).to_s)
      @user.errors.add(:current_password, "is incorrect")
      return render "profiles/show", status: :unprocessable_entity
    end

    if @user.update(password_params)
      # Every other device is signed out; the current session is kept so the
      # user is not bounced back to the sign in form.
      @user.sessions.where.not(id: Current.session.id).destroy_all
      redirect_to profile_path, notice: "Your password has been changed. Other devices were signed out."
    else
      render "profiles/show", status: :unprocessable_entity
    end
  end

  private
    def password_params
      params.expect(user: [ :password, :password_confirmation ])
    end
end
