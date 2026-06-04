@echo off
cd /d "%~dp0"

yolo export ^
  model=runs/player_yolo11n_test/weights/best.pt ^
  format=tflite ^
  imgsz=416

pause
