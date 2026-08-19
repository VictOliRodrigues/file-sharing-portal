require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FileSharingPortal
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = ENV.fetch("TIME_ZONE", "UTC")

    # Generators: no helper or asset files.
    config.generators do |g|
      g.helper false
      g.assets false
    end

    # Active Storage's own routes are disabled on purpose. Every byte is served
    # by FilesController or Public::SharesController so that ownership, share
    # link validity and download accounting are always enforced, and so that no
    # blob key or filesystem path is ever exposed to a client.
    config.active_storage.draw_routes = false

    # Only these content types may ever be rendered inline in the browser.
    # Serving arbitrary user uploads inline on the application origin would
    # allow stored cross-site scripting.
    config.active_storage.content_types_allowed_inline = %w[
      image/png image/jpeg image/gif image/webp
    ]

    # Rack::Attack provides request throttling for authentication and for the
    # public share endpoints.
    config.middleware.use Rack::Attack
  end
end
