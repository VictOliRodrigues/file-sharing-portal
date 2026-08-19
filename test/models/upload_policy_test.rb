require "test_helper"

class UploadPolicyTest < ActiveSupport::TestCase
  teardown do
    ENV.delete("UPLOAD_ALLOWED_EXTENSIONS")
    ENV.delete("UPLOAD_BLOCKED_EXTENSIONS")
    UploadPolicy.reset!
  end

  test "accepts everything when neither list is configured" do
    configure(allowed: nil, blocked: nil)

    assert UploadPolicy.allows?(name: "report.pdf")
    assert UploadPolicy.allows?(name: "tool.exe")
    assert UploadPolicy.allows?(name: "no-extension")
  end

  test "rejects a blocked extension" do
    configure(blocked: "exe, bat")

    assert_not UploadPolicy.allows?(name: "tool.exe")
    assert_not UploadPolicy.allows?(name: "script.bat")
    assert UploadPolicy.allows?(name: "report.pdf")
  end

  test "matching is case insensitive and tolerates a leading dot" do
    configure(blocked: ".EXE")

    assert_not UploadPolicy.allows?(name: "tool.exe")
    assert_not UploadPolicy.allows?(name: "TOOL.EXE")
  end

  test "an allowlist rejects everything outside it" do
    configure(allowed: "pdf,png")

    assert UploadPolicy.allows?(name: "report.pdf")
    assert UploadPolicy.allows?(name: "photo.PNG")
    assert_not UploadPolicy.allows?(name: "notes.txt")
    assert_not UploadPolicy.allows?(name: "no-extension")
  end

  test "the blocklist wins over the allowlist" do
    configure(allowed: "pdf,exe", blocked: "exe")

    assert UploadPolicy.allows?(name: "report.pdf")
    assert_not UploadPolicy.allows?(name: "tool.exe")
  end

  test "only the final extension counts, so a double extension cannot slip through" do
    configure(blocked: "exe")

    assert_not UploadPolicy.allows?(name: "invoice.pdf.exe")
    assert UploadPolicy.allows?(name: "invoice.exe.pdf")
  end

  private
    def configure(allowed: nil, blocked: nil)
      ENV["UPLOAD_ALLOWED_EXTENSIONS"] = allowed
      ENV["UPLOAD_BLOCKED_EXTENSIONS"] = blocked
      UploadPolicy.reset!
    end
end
