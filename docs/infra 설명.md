# `infra/` 설명

작성일: 2026-10-03 · 기준 커밋: `59930c3`

`infra/`는 **개발 PC에서 서버가 의존하는 두 가지 프로그램(PostgreSQL, MQTT 브로커)을 Docker로 띄우는 설정**을 모아 둔 폴더입니다. Rails 앱과 ESP32 펌웨어는 여기서 띄운 두 서비스에 접속합니다. 운영(production) 배포용 설정이 아니라 개발용입니다.

## 1. 폴더 구성

```text
infra/
├─ docker-compose.yml        기본 구성: PostgreSQL 17 + Mosquitto 2 (익명 접속 허용)
├─ docker-compose.auth.yml   선택: Mosquitto에 인증·접근 제어를 덧씌우는 override
└─ mosquitto/
   ├─ mosquitto.conf         기본 브로커 설정 (개발 전용, 익명 허용)
   ├─ mosquitto.auth.conf    인증을 켠 브로커 설정 (선택)
   ├─ acl                    계정별 토픽 권한 목록 (선택)
   └─ passwd                 비밀번호 파일 (직접 만들어야 함, Git 제외)
```

`passwd`는 저장소에 없습니다. 인증을 켤 때만 직접 만듭니다(`.gitignore`에 등록됨).

## 2. 웹 개발자를 위한 개념 정리

| 용어 | 뜻 | 이 프로젝트에서 |
|---|---|---|
| Docker 컨테이너 | 프로그램을 격리된 환경에서 실행하는 가벼운 가상 환경 | PC에 PostgreSQL이나 Mosquitto를 직접 설치하지 않고 컨테이너로 실행 |
| Docker Compose | 여러 컨테이너를 YAML 파일 하나로 정의하고 한 번에 켜는 도구 | `docker-compose.yml` |
| 이미지 | 컨테이너를 만드는 설치 패키지 | `postgres:17`, `eclipse-mosquitto:2` |
| 볼륨(volume) | 컨테이너가 지워져도 남는 데이터 저장 공간 | DB 데이터, 브로커 저장 데이터 |
| 바인드 마운트 | PC의 파일을 컨테이너 안에 그대로 연결 | `mosquitto.conf`를 컨테이너에 읽기 전용으로 연결 |
| MQTT 브로커 | 발행·구독 메시지를 중계하는 서버 | Mosquitto. ESP32가 보내고 Rails 구독자가 받음 |

## 3. `docker-compose.yml` — 기본 구성

서비스 두 개를 정의합니다.

### 3.1 `postgres`

| 항목 | 값 | 설명 |
|---|---|---|
| 이미지 | `postgres:17` | PostgreSQL 17 |
| 재시작 | `unless-stopped` | 직접 멈추지 않는 한 PC나 Docker가 다시 켜질 때 같이 켜짐 |
| 계정 | `POSTGRES_USER` (기본 `smartfarm`) | `.env`에서 읽음 |
| 비밀번호 | `POSTGRES_PASSWORD` (필수) | 값이 없으면 `set POSTGRES_PASSWORD in .env` 오류로 실행 거부 |
| DB 이름 | `POSTGRES_DB` (기본 `smartfarm_development`) | |
| 포트 | `127.0.0.1:${POSTGRES_PORT:-5432}:5432` | PC의 `POSTGRES_PORT`(기본 5432) → 컨테이너 5432 |
| 볼륨 | `pgdata` → `/var/lib/postgresql/data` | DB 파일 보관 |

- **`127.0.0.1:` 접두사**: 같은 PC에서만 접속할 수 있고, 공유기 내부망의 다른 기기에서는 접속할 수 없습니다. DB는 Rails만 쓰면 되므로 노출하지 않는 설정입니다.
- **포트를 환경변수로 뺀 이유**: PC에 PostgreSQL이 이미 설치돼 5432가 사용 중이면 충돌합니다. `.env`의 `POSTGRES_PORT`만 5433 등으로 바꾸면 되고, Rails의 `server/config/database.yml`도 같은 변수를 읽어서 함께 따라갑니다.

### 3.2 `mosquitto`

