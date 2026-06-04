# Pocket Coach Flutter UI

Shared Flutter UI template for Android and iOS. The screens match the provided dark "Pocket Coach" concept and leave a native detector bridge ready for on-device YOLO integration.

## Screens

- Home dashboard with system readiness
- Live tracking view with camera preview, mock overlay boxes, and control panel
- Device status and calibration
- Recent videos list
- Camera preview screen

## Native YOLO Hook

Flutter UI calls the native layer through:

```text
pocket_coach/detector
```

Expected native methods:

```text
startLiveSession
stopLiveSession
lockTarget
runCalibration
servoTest
```

Android and iOS can implement those methods separately while keeping this Flutter UI common.

## iOS ExecuTorch Model

The current iOS Runner bundles:

```text
ios/Runner/detector.pte
ios/Runner/metadata.yaml
```

The iOS native bridge loads the model through ExecuTorch on:

```text
pocket_coach/detector
```

On the home screen, `AI Model Engine` shows `Ready` when the model is present in the native app bundle. `Start Tracking` runs one native warmup forward pass directly through the iOS bridge with input shape:

```text
[1, 3, 576, 1024]
```

The camera preview settings are left untouched. The Start Tracking button does not force a landscape camera view; it only calls the native model bridge.

## Run

Flutter SDK is configured at:

```text
/Users/joseoglae/flutter
```

Run a quick UI preview in Chrome:

```bash
cd app_flutter
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5500
```

Run on Android after Android Studio/Android SDK is installed:

```bash
cd app_flutter
flutter doctor
flutter run -d android
```

Run on iOS after a simulator or device is available:

```bash
cd app_flutter
flutter devices
flutter run -d <ios-device-id>
```

For a build that can be opened from the iPhone home screen without Flutter tooling attached:

```bash
cd app_flutter
flutter run --release -d <ios-device-id>
```
