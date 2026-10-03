# Mosquitto 2 와 MQTT 설명

작성일: 2026-10-03 · 확인한 버전: Mosquitto 2.1.2 (`eclipse-mosquitto:2` 이미지)

웹 개발 경험은 있지만 MQTT와 Mosquitto는 처음인 분을 위한 문서입니다. 앞부분은 개념, 뒷부분은 이 프로젝트에서 어떻게 쓰는지와 직접 만져 보는 방법입니다.

> 표기: 이 PC에서 직접 실행해 확인한 내용은 "확인함"으로, 일반 지식이나 코드만 읽고 설명한 것은 그렇게 표시하지 않거나 "추정"으로 적었습니다.

---

## 1. 한눈에 보기

- **MQTT**: 센서 같은 작은 기기가 값을 자주 보내기 위한 가벼운 메시지 규약입니다.
- **Mosquitto**: 그 규약을 구현한 **브로커**(메시지 중계 서버)입니다. Eclipse 재단의 오픈소스이고 C로 만들어져 가볍습니다.
- **Mosquitto 2**: 2020년대에 나온 2.x 버전 계열입니다. 프로젝트의 Docker 이미지 태그가 `eclipse-mosquitto:2`이고, 지금 받아지는 버전은 2.1.2입니다(확인함).

이 프로젝트에서의 위치:

```text
ESP32 ──발행(publish)──> [ Mosquitto ] ──전달──> Rails 구독자(bin/mqtt_subscriber) ──> DB
```

---

## 2. MQTT 기초

### 2.1 HTTP와 무엇이 다른가

| | HTTP | MQTT |
|---|---|---|
| 모델 | 요청(Request) → 응답(Response) | 발행(Publish) / 구독(Subscribe) |
| 통신 상대 | 클라이언트 ↔ 서버 직접 | 클라이언트 ↔ **브로커** ↔ 클라이언트 |
| 연결 | 요청마다 연결(또는 짧게 유지) | 한 번 연결해 **계속 유지** |
| 보내는 쪽이 받는 쪽을 아는가 | 안다(URL로 호출) | **모른다**(토픽에만 보냄) |
| 한 메시지를 받는 쪽 | 보통 서버 1곳 | 그 토픽을 구독한 **모두** |
| 헤더 크기 | 큼 | 매우 작음 (수 바이트) |
| 적합한 용도 | 웹 페이지, API | 센서·IoT, 알림 푸시 |

웹으로 빗대면 **Redis Pub/Sub이나 Kafka의 토픽, 혹은 WebSocket 채널**과 비슷합니다. 보내는 쪽(ESP32)은 Rails가 켜져 있는지 몰라도 되고, Rails가 꺼져 있어도 ESP32는 브로커에 발행만 하면 됩니다.

### 2.2 구성 요소

| 용어 | 뜻 | 이 프로젝트에서 |
|---|---|---|
| 브로커(broker) | 메시지를 받아서 구독자에게 전달하는 서버 | Mosquitto |
| 클라이언트 | 브로커에 접속하는 쪽 (발행자 또는 구독자, 둘 다 가능) | ESP32, `bin/mqtt_subscriber`, `bin/fake_sensor` |
| 토픽(topic) | 메시지의 "주소". `/`로 구분한 문자열 | `smartfarm/balcony-01/telemetry` |
| 발행(publish) | 토픽에 메시지를 보냄 | ESP32가 1분마다 수온 발행 |
| 구독(subscribe) | 토픽의 메시지를 받겠다고 등록 | Rails가 `smartfarm/+/telemetry` 구독 |
| 페이로드(payload) | 메시지 내용 (바이트. 형식은 자유) | JSON 문자열 |
| 클라이언트 ID | 브로커에서 클라이언트를 구분하는 이름 | ESP32는 `DEVICE_ID`, 구독자는 `rails-subscriber` |

브로커는 페이로드를 해석하지 않습니다. JSON인지 숫자인지는 보내는 쪽과 받는 쪽이 약속합니다. 이 프로젝트에서는 `schemaVersion: 1`인 JSON입니다.

### 2.3 토픽과 와일드카드

토픽은 폴더 경로처럼 `/`로 계층을 나눕니다.

