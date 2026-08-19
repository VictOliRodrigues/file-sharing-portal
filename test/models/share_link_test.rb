require "test_helper"

class ShareLinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @folder = @user.folders.create!(name: "Reports")
    @nested = @user.folders.create!(name: "2026", parent: @folder)
    @file = create_file(folder: @folder, name: "report.pdf")
  end

  test "generates a long unguessable token" do
    link = @user.share_links.create!(shareable: @file)

    assert link.token.present?
    assert_operator link.token.length, :>=, 40
    assert_not_equal link.token, @user.share_links.create!(shareable: @nested).token
  end

  test "is addressed by its token" do
    link = @user.share_links.create!(shareable: @file)
    assert_equal link.token, link.to_param
  end

  test "refuses to share something owned by somebody else" do
    foreign = users(:bob).folders.create!(name: "Bob")
    link = @user.share_links.new(shareable: foreign)

    assert_not link.valid?
    assert link.errors[:shareable].any?
  end

  test "refuses to share something that is in the trash" do
    @file.discard!
    link = @user.share_links.new(shareable: @file)

    assert_not link.valid?
  end

  test "refuses an expiry date in the past" do
    link = @user.share_links.new(shareable: @file, expires_at: 1.hour.ago)

    assert_not link.valid?
    assert link.errors[:expires_at].any?
  end

  test "refuses a non positive download limit" do
    assert_not @user.share_links.new(shareable: @file, download_limit: 0).valid?
    assert_not @user.share_links.new(shareable: @file, download_limit: -1).valid?
  end

  test "refuses a password that is too short" do
    assert_not @user.share_links.new(shareable: @file, password: "abc").valid?
  end

  test "stores the password as a digest" do
    link = @user.share_links.create!(shareable: @file, password: "share-secret")

    assert link.password_protected?
    assert_no_match(/share-secret/, link.password_digest)
    assert link.authenticate_password("share-secret")
    assert_not link.authenticate_password("wrong")
  end

  test "is available until it expires" do
    link = @user.share_links.create!(shareable: @file, expires_at: 1.hour.from_now)
    assert link.available?

    travel 2.hours do
      assert_not link.available?
      assert_equal :expired, link.unavailable_reason
    end
  end

  test "is unavailable once the download limit is reached" do
    link = @user.share_links.create!(shareable: @file, download_limit: 1)
    link.record_download!(@file)

    assert_not link.reload.available?
    assert_equal :limit_reached, link.unavailable_reason
    assert_equal 0, link.remaining_downloads
  end

  test "is unavailable once it is revoked" do
    link = @user.share_links.create!(shareable: @file)
    link.revoke!

    assert_not link.available?
    assert_equal :revoked, link.unavailable_reason
  end

  test "recording a download updates both the link and the file" do
    link = @user.share_links.create!(shareable: @file)

    assert_difference -> { Download.count }, 1 do
      link.record_download!(@file, ip_address: "203.0.113.9")
    end

    assert_equal 1, link.reload.download_count
    assert_equal 1, @file.reload.download_count
    assert_equal link, Download.last.share_link
    assert_nil Download.last.user
  end

  test "a file share contains only that file" do
    other = create_file(folder: @folder, name: "other.pdf")
    link = @user.share_links.create!(shareable: @file)

    assert link.contains?(@file)
    assert_not link.contains?(other)
    assert_not link.contains?(@folder)
  end

  test "a folder share contains its whole subtree and nothing else" do
    inside = create_file(folder: @nested, name: "inside.pdf")
    outside = create_file(folder: nil, name: "outside.pdf")
    other_folder = @user.folders.create!(name: "Private")

    link = @user.share_links.create!(shareable: @folder)

    assert link.contains?(@folder)
    assert link.contains?(@nested)
    assert link.contains?(@file)
    assert link.contains?(inside)
    assert_not link.contains?(outside)
    assert_not link.contains?(other_folder)
  end

  test "a share never contains a record belonging to another user" do
    foreign_file = create_file(folder: nil, name: "bob.pdf", user: users(:bob))
    link = @user.share_links.create!(shareable: @folder)

    assert_not link.contains?(foreign_file)
  end

  test "a share never contains a deleted record" do
    link = @user.share_links.create!(shareable: @folder)
    @file.discard!

    assert_not link.contains?(@file.reload)
  end

  test "enforces the server wide maximum lifetime when one is configured" do
    with_max_share_days(7) do
      assert_not @user.share_links.new(shareable: @file).valid?,
                 "an unlimited link must be refused when a maximum is configured"
      assert_not @user.share_links.new(shareable: @file, expires_at: 30.days.from_now).valid?
      assert @user.share_links.new(shareable: @file, expires_at: 3.days.from_now).valid?
    end
  end

  private
    def with_max_share_days(days)
      portal = Rails.application.config.x.portal
      previous = portal.max_share_link_days
      portal.max_share_link_days = days
      yield
    ensure
      portal.max_share_link_days = previous
    end

    def create_file(folder:, name: "file.txt", content: "content", user: nil)
      owner = user || @user
      stored_file = owner.stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: "text/plain"
      )
      stored_file.save!
      stored_file
    end
end
