# 펌웨어 `main.cpp` 설명 (웹 개발자용)

대상: `firmware/src/main.cpp` · 작성일: 2026-10-03

웹 개발 경험은 있지만 ESP32와 하드웨어는 처음인 분을 위한 설명입니다. 먼저 하드웨어 개념을 웹 개념에 빗대어 정리하고, 그다음 코드를 위에서 아래로 읽습니다.

> 주의: 이 펌웨어는 `esp32dev`와 `esp32dev_fake` 두 환경 모두 컴파일에 성공했지만(2026-10-03), 실물 ESP32에 올려 본 적은 없습니다(PRD의 P2-2). 이 문서는 코드를 읽고 설명한 것이며 Wi-Fi·MQTT·센서 동작을 실행으로 확인한 것이 아닙니다.

---

## 1. 이 프로그램이 하는 일

한 줄 요약: **수조 물의 온도를 5초마다 재서, 1분이 지나면 평균을 내어 Wi-Fi로 서버(MQTT 브로커)에 보낸다.**

```text
[온도센서 DS18B20] --선--> [ESP32 보드] --Wi-Fi--> [공유기] --> [PC의 Mosquitto] --> Rails 서버
```

웹 개발에 빗대면 "5초마다 값을 읽어서 모아 두고, 60초마다 평균을 계산해 서버에 POST하는 작은 백그라운드 프로그램"입니다.

---

## 2. 알아야 할 하드웨어 기초

### 2.1 ESP32가 뭔가요

- **마이크로컨트롤러(MCU)**: 작은 컴퓨터 칩입니다. OS(리눅스, 윈도우)가 없고, 우리가 올린 프로그램 하나만 전원이 켜지는 순간부터 계속 실행됩니다.
- Wi-Fi와 Bluetooth가 칩 안에 들어 있어서, 센서만 연결하면 인터넷에 붙는 기기를 만들 수 있습니다.
- 서버와 달리 터미널, 파일 시스템, 멀티프로세스가 없습니다. 메모리도 수백 KB 수준이라 아주 작습니다.
- 개발 보드(`esp32dev`)는 이 칩에 USB 연결 단자와 전원 회로를 붙여 놓은 것입니다. PC에서 USB로 프로그램을 올립니다(= "업로드" 또는 "플래시").

### 2.2 핀(GPIO)

보드 가장자리의 금속 핀들입니다. 코드에서 "4번 핀"이라고 하면 보드에 `GPIO4`라고 적힌 핀을 뜻합니다. 이 핀에 센서 선을 꽂으면, 코드가 전기 신호를 읽고 쓸 수 있습니다. 웹으로 치면 "포트 번호"와 비슷하게, 어느 입구로 통신할지 정하는 번호입니다.

### 2.3 센서 DS18B20

- 물에 담글 수 있는 방수형(검은 막대 모양이 흔함) **디지털 온도 센서**입니다. 읽으면 "19.25" 같은 숫자를 바로 줍니다.
- 선이 3개입니다: 전원(VCC, 3.3V), 접지(GND), 데이터(DATA).
- **OneWire**는 데이터 선 한 가닥으로 통신하는 방식(프로토콜)의 이름입니다. HTTP 같은 것이라고 생각하면 됩니다.
- 파일 맨 위 주석의 배선 설명: 데이터 선을 GPIO4에 꽂고, 데이터 선과 3.3V 사이에 4.7kΩ 저항을 하나 연결합니다. 이 저항을 **풀업 저항**이라고 하며, 신호선이 평소에 "켜진(HIGH) 상태"로 있게 잡아 주는 부품입니다. 없으면 센서가 안 읽힙니다. (코드 쪽 오류 메시지가 "배선과 풀업 저항 확인"이라고 하는 이유입니다.)

### 2.4 전압 단위 3.3V

ESP32는 3.3V로 동작합니다. 5V를 데이터 핀에 연결하면 칩이 고장 날 수 있으니, 센서 전원은 반드시 3.3V에 연결합니다.

