# ESP32 펌웨어

수온(DS18B20) 1분 평균을 MQTT로 서버에 보냅니다.

## 배선 (3.3V 저전압만 사용)

| DS18B20 | ESP32 |
|---|---|
| 빨강 (VCC) | 3V3 |
| 검정 (GND) | GND |
| 노랑 (DATA) | GPIO4, 그리고 DATA와 3V3 사이에 4.7kΩ 저항 |

USB를 뽑은 상태에서 배선을 바꾸세요.

## 빌드와 업로드 (PlatformIO)

```bash
cp src/secrets.h.example src/secrets.h    # Wi-Fi, 브로커 IP 입력 (Git에 올리지 않음)
pio run -e esp32dev_fake -t upload         # 센서 없이 가짜 수온으로 서버 연결 시험
pio run -e esp32dev -t upload              # 실제 DS18B20 사용
pio device monitor
```

서버의 `bin/mqtt_subscriber`가 켜져 있으면 1분 뒤 대시보드에 장치가 나타납니다.
`status` 토픽은 Last Will로 `online/offline`을 알립니다 (서버 구독은 다음 단계).
