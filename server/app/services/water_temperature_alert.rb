# 수온이 기준을 넘으면 알림을 열고, 회복되면 닫는다. 경계에서 깜빡이지 않도록 해제는 0.5℃ 여유를 둔다.
class WaterTemperatureAlert
  HIGH = 24.0
  LOW = 15.0
  MARGIN = 0.5

  def self.call(reading) = new(reading).call

  def initialize(reading)
    @reading = reading
    @device = reading.device
    @temp = reading.water_temperature_c&.to_f
  end

  def call
    return if @temp.nil?

    evaluate("high_water_temp", @temp >= HIGH, @temp < HIGH - MARGIN, "수온 #{@temp}℃ (기준 #{HIGH}℃ 이상)")
    evaluate("low_water_temp", @temp <= LOW, @temp > LOW + MARGIN, "수온 #{@temp}℃ (기준 #{LOW}℃ 이하)")
  end

  private

  def evaluate(kind, breached, recovered, message)
    open_alert = @device.alert_events.open.find_by(kind: kind)

    if breached && open_alert.nil?
      @device.alert_events.create!(kind: kind, message: message, triggered_at: @reading.measured_at)
    elsif recovered && open_alert
      open_alert.update!(resolved_at: @reading.measured_at)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
