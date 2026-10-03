require "test_helper"
require "turbo/broadcastable/test_helper"

class IngestSensorReadingJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper
  include Turbo::Broadcastable::TestHelper

  def payload(temp)
    { schemaVersion: 1, deviceId: "balcony-01", measuredAt: "2026-10-03T03:30:00Z", waterTemperatureC: temp }.to_json
  end

  test "저장하고 고온이면 알림을 만든다" do
    IngestSensorReadingJob.perform_now(payload(26.0))

    assert_equal 1, SensorReading.count
    assert_equal [ "high_water_temp" ], AlertEvent.open.pluck(:kind)
  end

  test "거절된 메시지는 아무것도 만들지 않는다" do
    IngestSensorReadingJob.perform_now("{broken")

    assert_equal 0, SensorReading.count
    assert_equal 0, AlertEvent.count
  end

  test "첫 장치가 생기면 #devices 컨테이너 전체를 방송한다" do
    assert_broadcasts("dashboard", 3) do
      IngestSensorReadingJob.perform_now(payload(20.0))
    end
  end

  test "장치가 없던 화면에 첫 메시지가 오면 카드와 입력 폼을 방송한다" do
    assert_equal 0, Device.count

    streams = capture_turbo_stream_broadcasts("dashboard") do
      IngestSensorReadingJob.perform_now(payload(20.0))
    end
    by_target = streams.index_by { |s| s["target"] }

    devices = by_target.fetch("devices")
    assert_equal "replace", devices["action"]
    assert_match(/<section id="device_\d+"/, devices.to_html)
    assert_no_match(/수신된 장치가 없습니다/, devices.to_html)

    assert_match(/<form/, by_target.fetch("manual-section").to_html)
  end

  test "알림이 하나도 없던 화면에 첫 알림이 생기면 알림 목록을 방송한다" do
    assert_equal 0, AlertEvent.count

    streams = capture_turbo_stream_broadcasts("dashboard") do
      IngestSensorReadingJob.perform_now(payload(26.0))
    end
    alerts = streams.find { |s| s["target"] == "alerts" }.to_html

    assert_match(/26\.0/, alerts)
    assert_no_match(/알림이 없습니다/, alerts)
  end
end
