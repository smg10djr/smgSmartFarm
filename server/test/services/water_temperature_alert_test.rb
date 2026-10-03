require "test_helper"

class WaterTemperatureAlertTest < ActiveSupport::TestCase
  setup { @device = Device.create!(device_id: "balcony-01") }

  def reading(temp, minute)
    @device.sensor_readings.create!(measured_at: Time.utc(2026, 10, 3, 3, minute), water_temperature_c: temp)
  end

  test "24℃ 이상이면 알림을 한 번만 연다" do
    WaterTemperatureAlert.call(reading(24.5, 0))
    WaterTemperatureAlert.call(reading(25.0, 1))

    assert_equal 1, @device.alert_events.open.where(kind: "high_water_temp").count
  end

  test "기준 아래로 0.5℃ 이상 내려가야 해제한다" do
    WaterTemperatureAlert.call(reading(24.5, 0))
    WaterTemperatureAlert.call(reading(23.8, 1))
    assert_equal 1, @device.alert_events.open.count

    WaterTemperatureAlert.call(reading(23.0, 2))
    assert_equal 0, @device.alert_events.open.count
    assert_equal Time.utc(2026, 10, 3, 3, 2), @device.alert_events.first.resolved_at
  end

  test "15℃ 이하이면 저수온 알림을 연다" do
    WaterTemperatureAlert.call(reading(14.0, 0))

    assert_equal [ "low_water_temp" ], @device.alert_events.open.pluck(:kind)
  end

  test "정상 수온이면 알림이 없다" do
    WaterTemperatureAlert.call(reading(19.0, 0))

    assert_equal 0, AlertEvent.count
  end
end
