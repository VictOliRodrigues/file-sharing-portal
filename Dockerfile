# syntax=docker/dockerfile:1
# check=error=true

# Production image for the File Sharing Portal.
#
#   docker build -t file-sharing-portal .
#   docker run -d -p 3000:80 --env-file .env -v portal_storage:/rails/storage file-sharing-portal
#
# See docs/deployment.md for Docker Compose, VPS and Coolify instructions.

ARG RUBY_VERSION=3.4.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages only. libvips powers image previews, postgresql-client is
# used by the entrypoint to wait for and prepare the database.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# ---------------------------------------------------------------------------
# Build stage: compile gems and assets, then throw the toolchain away.
# ---------------------------------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

# Ensure the helper scripts stay executable regardless of the host filesystem.
RUN chmod +x bin/*

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Assets are precompiled without any real secret; SECRET_KEY_BASE_DUMMY tells
# Rails to use a throw-away key for the duration of the build.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---------------------------------------------------------------------------
# Final image.
# ---------------------------------------------------------------------------
FROM base

# Run as an unprivileged user.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Writable locations for the runtime user. /rails/storage is the default target
# for the local Active Storage service and should be backed by a volume.
RUN mkdir -p /rails/storage /rails/tmp /rails/log && \
    chown -R rails:rails /rails/storage /rails/tmp /rails/log

USER 1000:1000

VOLUME ["/rails/storage"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl --fail --silent --output /dev/null http://localhost/up || exit 1

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
