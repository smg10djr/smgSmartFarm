require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "장치가 없으면 안내 문구를 보여준다" do
    get root_url

    assert_response :success
    assert_select "p", /수신된 장치가 없습니다/
  end

  test "최신 수온과 알림, 그래프를 보여준다" do
    device = Device.create!(device_id: "balcony-01", last_seen_at: Time.current)
    [ 20.0, 25.0 ].each_with_index do |temp, i|
      device.sensor_readings.create!(measured_at: (2 - i).hours.ago, water_temperature_c: temp)
    end
    device.alert_events.create!(kind: "high_water_temp", message: "수온 25.0℃", triggered_at: Time.current)

    get root_url

    assert_response :success
    assert_select "section#device_#{device.id}", /25\.0 ℃/
    assert_select "svg.chart polyline"
    assert_select "#alerts li.alert-open", /수온 25.0℃/
  end
end
