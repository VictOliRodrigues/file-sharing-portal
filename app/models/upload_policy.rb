# Decides whether a given upload may be stored.
#
# Two independent lists are supported, both configured through the environment:
#
#   UPLOAD_ALLOWED_EXTENSIONS  when set, only these extensions are accepted
#   UPLOAD_BLOCKED_EXTENSIONS  these extensions are always rejected
#
# Both default to empty, because a general purpose file portal has to accept
# arbitrary files. Blocking types is a policy decision for the operator, not a
# security control: the portal never executes an upload, always serves it with
# `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`, and
# only ever renders a short allowlist of raster image types inline.
module UploadPolicy
  module_function

  def allows?(name:, content_type: nil)
    extension = File.extname(name.to_s).delete_prefix(".").downcase

    return false if blocked_extensions.include?(extension)
    return true  if allowed_extensions.empty?

    allowed_extensions.include?(extension)
  end

  def allowed_extensions
    @allowed_extensions ||= parse(ENV["UPLOAD_ALLOWED_EXTENSIONS"])
  end

  def blocked_extensions
    @blocked_extensions ||= parse(ENV["UPLOAD_BLOCKED_EXTENSIONS"])
  end

  # Used by the test suite to exercise a different policy.
  def reset!
    @allowed_extensions = nil
    @blocked_extensions = nil
  end

  def parse(value)
    value.to_s.split(",").map { |item| item.strip.delete_prefix(".").downcase }.reject(&:blank?).to_set
  end
end
