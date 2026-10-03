require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  test "최근에 수신했으면 온라인이다" do
    device = Device.create!(device_id: "balcony-01", last_seen_at: 4.minutes.ago)

    assert device.online?
  end

  test "5분 넘게 수신이 없으면 오프라인이다" do
    device = Device.create!(device_id: "balcony-01", last_seen_at: 6.minutes.ago)

    assert_not device.online?
  end

  test "한 번도 수신하지 않았으면 오프라인이다" do
    device = Device.create!(device_id: "balcony-01", last_seen_at: nil)

    assert_not device.online?
  end
end
