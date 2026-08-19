require "test_helper"

# Forgery protection is disabled for the rest of the suite, which is the Rails
# default in the test environment. It is turned back on here so the protection
# itself is actually exercised.
#
# Rails maps ActionController::InvalidAuthenticityToken to 422, so a rejected
# request shows up as an unprocessable entity response rather than as an
# exception.
class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous
  end

  test "uploading without a token is rejected" do
    sign_in_with_token(users(:alice))

    assert_no_difference -> { StoredFile.count } do
      post files_path, params: { files: [ uploaded_file ] }
    end

    assert_response :unprocessable_entity
  end

  test "deleting a file without a token is rejected" do
    stored_file = users(:alice).stored_files.new
    stored_file.attachment.attach(
      io: StringIO.new("content"), filename: "notes.txt", content_type: "text/plain"
    )
    stored_file.save!

    sign_in_with_token(users(:alice))

    delete file_path(stored_file)

    assert_response :unprocessable_entity
    assert_not stored_file.reload.deleted?
  end

  test "unlocking a share link without a token is rejected" do
    owner = users(:alice)
    stored_file = owner.stored_files.new
    stored_file.attachment.attach(
      io: StringIO.new("secret"), filename: "secret.txt", content_type: "text/plain"
    )
    stored_file.save!
    link = owner.share_links.create!(shareable: stored_file, password: "share-secret")

    post unlock_share_path(link.token), params: { password: "share-secret" }

    assert_response :unprocessable_entity
  end

  test "signing in without a token is rejected" do
    assert_no_difference -> { Session.count } do
      post sign_in_path, params: {
        email_address: users(:alice).email_address, password: TEST_PASSWORD
      }
    end

    assert_response :unprocessable_entity
  end

  test "a request carrying the token from the form succeeds" do
    get sign_in_path
    token = authenticity_token_from(response.body)
    assert token.present?

    assert_difference -> { Session.count }, 1 do
      post sign_in_path, params: {
        email_address: users(:alice).email_address,
        password: TEST_PASSWORD,
        authenticity_token: token
      }
    end

    assert_redirected_to root_path
  end

  private
    # Signs in the way a browser would, so the session carries a usable token.
    def sign_in_with_token(user)
      get sign_in_path
      post sign_in_path, params: {
        email_address: user.email_address,
        password: TEST_PASSWORD,
        authenticity_token: authenticity_token_from(response.body)
      }
    end

    def authenticity_token_from(body)
      body[/name="authenticity_token" value="([^"]+)"/, 1]
    end
end
