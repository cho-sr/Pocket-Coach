from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import torch


REPO_ROOT = Path(__file__).resolve().parents[2]
YOLO_CONFIG_DIR = REPO_ROOT / ".ultralytics"
YOLO_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("YOLO_CONFIG_DIR", str(YOLO_CONFIG_DIR))


def resolve_default_device() -> str:
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


@dataclass(slots=True)
class CameraControlConfig:
    yolo_weights_path: Path
    video_path: Path
    output_video_path: Path
    detector_conf_threshold: float = 0.35
    similarity_threshold: float = 0.40
    max_center_distance: float = 220.0
    min_crop_width: int = 24
    min_crop_height: int = 48
    yolo_person_class_id: int = 0
    osnet_model_name: str = "osnet_x1_0"
    osnet_weights_path: Optional[Path] = None
    display_window_name: str = "CameraControlTargetSelection"
    save_output: bool = True
    draw_all_boxes: bool = True
    device: str = resolve_default_device()

    @classmethod
    def create_default(cls) -> "CameraControlConfig":
        script_dir = Path(__file__).resolve().parent
        return cls(
            yolo_weights_path=REPO_ROOT / "yolo26n.pt",
            video_path=REPO_ROOT / "soccer_data_1.mp4",
            output_video_path=script_dir / "outputs" / "tracking_result.mp4",
        )
