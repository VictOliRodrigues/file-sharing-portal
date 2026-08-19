require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires a name, an email address and a password" do
    user = User.new
    assert_not user.valid?
    assert user.errors[:name].any?
    assert user.errors[:email_address].any?
    assert user.errors[:password].any?
  end

  test "normalizes the email address" do
    user = User.create!(name: "Case Test", email_address: "  MiXeD@Example.COM ",
                        password: "a-long-enough-password")
    assert_equal "mixed@example.com", user.email_address
  end

  test "rejects a duplicate email address regardless of case" do
    user = User.new(name: "Copy", email_address: "ADA@example.com", password: "a-long-enough-password")
    assert_not user.valid?
    assert user.errors[:email_address].any?
  end

  test "rejects passwords shorter than the minimum length" do
    user = User.new(name: "Shorty", email_address: "shorty@example.com", password: "short")
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "stores the password as a bcrypt digest and never in clear text" do
    user = users(:alice)
    assert_no_match(/correct horse/, user.password_digest)
    assert user.authenticate(TEST_PASSWORD)
    assert_not user.authenticate("wrong password")
  end

  test "disabling revokes every session" do
    user = users(:alice)
    user.sessions.create!(ip_address: "127.0.0.1", user_agent: "test")
    assert_difference -> { Session.count }, -1 do
      user.disable!
    end
    assert user.reload.disabled?
  end

  test "password reset tokens stop working once the password changes" do
    user = users(:alice)
    token = user.generate_token_for(:password_reset)
    assert_equal user, User.find_by_token_for(:password_reset, token)

    user.update!(password: "a-brand-new-password")
    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "storage quota falls back to the deployment default and treats zero as unlimited" do
    user = users(:alice)
    assert_nil user.storage_quota

    user.update!(storage_quota_bytes: 10.megabytes)
    assert_equal 10.megabytes, user.storage_quota

    user.update!(storage_quota_bytes: 0)
    assert_nil user.storage_quota
  end
end
