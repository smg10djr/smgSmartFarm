# Rails 구독자 (`bin/mqtt_subscriber`) 설명

작성일: 2026-10-03 · 관련 파일: `server/bin/mqtt_subscriber`, `server/lib/smart_farm/mqtt_subscriber.rb`

> 표기: 코드를 읽어서 알게 된 내용과 이 PC에서 실행해 확인한 내용을 구분했습니다. "확인함"은 직접 실행한 결과, "코드상"은 소스(`mqtt` 젬 0.7.0 포함)를 읽은 결과, "추정"은 둘 다 아닌 추론입니다.

---

## 1. 한 줄 요약

**Mosquitto에 계속 접속해 있다가, 장치가 보낸 메시지가 오면 그 내용을 Rails의 job(작업)으로 넘기기만 하는 별도 프로세스입니다.** 웹 서버(`rails server`)와는 다른 프로세스이고, 터미널을 하나 따로 열어 실행합니다.

웹 개발에 빗대면 **메시지 큐 컨슈머(워커)** 와 같은 역할입니다. HTTP 요청을 받는 컨트롤러가 아니라, 브로커에서 메시지를 끌어와 처리 쪽으로 넘기는 "수신 전용 데몬"입니다.

```text
ESP32 ──> Mosquitto ──> [ bin/mqtt_subscriber ] ──perform_later──> Job ──> 서비스 ──> DB / 화면
                          (이 문서의 주제)         (여기서는 넘기기만)    (실제 처리)
```

---

## 2. 왜 웹 서버와 분리돼 있나

- `rails server`(Puma)는 **HTTP 요청이 올 때** 코드를 실행합니다. MQTT는 연결을 **계속 열어 두고 메시지를 기다려야** 해서, 요청-응답 구조에 맞지 않습니다.
- 그래서 `while` 루프로 영원히 도는 별도 프로세스를 두었습니다. 이 프로세스가 죽거나 안 켜져 있으면 **웹 화면은 정상이어도 새 데이터가 들어오지 않습니다.** 장치가 화면에 안 나타날 때 가장 먼저 확인할 것입니다(`docs/testing.md`의 문제 해결 표 첫 줄).
- 처리 로직을 구독자 안에 넣지 않은 이유는 "이 프로세스를 얇게 유지"하기 위해서입니다(코드 주석). 저장·검증·알림은 job과 서비스가 맡으므로, 처리 로직은 구독자 없이도 단위 테스트할 수 있습니다.

---

## 3. 파일 구성

| 파일 | 역할 |
|---|---|
| `server/bin/mqtt_subscriber` | 실행 진입점. Rails를 불러오고, 로그를 터미널에 연결하고, 구독자를 만들어 `run`을 호출 |
| `server/lib/smart_farm/mqtt_subscriber.rb` | `SmartFarm::MqttSubscriber` 클래스. 접속·구독·재접속·토픽 분기 |
| `server/app/jobs/ingest_sensor_reading_job.rb` | telemetry 메시지를 받아 저장·알림·화면 갱신 |
| `server/app/jobs/update_device_status_job.rb` | status 메시지를 받아 온라인 상태·오프라인 알림 처리 |
| `server/test/lib/mqtt_subscriber_test.rb` | `dispatch`의 토픽 분기 테스트 3건 |

`lib/`에 둔 이유: 모델·컨트롤러처럼 Rails가 자동 로드하는 `app/` 폴더가 아니라, Rails 밖에서 도는 루프 코드이기 때문입니다. 그래서 `bin/mqtt_subscriber`나 테스트가 `smart_farm/mqtt_subscriber`를 따로 `require`합니다(테스트 파일 첫 줄).

---

## 4. 실행하기

```bash
cd server
set -a; . ../.env; set +a       # .env를 환경변수로 불러옴 (WSL에서는 CRLF 주의: docs/testing.md)
ruby bin/mqtt_subscriber        # Windows 체크아웃에서는 'ruby '를 앞에 붙임. 종료는 Ctrl+C
```

정상이면 이런 로그가 나옵니다(확인함).

```text
[mqtt] subscribed smartfarm/+/telemetry, smartfarm/+/status
```

