class Device < ApplicationRecord
  OFFLINE_AFTER = 5.minutes

  has_many :sensor_readings, dependent: :destroy
  has_many :alert_events, dependent: :destroy

  validates :device_id, presence: true, uniqueness: true

  def latest_reading = sensor_readings.order(measured_at: :desc).first
  def online? = last_seen_at.present? && last_seen_at > OFFLINE_AFTER.ago
end
