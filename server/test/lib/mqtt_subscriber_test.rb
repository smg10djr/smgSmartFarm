require "test_helper"
require "smart_farm/mqtt_subscriber"

class MqttSubscriberTest < ActiveJob::TestCase
  setup { @subscriber = SmartFarm::MqttSubscriber.new }

  test "telemetry 토픽은 수집 Job으로 넘긴다" do
    assert_enqueued_with(job: IngestSensorReadingJob, args: [ '{"a":1}' ]) do
      @subscriber.dispatch("smartfarm/balcony-01/telemetry", '{"a":1}')
    end
  end

  test "status 토픽은 장치 ID와 상태를 Job으로 넘긴다" do
    @subscriber.dispatch("smartfarm/balcony-01/status", "offline")

    job = enqueued_jobs.last
    assert_equal "UpdateDeviceStatusJob", job["job_class"]
    assert_equal [ "balcony-01", "offline" ], job["arguments"].first(2)
  end

  test "모르는 토픽은 Job을 만들지 않는다" do
    @subscriber.dispatch("smartfarm/balcony-01/other", "x")

    assert_no_enqueued_jobs
  end
end
