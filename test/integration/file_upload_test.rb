require "test_helper"

class FileUploadTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alice) }

  test "uploading a file stores it for the signed-in user" do
    assert_difference -> { StoredFile.count }, 1 do
      post files_path, params: { files: [ uploaded_file(filename: "notes.txt", content: "hello") ] }
    end

    stored_file = StoredFile.order(:created_at).last
    assert_redirected_to files_path
    assert_equal users(:alice), stored_file.user
    assert_equal "notes.txt", stored_file.name
    assert_equal 5, stored_file.byte_size
    assert stored_file.attachment.attached?
  end

  test "several files can be uploaded at once" do
    assert_difference -> { StoredFile.count }, 2 do
      post files_path, params: { files: [
        uploaded_file(filename: "one.txt", content: "one"),
        uploaded_file(filename: "two.txt", content: "two")
      ] }
    end
  end

  test "a hostile filename is sanitized before it is stored" do
    post files_path, params: { files: [ uploaded_file(filename: "../../etc/passwd", content: "x") ] }

    stored_file = StoredFile.order(:created_at).last
    assert_equal "passwd", stored_file.name
    assert_not stored_file.name.include?("/")
  end

  test "the content type is sniffed rather than taken from the client" do
    post files_path, params: { files: [
      uploaded_file(filename: "sneaky.txt", content: "%PDF-1.4\n%fake pdf", content_type: "text/html")
    ] }

    stored_file = StoredFile.order(:created_at).last
    assert_not_equal "text/html", stored_file.content_type
  end

  test "an upload over the size limit is refused and nothing is stored" do
    with_max_upload_size(10) do
      assert_no_difference -> { StoredFile.count } do
        assert_no_difference -> { ActiveStorage::Blob.count } do
          post files_path, params: { files: [ uploaded_file(content: "x" * 100) ] }
        end
      end
    end

    assert_redirected_to new_file_path
  end

  test "an upload beyond the storage quota is refused" do
    users(:alice).update!(storage_quota_bytes: 10)

    assert_no_difference -> { StoredFile.count } do
      post files_path, params: { files: [ uploaded_file(content: "x" * 100) ] }
    end
  end

  test "a blocked extension is refused" do
    with_blocked_extensions("exe") do
      assert_no_difference -> { StoredFile.count } do
        post files_path, params: { files: [ uploaded_file(filename: "tool.exe", content: "MZ") ] }
      end
    end
  end

  test "an allowlist rejects everything outside it" do
    with_allowed_extensions("pdf") do
      assert_no_difference -> { StoredFile.count } do
        post files_path, params: { files: [ uploaded_file(filename: "notes.txt", content: "x") ] }
      end

      assert_difference -> { StoredFile.count }, 1 do
        post files_path, params: { files: [ uploaded_file(filename: "notes.pdf", content: "%PDF-1.4") ] }
      end
    end
  end

  test "submitting the form without a file is rejected" do
    assert_no_difference -> { StoredFile.count } do
      post files_path, params: { files: [ "" ] }
    end

    assert_redirected_to new_file_path
  end

  test "uploading requires authentication" do
    sign_out

    assert_no_difference -> { StoredFile.count } do
      post files_path, params: { files: [ uploaded_file ] }
    end

    assert_redirected_to sign_in_path
  end

  private
    def with_max_upload_size(bytes)
      portal = Rails.application.config.x.portal
      previous = portal.max_upload_size
      portal.max_upload_size = bytes
      yield
    ensure
      portal.max_upload_size = previous
    end

    def with_blocked_extensions(value)
      UploadPolicy.reset!
      previous = ENV["UPLOAD_BLOCKED_EXTENSIONS"]
      ENV["UPLOAD_BLOCKED_EXTENSIONS"] = value
      UploadPolicy.reset!
      yield
    ensure
      ENV["UPLOAD_BLOCKED_EXTENSIONS"] = previous
      UploadPolicy.reset!
    end

    def with_allowed_extensions(value)
      UploadPolicy.reset!
      previous = ENV["UPLOAD_ALLOWED_EXTENSIONS"]
      ENV["UPLOAD_ALLOWED_EXTENSIONS"] = value
      UploadPolicy.reset!
      yield
    ensure
      ENV["UPLOAD_ALLOWED_EXTENSIONS"] = previous
      UploadPolicy.reset!
    end
end
