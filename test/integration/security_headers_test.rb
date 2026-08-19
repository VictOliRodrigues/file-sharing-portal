require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "every response carries the hardening headers" do
    get sign_in_path

    assert_response :success
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "none", response.headers["X-Permitted-Cross-Domain-Policies"]
    assert_match(/camera=\(\)/, response.headers["Permissions-Policy"])
  end

  test "a content security policy is sent and does not allow inline scripts" do
    get sign_in_path

    policy = response.headers["Content-Security-Policy"]

    assert policy.present?
    assert_match(/default-src 'self'/, policy)
    assert_match(/object-src 'none'/, policy)
    assert_match(/frame-ancestors 'none'/, policy)
    assert_match(/base-uri 'self'/, policy)
    assert_match(/form-action 'self'/, policy)
    assert_no_match(/'unsafe-inline'/, policy)
    assert_no_match(/'unsafe-eval'/, policy)
  end

  test "the nonce in the policy is present and matches the one used by the page" do
    get sign_in_path

    policy = response.headers["Content-Security-Policy"]
    nonce = response.body[/name="csp-nonce" content="([^"]+)"/, 1]

    assert nonce.present?, "the page must carry a non-empty nonce"
    assert_includes policy, "'nonce-#{nonce}'"
    # The import map is an inline script; without a matching nonce the whole
    # front-end is blocked by the policy.
    assert_match(/<script type="importmap"[^>]*nonce="#{Regexp.escape(nonce)}"/, response.body)
  end

  test "the nonce changes on every response" do
    get sign_in_path
    first = response.body[/name="csp-nonce" content="([^"]+)"/, 1]

    get sign_in_path
    second = response.body[/name="csp-nonce" content="([^"]+)"/, 1]

    assert first.present?
    assert_not_equal first, second
  end

  test "public share pages are protected by the same headers" do
    owner = users(:alice)
    stored_file = owner.stored_files.new
    stored_file.attachment.attach(
      io: StringIO.new("content"), filename: "shared.txt", content_type: "text/plain"
    )
    stored_file.save!
    link = owner.share_links.create!(shareable: stored_file)

    get share_path(link.token)

    assert_response :success
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert response.headers["Content-Security-Policy"].present?
    assert_match(/name="referrer" content="no-referrer"/, response.body)
  end

  test "the session cookie is marked HttpOnly and SameSite Lax" do
    sign_in_as users(:alice)

    cookie_header = Array(response.headers["set-cookie"]).join("\n")
    session_cookie = cookie_header.lines.find { |line| line.start_with?("session_id=") }

    assert session_cookie.present?
    assert_match(/httponly/i, session_cookie)
    assert_match(/samesite=lax/i, session_cookie)
  end
end
