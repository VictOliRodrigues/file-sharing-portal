require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings.
  config.eager_load = true

  # Never leak internal details through error pages.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Uploaded files are stored either on disk or on an S3-compatible service.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym

  # Almost every deployment (Docker, Coolify, nginx, Traefik, Caddy) terminates
  # TLS in front of the application, so trust the proxy headers.
  config.assume_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch("ASSUME_SSL", "true"))

  # Force HTTPS, enable HSTS and mark cookies as secure. Operators running the
  # portal on a private network without TLS can opt out with FORCE_SSL=false.
  config.force_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch("FORCE_SSL", "true"))

  # The health check endpoint must stay reachable over plain HTTP so that
  # container orchestrators can probe it.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT so the container runtime owns log collection.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  # A shared cache store keeps rate limiting accurate across Puma workers.
  # Without REDIS_URL the portal should be run as a single Puma process
  # (WEB_CONCURRENCY=0, the default), where the in-memory store is shared by
  # every request thread.
  config.cache_store =
    if ENV["REDIS_URL"].present?
      [ :redis_cache_store, { url: ENV["REDIS_URL"], error_handler: ->(method:, returning:, exception:) {
        Rails.logger.error("Cache error in #{method}: #{exception.class}")
      } } ]
    else
      :memory_store
    end

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    protocol: ActiveModel::Type::Boolean.new.cast(ENV.fetch("FORCE_SSL", "true")) ? "https" : "http"
  }

  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      domain: ENV["SMTP_DOMAIN"].presence,
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").presence,
      enable_starttls_auto: ActiveModel::Type::Boolean.new.cast(ENV.fetch("SMTP_ENABLE_STARTTLS", "true"))
    }.compact
  else
    # Without SMTP configured, password reset instructions are written to the
    # application log instead of being silently dropped.
    config.action_mailer.delivery_method = :logger
  end

  config.i18n.fallbacks = true

  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding protection. ALLOWED_HOSTS is a comma separated list; when it
  # is empty every host is accepted, which is the only workable default for
  # self-hosted deployments behind an unknown reverse proxy.
  allowed_hosts = ENV.fetch("ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:blank?)
  allowed_hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?
  config.hosts = allowed_hosts.uniq if allowed_hosts.any?
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
