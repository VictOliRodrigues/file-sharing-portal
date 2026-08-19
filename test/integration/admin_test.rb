require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:alice)
  end

  # --- Access control ------------------------------------------------------

  test "an ordinary user cannot reach the administration dashboard" do
    sign_in_as @member

    get admin_root_path

    assert_redirected_to root_path
    assert_match(/not allowed/i, flash[:alert])
  end

  test "an ordinary user cannot list accounts" do
    sign_in_as @member

    get admin_users_path
    assert_redirected_to root_path
  end

  test "an ordinary user cannot disable another account" do
    sign_in_as @member

    post disable_admin_user_path(users(:bob))

    assert_redirected_to root_path
    assert_not users(:bob).reload.disabled?
  end

  test "an ordinary user cannot delete another account" do
    sign_in_as @member

    assert_no_difference -> { User.count } do
      delete admin_user_path(users(:bob))
    end
  end

  test "a signed out visitor is sent to the sign in form" do
    get admin_root_path
    assert_redirected_to sign_in_path
  end

  test "an administrator can reach the dashboard" do
    sign_in_as @admin

    get admin_root_path

    assert_response :success
    assert_match "System overview", response.body
  end

  # --- User management -----------------------------------------------------

  test "an administrator can list every account" do
    sign_in_as @admin

    get admin_users_path

    assert_response :success
    assert_match @member.email_address, response.body
    assert_match users(:bob).email_address, response.body
  end

  test "an administrator can disable an account, which signs it out everywhere" do
    @member.sessions.create!(ip_address: "10.0.0.1", user_agent: "browser")
    sign_in_as @admin

    post disable_admin_user_path(@member)

    assert @member.reload.disabled?
    assert_equal 0, @member.sessions.count
  end

  test "an administrator can re-enable a disabled account" do
    sign_in_as @admin

    post enable_admin_user_path(users(:disabled))

    assert_not users(:disabled).reload.disabled?
  end

  test "an administrator cannot disable their own account" do
    sign_in_as @admin

    post disable_admin_user_path(@admin)

    assert_not @admin.reload.disabled?
    assert_match(/your own account/i, flash[:alert])
  end

  test "an administrator cannot delete their own account" do
    sign_in_as @admin

    assert_no_difference -> { User.count } do
      delete admin_user_path(@admin)
    end
  end

  test "deleting an account removes its folders, files and links" do
    folder = @member.folders.create!(name: "Reports")
    file = create_file(owner: @member, folder: folder)
    @member.share_links.create!(shareable: file)

    sign_in_as @admin

    assert_difference -> { User.count }, -1 do
      delete admin_user_path(@member)
    end

    assert_not Folder.exists?(folder.id)
    assert_not StoredFile.exists?(file.id)
    assert_equal 0, ShareLink.where(user_id: @member.id).count
  end

  test "the last administrator cannot be demoted" do
    User.administrators.where.not(id: @admin.id).update_all(admin: false)
    sign_in_as @admin
    other = users(:bob)

    # Promote somebody else first, then demote them: that must work.
    patch admin_user_path(other), params: { user: { admin: "1" } }
    assert other.reload.admin?

    patch admin_user_path(other), params: { user: { admin: "0" } }
    assert_not other.reload.admin?
  end

  test "an administrator can grant and set a quota on an account" do
    sign_in_as @admin

    patch admin_user_path(@member), params: {
      user: { admin: "1", storage_quota_bytes: 1_048_576 }
    }

    @member.reload
    assert @member.admin?
    assert_equal 1_048_576, @member.storage_quota_bytes
  end

  test "an administrator cannot change somebody's password through this form" do
    sign_in_as @admin
    original_digest = @member.password_digest

    patch admin_user_path(@member), params: {
      user: { admin: "0", password: "hijacked-password" }
    }

    assert_equal original_digest, @member.reload.password_digest
  end

  test "an administrator can create an account" do
    sign_in_as @admin

    assert_difference -> { User.count }, 1 do
      post admin_users_path, params: { user: {
        name: "New Colleague", email_address: "colleague@example.com",
        password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
      } }
    end

    assert User.exists?(email_address: "colleague@example.com")
  end

  # --- Statistics ----------------------------------------------------------

  test "the dashboard reports storage and sharing usage" do
    file = create_file(owner: @member, folder: nil, content: "0123456789")
    @member.share_links.create!(shareable: file)

    sign_in_as @admin
    get admin_root_path

    assert_response :success
    assert_match "Storage used", response.body
    assert_match "Share links", response.body
  end

  test "statistics count files across every account" do
    create_file(owner: @member, folder: nil, content: "12345")
    create_file(owner: users(:bob), folder: nil, content: "1234567890")

    statistics = SystemStatistics.new

    assert_equal 2, statistics.files_count
    assert_equal 15, statistics.storage_used
  end

  private
    def create_file(owner:, folder:, name: "file.txt", content: "content")
      stored_file = owner.stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: "text/plain"
      )
      stored_file.save!
      stored_file
    end
end
