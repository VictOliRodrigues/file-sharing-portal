# Per-request state. Anything stored here is reset between requests.
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user_agent, :ip_address

  delegate :user, to: :session, allow_nil: true
end
