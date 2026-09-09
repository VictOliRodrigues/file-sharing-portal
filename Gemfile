source "https://rubygems.org"

# --- Framework -------------------------------------------------------------
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"

# --- Asset pipeline & front-end (Hotwire) ----------------------------------
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# --- Authentication --------------------------------------------------------
# Password hashing for `has_secure_password`.
gem "bcrypt", "~> 3.1.7"

# --- Storage ---------------------------------------------------------------
# Active Storage S3 service (also used for any S3-compatible provider such as
# MinIO, Backblaze B2, Cloudflare R2 or Hetzner Object Storage).
gem "aws-sdk-s3", "~> 1.0", require: false
# Image previews/variants for uploaded images. Since image_processing 2.0 the
# backend is no longer a dependency of the gem, so ruby-vips has to be declared
# explicitly -- it is the variant processor Rails defaults to, and the one the
# Docker image installs libvips for.
#
# Both are loaded lazily by Active Storage when a variant is actually
# processed, so neither is required at boot. ruby-vips binds to libvips through
# FFI and raises on load when that system library is absent, which would
# otherwise break every task that merely boots the application -- linting and
# security scanning in CI, for instance -- on a machine without it.
gem "image_processing", "~> 2.1", require: false
gem "ruby-vips", "~> 2.2", require: false

# --- Security --------------------------------------------------------------
# Request throttling and blocklisting.
gem "rack-attack", "~> 6.7"

# --- Runtime ---------------------------------------------------------------
# Windows does not include zoneinfo files, so bundle the tzinfo-data gem.
gem "tzinfo-data", platforms: %i[ windows jruby ]
# Reduces boot times through caching; required in config/boot.rb.
gem "bootsnap", require: false
# HTTP asset caching/compression and X-Sendfile acceleration in front of Puma.
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  # Audits gems for known security advisories.
  gem "bundler-audit", require: false
  # Static analysis for security vulnerabilities.
  gem "brakeman", require: false
  # Omakase Ruby styling.
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Runs the Procfile.dev processes for bin/dev.
  gem "foreman", require: false
  gem "web-console"
end
