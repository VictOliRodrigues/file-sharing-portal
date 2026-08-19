# Everything under /admin.
#
# Administrators can see and manage other accounts, so the whole namespace is
# gated in one place rather than action by action.
class Admin::BaseController < ApplicationController
  before_action :require_administrator

  layout "application"
end
