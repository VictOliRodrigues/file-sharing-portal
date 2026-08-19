# Serves the bytes behind a public share link.
#
# Separate from Public::SharesController because streaming pulls in
# ActionController::Live, which runs every action of its controller in its own
# thread.
class Public::DownloadsController < ApplicationController
  include ShareLinkAccess
  include BlobStreaming

  def show
    stored_file = shared_file(params[:file_id])
    return render_unavailable if stored_file.nil?

    # Checked once more here: a concurrent request may have consumed the last
    # download allowed by the limit since the before_action ran.
    return render_unavailable unless @share_link.available?

    @share_link.record_download!(stored_file, ip_address: request.remote_ip)
    stream_stored_file(stored_file, disposition: "attachment")
  end
end
