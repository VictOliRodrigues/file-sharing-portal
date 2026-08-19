require "test_helper"

class ShareLinkFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:alice)
    @folder = @owner.folders.create!(name: "Reports")
    @nested = @owner.folders.create!(name: "2026", parent: @folder)
    @file = create_file(owner: @owner, folder: @folder, name: "report.pdf", content: "quarterly")
  end

  # --- Creating links ------------------------------------------------------

  test "an owner can create a link for their own file" do
    sign_in_as @owner

    assert_difference -> { ShareLink.count }, 1 do
      post share_links_path, params: { stored_file_id: @file.id, share_link: {} }
    end

    link = ShareLink.order(:created_at).last
    assert_redirected_to share_link_path(link)
    assert_equal @file, link.shareable
  end

  test "a user cannot create a link for a file they do not own" do
    sign_in_as users(:bob)

    assert_no_difference -> { ShareLink.count } do
      post share_links_path, params: { stored_file_id: @file.id, share_link: {} }
    end
  end

  test "creating a link requires authentication" do
    assert_no_difference -> { ShareLink.count } do
      post share_links_path, params: { stored_file_id: @file.id, share_link: {} }
    end

    assert_redirected_to sign_in_path
  end

  test "an owner can revoke a link" do
    link = @owner.share_links.create!(shareable: @file)
    sign_in_as @owner

    delete share_link_path(link)

    assert link.reload.revoked?
  end

  test "a user cannot revoke a link created by somebody else" do
    link = @owner.share_links.create!(shareable: @file)
    sign_in_as users(:bob)

    delete share_link_path(link)

    assert_response :not_found
    assert_not link.reload.revoked?
  end

  # --- Using links without an account --------------------------------------

  test "a visitor can open a file link and download it without signing in" do
    link = @owner.share_links.create!(shareable: @file)

    get share_path(link.token)
    assert_response :success
    assert_match "report.pdf", response.body

    assert_difference -> { Download.count }, 1 do
      get share_download_path(link.token, @file)
    end

    assert_response :success
    assert_equal "quarterly", response.body
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_equal 1, link.reload.download_count
    assert_nil Download.last.user_id
  end

  test "a visitor can browse a shared folder and its subfolders" do
    inside = create_file(owner: @owner, folder: @nested, name: "detail.txt")
    link = @owner.share_links.create!(shareable: @folder)

    get share_path(link.token)
    assert_response :success
    assert_match "report.pdf", response.body
    assert_match "2026", response.body

    get share_folder_path(link.token, @nested)
    assert_response :success
    assert_match "detail.txt", response.body
    assert inside.persisted?
  end

  test "an unknown token is refused" do
    get share_path("this-token-does-not-exist")
    assert_response :not_found
  end

  test "a revoked link stops working" do
    link = @owner.share_links.create!(shareable: @file)
    link.revoke!

    get share_path(link.token)
    assert_response :not_found

    assert_no_difference -> { Download.count } do
      get share_download_path(link.token, @file)
    end
  end

  test "an expired link stops working" do
    link = @owner.share_links.create!(shareable: @file, expires_at: 1.hour.from_now)

    travel 2.hours do
      get share_path(link.token)
      assert_response :not_found
    end
  end

  test "a link stops working once its download limit is reached" do
    link = @owner.share_links.create!(shareable: @file, download_limit: 1)

    get share_download_path(link.token, @file)
    assert_response :success

    assert_no_difference -> { Download.count } do
      get share_download_path(link.token, @file)
    end
    assert_response :not_found
  end

  # --- Password protection -------------------------------------------------

  test "a password protected link asks for the password first" do
    link = @owner.share_links.create!(shareable: @file, password: "share-secret")

    get share_path(link.token)
    assert_redirected_to locked_share_path(link.token)

    get share_download_path(link.token, @file)
    assert_redirected_to locked_share_path(link.token)
  end

  test "a wrong password does not unlock the link" do
    link = @owner.share_links.create!(shareable: @file, password: "share-secret")

    post unlock_share_path(link.token), params: { password: "guess" }
    assert_redirected_to locked_share_path(link.token)

    get share_path(link.token)
    assert_redirected_to locked_share_path(link.token)
  end

  test "the right password unlocks the link for the rest of the session" do
    link = @owner.share_links.create!(shareable: @file, password: "share-secret")

    post unlock_share_path(link.token), params: { password: "share-secret" }
    assert_redirected_to share_path(link.token)

    get share_path(link.token)
    assert_response :success

    get share_download_path(link.token, @file)
    assert_response :success
  end

  test "unlocking one link does not unlock another" do
    unlocked = @owner.share_links.create!(shareable: @file, password: "share-secret")
    other_file = create_file(owner: @owner, folder: nil, name: "other.txt")
    locked = @owner.share_links.create!(shareable: other_file, password: "another-secret")

    post unlock_share_path(unlocked.token), params: { password: "share-secret" }

    get share_path(locked.token)
    assert_redirected_to locked_share_path(locked.token)
  end

  # --- Containment ---------------------------------------------------------

  test "a file link cannot be used to reach any other file" do
    other = create_file(owner: @owner, folder: @folder, name: "private.txt")
    link = @owner.share_links.create!(shareable: @file)

    assert_no_difference -> { Download.count } do
      get share_download_path(link.token, other)
    end
    assert_response :not_found
  end

  test "a folder link cannot be used to reach a file outside the folder" do
    outside = create_file(owner: @owner, folder: nil, name: "outside.txt")
    link = @owner.share_links.create!(shareable: @nested)

    assert_no_difference -> { Download.count } do
      get share_download_path(link.token, outside)
    end
    assert_response :not_found
  end

  test "a folder link cannot be used to browse a folder above the shared one" do
    link = @owner.share_links.create!(shareable: @nested)

    get share_folder_path(link.token, @folder)
    assert_response :not_found
  end

  test "a folder link cannot be used to reach a file belonging to another account" do
    foreign = create_file(owner: users(:bob), folder: nil, name: "bob-secret.txt")
    link = @owner.share_links.create!(shareable: @folder)

    get share_download_path(link.token, foreign)
    assert_response :not_found
  end

  test "a share link cannot serve a file that has been moved to the trash" do
    link = @owner.share_links.create!(shareable: @folder)
    @file.discard!

    get share_download_path(link.token, @file)
    assert_response :not_found
  end

  test "breadcrumbs never reveal folders above the shared root" do
    link = @owner.share_links.create!(shareable: @nested)

    get share_path(link.token)

    assert_response :success
    assert_match "2026", response.body
    assert_no_match(/Reports/, response.body)
  end

  test "public share pages ask search engines not to index them" do
    link = @owner.share_links.create!(shareable: @file)

    get share_path(link.token)

    assert_match(/noindex/, response.body)
  end

  private
    def create_file(owner:, folder:, name: "file.txt", content: "content")
      stored_file = owner.stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: "text/plain"
      )
      stored_file.save!
      stored_file
    end
end
