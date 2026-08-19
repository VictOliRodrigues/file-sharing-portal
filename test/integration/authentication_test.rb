require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "signing in with valid credentials starts a session" do
    assert_difference -> { Session.count }, 1 do
      sign_in_as users(:alice)
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_match "Alice Martin", response.body
  end

  test "signing in with a wrong password fails without revealing the reason" do
    assert_no_difference -> { Session.count } do
      post sign_in_path, params: { email_address: users(:alice).email_address, password: "nope" }
    end

    assert_redirected_to sign_in_path
    assert_equal "Incorrect email address or password.", flash[:alert]
  end

  test "an unknown email address produces the same message as a wrong password" do
    post sign_in_path, params: { email_address: "nobody@example.com", password: "whatever" }
    assert_equal "Incorrect email address or password.", flash[:alert]
  end

  test "a disabled account cannot sign in" do
    assert_no_difference -> { Session.count } do
      sign_in_as users(:disabled)
    end

    assert_redirected_to sign_in_path
    assert_match(/disabled/i, flash[:alert])
  end

  test "a session is revoked as soon as the account is disabled" do
    sign_in_as users(:alice)
    get root_path
    assert_response :success

    users(:alice).disable!

    get root_path
    assert_redirected_to sign_in_path
  end

  test "signing out destroys the session record" do
    sign_in_as users(:alice)

    assert_difference -> { Session.count }, -1 do
      sign_out
    end

    get root_path
    assert_redirected_to sign_in_path
  end

  test "unauthenticated visitors are sent to the sign in form" do
    get root_path
    assert_redirected_to sign_in_path
  end

  test "visitors are returned to the page they asked for after signing in" do
    get profile_path
    assert_redirected_to sign_in_path

    sign_in_as users(:alice)
    assert_redirected_to profile_path
  end

  test "the session cookie is HttpOnly" do
    sign_in_as users(:alice)
    cookie_header = Array(response.headers["set-cookie"]).join("\n")
    assert_match(/session_id=/, cookie_header)
    assert_match(/httponly/i, cookie_header)
  end

  test "signed in users are redirected away from the sign in form" do
    sign_in_as users(:alice)
    get sign_in_path
    assert_redirected_to root_path
  end

  test "a forged session cookie is rejected" do
    cookies[:session_id] = "1"
    get root_path
    assert_redirected_to sign_in_path
  end
end