---

## 3. 프로그램 실행 방식: `setup()`과 `loop()`

이 코드는 **Arduino 프레임워크**를 씁니다(`platformio.ini`의 `framework = arduino`). 규칙이 단순합니다.

| 함수 | 언제 실행 | 웹 개발에 빗대면 |
|---|---|---|
| `void setup()` | 전원이 켜질 때 **딱 한 번** | 서버 부팅 시 initializer |
| `void loop()` | `setup()` 뒤에 **무한 반복** (초당 수천 번 이상) | `while (true) { ... }` 이벤트 루프 |

- 멀티스레드가 없습니다. `loop()` 하나가 계속 돌면서 "할 일이 있나?" 하고 확인합니다. 이런 방식을 **폴링**이라고 합니다.
- 그래서 **한 곳에서 오래 멈추면(`delay`) 그동안 다른 일을 못 합니다.** Node.js에서 이벤트 루프를 오래 막으면 안 되는 것과 같은 이유입니다.
- `main()` 함수는 Arduino가 숨겨서 대신 만들어 주고, 그 안에서 `setup()` 한 번 → `loop()` 반복 호출을 합니다.

---

## 4. 코드를 위에서 아래로 읽기

### 4.1 `#include` 와 라이브러리

```cpp
#include <Arduino.h>          // Arduino 기본 함수 (millis, delay, Serial 등)
#include <ArduinoJson.h>      // JSON 만들기
#include <DallasTemperature.h>// DS18B20 온도 읽기
#include <OneWire.h>          // OneWire 통신
#include <PubSubClient.h>     // MQTT 클라이언트
#include <WiFi.h>             // Wi-Fi
#include <time.h>             // 시각 함수
#include "secrets.h"          // Wi-Fi 비밀번호 등 (Git에 안 올림)
```

- `#include`는 다른 파일의 내용을 가져오는 C의 방식입니다. JS의 `import`와 비슷합니다.
- 라이브러리는 `platformio.ini`의 `lib_deps`에 적혀 있고 빌드할 때 자동으로 내려받습니다(npm의 `package.json`과 비슷).
- `<파일>`은 라이브러리/시스템에서 찾고, `"파일"`은 프로젝트 폴더에서 찾습니다. `secrets.h`는 `secrets.h.example`을 복사해서 직접 만들어야 하는 파일이며 `WIFI_SSID`, `MQTT_HOST`, `DEVICE_ID` 같은 값이 `#define`으로 들어 있습니다.

### 4.2 상수와 전역 변수

```cpp
static const uint8_t ONE_WIRE_PIN = 4;
static const uint32_t SAMPLE_INTERVAL_MS = 5000;
static const uint32_t PUBLISH_INTERVAL_MS = 60000;
static const float WATER_TEMP_MIN_C = -10.0f;
static const float WATER_TEMP_MAX_C = 60.0f;
```

| 문법 | 의미 |
|---|---|
| `static` | 이 파일 안에서만 쓰는 이름(다른 파일에서 접근 불가). JS의 모듈 스코프 `const`와 비슷합니다 |
| `const` | 바꿀 수 없는 값 |
| `uint8_t` | 부호 없는 8비트 정수 (0~255). 핀 번호는 작아서 이걸 씁니다 |
| `uint32_t` | 부호 없는 32비트 정수 (0 ~ 약 43억). 밀리초 시간에 씁니다 |
| `uint16_t` | 부호 없는 16비트 정수 (0~65535) |
| `float` | 소수. `10.0f`의 `f`는 "float 타입 숫자"라는 표시 |
| `_MS`, `_C` | 이름 뒤 단위 표기: 밀리초, 섭씨 |

- 5초마다 측정(`SAMPLE_INTERVAL_MS`), 60초마다 발행(`PUBLISH_INTERVAL_MS`).
- 센서가 물리적으로 말이 안 되는 값(-10℃ 미만, 60℃ 초과)을 주면 오류로 보고 버리는 기준입니다. 서버의 `SensorReading` 검증 범위(-10~60)와 같습니다.