### 4.1 환경변수

| 변수 | 기본값 | 의미 |
|---|---|---|
| `MQTT_HOST` | `localhost` | 브로커 주소 |
| `MQTT_PORT` | `1883` | 브로커 포트 (정수로 변환됨) |
| `MQTT_USERNAME` | 없음 | 브로커 인증을 켰을 때의 사용자 (보통 `rails`) |
| `MQTT_PASSWORD` | 없음 | 위 사용자의 비밀번호 |

사용자·비밀번호가 없으면 옵션에서 아예 빠져서(`compact`) **익명으로** 접속합니다. 데이터베이스 접속 정보(`POSTGRES_PORT` 등)도 같은 환경에서 읽으므로, 이 프로세스도 `rails server`와 같은 DB를 보도록 `.env`를 불러온 상태에서 실행해야 합니다.

### 4.2 `bin/mqtt_subscriber` 스크립트 해설

```ruby
require_relative "../config/environment"        # Rails 앱 전체를 불러옴 (모델, job, 설정)

$stdout.sync = true                              # 출력을 버퍼에 쌓지 않고 즉시 터미널에 보여 줌
Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout, level: Logger::INFO))
                                                 # 로그를 파일(log/development.log)에 더해 터미널에도 출력

subscriber = SmartFarm::MqttSubscriber.new
%w[INT TERM].each { |sig| trap(sig) { subscriber.stop; exit } }
                                                 # Ctrl+C(INT)나 종료 신호(TERM)가 오면 멈추고 종료
subscriber.run                                   # 무한 루프 시작
```

- `config/environment`를 불러오기 때문에 이 프로세스는 **Rails 앱 전체를 메모리에 올린 상태**입니다. 그래서 모델(`Device` 등)과 `IngestSensorReadingJob`을 그대로 쓸 수 있습니다.
- 기본적으로 Rails 로그는 `log/development.log` 파일에만 쌓입니다. `broadcast_to`는 로그를 하나 더 만들어 터미널에도 보내는 Rails 7.1 이후의 기능입니다. 터미널에는 INFO 이상만 나옵니다.
- `trap`은 운영체제 신호를 가로채는 핸들러입니다. 종료 시 `exit`을 호출하면 `MQTT::Client.connect` 블록이 끝나면서 브로커와의 연결이 정리됩니다(코드상: 젬의 `connect`가 블록 종료 시 `ensure`에서 `disconnect`).

---

## 5. 클래스 해설 (`SmartFarm::MqttSubscriber`)

### 5.1 상수와 생성자

```ruby
TELEMETRY = "smartfarm/+/telemetry"
STATUS    = "smartfarm/+/status"
RETRY_SECONDS = 5

def initialize(host: ..., port: ..., username: ..., password: ..., logger: Rails.logger)
  @options = { host:, port:, username:, password:, client_id: "rails-subscriber" }.compact
  @logger  = logger
  @running = true
end
```

- 토픽의 `+`는 "한 단계 와일드카드"입니다. `smartfarm/+/telemetry`는 **모든 장치**의 telemetry를 뜻합니다. 장치를 추가해도 구독자 설정을 바꿀 필요가 없습니다.
- `client_id: "rails-subscriber"`는 고정입니다. MQTT 규격상 **같은 클라이언트 ID로 두 번째 접속이 오면 먼저 있던 연결이 끊깁니다.** 그래서 구독자를 두 개 동시에 켜면 서로 상대를 끊으며 재접속을 반복할 수 있습니다(규격상 동작이며, 이 프로젝트에서 직접 재현하지는 않음). 한 번에 하나만 실행하세요.
- `logger`를 주입받게 해 둔 덕분에 테스트에서 다른 로거로 바꿀 수 있습니다.

### 5.2 `dispatch(topic, message)` — 토픽별 분기

```ruby
def dispatch(topic, message)
  _root, device_id, kind = topic.split("/")
  case kind
  when "telemetry" then IngestSensorReadingJob.perform_later(message)
  when "status"    then UpdateDeviceStatusJob.perform_later(device_id, message, Time.current)
  else @logger.warn("[mqtt] ignored topic #{topic}")
  end
end
```

