require "test_helper"

# Rack::Attack is switched off for the rest of the suite so that ordinary tests
# are not throttled. It is turned back on here.
class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    @previously_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    Rails.cache.clear
  end

  teardown do
    Rack::Attack.enabled = @previously_enabled
    Rack::Attack.reset!
    Rails.cache.clear
  end

  test "repeated sign in attempts against one account are throttled" do
    5.times do
      post sign_in_path, params: { email_address: users(:alice).email_address, password: "wrong" }
      assert_response :redirect
    end

    post sign_in_path, params: { email_address: users(:alice).email_address, password: "wrong" }

    assert_response :too_many_requests
    assert response.headers["retry-after"].present?
  end

  test "the throttle does not stop a different account from signing in" do
    5.times do
      post sign_in_path, params: { email_address: users(:alice).email_address, password: "wrong" }
    end

    post sign_in_path, params: { email_address: users(:bob).email_address, password: "wrong" }
    assert_response :redirect
  end

  test "password reset requests are throttled per address" do
    3.times do
      post passwords_path, params: { email_address: users(:alice).email_address }
      assert_response :redirect
    end

    post passwords_path, params: { email_address: users(:alice).email_address }
    assert_response :too_many_requests
  end

  test "guessing the password of a share link is throttled" do
    owner = users(:alice)
    stored_file = owner.stored_files.new
    stored_file.attachment.attach(
      io: StringIO.new("secret"), filename: "secret.txt", content_type: "text/plain"
    )
    stored_file.save!
    link = owner.share_links.create!(shareable: stored_file, password: "share-secret")

    10.times do
      post unlock_share_path(link.token), params: { password: "guess" }
      assert_response :redirect
    end

    post unlock_share_path(link.token), params: { password: "guess" }
    assert_response :too_many_requests
  end

  test "the health check endpoint is never throttled" do
    40.times { get rails_health_check_path }

    assert_response :success
  end
end
