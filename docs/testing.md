# 테스트 방법

지금까지 만든 것(서버, 화면, 알림, ESP32 펌웨어)을 단계별로 시험합니다.
앞 단계가 되어야 다음 단계로 넘어가세요. 1~4단계는 센서와 ESP32 없이 PC만으로 할 수 있습니다.

## 준비물

- Docker (Docker Desktop 등), Ruby 3.3 이상, Git
- Windows는 WSL2(Ubuntu) 안에서 진행하는 것을 권장합니다.

```bash
git clone https://github.com/smg10djr/smgSmartFarm.git && cd smgSmartFarm
git checkout main        # PR 병합 전이라면 claude/project-thread-o1lire

cp .env.example .env     # POSTGRES_PASSWORD를 아무 값으로 바꿉니다
cd infra && docker compose --env-file ../.env up -d && cd ..
docker compose -f infra/docker-compose.yml ps    # postgres, mosquitto가 running인지 확인
```

터미널을 열 때마다 서버 폴더에서 환경변수를 읽어야 합니다.

```bash
cd server
set -a; . ../.env; set +a
bundle install
bin/rails db:prepare
```

## 1단계: 자동 테스트

```bash
bin/rails test
```

기대 결과: `22 runs, ... 0 failures, 0 errors`. 여기서 실패하면 환경 문제이므로 다음 단계로 가지 마세요.
(`could not connect to server`가 나오면 postgres 컨테이너가 떠 있는지, `.env`를 읽었는지 확인합니다.)

## 2단계: 가짜 센서로 화면까지 한 번에 확인

터미널 3개를 열고 모두 `server` 폴더에서 `set -a; . ../.env; set +a`를 먼저 실행합니다.

| 터미널 | 명령 | 역할 |
|---|---|---|
| A | `bin/rails server` | 웹 화면 (http://localhost:3000) |
| B | `bin/mqtt_subscriber` | MQTT 구독 후 저장 |
| C | `bin/fake_sensor` | 가짜 센서 메시지 1건 발행 |

1. 브라우저에서 http://localhost:3000 을 열어 둡니다. "수신된 장치가 없습니다"가 보입니다.
2. 터미널 C에서 `bin/fake_sensor`를 실행합니다.
3. **새로고침 없이** 화면에 `balcony-01` 카드가 나타나고 수온 19.3℃가 보이면 성공입니다.
4. 같은 명령을 다시 실행하면 값은 같고 시각만 바뀐 새 기록이 쌓입니다.
   (같은 측정 시각의 중복 메시지는 저장되지 않습니다.)
5. 그래프는 기록이 2건 이상, 시간 간격이 있어야 선이 그려집니다. 몇 분 간격으로 `bin/fake_sensor`를 반복해 보세요.

## 3단계: 알림 확인

수온 알림 (24℃ 이상 또는 15℃ 이하):

```bash
docker compose -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub \
  -t smartfarm/balcony-01/telemetry \
  -m '{"schemaVersion":1,"deviceId":"balcony-01","measuredAt":"2026-10-03T12:00:00Z","waterTemperatureC":26.5}'
```

- 화면 "알림"에 `수온 26.5℃ (기준 24.0℃ 이상)`이 빨간색 "진행 중"으로 뜹니다.
- `measuredAt`을 새 시각으로 바꾸고 `waterTemperatureC`를 `23.0`으로 보내면 "해제됨"으로 바뀝니다.
  (23.8℃처럼 기준 바로 아래는 0.5℃ 여유 때문에 해제되지 않습니다.)
- 같은 `measuredAt`으로 다시 보내면 무시됩니다 (터미널 B 로그에 duplicate).
- `waterTemperatureC`를 250으로 보내면 거절됩니다 (로그에 rejected, 화면 변화 없음).

장치 오프라인 알림 (ESP32의 Last Will과 같은 메시지):

```bash
docker compose -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub -r -t smartfarm/balcony-01/status -m offline
docker compose -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub -r -t smartfarm/balcony-01/status -m online
```

`offline`이면 카드가 "오프라인"으로 바뀌고 "장치가 오프라인입니다" 알림이 열리며, `online`이면 알림이 해제됩니다.
수신이 5분 넘게 없어도 카드는 "오프라인"으로 표시됩니다 (화면을 새로고침할 때 반영).

## 4단계: pH·EC 수동 입력

화면의 "pH·EC 수동 입력"에 `pH 6.1`, `EC 1.3`을 넣고 "기록"을 누르면 장치 카드에 `수동 측정 ... pH 6.1 · EC 1.3 mS/cm`이 보입니다.
pH 15처럼 범위를 벗어난 값이나 둘 다 비운 입력은 빨간 오류 문구가 나옵니다.

## 5단계: ESP32 (센서 없이)

ESP32와 USB 케이블이 있을 때 진행합니다. 배선은 필요 없습니다.

1. PC의 내부망 IP를 확인합니다 (`ipconfig` 또는 `ip addr`). Mosquitto가 이 PC에서 돌고 있어야 하고, PC 방화벽에서 1883 포트 접속을 허용해야 합니다.
2. `firmware/src/secrets.h.example`을 `secrets.h`로 복사하고 Wi-Fi 이름·비밀번호·`MQTT_HOST`(위 IP)를 채웁니다.
3. PlatformIO를 설치합니다 (`pip install platformio` 또는 VS Code 확장).
4. `cd firmware && pio run -e esp32dev_fake -t upload && pio device monitor`
5. 시리얼 모니터에 `Wi-Fi 연결됨`, `MQTT 연결됨`, 1분 뒤 `발행 성공`이 나오고, 화면의 수온이 17~21℃ 사이에서 갱신되면 성공입니다.
6. ESP32의 전원을 뽑으면 잠시 뒤 오프라인 알림이 뜨고, 다시 꽂으면 해제됩니다.

참고: 펌웨어는 이 문서를 쓴 환경에서 컴파일해 보지 못했습니다. 빌드 오류가 나면 메시지를 알려 주세요.

## 6단계: 실제 수온 센서

배선은 `firmware/README.md`를 따릅니다 (3.3V 저전압만 사용, USB를 뽑은 상태에서 배선).
`pio run -e esp32dev -t upload`로 올린 뒤, 센서를 손으로 쥐거나 따뜻한 물에 담가 값이 변하는지 화면에서 확인합니다.
시리얼에 `수온 센서 값을 읽지 못했습니다`가 나오면 4.7kΩ 저항과 배선을 먼저 의심하세요.

## 문제가 생기면

| 증상 | 확인 |
|---|---|
| 화면에 장치가 안 나타남 | 터미널 B(`mqtt_subscriber`)가 켜져 있는지, 로그에 `subscribed`가 있는지 |
| `[ingest] rejected` 로그 | JSON 형식(`schemaVersion: 1`, `deviceId`, ISO 8601 `measuredAt`)과 값 범위 |
| 저장은 되는데 화면이 안 바뀜 | 터미널 A(`rails server`)와 같은 DB를 보는지, 브라우저 새로고침 후 재확인 |
| `connection refused` (1883) | `docker compose ps`에서 mosquitto가 running인지 |
