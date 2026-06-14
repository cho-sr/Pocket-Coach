# Pocket Coach Workspace

이 저장소는 축구 영상 추적과 분석을 위한 여러 프로젝트를 한곳에 모아둔 작업공간입니다.

## 구성

- `AutomatedCameraTracking/`: Android 앱과 Arduino 서보 제어를 이용한 자동 카메라 추적
- `app_flutter/`: Flutter 기반 UI, 카메라 화면, 추적 오버레이, 네이티브 디텍터 브리지
- `sskit/`: Spiideo SoccerNet SynLoc 개발 키트와 평가 도구
- `README.md`: 작업공간 전체 안내

## 이 저장소에서 할 수 있는 일

- 경기 영상에서 선수와 공을 감지하고 추적
- 카메라를 자동으로 좌우 조향
- 모바일 앱에서 추적 상태와 최근 영상을 확인
- 좌표 변환과 데이터셋 평가 수행

## 하위 프로젝트 안내

### `AutomatedCameraTracking/`

- Android 코드: `android/app/src/main/java/gr/mybook/lunar_3/`
- Arduino 서보 제어: `arduino/camera_tracking_servo/camera_tracking_servo.ino`
- YOLO 모델 내보내기: `export_yolo.py`
- 모델 파일은 `android/app/src/main/assets/` 아래를 사용

### `app_flutter/`

- 메인 진입점: `lib/main.dart`
- 화면 구성: `lib/screens/`, `lib/widgets/`
- 네이티브 브리지: `lib/detection/detector_bridge.dart`

실행 예시:

```bash
cd app_flutter
flutter pub get
flutter run -d chrome
```

### `sskit/`

- Spiideo SoccerNet SynLoc용 개발 키트
- 좌표계 변환, mAP-LocSim 평가, 예제 데이터 포함
- 상세 문서: `sskit/README.md`

설치 예시:

```bash
cd sskit
pip install -e .
```

## 참고

- 영상, 모델, 로그 같은 대용량 파일은 `.gitignore`에 포함되어 있습니다.
- 각 모듈은 독립적으로 실행하고 테스트하는 것을 권장합니다.
