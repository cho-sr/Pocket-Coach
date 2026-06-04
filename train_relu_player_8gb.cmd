@echo off
setlocal

cd /d "%~dp0"
set PYTHONUTF8=1
set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

python Cho\yolo_fix\tools\finetune_relu_yolo.py ^
  --weights yolo26n.pt ^
  --data datasets\football-player-only\data.yaml ^
  --epochs 50 ^
  --batch 2 ^
  --imgsz 1024 ^
  --device 0 ^
  --workers 0 ^
  --name yolo26n_relu_player_b2
