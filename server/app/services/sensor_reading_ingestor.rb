# MQTT telemetry JSON 한 건을 검증하고 저장한다.
# 같은 (device, measured_at) 메시지가 다시 오면 저장하지 않고 :duplicate를 돌려준다.
class SensorReadingIngestor
  SCHEMA_VERSION = 1

  Result = Struct.new(:status, :reading, :error, keyword_init: true) do
    def stored? = status == :stored
  end

  def self.call(payload) = new(payload).call

  def initialize(payload)
    @payload = payload
  end

  def call
    data = parse
    return rejected("JSON 객체가 아닙니다") unless data.is_a?(Hash)
    return rejected("지원하지 않는 schemaVersion: #{data["schemaVersion"].inspect}") unless data["schemaVersion"] == SCHEMA_VERSION
    return rejected("deviceId가 없습니다") if data["deviceId"].blank?

    measured_at = parse_time(data["measuredAt"])
    return rejected("measuredAt이 올바르지 않습니다") unless measured_at

    store(data, measured_at)
  rescue JSON::ParserError => e
    rejected("JSON 파싱 실패: #{e.message}")
  end

  private

  def parse
    @payload.is_a?(String) ? JSON.parse(@payload) : @payload
  end

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def store(data, measured_at)
    device = Device.find_or_create_by!(device_id: data["deviceId"])
    reading = device.sensor_readings.new(
      measured_at: measured_at,
      sequence: data["sequence"],
      air_temperature_c: data["airTemperatureC"],
      humidity_pct: data["humidityPct"],
      water_temperature_c: data["waterTemperatureC"],
      illuminance_lux: data["illuminanceLux"],
      water_low: data["waterLow"],
      raw: data
    )

    return rejected(reading.errors.full_messages.to_sentence) unless reading.valid?

    reading.save!
    device.update!(last_seen_at: [ device.last_seen_at, measured_at ].compact.max)
    Result.new(status: :stored, reading: reading)
  rescue ActiveRecord::RecordNotUnique
    Result.new(status: :duplicate)
  end

  def rejected(message)
    Result.new(status: :rejected, error: message)
  end
end