| 항목 | 값 | 설명 |
|---|---|---|
| 이미지 | `eclipse-mosquitto:2` | Mosquitto 2 (확인한 버전: 2.1.2) |
| 포트 | `${MQTT_PORT:-1883}:1883` | 앞에 `127.0.0.1`이 없어서 **내부망의 다른 기기(ESP32)도 접속 가능** |
| 설정 | `./mosquitto/mosquitto.conf` → 컨테이너 안 설정 위치 (읽기 전용) | |
| 볼륨 | `mosquitto_data` → `/mosquitto/data` | 브로커가 저장하는 메시지(retained 등) 보관 |

PostgreSQL은 `127.0.0.1`로 막고 Mosquitto는 열어 둔 것이 의도된 차이입니다. ESP32가 다른 기기라서 PC의 1883 포트로 들어와야 하기 때문입니다.

## 4. `mosquitto/mosquitto.conf` — 기본 브로커 설정

```text
listener 1883              # 1883 포트에서 접속을 받음 (MQTT 기본 포트)
allow_anonymous true       # 계정 없이 접속 허용
persistence true           # 메시지·상태를 파일에 저장
persistence_location /mosquitto/data/
```

- **`allow_anonymous true`는 개발 전용입니다.** 같은 내부망에 있는 누구나 어떤 토픽에도 읽고 쓸 수 있습니다. 파일 주석도 "실제 장치를 연결하기 전에 인증과 ACL로 바꾸라"고 안내합니다.
- **`persistence`**: 브로커가 재시작돼도 retained 메시지가 유지됩니다. 펌웨어가 `status` 토픽에 retained로 `online`/`offline`을 남기는 것과 관련이 있습니다.

## 5. 인증을 켜는 선택 구성

기본 설정은 그대로 두고, **override 파일로 인증 설정을 덧씌우는 방식**입니다. 켜지 않으면 기존 개발 흐름은 바뀌지 않습니다.

### 5.1 `docker-compose.auth.yml`

`mosquitto` 서비스의 볼륨만 바꿉니다. 같은 컨테이너 경로(`/mosquitto/config/mosquitto.conf`)에 기본 설정 대신 `mosquitto.auth.conf`를 연결하고, `passwd`, `acl`을 추가로 연결합니다.

```bash
docker compose --env-file ../.env -f docker-compose.yml -f docker-compose.auth.yml up -d mosquitto
```

`-f`를 두 번 쓰면 뒤 파일이 앞 파일 위에 병합됩니다. 다시 익명으로 돌리려면 `-f docker-compose.auth.yml` 없이 `up -d mosquitto`를 실행합니다.

### 5.2 `mosquitto.auth.conf`

```text
listener 1883
allow_anonymous false                          # 익명 접속 거부
password_file /mosquitto/config/passwd         # 계정과 해시된 비밀번호
acl_file /mosquitto/config/acl                 # 계정별 토픽 권한
persistence true
persistence_location /mosquitto/data/
```

### 5.3 `acl` — 접근 제어 목록

```text
user rails
topic read smartfarm/+/telemetry
topic read smartfarm/+/status

pattern write smartfarm/%u/#
```

| 규칙 | 의미 |
|---|---|
| `user rails` + `topic read ...` | `rails` 계정(Rails 구독자)은 모든 장치의 telemetry와 status를 **읽기만** 가능 |
| `pattern write smartfarm/%u/#` | 모든 계정에 적용. `%u`는 로그인한 사용자 이름이므로, 사용자 이름이 `balcony-01`이면 `smartfarm/balcony-01/#`에만 **쓰기** 가능 |

- 토픽의 `+`는 한 단계 와일드카드, `#`은 그 아래 전체입니다.
- 이 설계에서는 **장치 계정의 사용자 이름이 장치 ID(`DEVICE_ID`)와 같아야** 합니다. 펌웨어 `secrets.h`의 `MQTT_USER`를 `DEVICE_ID`와 같게 넣는 이유입니다.
- ACL이 막은 발행은 발행자에게 오류 없이 조용히 버려집니다. 발행이 안 먹히면 사용자 이름과 토픽의 장치 ID가 같은지부터 확인하세요.

### 5.4 `passwd` 만들기

