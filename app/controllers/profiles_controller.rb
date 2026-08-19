class ProfilesController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to profile_path, notice: "Your profile has been updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def profile_params
      # Neither `admin` nor `disabled_at` may ever be set from this form.
      params.expect(user: [ :name, :email_address ])
    end
end