```text
smartfarm / balcony-01 / telemetry
 (프로젝트)   (장치 ID)    (종류)
```

구독할 때만 와일드카드를 쓸 수 있습니다(발행 토픽에는 못 씁니다).

| 기호 | 의미 | 예시 |
|---|---|---|
| `+` | **한 단계**만 대신함 | `smartfarm/+/telemetry` → 모든 장치의 telemetry |
| `#` | **그 아래 전부** (맨 끝에만 가능) | `smartfarm/balcony-01/#` → 이 장치의 모든 토픽 |

주의:
- `#`로 구독해도 `$`로 시작하는 시스템 토픽(`$SYS/...`)은 받지 못합니다. 브로커 내부 통계는 `$SYS/#`로 따로 구독해야 합니다.
- 토픽은 대소문자를 구분합니다. `Smartfarm`과 `smartfarm`은 다릅니다.

### 2.4 QoS (전달 보장 수준)

| QoS | 이름 | 의미 | 비용 |
|---|---|---|---|
| 0 | 최대 한 번 | 보내고 끝. 유실될 수 있음 | 가장 가벼움 |
| 1 | 최소 한 번 | 받았다는 확인(ACK)을 받을 때까지 재전송. **중복 가능** | 중간 |
| 2 | 정확히 한 번 | 4단계 핸드셰이크로 중복 없이 한 번 | 가장 무거움 |

- 메시지가 구독자에게 실제로 전달되는 QoS는 **발행 QoS와 구독 QoS 중 낮은 쪽**입니다.
- 이 프로젝트: 펌웨어가 쓰는 PubSubClient 라이브러리의 `publish()`는 QoS 0으로 보냅니다(라이브러리 특성, 코드 `main.cpp`의 호출에는 QoS 인자가 없음). `bin/fake_sensor`는 QoS 1로 보냅니다. 구독자는 QoS 1로 구독하지만, 펌웨어 메시지는 QoS 0이므로 실제 전달은 QoS 0입니다.
- QoS 1은 중복 전달이 있을 수 있어서, 서버가 `(device, measured_at)` 유일 인덱스로 중복을 막습니다(`SensorReadingIngestor`가 `:duplicate`로 처리).

### 2.5 연결 시 알아야 할 기능 세 가지

**① Retained (보존) 메시지**
- 발행할 때 `retained=true`를 주면 브로커가 그 토픽의 **마지막 메시지를 기억**해 둡니다.
- 나중에 그 토픽을 구독하는 클라이언트는 접속하자마자 마지막 메시지를 받습니다.
- 용도: "현재 상태" 같은 값. 이 프로젝트에서는 `status`(online/offline)가 retained입니다. 센서 값(`telemetry`)은 과거 값이 남으면 안 되므로 retained가 아닙니다.
- 지우려면 같은 토픽에 빈 페이로드를 retained로 발행합니다.

**② Last Will and Testament (유언 메시지, LWT)**
- 클라이언트가 접속할 때 "내 연결이 **비정상적으로 끊기면** 이 메시지를 이 토픽에 대신 발행해 달라"고 브로커에 맡겨 둡니다.
- 전원이 뽑히거나 Wi-Fi가 끊긴 기기는 스스로 "나 죽는다"를 보낼 수 없기 때문에 필요합니다.
- 클라이언트가 정상적으로 `DISCONNECT`하고 끊으면 유언은 발행되지 않습니다.
- 이 프로젝트: ESP32가 접속할 때 `smartfarm/<DEVICE_ID>/status`에 `"offline"`(retained)을 유언으로 맡기고, 접속 성공 직후 같은 토픽에 `"online"`을 발행합니다. 전원을 뽑으면 브로커가 `offline`을 대신 발행하고, Rails의 `DeviceStatusUpdater`가 받아 오프라인 알림을 엽니다.

