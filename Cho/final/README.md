# final

`final/`은 iPhone 카메라로 선수를 선택하고, USB MIDI로 Arduino Leonardo를 제어해 MG996R pan 서보를 움직이는 독립 실행 묶음입니다.

## 구조

- `ios/`
  - iPhone 실시간 검출 + 선수 선택 + deadzone 제어 + CoreMIDI 전송 앱
- `arduino/leonardo_usb_midi_mg996r.ino`
  - Leonardo용 USB MIDI 수신 + MG996R step-and-hold 스케치
- `tools/export_yolo_executorch.py`
  - `yolo26n.pt`를 iOS 앱 번들용 `detector.pte`로 export

## 동작 흐름

1. iPhone 카메라 프레임을 받습니다.
2. `yolo26n`으로 `person`만 검출합니다.
3. 사용자가 선수 박스를 탭하면 그 트랙을 선택합니다.
4. 선택된 선수의 중심 x 좌표를 deadzone으로 판정합니다.
5. deadzone 밖으로 3프레임 연속 나가면 `LEFT` 또는 `RIGHT`를 USB MIDI로 보냅니다.
6. Leonardo는 `CC 21`로 받은 strength와 `CC 20` 방향값으로 MG996R를 한 스텝만 이동시키고 현재 위치를 유지합니다.
7. 선택 선수가 6프레임 연속 prediction-only 또는 missing이면 앱이 `STOP`을 1회 보내고 선택을 해제합니다.

## 하드웨어 프로토콜

- USB MIDI channel `1`
- `CC 20`
  - `0` = `STOP`
  - `1` = `LEFT`
  - `2` = `RIGHT`
- `CC 21`
  - `0...127` = 스텝 강도
- 이동 명령은 항상 `CC 21` 다음 `CC 20` 순서로 전송합니다.

## MG996R 배선

- servo signal -> Leonardo `D9`
- servo GND -> 외부 안정화 `5V-6V` 전원 GND
- Leonardo GND -> 같은 외부 전원 GND
- servo V+ -> 외부 안정화 `5V-6V` 전원

`MG996R`는 Leonardo 5V 핀으로 직접 구동하지 마세요.

## 기본 제어값

- `deadzoneWidthRatio = 0.22`
- `consecutiveFramesToCommit = 3`
- `sendInterval = 0.15s`
- `stepStrength = 24`
- `lostTargetStopFrames = 6`
- `invertDirection = false`

Leonardo 기본 서보 상수:

- `startAngle = 90`
- `minAngle = 45`
- `maxAngle = 135`
- `minStepDegrees = 1`
- `maxStepDegrees = 5`

## 모델 export

저장소 루트에서 실행:

```bash
.venv/bin/python final/tools/export_yolo_executorch.py
```

기본값:

- 입력 weights: `./yolo26n.pt`
- 출력 bundle dir: `./final/ios/RealtimeDetectionMVP/build`
- 출력 파일명: `detector.pte`

## iPhone 앱 실행

1. `final/tools/export_yolo_executorch.py`로 `detector.pte`를 준비합니다.
2. Xcode에서 `final/ios/RealtimeDetectionMVP.xcodeproj`를 엽니다.
3. iPhone을 선택하고 빌드/실행합니다.
4. Leonardo를 USB MIDI 장치로 연결합니다.
5. 화면에서 선수 박스를 탭해 목표를 고정합니다.

오버레이 표시:

- 전체 person track
- 선택된 선수 강조
- 세로 deadzone band
- MIDI 연결 상태
- 최근 전송 명령

## Arduino 업로드

1. Arduino IDE에서 `final/arduino/leonardo_usb_midi_mg996r.ino`를 엽니다.
2. 보드를 `Arduino Leonardo`로 선택합니다.
3. 필요하면 `MIDIUSB` 라이브러리를 설치합니다.
4. 업로드 후 iPhone에 USB MIDI 장치로 연결합니다.

## 보정 포인트

- 팬 방향이 반대로 움직이면:
  - iOS: `TrackingTuning.invertDirection`
  - Arduino: `kInvertDirection`
- 기구가 끝까지 닿으면:
  - `kMinAngle`, `kMaxAngle`를 줄입니다.
- 움직임이 너무 크면:
  - `stepStrength` 또는 `kMaxStepDegrees`를 낮춥니다.
- 움직임이 너무 느리면:
  - `stepStrength`를 높이거나 `sendInterval`을 줄입니다.
