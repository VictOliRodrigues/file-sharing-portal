require "test_helper"

class SafeFilenameTest < ActiveSupport::TestCase
  test "keeps an ordinary filename intact" do
    assert_equal "quarterly-report.pdf", SafeFilename.call("quarterly-report.pdf")
  end

  test "strips POSIX directory traversal" do
    assert_equal "passwd", SafeFilename.call("../../../etc/passwd")
    assert_equal "passwd", SafeFilename.call("/etc/passwd")
  end

  test "strips Windows directory traversal" do
    assert_equal "config.ini", SafeFilename.call("..\\..\\windows\\config.ini")
    assert_equal "system.dll", SafeFilename.call("C:\\Windows\\System32\\system.dll")
  end

  test "removes null bytes and control characters" do
    assert_equal "notes.txt", SafeFilename.call("notes\u0000.txt")
    assert_equal "notes.txt", SafeFilename.call("no\u0007tes.txt")
    assert_equal "ab.txt", SafeFilename.call("a\nb.txt")
  end

  test "replaces characters that are unsafe in paths and headers" do
    assert_equal "a-b-c.txt", SafeFilename.call("a<b>c.txt")
    assert_equal "quote-.txt", SafeFilename.call("quote\".txt")
  end

  test "rejects bare relative path components" do
    assert_equal SafeFilename::FALLBACK, SafeFilename.call(".")
    assert_equal SafeFilename::FALLBACK, SafeFilename.call("..")
    assert_equal SafeFilename::FALLBACK, SafeFilename.call("...")
  end

  test "falls back for blank input" do
    assert_equal SafeFilename::FALLBACK, SafeFilename.call("")
    assert_equal SafeFilename::FALLBACK, SafeFilename.call(nil)
    assert_equal SafeFilename::FALLBACK, SafeFilename.call("   ")
  end

  test "keeps leading dots so dotfiles survive" do
    assert_equal ".gitignore", SafeFilename.call(".gitignore")
  end

  test "collapses whitespace and trims the edges" do
    assert_equal "my report.txt", SafeFilename.call("  my   report.txt  ")
  end

  test "truncates very long names but keeps the extension" do
    name = "#{'a' * 500}.pdf"
    result = SafeFilename.call(name)

    assert_operator result.length, :<=, SafeFilename::MAX_LENGTH
    assert result.end_with?(".pdf")
  end

  test "survives invalid byte sequences" do
    assert_nothing_raised { SafeFilename.call("bad\xC3.txt".dup.force_encoding("UTF-8")) }
  end

  test "never returns a value containing a path separator" do
    [ "../a/b", "a\\b", "//etc//shadow", "....//....//x", "\\\\server\\share\\f.txt" ].each do |candidate|
      result = SafeFilename.call(candidate)
      assert_not result.include?("/"), "#{candidate.inspect} produced #{result.inspect}"
      assert_not result.include?("\\"), "#{candidate.inspect} produced #{result.inspect}"
    end
  end
end