**③ Keep Alive (연결 유지 확인)**
- 클라이언트가 일정 시간(keepalive) 안에 아무 패킷도 안 보내면 `PINGREQ`라는 작은 패킷을 보냅니다. 브로커가 keepalive의 약 1.5배 시간 동안 아무 신호도 못 받으면 연결이 끊긴 것으로 보고 유언을 발행합니다.
- 그래서 전원을 뽑은 직후가 아니라 **잠시 뒤** 오프라인 알림이 뜹니다. `docs/testing.md`의 "잠시 뒤"가 이 시간입니다. 펌웨어의 `mqtt.loop()`가 핑을 처리하므로 자주 호출해야 합니다.

**클라이언트 ID는 유일해야 합니다.** 같은 ID로 두 번째 접속이 오면 브로커가 **먼저 있던 연결을 끊습니다**(MQTT 규격). 그래서 `bin/mqtt_subscriber`를 두 개 동시에 켜면 둘이 서로를 끊어 재접속을 반복할 수 있습니다. 구독자는 한 번에 하나만 실행하세요.

---

## 3. Mosquitto 2

### 3.1 무엇을 하는 프로그램인가

- 1883 같은 포트에서 클라이언트 접속을 받고, 토픽별로 발행·구독을 중계합니다.
- 메시지를 디스크에 저장(persistence)하고, 계정 인증과 토픽 권한(ACL)을 지원하며, TLS(암호화)와 WebSocket도 지원합니다(이 프로젝트는 TLS와 WebSocket을 쓰지 않음).
- 같은 패키지에 명령줄 도구 `mosquitto_pub`, `mosquitto_sub`, `mosquitto_passwd`가 들어 있습니다. 이 프로젝트의 Docker 이미지 안에서 쓸 수 있습니다(확인함).

### 3.2 2.x에서 알아둘 점

- 설정 파일에 `listener`를 따로 적지 않으면 **같은 컴퓨터(localhost)에서 오는 접속만** 받는 것이 기본입니다. 외부 기기(ESP32)가 붙으려면 `listener 1883`처럼 명시하고, 인증을 쓰거나 `allow_anonymous true`로 열어야 합니다. 이 프로젝트의 `mosquitto.conf`에 `listener 1883`과 `allow_anonymous true`가 둘 다 있는 이유입니다.
- 2.1.2는 인증 파일(`passwd`, `acl`)의 **소유자와 권한을 검사해 경고**를 냅니다. "world readable", "owner is not mosquitto", "향후 버전은 거부할 수 있음" 경고를 실제로 봤습니다(확인함). 자세한 내용은 5.4절.
- 이미지 태그 `:2`는 2.x 중 최신으로 계속 바뀝니다. 같은 `docker compose up`이라도 시점에 따라 마이너 버전이 달라질 수 있습니다. 고정하려면 `eclipse-mosquitto:2.1.2`처럼 정확한 태그를 씁니다.

### 3.3 Docker 안에서의 모습 (확인함)

| 항목 | 값 |
|---|---|
| 프로세스 사용자 | `mosquitto` (uid/gid 1883). root가 아님 |
| 설정 파일 위치 | `/mosquitto/config/mosquitto.conf` |
| 데이터 위치 | `/mosquitto/data/` (볼륨 `infra_mosquitto_data`) |
| 포트 | 컨테이너 1883 → PC `${MQTT_PORT:-1883}` |

프로젝트의 compose는 PC의 `infra/mosquitto/mosquitto.conf`를 컨테이너의 `/mosquitto/config/mosquitto.conf` 자리에 **읽기 전용**으로 연결합니다. 이미지에 들어 있는 기본 설정을 이 파일이 대체합니다.

---

## 4. 설정 파일 읽는 법

### 4.1 이 프로젝트의 기본 설정 (`infra/mosquitto/mosquitto.conf`)

```text
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
```

| 지시어 | 뜻 |
|---|---|
| `listener 1883` | 1883 포트에서 접속을 받는다. 포트를 더 열려면 `listener`를 여러 번 쓸 수 있다 |
| `allow_anonymous true` | 사용자 이름 없이도 접속 허용 (개발 전용) |
| `persistence true` | 메모리 상태(retained 메시지, 구독 정보 등)를 디스크에 저장 |
| `persistence_location` | 저장 위치. 끝에 `/`가 있어야 한다 |

