class UpdateDeviceStatusJob < ApplicationJob
  queue_as :default

  def perform(device_id, state, at = Time.current)
    device = DeviceStatusUpdater.call(device_id: device_id, state: state, at: at)
    DashboardBroadcaster.call(device) if device
  end
end
