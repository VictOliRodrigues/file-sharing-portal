# Streams Active Storage blobs through the application.
#
# Active Storage's own routes are disabled, so this is the only way bytes leave
# the server. Streaming rather than buffering keeps memory flat regardless of
# file size, and it means the storage backend (local disk or S3) is never
# exposed to the client.
#
# ActionController::Live runs the action in its own thread, so only the
# controllers that actually serve bytes should include this concern.
module BlobStreaming
  extend ActiveSupport::Concern

  included do
    include ActionController::DataStreaming
    include ActionController::Live
  end

  # Types a browser will happily execute in the context of our own origin if it
  # is ever tricked into rendering them. They are always served as an opaque
  # download instead.
  NEVER_SERVE_AS_DECLARED = %w[
    text/html application/xhtml+xml image/svg+xml application/xml text/xml
    application/javascript text/javascript application/x-shockwave-flash
  ].freeze

  BINARY_CONTENT_TYPE = "application/octet-stream".freeze

  private
    # `disposition` must be either "attachment" or "inline". Inline is only ever
    # used for the small allowlist of raster image types.
    def stream_stored_file(stored_file, disposition: "attachment")
      blob = stored_file.attachment.blob

      send_stream(
        filename: stored_file.name,
        disposition: disposition,
        type: serving_content_type(stored_file, disposition)
      ) do |stream|
        blob.download { |chunk| stream.write(chunk) }
      rescue ActiveStorage::FileNotFoundError
        # The metadata outlived the bytes; do not pretend the download worked.
        Rails.logger.error("Missing blob for stored file #{stored_file.id}")
      end
    end

    def serving_content_type(stored_file, disposition)
      return stored_file.content_type if disposition == "inline" && stored_file.previewable_image?
      return BINARY_CONTENT_TYPE if NEVER_SERVE_AS_DECLARED.include?(stored_file.content_type)

      stored_file.content_type.presence || BINARY_CONTENT_TYPE
    end
end
