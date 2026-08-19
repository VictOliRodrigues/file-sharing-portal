require "test_helper"

class FolderTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @documents = @user.folders.create!(name: "Documents")
    @invoices = @user.folders.create!(name: "Invoices", parent: @documents)
    @paid = @user.folders.create!(name: "Paid", parent: @invoices)
  end

  test "sanitizes the folder name" do
    folder = @user.folders.create!(name: "../../etc")
    assert_equal "etc", folder.name
  end

  test "rejects a duplicate name in the same parent regardless of case" do
    duplicate = @user.folders.new(name: "invoices", parent: @documents)
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "allows the same name in a different parent" do
    assert @user.folders.create!(name: "Invoices", parent: @paid).persisted?
  end

  test "allows another user to reuse a name" do
    assert users(:bob).folders.create!(name: "Documents").persisted?
  end

  test "reports its ancestors from the root down" do
    assert_equal [ @documents, @invoices ], @paid.ancestors
    assert_equal [ @documents, @invoices, @paid ], @paid.breadcrumbs
    assert_equal 2, @paid.depth
  end

  test "collects itself and every descendant" do
    assert_equal [ @documents.id, @invoices.id, @paid.id ].sort,
                 @documents.self_and_descendant_ids.sort
  end

  test "refuses to become its own parent" do
    @documents.parent = @documents
    assert_not @documents.valid?
    assert @documents.errors[:parent].any?
  end

  test "refuses to move into one of its own descendants" do
    @documents.parent = @paid
    assert_not @documents.valid?
    assert @documents.errors[:parent].any?
  end

  test "refuses a parent owned by somebody else" do
    foreign = users(:bob).folders.create!(name: "Bob files")
    folder = @user.folders.new(name: "Sneaky", parent: foreign)

    assert_not folder.valid?
    assert folder.errors[:parent].any?
  end

  test "refuses nesting beyond the depth limit" do
    deepest = @paid
    deepest = @user.folders.create!(name: "level-#{deepest.depth}", parent: deepest) while deepest.depth < Folder::MAX_DEPTH - 1

    assert_equal Folder::MAX_DEPTH - 1, deepest.depth
    too_deep = @user.folders.new(name: "one too many", parent: deepest)
    assert_not too_deep.valid?
  end

  test "deleting a folder deletes everything inside it" do
    file = create_file(folder: @invoices)

    @documents.discard!

    assert @documents.reload.deleted?
    assert @invoices.reload.deleted?
    assert @paid.reload.deleted?
    assert file.reload.deleted?
  end

  test "restoring a folder brings back exactly what was deleted with it" do
    kept_file = create_file(folder: @invoices, name: "keep.txt")
    already_trashed = create_file(folder: @invoices, name: "old.txt")
    already_trashed.discard!

    travel 1.minute do
      @documents.discard!
    end

    @documents.reload.undiscard!

    assert_not @documents.reload.deleted?
    assert_not @invoices.reload.deleted?
    assert_not kept_file.reload.deleted?
    assert already_trashed.reload.deleted?, "a file trashed earlier must stay in the trash"
  end

  test "restoring a folder whose parent is still deleted returns it to the root" do
    @invoices.discard!
    travel 1.minute do
      @documents.discard!
    end

    @invoices.reload.undiscard!

    assert_nil @invoices.reload.parent_id
    assert_not @invoices.deleted?
  end

  test "purging a folder removes every descendant and file" do
    file = create_file(folder: @paid)

    assert_difference -> { StoredFile.count }, -1 do
      assert_difference -> { Folder.count }, -3 do
        @documents.purge!
      end
    end

    assert_not StoredFile.exists?(file.id)
  end

  test "reports the total size of everything underneath it" do
    create_file(folder: @invoices, content: "12345")
    create_file(folder: @paid, content: "1234567890")

    assert_equal 15, @documents.total_byte_size
  end

  private
    def create_file(folder:, name: "file.txt", content: "content")
      stored_file = @user.stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new(content), filename: name, content_type: "text/plain"
      )
      stored_file.save!
      stored_file
    end
end
