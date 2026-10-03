// 수온(DS18B20) 1분 평균을 MQTT로 발행한다.
// 토픽: smartfarm/<DEVICE_ID>/telemetry  (서버가 구독, JSON schemaVersion 1)
//       smartfarm/<DEVICE_ID>/status     (online/offline, retained, Last Will)
// 배선: DS18B20 데이터 -> GPIO4, 데이터와 3.3V 사이 4.7kΩ 풀업, VCC 3.3V, GND 공통.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <DallasTemperature.h>
#include <OneWire.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <time.h>

#include "secrets.h"

static const uint8_t ONE_WIRE_PIN = 4;
static const uint32_t SAMPLE_INTERVAL_MS = 5000;     // 5초마다 측정
static const uint32_t PUBLISH_INTERVAL_MS = 60000;   // 1분마다 평균 발행
static const float WATER_TEMP_MIN_C = -10.0f;        // 이 범위를 벗어나면 센서 오류로 보고 버린다
static const float WATER_TEMP_MAX_C = 60.0f;

static String telemetryTopic = String("smartfarm/") + DEVICE_ID + "/telemetry";
static String statusTopic = String("smartfarm/") + DEVICE_ID + "/status";

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature sensors(&oneWire);

static float tempSum = 0;
static uint16_t tempCount = 0;
static uint32_t lastSampleAt = 0;
static uint32_t lastPublishAt = 0;
static uint32_t lastMqttAttemptAt = 0;
static uint32_t sequence = 0;

static void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Wi-Fi 연결 중");
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " 연결됨" : " 실패 (나중에 다시 시도)");
}

static bool timeIsSet() { return time(nullptr) > 1700000000; }

// 서버가 UTC ISO 8601 시각을 요구하므로 NTP로 시계를 맞춘다.
static void syncClock() {
  configTime(0, 0, "pool.ntp.org", "time.google.com");
}

static void connectMqtt() {
  if (mqtt.connected() || WiFi.status() != WL_CONNECTED) return;
  if (millis() - lastMqttAttemptAt < 5000 && lastMqttAttemptAt != 0) return;  // 5초 간격으로만 재시도
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

static bool readWaterTemp(float& out) {
#ifdef FAKE_SENSOR
  out = 19.0f + 2.0f * sinf(millis() / 600000.0f);  // 가짜 값: 17~21℃를 천천히 오간다
  return true;
#else
  sensors.requestTemperatures();
  float c = sensors.getTempCByIndex(0);
  if (c == DEVICE_DISCONNECTED_C || c < WATER_TEMP_MIN_C || c > WATER_TEMP_MAX_C) return false;
  out = c;
  return true;
#endif
}

static void sample() {
  float c;
  if (readWaterTemp(c)) {
    tempSum += c;
    tempCount++;
  } else {
    Serial.println("수온 센서 값을 읽지 못했습니다 (배선과 풀업 저항 확인)");
  }
}

static void publishAverage() {
  if (tempCount == 0) return;         // 유효한 측정이 없으면 보내지 않는다
  if (!timeIsSet()) {
    Serial.println("시계가 아직 맞춰지지 않아 발행을 건너뜁니다");
    return;
  }
  if (!mqtt.connected()) return;      // 연결이 없으면 이번 평균은 버리고 새로 모은다

  char measuredAt[25];
  time_t now = time(nullptr);
  strftime(measuredAt, sizeof(measuredAt), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));

  JsonDocument doc;
  doc["schemaVersion"] = 1;
  doc["deviceId"] = DEVICE_ID;
  doc["sequence"] = ++sequence;
  doc["measuredAt"] = measuredAt;
  char avg[12];
  snprintf(avg, sizeof(avg), "%.2f", tempSum / tempCount);
  doc["waterTemperatureC"] = serialized(avg);  // 소수 둘째 자리까지 그대로 JSON 숫자로 넣는다

  char payload[256];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  bool ok = mqtt.publish(telemetryTopic.c_str(), reinterpret_cast<const uint8_t*>(payload), n, false);
  Serial.printf("발행 %s: %s\n", ok ? "성공" : "실패", payload);
}

void setup() {
  Serial.begin(115200);
#ifndef FAKE_SENSOR
  sensors.begin();
#endif
  connectWifi();
  syncClock();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  lastSampleAt = lastPublishAt = millis();
}

void loop() {
  connectWifi();    // 공유기가 재시작돼도 다시 붙는다
  connectMqtt();
  mqtt.loop();

  uint32_t now = millis();
  if (now - lastSampleAt >= SAMPLE_INTERVAL_MS) {
    lastSampleAt = now;
    sample();
  }
  if (now - lastPublishAt >= PUBLISH_INTERVAL_MS) {
    lastPublishAt = now;
    publishAverage();
    tempSum = 0;
    tempCount = 0;
  }
}
