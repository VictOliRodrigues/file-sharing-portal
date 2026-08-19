require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "the reset email is addressed to the account holder and carries a working link" do
    user = users(:alice)
    email = PasswordsMailer.reset(user)

    assert_equal [ user.email_address ], email.to
    assert_match(/reset your/i, email.subject)

    # The plain text part is read rather than the raw source, so the assertion
    # is not defeated by quoted-printable line wrapping.
    body = email.text_part&.decoded || email.body.decoded
    token = body[%r{/passwords/([^/\s]+)/edit}, 1]

    assert token.present?, "the email must contain a password reset link"
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "both a plain text and an HTML part are sent" do
    email = PasswordsMailer.reset(users(:alice))

    assert email.multipart?
    assert email.text_part.present?
    assert email.html_part.present?
  end

  test "the reset email never contains the password digest" do
    user = users(:alice)
    email = PasswordsMailer.reset(user)

    assert_not email.body.encoded.include?(user.password_digest)
  end

  test "the sender is set" do
    email = PasswordsMailer.reset(users(:alice))

    assert email.from.present?
  end
end