예: 토픽 `smartfarm/balcony-01/status`, 메시지 `online`
- `topic.split("/")` → `["smartfarm", "balcony-01", "status"]` → `device_id = "balcony-01"`, `kind = "status"`
- `UpdateDeviceStatusJob.perform_later("balcony-01", "online", 지금시각)`

| 종류 | 넘기는 job | 넘기는 인자 |
|---|---|---|
| `telemetry` | `IngestSensorReadingJob` | 메시지 원문(JSON 문자열) 하나. 장치 ID는 JSON 안의 `deviceId`를 쓴다 |
| `status` | `UpdateDeviceStatusJob` | 장치 ID(토픽에서 추출), 상태 문자열, **수신 시각** |

알아둘 점:
- **telemetry의 장치 ID는 토픽이 아니라 JSON의 `deviceId`를 씁니다.** 토픽의 장치 ID와 JSON의 `deviceId`가 다르면 구독자는 검증하지 않고 JSON 값을 따릅니다(코드상). 인증을 켜면 ACL이 토픽 쪽을 제한하지만, JSON 안의 값까지는 검증하지 않습니다.
- **status의 시각은 메시지 시각이 아니라 구독자가 받은 시각(`Time.current`)** 입니다. 브로커가 보존(retained)해 둔 옛 `status`가 구독 직후 전달되면 "지금 일어난 일"처럼 처리됩니다(코드상). 실제로 구독자를 켜자마자 `balcony-01 online` status job이 곧바로 만들어지는 것을 로그로 봤습니다(확인함).
- 메시지 원문을 해석하지 않고 그대로 넘기므로 **구독자는 잘못된 JSON에도 죽지 않습니다.** 검증과 거절(`[ingest] rejected`)은 job 쪽에서 합니다(확인함).

### 5.3 `run` — 접속·구독·수신·재접속 루프

```ruby
def run
  while @running
    begin
      MQTT::Client.connect(@options) do |client|
        client.subscribe([ TELEMETRY, 1 ], [ STATUS, 1 ])
        @logger.info("[mqtt] subscribed #{TELEMETRY}, #{STATUS}")
        client.get { |topic, message| dispatch(topic, message) }
      end
    rescue MQTT::Exception, SystemCallError, SocketError, IOError => e
      @logger.error("[mqtt] connection lost: #{e.class}: #{e.message}")
      sleep RETRY_SECONDS if @running
    end
  end
end
```

흐름:
1. `@running`이 true인 동안 바깥 `while`이 계속 돕니다.
2. `MQTT::Client.connect`로 브로커에 접속합니다. 블록이 끝나면 자동으로 연결을 닫습니다.
3. 두 토픽을 **QoS 1**로 구독하고 `subscribed` 로그를 남깁니다.
4. `client.get { ... }`은 **메시지가 올 때마다 블록을 실행하며 영원히 대기**합니다(블로킹). 메시지 하나당 `dispatch`가 한 번 불립니다.
5. 연결이 끊기거나 접속이 거부되면 예외가 나서 `rescue`로 가고, 에러 로그를 남긴 뒤 5초 쉬고 처음부터 다시 접속합니다.

잡는 예외 네 가지:

| 예외 | 언제 |
|---|---|
| `MQTT::Exception` (및 하위 `ProtocolException` 등) | 인증 거부, 핑 응답 없음, 프로토콜 오류 |
| `SystemCallError` (`Errno::ECONNREFUSED` 등) | 브로커가 꺼져 있어 접속 거절됨 |
| `SocketError` | 호스트 이름을 찾지 못함 |
| `IOError` | 소켓이 이미 닫힘 |

이 목록에 없는 예외(예: `dispatch` 안에서 난 다른 오류)는 잡히지 않아 **프로세스가 종료**됩니다(코드상).

---

## 6. 메시지 한 건이 처리되는 과정

실제 로그(확인함, 일부 줄임):

