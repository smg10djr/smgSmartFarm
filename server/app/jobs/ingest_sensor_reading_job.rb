class IngestSensorReadingJob < ApplicationJob
  queue_as :default

  def perform(payload)
    result = SensorReadingIngestor.call(payload)
    case result.status
    when :stored then Rails.logger.info("[ingest] stored reading #{result.reading.id}")
    when :duplicate then Rails.logger.info("[ingest] duplicate ignored")
    else Rails.logger.warn("[ingest] rejected: #{result.error}")
    end
  end
end
