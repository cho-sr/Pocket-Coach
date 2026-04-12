# Poket Coach (KIM) 통합 README

이 디렉터리는 iOS 비전 추적과 Arduino 서보 제어를 USB MIDI로 연결하는 Poket Coach 구현 코드를 포함합니다.

## 1. 디렉터리 구조

- `PoketiOS/`
  - `CameraTrackerManager.swift`: 카메라 입력, YOLO 기반 person 검출, 하이브리드 추적(Fast/Slow path), 7구역 Delta 산출
  - `CoreMIDIManager.swift`: CoreMIDI CC 송신(중심값 64 + Delta), 200ms 스로틀링
  - `CameraPreviewLockOnIntegration.swift`: 프리뷰 렌더링, 터치 기반 Lock-on, 실시간 타겟 오버레이/Confidence 라벨
- `PoketArduino/`
  - `leonardo_usb_midi_mg996r.ino`: Leonardo USB MIDI CC 수신, Delta 복원, 누적 각도 제어, 안전각 클램프, 논블로킹 LED

## 2. 시스템 개요

- Vision: YOLO26n (CoreML)
- Re-ID: OSNet (CoreML)
- MCU: Arduino Leonardo
- Actuator: MG996R
- 통신: USB MIDI (CoreMIDI <-> MIDIUSB)

동작 흐름:
1. iOS 카메라 프레임을 모델 입력(640x640)으로 전처리
2. person 박스를 검출
3. Fast-path(IoU + 중심거리)로 타겟 유지
4. 실패 시 Slow-path(OSNet 코사인 유사도)로 재식별
5. 타겟 중심 x 좌표를 7구역으로 양자화해 Delta 산출
6. CC 값 = 64 + Delta 전송 (Delta=0은 전송 안 함)
7. Arduino에서 Delta 복원 후 `currentAngle += delta`, 안전 범위 클램프 후 서보 구동

## 3. iOS 동작 포인트

### 3.1 Touch-to-Track
- 사용자가 프리뷰를 탭하면 탭 좌표를 카메라 정규화 좌표로 변환한 뒤 640x640 기준 좌표로 스케일링합니다.
- 해당 좌표를 `lockOnTarget(at:)`에 전달해 최초 타겟을 고정합니다.

### 3.2 프리뷰/오버레이
- `AVCaptureVideoPreviewLayer`는 `.resizeAspectFill`로 화면 전체 표시합니다.
- `didUpdateTarget` 콜백에서 `rect640`을 화면 좌표로 역변환하여 빨간 박스를 갱신합니다.
- 라벨은 `Target (xx%)` 형식으로 선택 타겟의 confidence만 표시합니다(ID 미사용).

### 3.3 MIDI 송신 정책
- CC 범위는 0~127을 사용합니다.
- 중심값 64에 Delta를 더해 송신합니다.
- 모터 헌팅 방지를 위해 최소 200ms 스로틀링을 적용합니다.

## 4. Arduino 동작 포인트

- `MIDIUSB.read()`로 CC 메시지를 폴링합니다.
- 채널/CC 번호가 일치하면 `delta = ccValue - 64`로 복원합니다.
- `currentAngle += delta` 누적 후 안전각 범위로 클램프합니다.
- LED 상태 표시는 논블로킹(`millis` 경과시간 비교)으로 처리합니다.

## 5. 하드웨어 연결 주의 (중요)

MG996R은 전류 소모가 큽니다.

- Arduino 5V 핀에 직접 연결하지 마세요.
- 반드시 외부 5~6V 전원을 사용하세요.
- Arduino GND와 외부 전원 GND를 공통으로 연결(Common GND)하세요.
- USB 케이블은 회전 시 꼬임/장력 문제를 피하도록 슬랙(여유 길이)과 스트레인 릴리프를 확보하세요.

## 6. 시연 체크리스트

1. iOS 앱에서 카메라 권한 허용
2. 모델 파일(YOLO/OSNet) 로드 확인
3. USB로 iPhone(또는 iPad)-Leonardo 연결
4. 탭으로 타겟 Lock-on
5. 오버레이 박스/Confidence 라벨 추종 확인
6. 서보가 안전각 범위에서 좌우 제어되는지 확인

## 7. 현재 코드 상태 요약

- KIM 폴더 내 Swift/INO 파일 기준 컴파일/문법 오류 없음
- 시연 관점에서 블로킹 이슈 없이 동작 가능한 상태
- 다중 객체 글로벌 ID는 구현하지 않았으며, 단일 선택 타겟 기반 추적/표시 정책을 사용

## 8. 1회 시연용 점검 순서표

아래 순서대로 진행하면 현장 시연에서 실패 확률을 낮출 수 있습니다.

### 8.1 시연 10분 전
1. Arduino Leonardo 전원/USB 연결 상태 확인
2. MG996R 외부 전원(5~6V) 인가 및 Common GND 연결 재확인
3. 짐벌 기구물의 물리적 간섭(프레임, 케이블, 브라켓) 점검
4. USB 케이블 슬랙(여유 길이) 확보 및 회전축 중심 라우팅 확인

### 8.2 시연 5분 전
1. iOS 앱 실행 후 카메라 권한 상태 확인
2. 프리뷰가 전체 화면(`.resizeAspectFill`)으로 정상 표시되는지 확인
3. 모델 로드 실패 메시지 유무 확인
4. 정지 화면 기준으로 오버레이/라벨이 기본 숨김 상태인지 확인

### 8.3 시연 직전 기능 점검
1. 화면 좌측/중앙/우측을 순서대로 탭하여 Lock-on 동작 확인
2. Lock-on 이후 빨간 박스와 `Target (xx%)` 라벨이 타겟을 지연 없이 추종하는지 확인
3. 타겟이 화면에서 사라질 때 오버레이/라벨이 숨김 처리되는지 확인
4. 서보가 안전각 범위 내에서만 움직이는지 확인

### 8.4 장애 발생 시 빠른 복구 절차
1. 오버레이가 안 뜨면: 사람(person) 검출 여부와 탭 좌표를 먼저 재확인
2. 서보가 안 움직이면: USB MIDI 연결 상태와 CC 채널/번호 일치 여부 확인
3. 서보가 떨리면: 전원(전압 강하), GND, 케이블 접촉 불량 우선 점검
4. 포트 불안정 시: USB 재연결 후 앱 재실행, Arduino 리셋 순서로 복구

### 8.5 시연 성공 기준(완료 조건)
1. 탭으로 지정한 대상 1명을 연속 추적한다.
2. `Target (xx%)` 라벨이 박스 상단에서 끊김 없이 따라간다.
3. 좌/우 이동 시 서보가 의도한 방향으로 반응한다.
4. 타겟 상실 시 오버레이가 즉시 사라진다.