```cpp
static String telemetryTopic = String("smartfarm/") + DEVICE_ID + "/telemetry";
static String statusTopic    = String("smartfarm/") + DEVICE_ID + "/status";
```

- **토픽**은 MQTT에서 메시지를 보내는 "주소"입니다. URL 경로처럼 `/`로 구분합니다. 예: `smartfarm/balcony-01/telemetry`.
- `String`은 Arduino의 문자열 클래스입니다. `+`로 이어 붙일 수 있습니다.
- `DEVICE_ID`는 `secrets.h`에 `#define`으로 정의된 문자열 상수입니다. `#define`은 컴파일 전에 글자 그대로 치환하는 매크로입니다.

```cpp
WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature sensors(&oneWire);
```

- 객체를 만드는 부분입니다. `PubSubClient mqtt(wifiClient)`는 "MQTT 클라이언트는 이 Wi-Fi 연결 위로 통신한다"는 뜻입니다.
- `&oneWire`는 "oneWire의 **주소**(참조)를 넘긴다"는 C/C++ 문법입니다. 복사하지 않고 같은 객체를 쓰게 합니다.

```cpp
static float tempSum = 0;          // 5초마다 측정한 값의 합
static uint16_t tempCount = 0;     // 몇 번 측정했는지
static uint32_t lastSampleAt = 0;  // 마지막으로 측정한 시각 (millis)
static uint32_t lastPublishAt = 0; // 마지막으로 발행한 시각
static uint32_t lastMqttAttemptAt = 0; // 마지막 MQTT 접속 시도 시각
static uint32_t sequence = 0;      // 발행 일련번호
```

상태를 담는 전역 변수들입니다. 웹으로 치면 서버 메모리에 들고 있는 싱글턴 상태입니다. 평균은 "합 ÷ 개수"로 구합니다.

### 4.3 `millis()` 가 뭔가요

코드 전체에서 계속 나오는 함수입니다. **전원이 켜진 뒤 지난 시간을 밀리초(1/1000초)로 돌려줍니다.** 이 칩에는 `setTimeout` 같은 게 없어서, 시간 간격을 직접 이렇게 확인합니다.

```cpp
if (now - lastSampleAt >= SAMPLE_INTERVAL_MS) {   // "마지막 측정 후 5초 지났나?"
  lastSampleAt = now;
  sample();
}
```

- `millis()`는 약 49.7일 뒤에 4,294,967,295(32비트 최대)를 넘어 0으로 되돌아갑니다. 그런데 `now - lastSampleAt`처럼 **뺄셈으로 경과 시간을 구하면 부호 없는 정수의 특성상 되돌아가는 순간에도 올바른 값이 나옵니다.** 그래서 이 방식(`현재 - 이전 >= 간격`)을 쓰는 것이 정석입니다.

### 4.4 `connectWifi()` — Wi-Fi 연결

```cpp
static void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;   // 이미 연결됐으면 바로 끝
  WiFi.mode(WIFI_STA);                          // 공유기에 붙는 "클라이언트 모드"
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);         // 연결 시작
  Serial.print("Wi-Fi 연결 중");
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " 연결됨" : " 실패 (나중에 다시 시도)");
}
```

- `WIFI_STA`(Station)는 "공유기에 접속하는 기기" 모드입니다. 반대는 ESP32가 직접 공유기가 되는 AP 모드입니다.
- `Serial`은 **USB 케이블로 PC에 글자를 출력하는 통로**입니다. `console.log`에 해당합니다. PC에서 `pio device monitor`(또는 Arduino 시리얼 모니터)로 볼 수 있고, 속도(`monitor_speed = 115200`)와 `Serial.begin(115200)`이 일치해야 글자가 깨지지 않습니다.
- `delay(500)`은 500ms 동안 멈춥니다. 최대 15초까지 연결을 기다리고 실패하면 포기합니다.
- `cond ? A : B`는 JS와 같은 삼항 연산자입니다.
- `loop()` 안에서 매번 호출되지만 이미 연결돼 있으면 첫 줄에서 바로 `return`하므로 비용이 거의 없습니다. 덕분에 공유기가 재시작되어 끊겨도 자동으로 다시 붙습니다.

