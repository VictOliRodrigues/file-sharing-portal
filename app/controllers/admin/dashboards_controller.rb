class Admin::DashboardsController < Admin::BaseController
  def show
    @statistics = SystemStatistics.new
  end
end
