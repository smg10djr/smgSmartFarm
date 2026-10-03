require "mqtt"

module SmartFarm
  # Mosquitto의 telemetry 토픽을 구독하고 메시지를 Solid Queue에 넘기기만 한다.
  # 저장·검증은 IngestSensorReadingJob이 맡는다 (이 프로세스는 얇게 유지).
  class MqttSubscriber
    TOPIC = "smartfarm/+/telemetry".freeze
    RETRY_SECONDS = 5

    def initialize(host: ENV.fetch("MQTT_HOST", "localhost"),
                   port: Integer(ENV.fetch("MQTT_PORT", 1883)),
                   username: ENV["MQTT_USERNAME"],
                   password: ENV["MQTT_PASSWORD"],
                   logger: Rails.logger)
      @options = { host: host, port: port, username: username, password: password, client_id: "rails-subscriber" }.compact
      @logger = logger
      @running = true
    end

    def stop = @running = false

    def run
      while @running
        begin
          MQTT::Client.connect(@options) do |client|
            client.subscribe(TOPIC)
            @logger.info("[mqtt] subscribed #{TOPIC}")
            client.get { |_topic, message| IngestSensorReadingJob.perform_later(message) }
          end
        rescue MQTT::Exception, SystemCallError, SocketError, IOError => e
          @logger.error("[mqtt] connection lost: #{e.class}: #{e.message}")
          sleep RETRY_SECONDS if @running
        end
      end
    end
  end
end