### 4.5 `timeIsSet()` 과 `syncClock()` — 시계 맞추기

```cpp
static bool timeIsSet() { return time(nullptr) > 1700000000; }

static void syncClock() {
  configTime(0, 0, "pool.ntp.org", "time.google.com");
}
```

- ESP32에는 건전지로 유지되는 시계(RTC)가 없습니다. 전원을 켜면 시각이 **1970-01-01**(유닉스 시간 0)에서 시작합니다. 서버는 `measuredAt`을 ISO 8601 UTC 시각으로 받아야 하므로, 인터넷 시간 서버(NTP)에서 현재 시각을 받아 옵니다.
- `configTime(0, 0, 서버1, 서버2)`: 앞의 두 인자는 시간대 오프셋(UTC 기준, 서머타임 없음)이고 뒤는 NTP 서버 주소입니다. 한 번 호출하면 백그라운드에서 시각을 맞춥니다.
- `time(nullptr)`은 현재 유닉스 시간(초)입니다. `1700000000`은 2023년 11월입니다. 이보다 크면 "실제 시각으로 맞춰졌다"고 판단합니다(아직 1970년 근처면 맞춰지지 않은 것).
- 서버(`SensorReadingIngestor`)는 `Time.iso8601`로 파싱하고 `(device, measured_at)`이 같으면 중복으로 버리므로, 시각이 틀리면 데이터가 이상해집니다. 그래서 시각을 모를 때는 발행하지 않습니다(4.9 참고).

### 4.6 `connectMqtt()` — MQTT 연결

**MQTT란?** 가벼운 메시지 통신 규약입니다. 서버-클라이언트가 직접 통신하는 HTTP와 달리, 가운데 **브로커**(Mosquitto)가 있고 한쪽이 토픽에 **발행(publish)**하면 그 토픽을 **구독(subscribe)**한 쪽이 받습니다. 센서처럼 작은 기기가 값을 자주 보내는 용도에 많이 씁니다. 이 프로젝트에서는 ESP32가 발행하고 Rails의 `bin/mqtt_subscriber`가 구독합니다.

```cpp
static void connectMqtt() {
  if (mqtt.connected() || WiFi.status() != WL_CONNECTED) return;
  if (millis() - lastMqttAttemptAt < 5000 && lastMqttAttemptAt != 0) return;
  lastMqttAttemptAt = millis();

  const char* user = strlen(MQTT_USER) ? MQTT_USER : nullptr;
  const char* pass = strlen(MQTT_USER) ? MQTT_PASSWORD : nullptr;
  bool ok = mqtt.connect(DEVICE_ID, user, pass, statusTopic.c_str(), 1, true, "offline");
  if (ok) {
    mqtt.publish(statusTopic.c_str(), "online", true);
    Serial.println("MQTT 연결됨");
  } else {
    Serial.printf("MQTT 연결 실패 rc=%d\n", mqtt.state());
  }
}
```

한 줄씩:
1. 이미 연결됐거나 Wi-Fi가 없으면 할 일이 없으니 종료.
2. 마지막 시도 후 5초가 안 지났으면 종료. 실패할 때 쉬지 않고 두드리지 않으려는 **재시도 간격 제한**입니다(첫 시도는 `lastMqttAttemptAt == 0`이라 바로 진행).
3. `user`, `pass`: `MQTT_USER`가 빈 문자열(`""`)이면 계정 없이(`nullptr` = 널 포인터, JS의 `null`과 비슷) 접속하고, 값이 있으면 계정으로 접속합니다. 브로커에 인증을 켠 뒤에 쓰는 대비입니다.
4. `const char*`는 C 스타일 문자열(글자 배열의 시작 주소)입니다. `statusTopic.c_str()`는 `String`을 이 형태로 바꿔 줍니다. C 라이브러리 함수들이 이 형태를 요구합니다.
5. `mqtt.connect(클라이언트ID, 사용자, 비밀번호, 유언토픽, 유언QoS, 유언retain, 유언메시지)`

