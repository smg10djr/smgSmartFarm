class Device < ApplicationRecord
  has_many :sensor_readings, dependent: :destroy

  validates :device_id, presence: true, uniqueness: true
end
