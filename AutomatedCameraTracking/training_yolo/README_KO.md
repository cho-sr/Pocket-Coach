# YOLO11n player training guide

This folder is for training a custom YOLO11n player detector before replacing the current MobileNet SSD model in the Android app.

## Folder layout

```text
training_yolo/
  data.yaml
  requirements.txt
  train_gtx1650_test.bat
  export_tflite.bat
  scripts/
    extract_frames.py
    split_yolo_dataset.py
  raw/
    videos/
    frames/
  dataset/
    images/train
    images/val
    images/test
    labels/train
    labels/val
    labels/test
```

## Recommended first experiment

Use GTX 1650 4GB with conservative settings:

```bash
yolo detect train model=yolo11n.pt data=data.yaml epochs=50 imgsz=416 batch=4 device=0 workers=2
```

If CUDA memory fails, reduce to:

```bash
yolo detect train model=yolo11n.pt data=data.yaml epochs=50 imgsz=320 batch=4 device=0 workers=2
```

If it runs comfortably, try:

```bash
yolo detect train model=yolo11n.pt data=data.yaml epochs=100 imgsz=416 batch=8 device=0 workers=2
```

## Dataset rule

Use one class first:

```text
0: player
```

Do not label target_player separately. Target selection is handled later by the tracker, tap lock, and re-identification logic.

## Direct data workflow

1. Put videos in `raw/videos`.
2. Extract frames:

```bash
python scripts/extract_frames.py --video raw/videos/sample.mp4 --out raw/frames --every-sec 0.5 --prefix futsal
```

3. Label frames with CVAT, Roboflow, Label Studio, or LabelImg in YOLO format.
4. Split labeled images and labels:

```bash
python scripts/split_yolo_dataset.py --images labeled/images --labels labeled/labels --out dataset
```

5. Run `train_gtx1650_test.bat`.
6. Export TFLite with `export_tflite.bat` after training.

## Notes

- Start with 300-500 labeled images to verify the pipeline.
- Use video-level splits if possible. Do not randomly mix near-duplicate frames from the same sequence into both train and test when measuring final quality.
- Include edge cases: overlap, far players, side exits, motion blur, dark indoor lighting, and partially visible bodies.
