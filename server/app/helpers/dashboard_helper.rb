module DashboardHelper
  CHART_W = 600
  CHART_H = 120

  # 최근 24시간 수온을 SVG 선으로 그린다. 좌표 문자열을 돌려주고, 데이터가 2개 미만이면 nil.
  def water_temp_points(device, now: Time.current)
    from = now - 24.hours
    rows = device.sensor_readings.where(measured_at: from..now).where.not(water_temperature_c: nil)
                 .order(:measured_at).pluck(:measured_at, :water_temperature_c)
    return if rows.size < 2

    temps = rows.map { |_, t| t.to_f }
    lo, hi = temps.min - 1, temps.max + 1
    rows.map do |at, t|
      x = ((at - from) / 24.hours * CHART_W).round(1)
      y = (CHART_H - (t.to_f - lo) / (hi - lo) * CHART_H).round(1)
      "#{x},#{y}"
    end.join(" ")
  end
end
