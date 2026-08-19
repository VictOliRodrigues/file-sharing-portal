class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: %i[show update destroy disable enable]
  before_action :prevent_acting_on_self, only: %i[destroy disable]

  def index
    @users = User.ordered
    @storage_by_user = StoredFile.group(:user_id).sum(:byte_size)
    @files_by_user = StoredFile.kept.group(:user_id).count
  end

  def show
    @stored_files = @user.stored_files.kept.recent.limit(20)
    @share_links = @user.share_links.recent.limit(20)
  end

  # Lets an administrator provision accounts on a deployment where open
  # registration is turned off.
  def new
    @user = User.new
  end

  def create
    @user = User.new(create_params)

    if @user.save
      redirect_to admin_user_path(@user), notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Only the administrator flag and the storage quota can be changed here.
  # Names, addresses and passwords stay under the account holder's control.
  def update
    if demoting_last_administrator?
      return redirect_to admin_user_path(@user),
                         alert: "There has to be at least one administrator."
    end

    if @user.update(update_params)
      redirect_to admin_user_path(@user), notice: "Account updated."
    else
      redirect_to admin_user_path(@user), alert: @user.errors.full_messages.to_sentence
    end
  end

  def disable
    @user.disable!
    redirect_back_or_to admin_users_path, notice: "#{@user.name} has been disabled."
  end

  def enable
    @user.enable!
    redirect_back_or_to admin_users_path, notice: "#{@user.name} has been re-enabled."
  end

  # Removing an account removes its folders, files, share links and stored
  # bytes with it.
  def destroy
    if @user.admin? && User.administrators.count <= 1
      return redirect_to admin_users_path, alert: "There has to be at least one administrator."
    end

    name = @user.name
    @user.destroy!
    redirect_to admin_users_path, notice: "#{name} and all of their data have been deleted."
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    # An administrator locking or deleting their own account would leave the
    # deployment without anybody able to fix it.
    def prevent_acting_on_self
      return unless @user == current_user

      redirect_to admin_users_path, alert: "You cannot do that to your own account."
    end

    def create_params
      params.expect(user: [ :name, :email_address, :password, :password_confirmation,
                            :admin, :storage_quota_bytes ])
    end

    def update_params
      params.expect(user: [ :admin, :storage_quota_bytes ])
    end

    def demoting_last_administrator?
      return false unless @user.admin?
      return false if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :admin))

      params.dig(:user, :admin).present? && User.administrators.count <= 1
    end
end
