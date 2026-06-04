# Automated Camera Tracking

생성 위치: `C:\a\Nam Kung\AutomatedCameraTracking`

## 파일 구성

- `android/app/src/main/java/gr/mybook/lunar_3/MainActivity.java`
  - CameraX 카메라 프리뷰와 ImageAnalysis 구성
  - TFLite 결과를 기반으로 사람의 중심 X 좌표 계산
  - 화면을 Left 0-35%, Center 35-65%, Right 65-100%로 나눠 `L`, `F`, `R`, `S` 전송
  - mik3y usb-serial-for-android로 Arduino Uno USB OTG 연결, 9600 baud 사용

- `android/app/src/main/java/gr/mybook/lunar_3/ObjectDetectorHelper.java`
  - assets의 `mobilenet_v2_ssd.tflite` 로드
  - SSD 출력 `boxes/classes/scores/count`에서 person 클래스만 선택
  - 가장 confidence가 높은 person bounding box 반환

- `arduino/camera_tracking_servo/camera_tracking_servo.ino`
  - Serial 9600으로 `L`, `R`, `F`, `S` 수신
  - `L/R`은 서보 각도를 조금씩 이동
  - `F/S`는 현재 위치 유지

## 필요한 모델 파일

Android 프로젝트의 다음 경로에 모델을 넣으세요.

`android/app/src/main/assets/mobilenet_v2_ssd.tflite`

SSD MobileNet 계열 TFLite 모델은 출력 순서가 보통 다음과 같습니다.

1. boxes: `[1, 10, 4]`, 좌표 순서 `[top, left, bottom, right]`
2. classes: `[1, 10]`
3. scores: `[1, 10]`
4. count: `[1]`

COCO 모델에서 person은 보통 class id 1입니다. 일부 TFLite 샘플 모델은 0-based로 person이 0으로 나오기 때문에 코드에서 0도 person으로 보정했습니다.

## 연결 방법

1. Arduino Uno에 `camera_tracking_servo.ino` 업로드
2. Servo signal을 D9, VCC/GND를 외부 전원 또는 안정적인 5V/GND에 연결
3. Android 폰과 Arduino Uno를 USB OTG 케이블로 연결
4. 앱 실행 후 USB 권한 허용
5. 사람이 왼쪽이면 `L`, 중앙이면 `F`, 오른쪽이면 `R`, 미검출이면 `S`가 전송됩니다.