**Last Will(유언)과 retained**
- `statusTopic`에 `"offline"`을 **유언 메시지**로 등록합니다. ESP32가 전원이 뽑히거나 네트워크가 끊겨 **연결이 비정상적으로 끊기면 브로커가 대신 이 메시지를 발행**해 줍니다. 장치는 이미 죽었으니 스스로 "나 죽는다"를 보낼 수 없기 때문에 쓰는 장치입니다.
- 연결에 성공하면 같은 토픽에 `"online"`을 보냅니다.
- `true`(retained)는 "브로커가 이 메시지를 계속 기억해 두라"는 뜻입니다. 나중에 접속한 구독자도 마지막 상태를 바로 받을 수 있습니다.
- 서버의 `DeviceStatusUpdater`가 이 online/offline을 받아 `mqtt_state`를 바꾸고 오프라인 알림을 열고 닫습니다.

`Serial.printf("... rc=%d\n", mqtt.state())`는 C의 `printf`입니다. `%d`가 뒤의 값(정수)으로 치환됩니다. `rc`는 return code로, 실패 원인 번호입니다(예: 접속 거부, 브로커 주소 오류 등).

### 4.7 `readWaterTemp()` — 수온 읽기 (센서 / 가짜 센서)

```cpp
static bool readWaterTemp(float& out) {
#ifdef FAKE_SENSOR
  out = 19.0f + 2.0f * sinf(millis() / 600000.0f);
  return true;
#else
  sensors.requestTemperatures();
  float c = sensors.getTempCByIndex(0);
  if (c == DEVICE_DISCONNECTED_C || c < WATER_TEMP_MIN_C || c > WATER_TEMP_MAX_C) return false;
  out = c;
  return true;
#endif
}
```

- **`float& out`** 는 "참조로 받는 매개변수"입니다. 함수 안에서 `out`을 바꾸면 호출한 쪽의 변수가 바뀝니다. C에는 여러 값을 반환하는 문법이 없어서, "성공 여부는 `return`(bool)으로, 실제 값은 `out`으로" 돌려주는 패턴을 씁니다. JS라면 `{ ok, value }`를 반환하는 것에 해당합니다.
- **`#ifdef FAKE_SENSOR ... #else ... #endif`** 는 **컴파일 전 조건**입니다. `FAKE_SENSOR`가 정의돼 있으면 위쪽 코드만, 아니면 아래쪽 코드만 프로그램에 들어갑니다(런타임 `if`가 아니라 빌드할 때 한쪽이 아예 사라집니다).
  - `platformio.ini`의 `[env:esp32dev_fake]`가 `-DFAKE_SENSOR=1`을 붙여서 가짜 모드로 빌드합니다. 센서를 아직 안 샀거나 배선 전에 서버 연결만 시험할 때 씁니다.
  - 가짜 값: `19 + 2 × sin(시간)` → 17~21℃를 천천히 오갑니다. `600000.0f`는 10분 단위이고 사인 한 주기는 약 62.8분입니다.
- **실제 센서 모드**:
  - `requestTemperatures()`: 센서에 "지금 온도를 재라"고 명령합니다(약 0.1~0.75초 걸릴 수 있음, 이 동안 코드가 대기합니다).
  - `getTempCByIndex(0)`: 연결된 첫 번째 센서의 섭씨 값을 읽습니다. 한 선에 여러 센서를 달 수 있어서 번호(index)로 구분합니다.
  - `DEVICE_DISCONNECTED_C`는 라이브러리가 "센서가 안 보인다"는 뜻으로 돌려주는 특수 값(-127)입니다. 이 값이거나 범위를 벗어나면 `false`(실패)를 돌려줍니다.