저장은 종료할 때와 주기적으로 일어납니다. 컨테이너를 내릴 때 `Saving in-memory database to /mosquitto/data//mosquitto.db`라는 로그가 나옵니다(확인함). 다시 켤 때 `Restored N subscriptions` 로그가 나옵니다.

### 4.2 인증을 켠 설정 (`mosquitto.auth.conf`)

```text
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
acl_file /mosquitto/config/acl
persistence true
persistence_location /mosquitto/data/
```

| 지시어 | 뜻 |
|---|---|
| `allow_anonymous false` | 계정이 없으면 접속 거부 |
| `password_file` | `사용자:해시된비밀번호` 목록 파일 |
| `acl_file` | 계정별로 어떤 토픽을 읽고 쓸 수 있는지 적은 파일 |

### 4.3 이 프로젝트에서 안 쓰지만 자주 나오는 지시어 (일반 지식)

| 지시어 | 용도 |
|---|---|
| `listener 8883` + `cafile`, `certfile`, `keyfile` | TLS(암호화) 접속 |
| `listener 9001` + `protocol websockets` | 브라우저에서 WebSocket으로 접속 |
| `max_connections N` | 동시 접속 수 제한 |
| `log_type all` / `log_dest stdout` | 로그 상세도와 출력 위치 |
| `max_keepalive` | 허용하는 keepalive 상한 |

---

## 5. 접근 제어 (인증과 ACL)

### 5.1 개념

- **인증(Authentication)**: "너 누구냐" → 사용자 이름과 비밀번호 확인.
- **권한(Authorization, ACL)**: "그 토픽에 읽고 쓸 수 있느냐" → `acl` 파일의 규칙.

### 5.2 이 프로젝트의 ACL (`infra/mosquitto/acl`)

```text
user rails
topic read smartfarm/+/telemetry
topic read smartfarm/+/status

pattern write smartfarm/%u/#
```

| 규칙 | 설명 |
|---|---|
| `user 이름` | 이 줄 아래의 `topic` 규칙은 그 사용자에게만 적용 |
| `topic read\|write\|readwrite\|deny 토픽` | 해당 사용자의 권한 |
| `pattern ...` | **모든 사용자**에게 적용되는 규칙. `%u`는 사용자 이름, `%c`는 클라이언트 ID로 치환 |

그래서 사용자 `balcony-01`은 `smartfarm/balcony-01/#`에만 쓸 수 있고, 사용자 `rails`는 두 읽기 규칙만 갖습니다. `acl_file`을 지정하면 **규칙에 없는 접근은 거부**됩니다.

### 5.3 실제로 확인한 동작

별도 브로커(1884 포트)로 시험했습니다(확인함).

| 시도 | 결과 |
|---|---|
| 익명 접속 | 거부 (`Connection refused: not authorised`) |
| 틀린 비밀번호 | 거부 |
| 장치 계정이 자기 토픽에 발행 | 구독자에게 전달됨 |
| 장치 계정이 **다른 장치** 토픽에 발행 | 구독자에게 전달되지 않음 |
| `rails` 계정이 telemetry에 발행 | 전달되지 않음 |

**중요한 함정:** ACL이 막은 발행은 **발행자에게 오류 없이 성공한 것처럼 보입니다**(QoS 1에서도 확인함). 에러로 알려 주지 않고 조용히 버립니다. 발행이 안 도착하면 먼저 사용자 이름이 토픽의 장치 ID와 같은지 확인하세요.

### 5.4 비밀번호 파일 권한 함정

- 브로커는 root가 아닌 `mosquitto` 사용자로 돌기 때문에, 파일이 `0700`(root 전용)이면 읽지 못해 `Unable to open pwfile`로 **시작하지 못합니다**(확인함).
- 파일을 `0644`로 두면 읽히지만 2.1.2가 경고를 냅니다(확인함): world readable, 소유자가 `mosquitto`가 아님, "향후 버전은 거부할 수 있음".
- 이상적인 해결은 `chown mosquitto passwd`와 `0600` 권한인데, Windows의 바인드 마운트에서는 소유자를 바꿀 수 없습니다. 지금은 경고를 감수합니다. Linux 서버에서 쓰게 되면 소유자를 맞추세요.
- 비밀번호는 평문이 아니라 해시(`$7$...`)로 저장됩니다(확인함).

