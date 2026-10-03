# SmgSmartFarm

상추 6포기 DWC 수경재배를 센서로 모니터링하는 스마트팜 학습 프로젝트입니다.

```text
ESP32 → Mosquitto(MQTT) → Ruby Subscriber → Solid Queue → Rails 8 → PostgreSQL → Hotwire
```

## 구성

| 폴더 | 내용 |
|---|---|
| `server/` | Rails 8 앱 (PostgreSQL, Solid Queue, Solid Cable, Hotwire) |
| `infra/` | 개발용 Docker Compose (Mosquitto, PostgreSQL) |
| `firmware/` | ESP32 프로그램 (PlatformIO, 수온 센서) |
| `docs/` | 계획, MQTT 토픽 명세, 결정 기록 |
| `data/` | 재배 일지 CSV |

## 개발 환경 실행

```bash
cp .env.example .env            # POSTGRES_PASSWORD 수정
cd infra && docker compose --env-file ../.env up -d
cd ../server
set -a; . ../.env; set +a
bin/rails db:prepare
bin/rails server
```

Wi-Fi·MQTT 비밀번호와 `.env`, `secrets.h`는 Git에 올리지 않습니다.

## 계획

단계별 목표와 일정은 `docs/plan.md`를 봅니다. 첫 목표는
`수온 센서 → MQTT → Rails → DB → 실시간 화면 → 수온 이상 알림` 한 줄을 완성하는 것입니다.
