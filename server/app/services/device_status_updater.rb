# status 토픽(online/offline)을 반영한다. offline이면 알림을 열고 online이면 닫는다.
class DeviceStatusUpdater
  STATES = %w[online offline].freeze

  def self.call(device_id:, state:, at: Time.current) = new(device_id, state.to_s.strip, at).call

  def initialize(device_id, state, at)
    @device_id = device_id
    @state = state
    @at = at
  end

  def call
    return unless STATES.include?(@state) && @device_id.present?

    device = Device.find_or_create_by!(device_id: @device_id)
    device.update!(mqtt_state: @state)
    @state == "offline" ? open_alert(device) : close_alert(device)
    device
  end

  private

  def open_alert(device)
    return if device.alert_events.open.exists?(kind: "device_offline")

    device.alert_events.create!(kind: "device_offline", message: "장치가 오프라인입니다", triggered_at: @at)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def close_alert(device)
    device.alert_events.open.where(kind: "device_offline").update_all(resolved_at: @at, updated_at: @at)
  end
end