### 5.5 보안 한계

- 이 구성은 **암호화되지 않은 1883 포트**입니다. 사용자 이름과 비밀번호가 Wi-Fi 구간에서 평문으로 오갑니다. 공유기 내부망 안에서만 쓰는 전제입니다.
- 외부에서 접속하거나 공용 네트워크에 노출하려면 TLS(8883)를 설정해야 합니다. 이 프로젝트에는 없습니다.
- 기본 설정(`allow_anonymous true`)은 같은 네트워크의 누구나 어떤 토픽에도 읽고 쓸 수 있습니다.

---

## 6. 이 프로젝트의 토픽과 메시지

| 토픽 | 발행자 | 내용 | retained | 구독자 |
|---|---|---|---|---|
| `smartfarm/<deviceId>/telemetry` | ESP32, `bin/fake_sensor` | 1분 평균 수온 등 JSON (`schemaVersion: 1`) | 아니오 | Rails |
| `smartfarm/<deviceId>/status` | ESP32 (접속 시), **브로커**(유언) | `online` / `offline` 문자열 | 예 | Rails |

telemetry 예:

```json
{"schemaVersion":1,"deviceId":"balcony-01","sequence":3,"measuredAt":"2026-10-03T13:12:48Z","waterTemperatureC":19.25}
```

Rails 쪽 처리: 토픽 마지막 단계(`telemetry`/`status`)로 나눠 각각 `IngestSensorReadingJob`, `UpdateDeviceStatusJob`에 넘기고, 저장·알림·화면 갱신은 서비스 객체가 합니다(`docs/소스 구조 분석.md` 참고).

---

## 7. 직접 만져 보기

모두 Mosquitto 컨테이너 안의 도구를 `docker exec`로 실행합니다(컨테이너 이름 `infra-mosquitto-1`). PowerShell 기준입니다.

### 7.1 브로커 정보 보기 (확인함)

```powershell
docker exec infra-mosquitto-1 mosquitto_sub -t '$SYS/broker/version' -C 1 -W 5 -v
# $SYS/broker/version mosquitto version 2.1.2
docker exec infra-mosquitto-1 mosquitto_sub -t '$SYS/broker/clients/connected' -C 1 -W 5 -v
```

- `-t` 토픽, `-v` 토픽 이름도 함께 출력, `-C 1` 메시지 1개 받으면 종료, `-W 5` 5초 안에 안 오면 종료.
- `$SYS/...`는 브로커가 스스로 발행하는 통계 토픽입니다(접속 수, 메시지 수, 버전 등). PowerShell에서는 `$`가 변수로 해석되므로 작은따옴표로 감쌉니다.

### 7.2 메시지 흐름 지켜보기

터미널 하나에서 프로젝트의 모든 메시지를 실시간으로 봅니다(끝내려면 Ctrl+C).

```powershell
docker exec infra-mosquitto-1 mosquitto_sub -t 'smartfarm/#' -v
```

다른 터미널에서 `bin/fake_sensor`를 실행하면 구독 쪽에 JSON이 찍힙니다. ESP32를 연결한 뒤에는 이 명령으로 "브로커까지 도착했는지"를 서버와 분리해서 확인할 수 있어서 문제 위치를 좁히는 데 유용합니다.

### 7.3 직접 발행하기

```powershell
docker exec infra-mosquitto-1 mosquitto_pub -t smartfarm/balcony-01/status -m offline
```

- 따옴표가 없는 단순 문자열은 문제없이 갑니다(확인함).
- **JSON처럼 큰따옴표가 들어간 페이로드는 PowerShell 5.1이 따옴표를 지워서 깨진 JSON이 전달됩니다**(확인함). 표준입력(`-s`)으로 넘겨도 PowerShell이 UTF-8 BOM을 앞에 붙여서 서버가 JSON 파싱에 실패했습니다(확인함). JSON을 보낼 때는 `bin/fake_sensor`나 Ruby `mqtt` 젬을 쓰거나, bash(`docs/testing.md` 3단계의 방식)에서 실행하세요.

### 7.4 인증이 켜진 브로커에서

