# 목표와 실행 계획 (요약)

전체 문서: https://claude.ai/code/artifact/a09ceb5a-14a4-40f7-981b-3b980d88f3ee

- 결정: 서버 스택은 Rails 8 (2026-10-03 확정)
- 11월 말: 상추 첫 수확 + 수온 센서 → 화면 → 알림 한 줄 완성
- 12월 중순: 온습도·조도·수위 센서, 장치 오프라인 감지, pH·EC 수동 입력
- 이후(선택): 명령·ACK, Jev 판단 보조, 물류 시뮬레이터
- 보류: 220V 직접 제어, 자동 pH·EC 주입

## 센서 데이터 수신 (구현됨)

- 토픽: `smartfarm/<deviceId>/telemetry`, 페이로드는 `schemaVersion: 1` JSON (`deviceId`, `sequence`, `measuredAt`, `airTemperatureC`, `humidityPct`, `waterTemperatureC`, `illuminanceLux`, `waterLow`)
- `server/bin/mqtt_subscriber`: 구독 후 Solid Queue에 넘기기만 함 (끊기면 5초 후 재연결)
- `IngestSensorReadingJob` → `SensorReadingIngestor`: 검증, 저장, 중복 무시
- 가짜 메시지 발행: `server/bin/fake_sensor [deviceId]`

## 화면과 알림 (구현됨)

- `/` 대시보드: 장치별 현재 수온·기온·습도·조도·수위, 온라인 여부(5분 이상 수신 없으면 오프라인), 최근 24시간 수온 그래프
- 새 측정값이 저장되면 Turbo Streams로 화면이 새로고침 없이 갱신됨
- 수온 알림: 24℃ 이상 또는 15℃ 이하이면 알림 생성, 0.5℃ 여유를 두고 해제 (같은 종류의 열린 알림은 장치당 1개)
