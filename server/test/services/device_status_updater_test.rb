require "test_helper"

class DeviceStatusUpdaterTest < ActiveSupport::TestCase
  test "offline이면 알림을 한 번만 열고 online이면 닫는다" do
    DeviceStatusUpdater.call(device_id: "balcony-01", state: "offline")
    DeviceStatusUpdater.call(device_id: "balcony-01", state: "offline")
    device = Device.find_by!(device_id: "balcony-01")

    assert_equal "offline", device.mqtt_state
    assert_equal 1, device.alert_events.open.where(kind: "device_offline").count

    DeviceStatusUpdater.call(device_id: "balcony-01", state: "online")
    assert_equal 0, device.alert_events.open.count
    assert_not device.reload.alert_events.first.open?
  end

  test "알 수 없는 상태 문자열은 무시한다" do
    assert_nil DeviceStatusUpdater.call(device_id: "balcony-01", state: "???")
    assert_equal 0, Device.count
  end

  test "offline 상태 장치는 최근에 수신했어도 오프라인으로 본다" do
    device = Device.create!(device_id: "balcony-01", last_seen_at: Time.current)
    assert device.online?

    device.update!(mqtt_state: "offline")
    assert_not device.online?
  end
end
