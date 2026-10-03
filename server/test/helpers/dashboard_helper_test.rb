require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  setup do
    @now = Time.zone.parse("2026-10-03 12:00")
    @device = Device.create!(device_id: "balcony-01")
  end

  def add_reading(minutes_ago, temp)
    @device.sensor_readings.create!(measured_at: @now - minutes_ago.minutes, water_temperature_c: temp)
  end

  test "24시간 안에 두 개 이상이면 좌표를 돌려준다" do
    add_reading(120, 20.0)
    add_reading(60, 22.0)

    points = water_temp_points(@device, now: @now)

    assert_equal 2, points.split.size
  end

  test "데이터가 하나뿐이면 nil이다" do
    add_reading(60, 20.0)

    assert_nil water_temp_points(@device, now: @now)
  end

  test "24시간보다 오래된 값은 그리지 않는다" do
    add_reading(25 * 60, 18.0)
    add_reading(60, 22.0)

    assert_nil water_temp_points(@device, now: @now)
  end
end
