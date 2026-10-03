class DashboardController < ApplicationController
  def show
    @devices = Device.order(:device_id)
    @alerts = AlertEvent.includes(:device).recent
  end
end
