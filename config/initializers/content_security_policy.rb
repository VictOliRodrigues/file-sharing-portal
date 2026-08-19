# frozen_string_literal: true

# Content Security Policy.
#
# The portal serves only first-party assets, so the policy can stay strict.
# Inline <script> and <style> elements are allowed exclusively through a
# per-request nonce, which Rails injects into the tags it renders.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.font_src        :self, :data
    policy.img_src         :self, :data, :blob
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self
    policy.connect_src     :self
    policy.form_action     :self
    policy.frame_ancestors :none
    policy.frame_src       :none
  end

  # A fresh nonce per response. The Rails default derives the nonce from the
  # session id, which is empty before a session exists -- that produces a
  # nonce- source that matches nothing and blocks the import map on the sign
  # in page -- and is predictable for the lifetime of a session.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # Report violations without enforcing them by setting CSP_REPORT_ONLY=true,
  # which is useful when putting the portal behind a custom front-end.
  config.content_security_policy_report_only =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("CSP_REPORT_ONLY", "false"))
end
