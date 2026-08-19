require "test_helper"

class FileManagementTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
    @stored_file = create_file_for(users(:alice), name: "report.txt", content: "annual report")
  end

  test "a file can be downloaded and the download is recorded" do
    assert_difference -> { Download.count }, 1 do
      get download_file_path(@stored_file)
    end

    assert_response :success
    assert_equal "annual report", response.body
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/report.txt/, response.headers["Content-Disposition"])

    @stored_file.reload
    assert_equal 1, @stored_file.download_count
    assert_not_nil @stored_file.last_downloaded_at
  end

  test "a file can be renamed" do
    patch file_path(@stored_file), params: { stored_file: { name: "annual-report.txt" } }
    assert_equal "annual-report.txt", @stored_file.reload.name
  end

  test "renaming cannot smuggle a path into the name" do
    patch file_path(@stored_file), params: { stored_file: { name: "../../etc/passwd" } }

    name = @stored_file.reload.name
    assert_not name.include?("/")
    assert_not name.include?("\\")
    assert_equal "passwd", name
  end

  test "deleting moves the file to the trash and keeps the bytes" do
    delete file_path(@stored_file)

    assert @stored_file.reload.deleted?
    assert @stored_file.attachment.attached?
    assert_not StoredFile.kept.exists?(@stored_file.id)
  end

  test "a trashed file can be restored" do
    @stored_file.discard!

    post restore_file_path(@stored_file)

    assert_not @stored_file.reload.deleted?
    assert_redirected_to trash_path
  end

  test "a trashed file can be purged for good" do
    @stored_file.discard!

    assert_difference -> { StoredFile.count }, -1 do
      delete purge_file_path(@stored_file)
    end

    assert_redirected_to trash_path
  end

  test "a trashed file cannot be downloaded" do
    @stored_file.discard!

    get download_file_path(@stored_file)
    assert_response :not_found
  end

  test "the file listing only shows files that are not in the trash" do
    trashed = create_file_for(users(:alice), name: "archived-notes.txt")
    trashed.discard!

    get files_path
    assert_response :success
    assert_match "report.txt", response.body
    assert_no_match(/archived-notes/, response.body)
  end

  test "the trash only shows deleted files" do
    @stored_file.discard!

    get trash_path
    assert_response :success
    assert_match "report.txt", response.body
  end

  test "an image can be previewed inline" do
    image = create_file_for(users(:alice), name: "pixel.png", content: png_bytes,
                            content_type: "image/png")

    get preview_file_path(image)

    assert_response :success
    assert_match(/inline/, response.headers["Content-Disposition"])
    assert_match(%r{image/png}, response.headers["Content-Type"])
  end

  test "a non-image is never served inline" do
    get preview_file_path(@stored_file)
    assert_response :not_found
  end

  test "HTML is downloaded as an opaque binary rather than as a document" do
    page = create_file_for(users(:alice), name: "page.html",
                           content: "<html><script>alert(1)</script></html>",
                           content_type: "text/html")

    get download_file_path(page)

    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(%r{application/octet-stream}, response.headers["Content-Type"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  private
    def png_bytes
      # A 1x1 transparent PNG.
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end

    def create_file_for(user, name: "file.txt", content: "content", content_type: "text/plain")
      stored_file = user.stored_files.new
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: content_type
      )
      stored_file.save!
      stored_file
    end
end
