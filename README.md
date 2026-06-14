# Pocket Coach

<p align="center">
  <img src="./images/5조_판넬%20(841%20x%201189%20mm).png" alt="Pocket Coach panel" width="900" />
</p>

스마트폰 기반 AI 축구 선수 추적 시스템을 위한 작업공간입니다.  
이 저장소에는 실시간 자동 카메라 추적, Flutter UI, 데이터셋 평가 도구가 함께 들어 있습니다.

## 한눈에 보기

- `AutomatedCameraTracking/`: Android CameraX + TFLite + Arduino 서보 제어
- `app_flutter/`: Flutter 홈/라이브 추적 UI와 네이티브 브리지
- `sskit/`: Spiideo SoccerNet SynLoc 개발 키트와 평가 도구
- `images/`: 패널 사진과 아키텍처 이미지

## 실행 흐름

```
flowchart TD
    A[사용자] --> B[Flutter 홈 화면]
    B --> C[Start Tracking]
    C --> D[DetectorBridge.startLiveSession()]
    D --> E[Android 네이티브 세션 시작]
    E --> F[CameraX ImageAnalysis]
    F --> G[프레임 전처리 및 Bitmap 변환]
    G --> H[TFLite 사람 검출]
    H --> I[ByteTrack 기반 추적]
    I --> J[타겟 선택 / 재획득]
    J --> K[화면 중심 오차 계산]
    K --> L[MotionController]
    L --> M[USB OTG Serial: PAN:<angle>]
    M --> N[Arduino Servo 제어]
    I --> O[오버레이 / FPS / 상태 표시]
    O --> P[Flutter UI에 상태 반영]
    H --> Q[세션 기록 / 영상 저장]
    Q --> R[오프라인 평가 및 분석]
```

### 1. 앱 시작

- `app_flutter/lib/screens/home_screen.dart`의 홈 화면에서 사용자가 `Start Tracking` 버튼을 누릅니다.
- `app_flutter/lib/detection/detector_bridge.dart`가 `pocket_coach/detector` 채널로 네이티브 세션 시작을 요청합니다.
- 라이브 화면은 `app_flutter/lib/screens/live_tracking_screen.dart`에서 열리고, 상태 칩과 제어 패널을 함께 보여줍니다.

### 2. 카메라 입력

- `AutomatedCameraTracking/android/app/src/main/java/gr/mybook/lunar_3/MainActivity.java`가 CameraX `Preview`와 `ImageAnalysis`를 바인딩합니다.
- `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`로 최신 프레임만 처리하고, `RGBA_8888` 형식으로 변환합니다.
- 분석 스레드에서 `imageProxyToBitmap()`으로 프레임을 `Bitmap`으로 바꿉니다.

### 3. 객체 검출

- `AutomatedCameraTracking/android/app/src/main/java/gr/mybook/lunar_3/ObjectDetectorHelper.java`가 `mobilenet_v2_ssd.tflite`를 불러옵니다.
- 가능하면 NNAPI/NPU를 먼저 쓰고, 실패하면 CPU로 폴백합니다.
- 검출 결과에서 person 클래스만 남기고, confidence와 NMS를 거쳐 박스를 만듭니다.

### 4. 추적 및 타겟 유지

- `ByteTrackTracker.java`가 IoU와 색상 히스토그램을 함께 써서 트랙을 갱신합니다.
- `TargetLockManager.java`가 수동 고정 대상 또는 화면 중심에 가까운 대상을 우선 선택합니다.
- `TargetReacquisitionManager`가 잠시 놓친 트랙을 다시 살릴 수 있게 보조합니다.

### 5. 팬/틸트 제어

- `MotionController.java`가 화면 중심과 타겟 중심의 오차를 계산합니다.
- 데드존 안에서는 각도를 유지하고, 바깥에서는 P/D 제어로 `35~145`도 범위 안에서 조절합니다.
- `MainActivity.java`의 `sendPanAngle()`이 `PAN:<angle>` 문자열을 USB 시리얼로 보냅니다.
- 전송은 `80ms` 간격으로 제한되어 과도한 명령 폭주를 막습니다.

### 6. 서보 동작

- Arduino의 `camera_tracking_servo.ino`가 `PAN` 명령을 받아 서보를 움직입니다.
- 기존 문서 기준으로 `L`, `F`, `R`, `S` 방향 제어도 함께 지원합니다.

### 7. 화면 반영

- `TrackingSnapshot` 결과가 오버레이에 전달되어 추적 박스, 타겟 상태, FPS가 표시됩니다.
- Flutter 라이브 화면은 `DetectorBridge`의 상태를 읽어 `LOCKED`, `SCAN`, `NPU ON` 같은 상태 칩을 보여줍니다.

### 8. 기록과 평가

- 영상 기록은 Android 세션에서 저장할 수 있습니다.
- `sskit/`는 오프라인 평가와 좌표 변환, mAP-LocSim 계산에 사용합니다.
- 데이터셋 결과와 제출 형식은 `sskit/README.md`를 참고하면 됩니다.

## 시스템 구성도

<p align="center">
  <img src="./images/architecture.png" alt="Pocket Coach architecture" width="900" />
</p>

## 주요 폴더

### `AutomatedCameraTracking/`

- Android 카메라 추적 앱
- 사람 검출, 트랙 관리, 타겟 고정, USB OTG 서보 제어

### `app_flutter/`

- 홈 화면, 라이브 추적 화면, 최근 기록 화면
- 네이티브 디텍터 브리지와 UI 상태 표시

### `sskit/`

- Spiideo SoccerNet SynLoc 개발 키트
- 좌표계 변환, 제출 형식, 평가 스크립트

## 실행 예시

### Flutter UI

```bash
cd app_flutter
flutter pub get
flutter run -d chrome
```

### Android 카메라 추적

```bash
cd AutomatedCameraTracking
# Android Studio에서 열거나 Gradle 프로젝트로 실행
```

### 평가 도구

```bash
cd sskit
pip install -e .
```

## 참고

- 대용량 모델, 영상, 결과 파일은 `.gitignore`에 포함되어 있습니다.
- 각 모듈은 독립적으로 개발하고 검증하는 것을 권장합니다.
