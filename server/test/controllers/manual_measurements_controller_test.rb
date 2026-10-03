require "test_helper"

class ManualMeasurementsControllerTest < ActionDispatch::IntegrationTest
  setup { @device = Device.create!(device_id: "balcony-01") }

  test "pH와 EC를 기록하고 대시보드에 보여준다" do
    assert_difference -> { ManualMeasurement.count }, 1 do
      post manual_measurements_url, params: { manual_measurement: { device_id: @device.id, ph: "6.1", ec_ms_cm: "1.3", note: "양액 교체" } }
    end
    follow_redirect!

    assert_select "p.notice", /기록했습니다/
    assert_select "section#device_#{@device.id}", /pH 6\.1/
  end

  test "범위를 벗어난 값은 저장하지 않는다" do
    assert_no_difference -> { ManualMeasurement.count } do
      post manual_measurements_url, params: { manual_measurement: { device_id: @device.id, ph: "15" } }
    end
    follow_redirect!

    assert_select "p.alert-open"
  end

  test "pH와 EC가 모두 비면 저장하지 않는다" do
    assert_no_difference -> { ManualMeasurement.count } do
      post manual_measurements_url, params: { manual_measurement: { device_id: @device.id, note: "메모만" } }
    end
  end
end
