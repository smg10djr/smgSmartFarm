require "test_helper"

class SensorReadingIngestorTest < ActiveSupport::TestCase
  def payload(overrides = {})
    {
      "schemaVersion" => 1, "deviceId" => "balcony-01", "sequence" => 1,
      "measuredAt" => "2026-10-03T03:30:00Z", "airTemperatureC" => 20.4,
      "humidityPct" => 61.2, "waterTemperatureC" => 19.3,
      "illuminanceLux" => 8450, "waterLow" => false
    }.merge(overrides)
  end

  test "정상 메시지를 저장하고 장치를 만든다" do
    result = SensorReadingIngestor.call(payload.to_json)

    assert result.stored?
    assert_equal 19.3, result.reading.water_temperature_c.to_f
    assert_equal "balcony-01", result.reading.device.device_id
    assert_equal Time.utc(2026, 10, 3, 3, 30), result.reading.device.last_seen_at
  end

  test "같은 장치·측정시각 메시지는 중복으로 무시한다" do
    SensorReadingIngestor.call(payload)
    result = SensorReadingIngestor.call(payload)

    assert_equal :duplicate, result.status
    assert_equal 1, SensorReading.count
  end

  test "비정상 값은 거절한다" do
    result = SensorReadingIngestor.call(payload("waterTemperatureC" => 250))

    assert_equal :rejected, result.status
    assert_equal 0, SensorReading.count
  end

  test "깨진 JSON과 알 수 없는 schemaVersion을 거절한다" do
    assert_equal :rejected, SensorReadingIngestor.call("{not json").status
    assert_equal :rejected, SensorReadingIngestor.call(payload("schemaVersion" => 2)).status
    assert_equal :rejected, SensorReadingIngestor.call(payload("measuredAt" => "어제")).status
  end

  test "센서 일부가 빠져도 저장한다" do
    result = SensorReadingIngestor.call(payload.except("humidityPct", "illuminanceLux"))

    assert result.stored?
    assert_nil result.reading.humidity_pct
  end
end
