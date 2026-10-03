class Device < ApplicationRecord
  OFFLINE_AFTER = 5.minutes

  has_many :sensor_readings, dependent: :destroy
  has_many :alert_events, dependent: :destroy
  has_many :manual_measurements, dependent: :destroy

  validates :device_id, presence: true, uniqueness: true

  def latest_reading = sensor_readings.order(measured_at: :desc).first
  def latest_manual_measurement = manual_measurements.order(measured_at: :desc).first

  # 브로커가 offline(Last Will)을 알렸거나 5분 넘게 수신이 없으면 오프라인
  def online?
    mqtt_state != "offline" && last_seen_at.present? && last_seen_at > OFFLINE_AFTER.ago
  end
end
