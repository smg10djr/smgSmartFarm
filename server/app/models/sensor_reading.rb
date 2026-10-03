class SensorReading < ApplicationRecord
  belongs_to :device

  validates :measured_at, presence: true
  validates :air_temperature_c, numericality: { in: -40..85 }, allow_nil: true
  validates :humidity_pct, numericality: { in: 0..100 }, allow_nil: true
  validates :water_temperature_c, numericality: { in: -10..60 }, allow_nil: true
  validates :illuminance_lux, numericality: { in: 0..200_000, only_integer: true }, allow_nil: true
end
