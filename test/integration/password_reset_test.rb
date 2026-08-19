require "test_helper"

class PasswordResetTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "requesting a reset emails the account holder" do
    assert_enqueued_emails 1 do
      post passwords_path, params: { email_address: users(:alice).email_address }
    end

    assert_redirected_to sign_in_path
    assert_equal PasswordsController::CONFIRMATION_NOTICE, flash[:notice]
  end

  test "requesting a reset for an unknown address looks identical but sends nothing" do
    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: "nobody@example.com" }
    end

    assert_equal PasswordsController::CONFIRMATION_NOTICE, flash[:notice]
  end

  test "disabled accounts do not receive reset instructions" do
    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: users(:disabled).email_address }
    end
  end

  test "a valid token lets the user choose a new password" do
    user = users(:alice)
    token = user.generate_token_for(:password_reset)

    patch password_path(token), params: { user: {
      password: "a-brand-new-password", password_confirmation: "a-brand-new-password"
    } }

    assert_redirected_to sign_in_path
    assert user.reload.authenticate("a-brand-new-password")
  end

  test "an invalid token is refused" do
    get edit_password_path("not-a-real-token")
    assert_redirected_to new_password_path
  end

  test "an expired token is refused" do
    user = users(:alice)
    token = user.generate_token_for(:password_reset)

    travel 31.minutes do
      get edit_password_path(token)
      assert_redirected_to new_password_path
    end
  end

  test "a token cannot be replayed once the password has been changed" do
    user = users(:alice)
    token = user.generate_token_for(:password_reset)

    patch password_path(token), params: { user: {
      password: "a-brand-new-password", password_confirmation: "a-brand-new-password"
    } }
    assert_redirected_to sign_in_path

    patch password_path(token), params: { user: {
      password: "another-new-password", password_confirmation: "another-new-password"
    } }
    assert_redirected_to new_password_path
    assert user.reload.authenticate("a-brand-new-password")
  end

  test "resetting the password signs every device out" do
    user = users(:alice)
    user.sessions.create!(ip_address: "10.0.0.1", user_agent: "other device")
    token = user.generate_token_for(:password_reset)

    patch password_path(token), params: { user: {
      password: "a-brand-new-password", password_confirmation: "a-brand-new-password"
    } }

    assert_equal 0, user.reload.sessions.count
  end
end