### 4.8 `sample()` — 측정값 모으기

```cpp
static void sample() {
  float c;
  if (readWaterTemp(c)) {
    tempSum += c;
    tempCount++;
  } else {
    Serial.println("수온 센서 값을 읽지 못했습니다 (배선과 풀업 저항 확인)");
  }
}
```

성공한 값만 합과 개수에 누적합니다. 실패한 측정은 평균에서 제외됩니다. `readWaterTemp(c)`에서 `c`가 `out`으로 넘어가 값이 채워집니다.

### 4.9 `publishAverage()` — 평균 계산과 발행

```cpp
static void publishAverage() {
  if (tempCount == 0) return;          // 유효한 측정이 없으면 보내지 않는다
  if (!timeIsSet()) { ...; return; }   // 시계가 안 맞았으면 보내지 않는다
  if (!mqtt.connected()) return;       // 연결이 없으면 보내지 않는다
```

세 가지 가드(조건에 안 맞으면 조용히 건너뜀)입니다.
- 센서가 계속 실패했으면 평균을 낼 데이터가 없습니다. 0으로 나누는 일도 막아 줍니다.
- 시각을 모르면 `measuredAt`을 만들 수 없습니다.
- 서버에 못 보내는 상태입니다. 아래 설명처럼 이번 구간의 데이터는 버려집니다.

```cpp
  char measuredAt[25];
  time_t now = time(nullptr);
  strftime(measuredAt, sizeof(measuredAt), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
```

- 현재 유닉스 시간을 `2026-10-03T13:12:48Z` 형태의 문자열로 만듭니다. `gmtime`은 UTC 시각으로 분해하고, `strftime`은 날짜 서식 지정 함수입니다(JS의 `toISOString()`에 해당).
- `char measuredAt[25]`는 글자 25칸짜리 배열(문자열 버퍼)입니다. C에서는 문자열을 담을 공간을 미리 크기를 정해 잡아야 합니다. 결과는 끝의 널 문자 포함 21칸이면 충분합니다.
- `&now`의 `&`는 "변수의 주소"입니다. `gmtime`이 주소를 받는 함수입니다.

```cpp
  JsonDocument doc;
  doc["schemaVersion"] = 1;
  doc["deviceId"] = DEVICE_ID;
  doc["sequence"] = ++sequence;
  doc["measuredAt"] = measuredAt;
  char avg[12];
  snprintf(avg, sizeof(avg), "%.2f", tempSum / tempCount);
  doc["waterTemperatureC"] = serialized(avg);
```

- `JsonDocument`는 JS 객체처럼 `doc["키"] = 값`으로 채웁니다(ArduinoJson 7).
- `++sequence`는 1 증가시킨 값을 씁니다. 장치 재부팅 시 0부터 다시 시작합니다(저장하지 않으므로). 서버는 중복 판정을 `(device, measured_at)`으로 하고 `sequence`는 참고용으로 저장합니다.
- `snprintf(avg, 크기, "%.2f", 평균)`은 평균을 소수 둘째 자리 문자열(예: `"19.25"`)로 만들어 `avg`에 담습니다. `%.2f`는 "소수점 2자리 실수"입니다.
- `serialized(avg)`는 "이 문자열을 따옴표 없이 **JSON 숫자 그대로** 넣어라"는 뜻입니다. 그냥 `float`을 넣으면 `19.25` 대신 `19.25000`이나 부동소수 오차 표기가 나올 수 있어서, 원하는 자릿수를 문자열로 만든 뒤 숫자로 넣습니다.

```cpp
  char payload[256];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  bool ok = mqtt.publish(telemetryTopic.c_str(), reinterpret_cast<const uint8_t*>(payload), n, false);
  Serial.printf("발행 %s: %s\n", ok ? "성공" : "실패", payload);
}
```

