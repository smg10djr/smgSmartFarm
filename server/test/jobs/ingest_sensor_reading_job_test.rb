require "test_helper"

class IngestSensorReadingJobTest < ActiveJob::TestCase
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
end
