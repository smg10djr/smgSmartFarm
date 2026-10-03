# 테스트 방법

지금까지 만든 것(서버, 화면, 알림, ESP32 펌웨어)을 단계별로 시험합니다.
앞 단계가 되어야 다음 단계로 넘어가세요. 1~4단계는 센서와 ESP32 없이 PC만으로 할 수 있습니다.

## 준비물 (처음 한 번만)

이 프로젝트는 PC에서 실행해야 시험할 수 있습니다. 필요한 것은 네 가지입니다.

| 필요한 것 | 용도 |
|---|---|
| 소스 코드 | 이 저장소 |
| Docker | PostgreSQL과 MQTT 브로커(Mosquitto)를 한 줄로 실행 |
| Ruby 3.3 이상 | Rails 서버 실행 |
| Git (또는 ZIP 다운로드) | 소스 받기 |

### Windows (WSL2의 Ubuntu 안에서 진행)

1. PowerShell을 관리자 권한으로 열어 `wsl --install`을 실행하고 PC를 재시작합니다. 재시작 후 Ubuntu가 열리면 사용자 이름과 비밀번호를 정합니다.
2. [Docker Desktop](https://www.docker.com/products/docker-desktop/)을 설치하고, Settings → Resources → WSL integration에서 Ubuntu를 켭니다.
3. Ubuntu 터미널에서 필요한 패키지와 Ruby를 설치합니다 (Ruby 컴파일에 몇 분 걸립니다).

```bash
sudo apt update && sudo apt install -y git curl build-essential libpq-dev libyaml-dev libssl-dev zlib1g-dev
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && source ~/.bashrc
mise use -g ruby@3.3
ruby -v          # 3.3.x가 나와야 합니다
docker --version # 나오지 않으면 2번의 WSL integration을 확인합니다
```

### Mac

```bash
brew install git mise libpq
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && source ~/.zshrc
mise use -g ruby@3.3
```

그리고 Docker Desktop을 설치합니다.

### 소스 받기

터미널(Windows는 Ubuntu)에서 실행합니다. 지금은 모든 작업이 `claude/project-thread-o1lire` 브랜치(저장소의 기본 브랜치)에 있습니다.
PR을 병합한 뒤에는 `main`을 받으면 됩니다. Git이 어렵다면 저장소 페이지의 Code → Download ZIP으로 받아 압축을 풀어도 됩니다.

```bash
git clone https://github.com/smg10djr/smgSmartFarm.git
cd smgSmartFarm
git branch --show-current   # claude/project-thread-o1lire 이어야 합니다
```

### 데이터베이스와 브로커 켜기

```bash
cp .env.example .env        # 파일을 열어 POSTGRES_PASSWORD를 아무 값으로 바꿉니다 (예: farm1234)
                            # PC에 PostgreSQL이 이미 설치돼 있으면 POSTGRES_PORT=5433 처럼 바꿉니다
cd infra
docker compose --env-file ../.env up -d
docker compose --env-file ../.env ps    # postgres와 mosquitto가 running(Up)이어야 합니다
cd ..
```

Windows에서 Ubuntu 안에 `docker` 명령이 없다면 Docker Desktop의 WSL integration이 꺼진 것입니다. Settings → Resources → WSL integration에서 Ubuntu를 켜거나, 이 단계만 PowerShell에서 실행해도 됩니다.
`ports are not available ... 5432`가 나오면 PC에 PostgreSQL이 이미 있는 것이므로 `.env`의 `POSTGRES_PORT`를 5433으로 바꾸고 다시 실행하세요. (서버는 같은 `.env`의 값을 읽어 자동으로 따라갑니다.)

### 서버 준비

터미널을 새로 열 때마다 `server` 폴더에서 첫 줄(환경변수 읽기)을 먼저 실행합니다.

```bash
cd server
set -a; . ../.env; set +a
bundle install              # 처음 한 번 (몇 분 걸림)
bin/rails db:prepare        # 처음 한 번
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
3. **새로고침 없이** 화면에 `balcony-01` 카드와 pH·EC 입력란이 나타나고 수온 19.3℃가 보이면 성공입니다.
   터미널 B에는 `[ingest] stored reading 1`이 찍힙니다. (Rails를 WSL에서 실행할 때 Windows 브라우저에서 접속이 안 되면 `bin/rails server -b 0.0.0.0`으로 실행하세요.)
4. 같은 명령을 다시 실행하면 값은 같고 시각만 바뀐 새 기록이 쌓입니다.
   (같은 측정 시각의 중복 메시지는 저장되지 않습니다.)
5. 그래프는 **최근 24시간** 기록이 2건 이상이어야 선이 그려집니다. 몇 분 간격으로 `bin/fake_sensor`를 반복해 보세요. 미래 시각의 `measuredAt`은 그래프에 나오지 않습니다.

## 3단계: 알림 확인

수온 알림 (24℃ 이상 또는 15℃ 이하). `measuredAt`은 **현재 시각**을 써야 하므로 `date` 명령으로 만듭니다.

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
docker compose --env-file ../.env -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub \
  -t smartfarm/balcony-01/telemetry \
  -m "{\"schemaVersion\":1,\"deviceId\":\"balcony-01\",\"measuredAt\":\"$NOW\",\"waterTemperatureC\":26.5}"
```

- 화면 "알림"에 `수온 26.5℃ (기준 24.0℃ 이상)`이 빨간색 "진행 중"으로 뜹니다.
- 1초 뒤 `NOW`를 다시 만들어(`NOW=$(date -u ...)`) `waterTemperatureC`를 `23.0`으로 보내면 "해제됨"으로 바뀝니다.
  (23.8℃처럼 기준 바로 아래는 0.5℃ 여유 때문에 해제되지 않습니다.)
- **같은 `NOW`로** 같은 메시지를 다시 보내면 무시됩니다 (터미널 B에 `[ingest] duplicate ignored`).
- `waterTemperatureC`를 250으로 보내면 거절됩니다 (터미널 B에 `[ingest] rejected: 수온 값이 -10..60 범위를 벗어났습니다`, 화면 변화 없음).

장치 오프라인 알림 (ESP32의 Last Will과 같은 메시지):

```bash
docker compose --env-file ../.env -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub -r -t smartfarm/balcony-01/status -m offline
docker compose --env-file ../.env -f ../infra/docker-compose.yml exec mosquitto mosquitto_pub -r -t smartfarm/balcony-01/status -m online
```

`offline`이면 카드가 "오프라인"으로 바뀌고 "장치가 오프라인입니다" 알림이 열리며, `online`이면 알림이 해제됩니다.
수신이 5분 넘게 없어도 카드는 "오프라인"으로 표시됩니다 (화면을 새로고침할 때 반영).

## 4단계: pH·EC 수동 입력

화면의 "pH·EC 수동 입력"에 `pH 6.1`, `EC 1.3`을 넣고 "기록"을 누르면 장치 카드에 `수동 측정 ... pH 6.1 · EC 1.3 mS/cm`이 보입니다.
pH 15처럼 범위를 벗어난 값은 브라우저가 먼저 막고, 둘 다 비운 입력은 `pH 또는 EC 중 하나는 입력해야 합니다`라는 빨간 문구가 나옵니다.

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
| `ports are not available` (5432) | PC의 기존 PostgreSQL과 충돌입니다. `.env`의 `POSTGRES_PORT`를 5433으로 바꿉니다 |
| `connection refused` (1883) | `docker compose --env-file ../.env -f ../infra/docker-compose.yml ps`에서 mosquitto가 running인지 |