- `serializeJson`은 JSON을 `payload` 버퍼에 글자로 써 넣고, 쓴 글자 수(`n`)를 돌려줍니다. `JSON.stringify`에 해당합니다.
- `mqtt.publish(토픽, 바이트 배열, 길이, retained)`로 발행합니다. `reinterpret_cast<const uint8_t*>`는 "이 글자 배열을 바이트 배열로 취급하라"는 형 변환일 뿐 데이터가 바뀌지는 않습니다.
- `retained=false`: 센서 값은 과거 값이 남아 있으면 안 되므로 기억시키지 않습니다. 반면 상태(`status`)는 retained입니다.
- 발행된 JSON 예: `{"schemaVersion":1,"deviceId":"balcony-01","sequence":3,"measuredAt":"2026-10-03T13:12:48Z","waterTemperatureC":19.25}`

참고: `platformio.ini`의 `-DMQTT_MAX_PACKET_SIZE=512`는 MQTT 라이브러리의 메시지 버퍼를 늘리는 설정입니다(기본값이 작아 JSON이 잘릴 수 있어서).

### 4.10 `setup()` — 시작할 때 한 번

```cpp
void setup() {
  Serial.begin(115200);          // 시리얼 출력 시작 (속도 115200)
#ifndef FAKE_SENSOR
  sensors.begin();               // 실제 센서 모드일 때만 센서 초기화
#endif
  connectWifi();                 // Wi-Fi 접속 (최대 15초)
  syncClock();                   // 시간 서버에서 시각 받기 시작
  mqtt.setServer(MQTT_HOST, MQTT_PORT);  // 브로커 주소 설정 (접속은 아직 아님)
  lastSampleAt = lastPublishAt = millis(); // 타이머 기준점을 지금으로
}
```

- `#ifndef`는 "정의돼 있지 **않으면**"입니다.
- `a = b = c` 형태로 두 변수에 같은 값을 넣었습니다. 이 줄은 측정/발행 타이머의 기준을 "지금"으로 맞춥니다. 안 하면 시작하자마자 "0ms 이후 한참 지났다"고 판단해 즉시 실행합니다.
- `setServer`는 주소만 저장합니다. 실제 접속은 `loop()` 안의 `connectMqtt()`가 합니다.

### 4.11 `loop()` — 계속 반복되는 본체

```cpp
void loop() {
  connectWifi();    // 끊겼으면 다시 붙기
  connectMqtt();    // 끊겼으면 다시 붙기 (5초 간격 제한)
  mqtt.loop();      // MQTT 통신 처리 (필수)

  uint32_t now = millis();
  if (now - lastSampleAt >= SAMPLE_INTERVAL_MS) {   // 5초마다
    lastSampleAt = now;
    sample();
  }
  if (now - lastPublishAt >= PUBLISH_INTERVAL_MS) { // 60초마다
    lastPublishAt = now;
    publishAverage();
    tempSum = 0;       // 다음 구간을 위해 비움
    tempCount = 0;
  }
}
```

- **`mqtt.loop()`는 반드시 자주 불러야 합니다.** 브로커와 주고받는 신호(연결 유지 ping, 수신 처리)를 이 함수가 처리하기 때문입니다. 그래서 `loop()` 안에서 오래 멈추는 코드를 넣지 않는 것이 중요합니다.
- 두 개의 타이머가 `millis()` 뺄셈 방식으로 독립적으로 돌아갑니다. `loop()`가 쉬지 않고 돌고, 해당 시점이 오면 한 번씩 실행합니다.
- 발행 후 합과 개수를 0으로 비우므로, 평균은 **직전 1분 구간**의 값입니다. 발행이 건너뛰어진 경우(위 가드 3개)에도 비우기 때문에 그 구간의 데이터는 버려집니다("연결이 없으면 이번 평균은 버리고 새로 모은다"는 주석이 이 뜻입니다).

---

## 5. 시간 흐름으로 보기

