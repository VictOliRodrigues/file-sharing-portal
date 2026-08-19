# frozen_string_literal: true

# Request throttling.
#
# Rack::Attack sits in front of the application and limits how often a single
# client may hit sensitive endpoints. Counters live in the Rails cache, so with
# more than one Puma worker a shared cache store (REDIS_URL) is required for the
# limits to be exact -- see config/environments/production.rb.
class Rack::Attack
  # Throttling is disabled in the test environment by default; the dedicated
  # rate limiting test switches it back on.
  self.enabled =
    if Rails.env.test?
      ActiveModel::Type::Boolean.new.cast(ENV["ENABLE_RACK_ATTACK"])
    else
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("RATE_LIMIT_ENABLED", "true"))
    end

  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period] || 60
    [
      429,
      { "content-type" => "text/plain", "retry-after" => retry_after.to_s },
      [ "Too many requests. Please retry in #{retry_after} seconds.\n" ]
    ]
  end

  ### Safelists ###############################################################

  # Never throttle the container health check.
  safelist("allow health checks") { |request| request.path == "/up" }

  # Never throttle static assets.
  safelist("allow assets") { |request| request.path.start_with?("/assets") }

  ### General protection ######################################################

  # A generous ceiling that only catches automated abuse.
  throttle("req/ip", limit: ENV.fetch("RATE_LIMIT_REQUESTS", "300").to_i, period: 5.minutes) do |request|
    request.ip
  end

  ### Authentication ##########################################################

  # Credential stuffing protection, by source address.
  throttle("logins/ip", limit: 10, period: 1.minute) do |request|
    request.ip if request.post? && request.path == "/sign_in"
  end

  # Password spraying protection, by targeted account.
  throttle("logins/email", limit: 5, period: 20.minutes) do |request|
    if request.post? && request.path == "/sign_in"
      request.params.dig("email_address").to_s.downcase.strip.presence
    end
  end

  # Account creation abuse.
  throttle("signups/ip", limit: 5, period: 1.hour) do |request|
    request.ip if request.post? && request.path == "/sign_up"
  end

  # Password reset flooding, both by source address and by targeted account.
  throttle("password_resets/ip", limit: 5, period: 1.hour) do |request|
    request.ip if request.post? && request.path == "/passwords"
  end

  throttle("password_resets/email", limit: 3, period: 1.hour) do |request|
    if request.post? && request.path == "/passwords"
      request.params.dig("email_address").to_s.downcase.strip.presence
    end
  end

  ### Public share links ######################################################

  # Brute forcing the password of a protected share link.
  throttle("share_unlock/ip", limit: 10, period: 10.minutes) do |request|
    request.ip if request.post? && request.path.match?(%r{\A/s/[^/]+/unlock\z})
  end

  # Guessing share tokens.
  throttle("share_access/ip", limit: 60, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/s/")
  end
end

# Log throttled requests so operators can spot abuse.
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.warn(
    "[rack-attack] throttled #{request.env['rack.attack.matched']} " \
    "ip=#{request.ip} path=#{request.path}"
  )
end
