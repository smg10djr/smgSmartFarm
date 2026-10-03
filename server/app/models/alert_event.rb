class AlertEvent < ApplicationRecord
  belongs_to :device

  scope :open, -> { where(resolved_at: nil) }
  scope :recent, -> { order(triggered_at: :desc).limit(20) }

  def open? = resolved_at.nil?
end
