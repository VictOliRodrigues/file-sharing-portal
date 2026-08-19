require "test_helper"

class FileAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:bob)
    @stored_file = @owner.stored_files.new
    @stored_file.attachment.attach(
      io: StringIO.new("secret contents"), filename: "secret.txt", content_type: "text/plain"
    )
    @stored_file.save!

    sign_in_as users(:alice)
  end

  test "another user cannot view a file they do not own" do
    get file_path(@stored_file)
    assert_response :not_found
  end

  test "another user cannot download a file they do not own" do
    assert_no_difference -> { Download.count } do
      get download_file_path(@stored_file)
    end

    assert_response :not_found
  end

  test "another user cannot preview a file they do not own" do
    get preview_file_path(@stored_file)
    assert_response :not_found
  end

  test "another user cannot rename a file they do not own" do
    patch file_path(@stored_file), params: { stored_file: { name: "taken-over.txt" } }

    assert_response :not_found
    assert_equal "secret.txt", @stored_file.reload.name
  end

  test "another user cannot delete a file they do not own" do
    delete file_path(@stored_file)

    assert_response :not_found
    assert_not @stored_file.reload.deleted?
  end

  test "another user cannot purge a file they do not own" do
    @stored_file.discard!

    assert_no_difference -> { StoredFile.count } do
      delete purge_file_path(@stored_file)
    end

    assert_response :not_found
  end

  test "another user cannot restore a file they do not own" do
    @stored_file.discard!

    post restore_file_path(@stored_file)

    assert_response :not_found
    assert @stored_file.reload.deleted?
  end

  test "the file listing never leaks files owned by somebody else" do
    get files_path

    assert_response :success
    assert_no_match(/secret.txt/, response.body)
  end

  test "Active Storage does not expose its own routes" do
    blob = @stored_file.attachment.blob

    get "/rails/active_storage/blobs/redirect/#{blob.signed_id}/#{blob.filename}"
    assert_response :not_found

    get "/rails/active_storage/blobs/proxy/#{blob.signed_id}/#{blob.filename}"
    assert_response :not_found
  end
end
