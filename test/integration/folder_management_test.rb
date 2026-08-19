require "test_helper"

class FolderManagementTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
    @documents = users(:alice).folders.create!(name: "Documents")
  end

  test "a folder can be created at the root" do
    assert_difference -> { Folder.count }, 1 do
      post folders_path, params: { folder: { name: "Photos" } }
    end

    folder = Folder.order(:created_at).last
    assert_redirected_to folder_path(folder)
    assert_nil folder.parent_id
    assert_equal users(:alice), folder.user
  end

  test "a folder can be created inside another folder" do
    post folders_path, params: { folder: { name: "Invoices", parent_id: @documents.id } }

    assert_equal @documents, Folder.order(:created_at).last.parent
  end

  test "a folder cannot be created inside a folder owned by somebody else" do
    foreign = users(:bob).folders.create!(name: "Bob")

    assert_no_difference -> { Folder.count } do
      post folders_path, params: { folder: { name: "Sneaky", parent_id: foreign.id } }
    end
  end

  test "browsing a folder lists its subfolders and files" do
    child = users(:alice).folders.create!(name: "Invoices", parent: @documents)
    file = upload_into(@documents, "invoice.pdf")
    elsewhere = upload_into(nil, "unrelated.txt")

    get folder_path(@documents)

    assert_response :success
    assert_match "Invoices", response.body
    assert_match "invoice.pdf", response.body
    assert_no_match(/unrelated.txt/, response.body)
    assert child.persisted?
    assert file.persisted?
    assert elsewhere.persisted?
  end

  test "the root listing only shows items without a parent" do
    upload_into(@documents, "nested.txt")
    upload_into(nil, "at-root.txt")

    get files_path

    assert_response :success
    assert_match "at-root.txt", response.body
    assert_no_match(/nested.txt/, response.body)
  end

  test "a folder can be renamed" do
    patch folder_path(@documents), params: { folder: { name: "Paperwork" } }
    assert_equal "Paperwork", @documents.reload.name
  end

  test "a folder can be moved into another folder" do
    target = users(:alice).folders.create!(name: "Archive")

    patch folder_path(@documents), params: { folder: { parent_id: target.id } }

    assert_equal target, @documents.reload.parent
  end

  test "a folder cannot be moved inside itself" do
    child = users(:alice).folders.create!(name: "Invoices", parent: @documents)

    patch folder_path(@documents), params: { folder: { parent_id: child.id } }

    assert_nil @documents.reload.parent_id
  end

  test "deleting a folder trashes it together with its contents" do
    child = users(:alice).folders.create!(name: "Invoices", parent: @documents)
    file = upload_into(child, "invoice.pdf")

    delete folder_path(@documents)

    assert @documents.reload.deleted?
    assert child.reload.deleted?
    assert file.reload.deleted?
  end

  test "a trashed folder can be restored with its contents" do
    file = upload_into(@documents, "invoice.pdf")
    @documents.discard!

    post restore_folder_path(@documents)

    assert_not @documents.reload.deleted?
    assert_not file.reload.deleted?
  end

  test "a trashed folder can be purged with its contents" do
    upload_into(@documents, "invoice.pdf")
    @documents.discard!

    assert_difference -> { StoredFile.count }, -1 do
      assert_difference -> { Folder.count }, -1 do
        delete purge_folder_path(@documents)
      end
    end
  end

  test "a file can be moved into a folder" do
    file = upload_into(nil, "notes.txt")

    patch file_path(file), params: { stored_file: { folder_id: @documents.id } }

    assert_equal @documents, file.reload.folder
  end

  test "a file cannot be moved into a folder owned by somebody else" do
    foreign = users(:bob).folders.create!(name: "Bob")
    file = upload_into(nil, "notes.txt")

    patch file_path(file), params: { stored_file: { folder_id: foreign.id } }

    assert_nil file.reload.folder_id
  end

  test "restoring a file whose folder is still deleted returns it to the root" do
    file = upload_into(@documents, "notes.txt")
    file.discard!
    travel 1.minute do
      @documents.discard!
    end

    post restore_file_path(file)

    assert_not file.reload.deleted?
    assert_nil file.folder_id
  end

  test "uploads land in the folder they were started from" do
    post files_path, params: { folder_id: @documents.id, files: [ uploaded_file(filename: "x.txt") ] }

    assert_equal @documents, StoredFile.order(:created_at).last.folder
    assert_redirected_to folder_path(@documents)
  end

  test "another user cannot browse a folder they do not own" do
    foreign = users(:bob).folders.create!(name: "Bob private")

    get folder_path(foreign)
    assert_response :not_found
  end

  test "another user cannot rename or delete a folder they do not own" do
    foreign = users(:bob).folders.create!(name: "Bob private")

    patch folder_path(foreign), params: { folder: { name: "taken over" } }
    assert_response :not_found

    delete folder_path(foreign)
    assert_response :not_found
    assert_not foreign.reload.deleted?
  end

  private
    def upload_into(folder, name)
      stored_file = users(:alice).stored_files.new(folder: folder)
      stored_file.attachment.attach(
        io: StringIO.new("content"), filename: name, content_type: "text/plain"
      )
      stored_file.save!
      stored_file
    end
end
