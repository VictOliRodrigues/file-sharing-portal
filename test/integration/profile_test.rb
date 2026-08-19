require "test_helper"

class ProfileTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alice) }

  test "a user can update their name and email address" do
    patch profile_path, params: { user: { name: "Alice M.", email_address: "alice.m@example.com" } }

    assert_redirected_to profile_path
    users(:alice).reload
    assert_equal "Alice M.", users(:alice).name
    assert_equal "alice.m@example.com", users(:alice).email_address
  end

  test "a user cannot make themselves an administrator through the profile form" do
    patch profile_path, params: { user: { name: "Alice", admin: true } }
    assert_not users(:alice).reload.admin?
  end

  test "changing the password requires the current one" do
    patch profile_password_path, params: { user: {
      current_password: "wrong", password: "a-brand-new-password",
      password_confirmation: "a-brand-new-password"
    } }

    assert_response :unprocessable_entity
    assert users(:alice).reload.authenticate(TEST_PASSWORD)
  end

  test "changing the password keeps the current session and drops the others" do
    other = users(:alice).sessions.create!(ip_address: "10.0.0.1", user_agent: "other")

    patch profile_password_path, params: { user: {
      current_password: TEST_PASSWORD, password: "a-brand-new-password",
      password_confirmation: "a-brand-new-password"
    } }

    assert_redirected_to profile_path
    assert_not Session.exists?(other.id)

    get profile_path
    assert_response :success
  end

  test "a user cannot revoke a session belonging to somebody else" do
    foreign = users(:bob).sessions.create!(ip_address: "10.0.0.2", user_agent: "bob")

    delete profile_session_path(foreign)

    assert_response :not_found
    assert Session.exists?(foreign.id)
  end
end
