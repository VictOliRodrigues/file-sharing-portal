# Serves the bytes of a file to its owner.
#
# Kept separate from FilesController because streaming pulls in
# ActionController::Live, which runs every action of its controller in a
# dedicated thread. Only the two actions that actually move bytes need that.
class FileTransfersController < ApplicationController
  include BlobStreaming

  before_action :set_stored_file

  def download
    @stored_file.record_download!(user: current_user, ip_address: request.remote_ip)
    stream_stored_file(@stored_file, disposition: "attachment")
  end

  # Serves small raster images inline so the interface can show a preview.
  # Anything else is refused rather than being rendered on our own origin.
  def preview
    head :not_found and return unless @stored_file.previewable_image?

    stream_stored_file(@stored_file, disposition: "inline")
  end

  private
    # Scoped to the signed-in user, so a file owned by somebody else simply
    # cannot be found and the request is answered with a 404.
    def set_stored_file
      @stored_file = current_user.stored_files.kept.find(params[:id])
    end
end
