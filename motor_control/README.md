# motor_control

`motor_control/`는 `final/`과 분리된 독립 패키지입니다.  
iPhone 17의 수동 버튼 UI에서 `LEFT`, `RIGHT` 명령을 USB MIDI로 전송하고, Arduino Leonardo가 MG996R 서보를 한 번에 `15도`씩 움직이도록 구성합니다.

## 구조

- `ios/`
  - 수동 제어 전용 iPhone 앱
- `arduino/leonardo_usb_midi_mg996r_manual/`
  - Leonardo USB MIDI 수신 + MG996R 고정 15도 step 제어 스케치

## 동작 흐름

1. iPhone 앱이 CoreMIDI 목적지를 검색합니다.
2. 이름에 `Leonardo`가 포함된 USB MIDI 장치를 우선 연결합니다.
3. 사용자가 `Left` 또는 `Right` 버튼을 탭합니다.
4. 앱은 각도 한계를 확인한 뒤 `CC 20` 명령을 1회 전송합니다.
5. Leonardo는 명령을 수신하면 서보를 정확히 `15도` 이동시키고 현재 위치를 유지합니다.

## MIDI 프로토콜

- 채널 `1`
- `CC 20`
  - `0` = `STOP`
  - `1` = `LEFT`
  - `2` = `RIGHT`

이 패키지의 수동 제어 앱은 `CC 21`을 사용하지 않습니다.

## iPhone 앱 빌드

1. Xcode에서 `motor_control/ios/MotorControlApp.xcodeproj`를 엽니다.
2. 실제 iPhone 17을 실행 대상으로 선택합니다.
3. 필요하면 Signing Team을 확인합니다.
4. 빌드 후 앱을 실행합니다.

앱 화면에는 아래 항목이 표시됩니다.

- MIDI 연결 상태
- 현재 각도
- `Left` 버튼
- `Right` 버튼

기본 설정:

- 시작 각도 `90`
- 표준 서보 각도 `0~180` 기준 사용
- 버튼 1회당 이동 `15도`

## Arduino 업로드

1. Arduino IDE에서 `motor_control/arduino/leonardo_usb_midi_mg996r_manual/leonardo_usb_midi_mg996r_manual.ino`를 엽니다.
2. 보드를 `Arduino Leonardo`로 선택합니다.
3. 필요하면 `MIDIUSB` 라이브러리를 설치합니다.
4. 업로드합니다.

## MG996R 배선

- servo signal -> Leonardo `D9`
- servo GND -> 외부 안정화 `5V-6V` 전원 GND
- Leonardo GND -> 같은 외부 전원 GND
- servo V+ -> 외부 안정화 `5V-6V` 전원

`MG996R`는 Leonardo 5V 핀에서 직접 전원 공급하지 마세요.

## 권장 테스트 순서

1. Leonardo 스케치를 먼저 업로드합니다.
2. 서보 부하를 연결하기 전 LED 반응과 MIDI 수신 여부를 먼저 확인합니다.
3. 외부 전원까지 포함해 서보를 연결합니다.
4. iPhone 앱에서 Leonardo가 MIDI 장치로 보이는지 확인합니다.
5. `Left` 1회, `Right` 1회 순서로 테스트합니다.

## Mac에서 테스트 가능한 범위

- 가능:
  - Leonardo가 Mac에서 USB MIDI 장치로 보이는지 확인
  - Mac의 MIDI 툴이나 간단한 송신 프로그램으로 `CC 20` 값을 보내 동작 확인
  - 앱 소스 빌드 확인
- 제한:
  - 현재 프로젝트는 iPhone 앱이므로 `iPhone -> USB MIDI -> Leonardo` 전체 경로를 Mac만으로 완전히 대체할 수는 없음
  - 실제 iPhone USB 연결 인식은 실기기에서 최종 확인 필요

## 향후 확장 추천

- `Center 90°` 버튼
- `Reconnect` 버튼
- 길게 누르기 반복 이동
- 시작/최소/최대 각도 보정 UI
