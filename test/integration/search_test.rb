require "test_helper"

class SearchTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:alice)
    sign_in_as @owner

    @reports = @owner.folders.create!(name: "Reports")
    @archive = @owner.folders.create!(name: "Archive", parent: @reports)
    @private_folder = @owner.folders.create!(name: "Personal")

    @quarterly = create_file(owner: @owner, folder: @reports, name: "quarterly-report.pdf",
                             content: "%PDF-1.4 report", content_type: "application/pdf")
    @photo = create_file(owner: @owner, folder: @archive, name: "team-photo.png",
                         content: "png bytes", content_type: "image/png")
    @notes = create_file(owner: @owner, folder: nil, name: "meeting-notes.txt")
  end

  test "searching by name matches part of a file name" do
    get search_path, params: { q: "quarterly" }

    assert_response :success
    assert_match "quarterly-report.pdf", response.body
    assert_no_match(/meeting-notes/, response.body)
  end

  test "searching by name is case insensitive" do
    get search_path, params: { q: "QUARTERLY" }

    assert_response :success
    assert_match "quarterly-report.pdf", response.body
  end

  test "searching by name also matches folders" do
    get search_path, params: { q: "Arch" }

    assert_response :success
    assert_match "Archive", response.body
  end

  test "searching within a folder includes its subfolders" do
    get search_path, params: { folder_id: @reports.id }

    assert_response :success
    assert_match "quarterly-report.pdf", response.body
    assert_match "team-photo.png", response.body
    assert_no_match(/meeting-notes/, response.body)
  end

  test "searching within a folder excludes everything outside it" do
    get search_path, params: { folder_id: @private_folder.id, q: "quarterly" }

    assert_response :success
    assert_no_match(/quarterly-report/, response.body)
  end

  test "searching by file type filters on the sniffed content type" do
    get search_path, params: { type: "image" }

    assert_response :success
    assert_match "team-photo.png", response.body
    assert_no_match(/quarterly-report/, response.body)
  end

  test "filters combine" do
    get search_path, params: { q: "report", type: "document", folder_id: @reports.id }

    assert_response :success
    assert_match "quarterly-report.pdf", response.body
    assert_no_match(/team-photo/, response.body)
  end

  test "an unknown file type filter is ignored rather than trusted" do
    get search_path, params: { type: "'; DROP TABLE stored_files; --" }

    assert_response :success
    assert StoredFile.exists?(@quarterly.id)
  end

  test "a wildcard in the search term is treated literally" do
    create_file(owner: @owner, folder: nil, name: "annual_report.txt")

    # _ matches any single character in a raw SQL LIKE pattern, so an
    # unescaped term would match every file rather than only this one.
    get search_path, params: { q: "_" }

    assert_response :success
    assert_match "annual_report.txt", response.body
    assert_no_match(/meeting-notes/, response.body)
  end

  test "search never returns files belonging to another account" do
    create_file(owner: users(:bob), folder: nil, name: "quarterly-secret.txt")

    get search_path, params: { q: "quarterly" }

    assert_response :success
    assert_no_match(/quarterly-secret/, response.body)
  end

  test "search never returns files that are in the trash" do
    @quarterly.discard!

    get search_path, params: { q: "quarterly" }

    assert_response :success
    assert_no_match(/quarterly-report/, response.body)
  end

  test "a folder filter pointing at another account is ignored" do
    foreign = users(:bob).folders.create!(name: "Bob folder")

    get search_path, params: { folder_id: foreign.id, q: "quarterly" }

    assert_response :success
    assert_match "quarterly-report.pdf", response.body
  end

  test "search requires authentication" do
    sign_out

    get search_path
    assert_redirected_to sign_in_path
  end

  private
    def create_file(owner:, folder:, name:, content: "content", content_type: "text/plain")
      stored_file = owner.stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: content_type
      )
      stored_file.save!
      stored_file
    end
end
