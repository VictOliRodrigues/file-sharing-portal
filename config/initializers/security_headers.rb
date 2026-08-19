# frozen_string_literal: true

# Response headers applied to every request.
#
# Rails already sets a sensible baseline; these values tighten it further.
Rails.application.config.action_dispatch.default_headers.merge!(
  # The portal is never meant to be embedded in a frame.
  "X-Frame-Options" => "DENY",
  # Do not let browsers guess a content type for downloads.
  "X-Content-Type-Options" => "nosniff",
  # Do not leak paths or share tokens through the Referer header.
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  # No page in the portal needs any of these device APIs.
  "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), " \
                          "magnetometer=(), microphone=(), payment=(), usb=()",
  # Isolate the browsing context from cross-origin windows.
  "Cross-Origin-Opener-Policy" => "same-origin",
  "X-Permitted-Cross-Domain-Policies" => "none"
)