```text
[mqtt] subscribed smartfarm/+/telemetry, smartfarm/+/status
Enqueued UpdateDeviceStatusJob ... arguments: "balcony-01", "online", 2026-10-03 22:12:44 ...
↳ lib/smart_farm/mqtt_subscriber.rb:28:in `dispatch'
Performed UpdateDeviceStatusJob ... in 755.87ms
Enqueued IngestSensorReadingJob ... arguments: "{\"schemaVersion\":1,\"deviceId\":\"balcony-01\", ...}"
↳ lib/smart_farm/mqtt_subscriber.rb:27:in `dispatch'
Performing IngestSensorReadingJob ...
[ingest] stored reading 13
Performed IngestSensorReadingJob ... in 68.33ms
```

| 단계 | 어디서 | 로그 |
|---|---|---|
| ① 브로커에서 메시지 수신 | 구독자 `client.get` | (없음) |
| ② 토픽 분기, job 큐에 넣기 | 구독자 `dispatch` | `Enqueued ...` (어느 코드 줄에서 큐잉했는지 `↳ lib/...:27`로 표시) |
| ③ job 실행 | Active Job | `Performing ...` |
| ④ 검증·저장 | `SensorReadingIngestor` | |
| ⑤ 알림 판단 | `WaterTemperatureAlert` | |
| ⑥ 화면 갱신 방송 | `DashboardBroadcaster` | |
| ⑦ 결과 로그 | job | `[ingest] stored reading N` / `duplicate ignored` / `rejected: ...` |

`[ingest]`로 시작하는 세 가지 결과(`stored`, `duplicate`, `rejected`)는 모두 터미널에서 직접 확인했습니다. 특히 범위를 벗어난 수온에는 `[ingest] rejected: 수온 값이 -10..60 범위를 벗어났습니다`가 나옵니다.

---

## 7. 개발과 운영의 차이: job은 어디서 실행되나

구독자는 `perform_later`로 job을 "예약"만 하고, **실제 실행은 큐 어댑터가 정합니다.**

| 환경 | 어댑터 | job이 실행되는 곳 |
|---|---|---|
| development (지금) | 설정 없음 → Rails 기본 `async` | **구독자 프로세스 안의 스레드 풀**. 별도 워커가 필요 없음 |
| production | `solid_queue` (`config/environments/production.rb`) | DB 큐에 쌓이고 **별도 워커**가 실행 |

- 개발 환경에서 구독자 터미널에 `Performing ...`, `[ingest] stored ...` 로그가 같이 찍히는 이유가 이것입니다(확인함). 그래서 `rails server`와 `mqtt_subscriber` 두 프로세스만 있으면 전체 흐름이 돕니다.
- production에서는 `bin/jobs`로 워커를 띄우거나 `SOLID_QUEUE_IN_PUMA=1`을 줘서 Puma 안에서 돌립니다(`config/puma.rb`).
- **구독자 자체를 production에서 자동으로 켜 주는 설정(Procfile, systemd, Docker 서비스 등)은 이 저장소에 없습니다.** `bin/dev`도 `rails server`만 실행합니다(확인함). 운영에 올릴 때는 구독자를 별도 프로세스로 띄우고 죽으면 다시 켜 주는 방법을 정해야 합니다.
- `async` 어댑터는 job을 여러 스레드에서 동시에 처리하므로 **메시지 도착 순서와 처리 완료 순서가 다를 수 있습니다**(추정, 어댑터의 일반적인 특성).

---

## 8. 연결이 끊기면: 재접속과 데이터 유실

### 8.1 끊김을 알아채는 방법 (`mqtt` 젬 0.7.0, 코드상)

- 접속 옵션 `keep_alive` 기본값은 **15초**입니다. 15초 동안 아무 패킷이 없으면 젬이 `PINGREQ`를 보내고, 응답이 `15 × 1.5 = 22.5 → 23초` 안에 없으면 `MQTT::ProtocolException: No Ping Response received ...`를 일으킵니다.
- 젬은 별도 읽기 스레드에서 패킷을 받고, 오류가 나면 **메인 스레드(`client.get`을 기다리던 곳)로 예외를 던집니다.** 그래서 `run`의 `rescue`가 이 예외를 잡을 수 있습니다.
- 브로커가 꺼지는 경우는 소켓이 닫히면서 곧바로 예외가 날 수 있고, 네트워크가 조용히 끊기는 경우는 위 핑 타임아웃(수십 초)이 지나서야 알게 됩니다.