`passwd`는 저장소에 올리지 않으므로 직접 만듭니다. 계정마다 한 번씩 실행하고 첫 계정에만 `-c`를 붙입니다.

```bash
cd infra
docker run --rm -v "$PWD/mosquitto:/work" eclipse-mosquitto:2 sh -c \
  "mosquitto_passwd -c -b /work/passwd rails '<railsPW>' && mosquitto_passwd -b /work/passwd balcony-01 '<장치PW>' && chmod 0644 /work/passwd"
```

- 비밀번호는 해시되어 저장됩니다(파일에 평문이 없음).
- 파일 권한을 `0700`으로 만들면 브로커가 `Unable to open pwfile`로 시작하지 못합니다. 브로커가 `root`가 아닌 `mosquitto` 사용자로 돌기 때문입니다.
- `0644`로 두면 Mosquitto 2.1.2가 "world readable, 소유자가 mosquitto가 아님, 향후 버전은 거부할 수 있음" 경고를 냅니다. Windows 바인드 마운트에서는 소유자를 바꿀 수 없어서 지금은 경고만 감수합니다.

## 6. 자주 쓰는 명령

모두 `infra/` 폴더에서 실행합니다. (PostgreSQL 포트 충돌 등으로 `.env`를 읽어야 해서 `--env-file ../.env`가 필요합니다.)

| 하고 싶은 일 | 명령 |
|---|---|
| 처음 켜기 / 다시 켜기 | `docker compose --env-file ../.env up -d` |
| 상태 보기 | `docker compose --env-file ../.env ps` |
| 로그 보기 | `docker compose --env-file ../.env logs -f mosquitto` |
| 멈추기 (데이터 유지) | `docker compose --env-file ../.env stop` |
| 내리기 (컨테이너 삭제, 데이터 유지) | `docker compose --env-file ../.env down` |
| 데이터까지 삭제 (주의) | `docker compose --env-file ../.env down -v` — DB와 브로커 데이터가 지워짐 |

## 7. 다른 폴더와의 연결

| 연결 대상 | 어떻게 |
|---|---|
| 루트 `.env` / `.env.example` | `POSTGRES_*`, `MQTT_PORT`, (인증 시) `MQTT_USERNAME`/`MQTT_PASSWORD`를 compose와 서버가 함께 읽음 |
| `server/config/database.yml` | `POSTGRES_PORT`, `DATABASE_HOST` 환경변수로 이 PostgreSQL에 접속 |
| `server/lib/smart_farm/mqtt_subscriber.rb` | `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`로 이 브로커에 접속해 구독 |
| `server/bin/fake_sensor` | 같은 환경변수로 접속해 가짜 센서 메시지를 발행 |
| `firmware/src/secrets.h` | `MQTT_HOST`(이 PC의 내부망 IP), `MQTT_PORT`, `MQTT_USER`, `MQTT_PASSWORD` |
| `docs/testing.md` | 단계별 시험 절차와 "Mosquitto 인증 켜기" |

## 8. 알아둘 점

- 데이터는 Docker 볼륨(`infra_pgdata`, `infra_mosquitto_data`)에 보관됩니다. `down`만 하면 남고 `down -v`를 하면 지워집니다.
- `restart: unless-stopped`라서 Docker Desktop을 다시 켜면 두 컨테이너가 자동으로 올라옵니다.
- Windows(WSL)에서는 Docker Desktop의 WSL integration이 꺼져 있으면 Ubuntu에서 `docker` 명령이 없다고 나옵니다. 이 경우 PowerShell에서 실행해도 됩니다(`docs/testing.md`의 "문제가 생기면" 참고).
- 포트가 이미 사용 중이면: PostgreSQL은 `POSTGRES_PORT`, Mosquitto는 `MQTT_PORT`를 `.env`에서 바꿉니다. `MQTT_PORT`를 바꾸면 펌웨어 `secrets.h`의 `MQTT_PORT`도 같이 바꿔야 합니다.
- 인증 설정은 별도 브로커로 시험했지만, 실물 ESP32가 인증 접속하는 것은 확인하지 못했습니다.
- 운영 배포용 구성(TLS, 백업, 모니터링 등)은 이 폴더에 없습니다.
