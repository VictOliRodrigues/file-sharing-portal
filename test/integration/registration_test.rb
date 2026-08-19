require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  test "a visitor can create an account" do
    assert_difference -> { User.count }, 1 do
      post sign_up_path, params: { user: {
        name: "New Person", email_address: "new@example.com",
        password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
      } }
    end

    assert_redirected_to root_path
    assert_not User.find_by(email_address: "new@example.com").admin?
  end

  test "a mismatched confirmation is rejected" do
    assert_no_difference -> { User.count } do
      post sign_up_path, params: { user: {
        name: "New Person", email_address: "new@example.com",
        password: "a-long-enough-password", password_confirmation: "something-else"
      } }
    end

    assert_response :unprocessable_entity
  end

  test "registration cannot grant administrator rights" do
    post sign_up_path, params: { user: {
      name: "Sneaky", email_address: "sneaky@example.com",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password",
      admin: true
    } }

    assert_not User.find_by(email_address: "sneaky@example.com").admin?
  end

  test "the first account on an empty installation becomes an administrator" do
    Session.delete_all
    User.delete_all

    post sign_up_path, params: { user: {
      name: "Owner", email_address: "owner@example.com",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
    } }

    assert User.find_by(email_address: "owner@example.com").admin?
  end

  test "registration can be closed by configuration" do
    with_registration_disabled do
      assert_no_difference -> { User.count } do
        post sign_up_path, params: { user: {
          name: "Late", email_address: "late@example.com",
          password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
        } }
      end

      assert_redirected_to sign_in_path
    end
  end

  private
    def with_registration_disabled
      portal = Rails.application.config.x.portal
      previous = portal.registration_enabled
      portal.registration_enabled = false
      yield
    ensure
      portal.registration_enabled = previous
    end
end