### 8.2 재접속

`rescue` 후 5초 쉬고 처음부터 다시 접속하므로, 브로커가 다시 켜지면 **사람이 개입하지 않아도 자동으로 복구**됩니다. 재접속에 성공하면 `subscribed` 로그가 다시 나옵니다.

### 8.3 끊긴 동안의 메시지는 어떻게 되나 (중요)

`mqtt` 젬의 `clean_session` 기본값이 **true**이고 이 코드는 바꾸지 않았습니다(코드상). 그 결과:

- 구독자가 끊겨 있는 동안 발행된 telemetry는 **브로커가 보관해 주지 않아 영영 받지 못합니다.** (clean session에서는 오프라인 클라이언트용 메시지 큐가 없습니다.)
- 장치는 1분 평균을 보내는데 그 시간대는 DB에 구멍이 나고, 나중에 다시 보내 주는 기능도 없습니다. 펌웨어는 연결이 없을 때 그 구간 평균을 버립니다.
- 예외는 **retained(보존) 메시지**입니다. `status`는 retained라서, 구독자가 다시 접속하면 마지막 `online`/`offline`을 받습니다(확인함). 구독자를 켜자마자 `status` job이 도는 이유입니다.

개선 방향(이 프로젝트에는 아직 없음): `clean_session: false`와 고정 `client_id`로 영속 세션을 쓰면 QoS 1 메시지는 구독자가 꺼진 동안에도 브로커가 쌓아 두었다가 다시 접속할 때 전달해 줍니다. 필요해지면 검토할 항목입니다.

---

## 9. 인증을 켰을 때

`MQTT_USERNAME=rails`, `MQTT_PASSWORD=...`를 구독자 실행 환경에 지정합니다. 이 계정은 ACL에서 `smartfarm/+/telemetry`, `smartfarm/+/status`를 **읽기만** 허용됩니다(`docs/infra 설명.md`, `docs/Mosquitto 설명.md`).

- `rails` 계정으로 `bin/mqtt_subscriber`가 인증 브로커에 접속해 `subscribed`까지 가는 것을 확인했습니다(확인함).
- 계정이 틀리면 `MQTT::ProtocolException: Connection refused: not authorised`가 나고, 구독자는 에러 로그를 남긴 뒤 **5초마다 계속 재시도**합니다(확인함: 예외 메시지, 코드상: 재시도). 비밀번호를 틀리게 넣은 채 켜 두면 로그가 쌓이기만 하므로 로그를 확인하세요.
- 연결은 TLS 없이 평문입니다(1883). 내부망 안에서만 쓰는 전제입니다.

---

## 10. 테스트

`server/test/lib/mqtt_subscriber_test.rb`는 `dispatch`만 시험합니다.

| 테스트 | 검증 |
|---|---|
| telemetry 토픽은 수집 Job으로 넘긴다 | `IngestSensorReadingJob`이 메시지 원문 인자로 큐에 들어감 |
| status 토픽은 장치 ID와 상태를 Job으로 넘긴다 | `UpdateDeviceStatusJob`의 인자 앞 두 개가 `["balcony-01", "offline"]` |
| 모르는 토픽은 Job을 만들지 않는다 | `smartfarm/balcony-01/other`는 아무 job도 만들지 않음 |

테스트하지 않는 것: `run`의 접속·구독·재접속 루프, 로그 출력. 브로커 없이 시험하려고 `dispatch`만 분리해 둔 구조라서, 접속 부분은 위 4절의 실제 실행으로만 확인할 수 있습니다.

---

## 11. 직접 시험해 보기

터미널 3개를 열어 모두 `server/`에서 `.env`를 불러옵니다.

| 터미널 | 명령 | 역할 |
|---|---|---|
| A | `bin/rails server` | 화면 |
| B | `bin/mqtt_subscriber` | 구독자 (이 문서의 주제) |
| C | `bin/fake_sensor` | 가짜 센서 메시지 1건 발행 |

