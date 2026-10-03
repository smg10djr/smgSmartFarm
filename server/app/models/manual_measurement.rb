# 휴대용 측정기로 잰 pH·EC를 사람이 입력한 기록.
class ManualMeasurement < ApplicationRecord
  belongs_to :device

  scope :recent, -> { order(measured_at: :desc).limit(10) }

  validates :measured_at, presence: true
  validates :ph, numericality: { in: 0..14 }, allow_nil: true
  validates :ec_ms_cm, numericality: { in: 0..10 }, allow_nil: true
  validate :ph_or_ec_present

  private

  def ph_or_ec_present
    errors.add(:base, "pH 또는 EC 중 하나는 입력해야 합니다") if ph.nil? && ec_ms_cm.nil?
  end
end
