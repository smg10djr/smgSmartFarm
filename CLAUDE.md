# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

상추 DWC 수경재배 스마트팜 학습 프로젝트. 문서와 주석은 한국어로 작성되어 있으며 이를 따른다.

```text
ESP32 → Mosquitto(MQTT) → bin/mqtt_subscriber → Solid Queue → Rails 8 → PostgreSQL → Turbo Streams
```

- `server/` Rails 8 앱, `infra/` 개발용 Docker Compose(PostgreSQL, Mosquitto), `firmware/` ESP32(PlatformIO), `docs/` 계획·테스트 가이드(`plan.md`, `testing.md`).
- Rails 앱은 저장소 루트가 아니라 `server/`에 있다. 모든 `bin/rails` 명령은 `server/`에서 실행한다.

## 명령어

```bash
# 인프라 (저장소 루트에서)
cp .env.example .env                                  # POSTGRES_PASSWORD 수정
cd infra && docker compose --env-file ../.env up -d

# 서버 (server/ 에서, .env를 환경변수로 불러온 뒤)
set -a; . ../.env; set +a
bin/rails db:prepare
bin/rails server
bin/mqtt_subscriber           # MQTT 구독 프로세스 (별도 터미널)
bin/jobs                      # Solid Queue 워커 (또는 SOLID_QUEUE_IN_PUMA=1 로 Puma에서 실행)
bin/fake_sensor [deviceId]    # 센서 없이 가짜 telemetry 발행

# 검사·테스트
bin/ci                        # rubocop, bundler-audit, importmap audit, brakeman, rails test, seeds (config/ci.rb)
bin/rails test
bin/rails test test/lib/mqtt_subscriber_test.rb       # 파일 하나
bin/rails test test/lib/mqtt_subscriber_test.rb:12    # 테스트 하나 (줄 번호)
bin/rubocop

# 펌웨어 (firmware/ 에서)
pio run -e esp32dev_fake -t upload   # 가짜 수온 (센서 없이 서버 연결 시험)
pio run -e esp32dev -t upload        # 실제 DS18B20
```

단계별 수동 시험 절차는 `docs/testing.md`를 따른다. Wi-Fi·MQTT 비밀번호, `.env`, `firmware/src/secrets.h`는 Git에 올리지 않는다.

## 아키텍처 (여러 파일을 읽어야 보이는 흐름)

1. **수신**: `server/lib/smart_farm/mqtt_subscriber.rb`(`bin/mqtt_subscriber`가 실행)가 `smartfarm/+/telemetry`와 `smartfarm/+/status`를 구독한다. 구독자는 처리하지 않고 Solid Queue에 job만 넣는다. 연결이 끊기면 5초 후 재연결한다.
   - `telemetry` → `IngestSensorReadingJob` → `SensorReadingIngestor`
   - `status`(ESP32 Last Will의 online/offline) → `UpdateDeviceStatusJob` → `DeviceStatusUpdater`
2. **저장**: `SensorReadingIngestor`가 페이로드(`schemaVersion: 1` JSON)를 검증하고 `Device`를 `find_or_create_by`로 만든 뒤 `SensorReading`을 저장한다. 같은 `(device, measured_at)`은 `RecordNotUnique`로 잡아 `:duplicate`를 돌려준다(예외로 흘리지 않음). 결과는 `Result` 구조체(`:stored/:duplicate/:rejected`)로 반환한다. 페이로드 스키마를 바꾸면 `schemaVersion`과 펌웨어(`firmware/src/main.cpp`)를 함께 수정한다.
3. **알림**: `WaterTemperatureAlert`가 수온 24℃ 이상 / 15℃ 이하에서 `AlertEvent`를 열고, 0.5℃ 여유(히스테리시스)를 두고 닫는다. 같은 종류의 열린 알림은 장치당 1개.
4. **화면**: `DashboardController`(`/`)가 장치별 현재값, 온라인 여부(5분 이상 수신 없으면 오프라인), 24시간 수온 그래프를 보여 준다. 새 측정값이 저장되면 `DashboardBroadcaster`가 Turbo Streams(Solid Cable)로 화면을 갱신한다.
5. **수동 입력**: pH·EC는 센서가 없어 `ManualMeasurementsController`/`ManualMeasurement`로 직접 입력한다.

서비스 객체는 `app/services/`에 두고 `Klass.call(...)` 형태를 쓴다. Job은 얇게 유지하고 로직은 서비스에 둔다.

## 상태 메모

- 펌웨어는 작성만 되었고 이 저장소를 작성한 환경에서는 컴파일해 보지 못했다. 처음 빌드 오류는 실제 코드 문제일 수 있다.
- 보류 범위(`docs/plan.md`): 220V 직접 제어, 자동 pH·EC 주입.
