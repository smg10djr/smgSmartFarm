class ManualMeasurementsController < ApplicationController
  def create
    device = Device.find(params.require(:manual_measurement)[:device_id])
    measurement = device.manual_measurements.new(measurement_params.merge(measured_at: Time.current))

    if measurement.save
      DashboardBroadcaster.call(device)
      redirect_to root_path, notice: "pH·EC를 기록했습니다."
    else
      redirect_to root_path, alert: measurement.errors.full_messages.to_sentence
    end
  end

  private

  def measurement_params
    params.require(:manual_measurement).permit(:ph, :ec_ms_cm, :note)
  end
end
