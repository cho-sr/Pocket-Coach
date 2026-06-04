# yolo_bytetrack

This folder is a standalone copy of `Cho/yolo_fix` with live ByteTrack tracking added on top of the existing YOLO detection pipeline.

Open:

```text
Cho/yolo_bytetrack/yolo_fix/yolo_fix.xcodeproj
```

Use the `Track` mode to run live YOLO detection and assign stable ByteTrack IDs to `person` and `ball` detections.

This folder is a drop-in test UI bundle for `Cho/final/ios/RealtimeDetectionMVP`.
It does not edit the original app directly.

## What This Adds

- A new root screen with three buttons:
  - `Detect`: show the camera, then run one detection on the latest frame.
  - `Test Image`: run detection on bundled `test_1.jpg`, `test_2.jpg`, and `test_3.jpg`.
  - `Live`: run live model detection and show bbox, FPS, and inference time.
- Shared `DetectorPipeline` for:
  - letterbox preprocessing
  - ExecuTorch inference
  - letterbox-aware bbox restoration
- No tracker, deadzone, or USB MIDI in `Live`.

## Apply To The App

Copy these files into `Cho/final/ios/RealtimeDetectionMVP`:

- `DetectionMode.swift`
- `DetectionResultView.swift`
- `DetectorPipeline.swift`
- `LiveDetectionViewController.swift`
- `ModeSelectionView.swift`
- `StillDetectionViewController.swift`

Replace these existing app files with the versions from this folder:

- `Models.swift`
- `FramePreprocessor.swift`
- `DetectionPostProcessor.swift`
- `RealtimeDetectionMVPApp.swift`

Keep the existing app files below:

- `CameraService.swift`
- `ExecuTorchRunner.swift`
- `OverlayView.swift`
- `SimpleTracker.swift`
- `TrackingControl.swift`
- `USBMIDIServoOutput.swift`

`DetectionViewController.swift` can remain in the target. The new root screen does not route to it.

## Test Images

Create this folder in the app bundle source directory:

```text
Cho/yolo_fix/yolo_fix/yolo_fix/test_images/
```

Then add:

```text
test_1.jpg
test_2.jpg
test_3.jpg
```

The `Test Image` screen also checks for `test_1.jpg` through `test_3.jpg` at the bundle root.
If a file is missing, the app shows `test_1.jpg missing` instead of crashing.

## Model Input Size

The default configuration is the current model contract:

```swift
DetectorPipeline(configuration: .current640)
```

That means:

```text
input: [1, 3, 640, 640]
```

For a re-exported 16:9 model, switch both `StillDetectionViewController` and
`LiveDetectionViewController` to:

```swift
DetectorPipeline(configuration: .highResolution1024x576)
```

Then bundle a `detector.pte` exported for:

```text
input: [1, 3, 576, 1024]
```

## Letterbox Behavior

The preprocessor keeps aspect ratio and pads with YOLO-style gray `114`.

Examples:

```text
1280x720 -> 640x640 model
scale 0.5
image 640x360
padX 0
padY 140
```

```text
1280x720 -> 1024x576 model
scale 0.8
image 1024x576
padX 0
padY 0
```

The postprocessor subtracts padding and divides by scale before returning normalized bbox rects.