계정 옵션을 붙입니다(`-u` 사용자, `-P` 비밀번호). 이 옵션 자체는 표준이지만 이 PC에서 도구로 직접 실행해 보지는 않았습니다.

```powershell
docker exec infra-mosquitto-1 mosquitto_sub -u rails -P '<railsPW>' -t 'smartfarm/#' -v
```

---

## 8. 문제 해결

### 8.1 펌웨어 시리얼에 `MQTT 연결 실패 rc=N`

PubSubClient의 `state()` 값입니다.

| rc | 의미 | 먼저 볼 것 |
|---|---|---|
| -4 | 응답 시간 초과 | 브로커 주소·네트워크 |
| -3 | 연결이 끊김 | Wi-Fi 신호, 브로커 재시작 |
| -2 | 접속 실패 | `MQTT_HOST` IP가 틀렸거나 방화벽이 1883을 막음 |
| -1 | 연결 끊긴 상태 | 접속 시도 전 |
| 0 | 연결됨 | (정상) |
| 1 | 프로토콜 버전 불일치 | 라이브러리·브로커 설정 |
| 2 | 클라이언트 ID 거부 | `DEVICE_ID` 형식 |
| 3 | 브로커 사용 불가 | 브로커 상태 |
| 4 | 사용자 이름·비밀번호 틀림 | `MQTT_USER`/`MQTT_PASSWORD` |
| 5 | 권한 없음 | 인증을 켠 브로커에서 계정이 없거나 거부됨 |

### 8.2 서버 쪽

| 증상 | 확인 |
|---|---|
| 구독자가 `connection lost`를 반복 | 브로커가 켜져 있는지(`docker compose ps`), `MQTT_HOST`/`MQTT_PORT`, 구독자를 두 개 켜지 않았는지 |
| 인증 켠 뒤 구독자가 접속 못 함 | `MQTT_USERNAME=rails`, `MQTT_PASSWORD`를 구독자 실행 환경에 지정했는지 |
| 브로커가 시작하자마자 종료 | `docker logs infra-mosquitto-1`에서 `Unable to open pwfile`(권한), 설정 오류 줄 확인 |
| 발행했는데 안 도착 | 인증 켠 경우 ACL(사용자 이름 = 장치 ID), 토픽 철자·대소문자 |
| 같은 메시지가 두 번 처리됨 | QoS 1의 중복 전달 가능. 서버는 `duplicate`로 무시함 |

로그 보기: `docker compose --env-file ../.env logs -f mosquitto` (`infra/` 폴더에서). 접속·종료·오류가 모두 시각과 함께 나옵니다.

---

## 9. 용어 정리

| 용어 | 뜻 |
|---|---|
| MQTT | Message Queuing Telemetry Transport. 발행·구독 방식의 경량 메시지 규약 |
| 브로커 | 메시지를 중계하는 서버 (Mosquitto) |
| 토픽 | 메시지 주소. `/`로 계층 구분 |
| `+` / `#` | 한 단계 / 하위 전체 와일드카드 (구독에서만) |
| QoS | 전달 보장 수준 0, 1, 2 |
| retained | 브로커가 토픽의 마지막 메시지를 기억하는 옵션 |
| LWT / Last Will | 비정상 종료 시 브로커가 대신 발행하는 유언 메시지 |
| keepalive | 연결 유지 확인 주기 |
| 클라이언트 ID | 접속한 클라이언트의 고유 이름. 중복 접속 시 먼저 것이 끊김 |
| ACL | 계정별 토픽 읽기·쓰기 권한 목록 |
| `$SYS` | 브로커가 자기 통계를 발행하는 시스템 토픽 |
| persistence | 브로커 상태를 디스크에 저장하는 기능 |

## 10. 더 읽을 문서

- `docs/infra 설명.md`: `infra/` 폴더 전체와 compose 설정
- `docs/testing.md`: 단계별 시험 절차와 "Mosquitto 인증 켜기"
- `docs/펌웨어 main.cpp 설명.md`: ESP32가 MQTT로 접속·발행하는 코드
- 공식 문서: Mosquitto 설정 `mosquitto.conf(5)` 매뉴얼, MQTT 규격(OASIS MQTT 3.1.1)