```text
전원 ON
 └ setup(): 시리얼 시작 → Wi-Fi 접속 → 시간 서버 요청 → 브로커 주소 설정
 loop() 반복:
   0.0s  MQTT 접속(첫 시도) → "online" 발행 (유언 offline 등록됨)
   5s    수온 측정 #1   (합=19.3, 개수=1)
  10s    수온 측정 #2
   ...   (12회)
  60s    평균 계산 → telemetry 발행 → 합/개수 초기화
  65s    수온 측정 → 다음 구간 시작
 전원 OFF(비정상) → 브로커가 "offline" 대신 발행 → 서버가 오프라인 알림
```

서버 쪽에서는 이 메시지를 `bin/mqtt_subscriber`가 받아 `IngestSensorReadingJob`(telemetry)과 `UpdateDeviceStatusJob`(status)로 넘기고, 화면은 Turbo Streams로 갱신됩니다(`docs/소스 구조 분석.md` 참고).

---

## 6. 용어 정리

| 용어 | 뜻 |
|---|---|
| MCU / ESP32 | OS 없이 프로그램 하나만 도는 작은 칩 / 그중 Wi-Fi 내장 제품 |
| GPIO | 센서를 연결하는 범용 입출력 핀 |
| 풀업 저항 | 신호선을 평소 HIGH로 잡아 주는 저항(여기선 4.7kΩ) |
| OneWire | 선 1개로 통신하는 방식. DS18B20이 사용 |
| 시리얼(Serial) | USB로 PC에 로그를 보내는 통로. `console.log`와 비슷 |
| 폴링 | `loop()`가 계속 돌면서 할 일이 있는지 확인하는 방식 |
| `millis()` | 부팅 후 경과 시간(ms) |
| NTP | 인터넷 시간 서버 프로토콜 |
| MQTT / 브로커 | 토픽 기반 발행·구독 메시징 / 중간에서 메시지를 전달하는 서버(Mosquitto) |
| 토픽 | MQTT 메시지의 주소(`smartfarm/<장치>/telemetry`) |
| Last Will | 연결이 비정상적으로 끊기면 브로커가 대신 발행하는 유언 메시지 |
| retained | 브로커가 마지막 메시지를 기억하게 하는 옵션 |
| `#ifdef` | 빌드할 때 코드를 포함/제외하는 컴파일 전 조건 |
| `float&` | 참조 매개변수. 호출한 쪽 변수에 값을 돌려줄 때 사용 |
| `const char*` | C 스타일 문자열 |

---

## 7. 코드를 읽으며 눈에 띈 점 (실행으로 확인하지 않음)

- **Wi-Fi가 끊긴 동안 `loop()`가 멈출 수 있습니다.** `connectWifi()`는 연결이 없으면 `loop()`가 돌 때마다 최대 15초씩 기다립니다. 이 시간 동안 측정도 못 하고 `mqtt.loop()`도 못 부릅니다. 안정적으로 연결되는 환경에서는 문제가 없지만, 공유기가 꺼진 동안은 측정 간격이 어긋납니다.
- **`syncClock()`은 `setup()`에서 한 번만 호출됩니다.** Wi-Fi 연결에 실패한 채 부팅하면 시각 동기화가 이루어지는지는 이 코드만으로는 알 수 없습니다(라이브러리 동작에 따라 다름, 추정). 시계가 안 맞으면 `publishAverage()`가 계속 건너뜁니다.
- **측정과 발행 사이에 `requestTemperatures()`가 센서 변환 시간만큼 코드를 멈춥니다.** 5초에 한 번이라 큰 문제는 없습니다.
- **재부팅하면 `sequence`가 1부터 다시 시작합니다.** 서버는 `measured_at`으로 중복을 판단하므로 영향은 없습니다.
- **현재 `esp32dev_fake` 환경은 센서 없이도 서버 연결을 시험할 수 있습니다.** 실물 확인은 PRD의 P2-2에서 진행할 항목입니다.