1. B에서 `[mqtt] subscribed ...`가 나오는지 봅니다.
2. C에서 `bin/fake_sensor`를 실행하면 B에 `Enqueued IngestSensorReadingJob` → `[ingest] stored reading N`이 찍힙니다.
3. 같은 `measuredAt`을 다시 보내면 `[ingest] duplicate ignored`, 깨진 JSON이나 범위를 벗어난 값이면 `[ingest] rejected: ...`가 찍힙니다(모두 확인함).
4. B를 `Ctrl+C`로 끈 상태에서 C를 실행하면 아무 일도 일어나지 않고, B를 다시 켜도 그때 보낸 telemetry는 들어오지 않습니다(8.3절의 이유. 코드상 설명이며 이 시나리오는 별도로 시험하지 않음).

브로커까지 메시지가 도착했는지 구독자와 별개로 보려면:

```powershell
docker exec infra-mosquitto-1 mosquitto_sub -t 'smartfarm/#' -v
```

---

## 12. 문제 해결

| 증상 | 확인 |
|---|---|
| 화면에 장치가 안 나타남 | 터미널 B가 켜져 있는지, `subscribed` 로그가 있는지, 다른 터미널의 `rails server`와 같은 DB(`POSTGRES_PORT`)를 보는지 |
| `[mqtt] connection lost: Errno::ECONNREFUSED` 반복 | Mosquitto 컨테이너가 떠 있는지(`docker compose ps`), `MQTT_HOST`·`MQTT_PORT` |
| `connection lost: MQTT::ProtocolException: Connection refused: not authorised` 반복 | 브로커 인증이 켜져 있는데 `MQTT_USERNAME`/`MQTT_PASSWORD`가 없거나 틀림 |
| 로그가 반복되며 접속이 잦게 끊김 | 구독자를 두 개 켰는지(같은 클라이언트 ID `rails-subscriber` 충돌) |
| `[ingest] rejected: JSON 파싱 실패` | 발행한 JSON이 깨짐. PowerShell에서 `mosquitto_pub`로 JSON을 보내면 따옴표가 지워지거나 BOM이 붙음(`docs/Mosquitto 설명.md` 7.3) |
| `[mqtt] ignored topic ...` | 토픽이 `smartfarm/<장치>/telemetry`·`status`가 아님 (구독 대상은 두 가지뿐이라 보통 다른 이름의 토픽이 이 구독에 걸릴 일은 없음) |
| 터미널에 로그가 안 나옴 | `bin/mqtt_subscriber`를 직접 실행했는지 (`bin/rails runner` 등으로 실행하면 stdout 로거가 붙지 않음), `log/development.log` 확인 |
| 터미널에서 `ruby\r: No such file or directory` | CRLF 문제. `ruby bin/mqtt_subscriber`로 실행 |

---

## 13. 알아둘 점 (정리)

- 구독자가 꺼져 있는 동안의 telemetry는 **복구되지 않습니다**(`clean_session: true`).
- 구독자는 **하나만** 실행해야 합니다(고정 클라이언트 ID).
- telemetry의 장치 ID는 JSON의 `deviceId`를 신뢰합니다. 토픽과 일치하는지 검증하지 않습니다.
- `status`의 시각은 도착 시각입니다. 보존된 옛 메시지도 "지금"으로 처리됩니다.
- `dispatch` 밖의 예외(`rescue` 목록 밖)는 프로세스를 종료시킵니다. 종료되면 아무도 다시 켜 주지 않습니다(저장소에 감시·자동 재시작 설정이 없음).
- 접속 로직(`run`)에는 자동 테스트가 없습니다.
- 운영 환경에서 구독자를 상시 실행하는 방법은 정해져 있지 않습니다.

## 14. 관련 문서

- `docs/Mosquitto 설명.md`: 브로커와 MQTT 개념 (QoS, retained, Last Will)
- `docs/infra 설명.md`: 브로커를 띄우는 Docker 설정
- `docs/소스 구조 분석.md`: 서버 전체 구조
- `docs/testing.md`: 단계별 시험 절차
