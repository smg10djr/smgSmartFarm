class IngestSensorReadingJob < ApplicationJob
  queue_as :default

  def perform(payload)
    result = SensorReadingIngestor.call(payload)

    if result.stored?
      WaterTemperatureAlert.call(result.reading)
      DashboardBroadcaster.call(result.reading.device)
      Rails.logger.info("[ingest] stored reading #{result.reading.id}")
    elsif result.status == :duplicate
      Rails.logger.info("[ingest] duplicate ignored")
    else
      Rails.logger.warn("[ingest] rejected: #{result.error}")
    end
  end
end
