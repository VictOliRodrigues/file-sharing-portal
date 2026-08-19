class TrashController < ApplicationController
  def show
    @stored_files = current_user.stored_files.discarded.order(deleted_at: :desc)
  end
end
