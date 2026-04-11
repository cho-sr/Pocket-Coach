from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

import cv2
import numpy as np


BBox = tuple[int, int, int, int]
Center = tuple[float, float]


@dataclass(slots=True)
class Detection:
    bbox_xyxy: BBox
    confidence: float
    center_xy: Center


@dataclass(slots=True)
class TargetState:
    reference_feature: Optional[np.ndarray]
    target_bbox: Optional[BBox]
    prev_center: Optional[Center]
    is_lost: bool = False


@dataclass(slots=True)
class MatchResult:
    target_bbox: Optional[BBox]
    similarity: Optional[float]
    center_distance: Optional[float]
    status: str
    detection_index: Optional[int] = None


def clamp_bbox_to_frame(bbox: BBox, frame_shape: tuple[int, ...]) -> BBox:
    height, width = frame_shape[:2]
    x1, y1, x2, y2 = bbox
    x1 = int(np.clip(x1, 0, width - 1))
    y1 = int(np.clip(y1, 0, height - 1))
    x2 = int(np.clip(x2, 0, width - 1))
    y2 = int(np.clip(y2, 0, height - 1))
    if x2 <= x1:
        x2 = min(width - 1, x1 + 1)
    if y2 <= y1:
        y2 = min(height - 1, y1 + 1)
    return x1, y1, x2, y2


def compute_bbox_center(bbox: BBox) -> Center:
    x1, y1, x2, y2 = bbox
    return (x1 + x2) / 2.0, (y1 + y2) / 2.0


def crop_bbox(frame: np.ndarray, bbox: BBox) -> np.ndarray:
    x1, y1, x2, y2 = clamp_bbox_to_frame(bbox, frame.shape)
    return frame[y1:y2, x1:x2].copy()


def is_crop_valid(crop: np.ndarray, min_w: int, min_h: int) -> bool:
    if crop.size == 0 or crop.ndim != 3:
        return False
    height, width = crop.shape[:2]
    return width >= min_w and height >= min_h


def ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def create_video_writer(path: Path, fps: float, width: int, height: int) -> cv2.VideoWriter:
    ensure_parent_dir(path)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, (width, height))
    if not writer.isOpened():
        raise RuntimeError(f"Failed to open output video writer: {path}")
    return writer


def draw_zone_lines(frame: np.ndarray, num_zones: int = 7) -> None:
    height, width = frame.shape[:2]
    zone_width = width / float(num_zones)
    for zone_boundary in range(1, num_zones):
        x = int(round(zone_boundary * zone_width))
        cv2.line(frame, (x, 0), (x, height), (255, 255, 0), 1, lineType=cv2.LINE_AA)


def _put_overlay_text(frame: np.ndarray, text_lines: list[str]) -> None:
    y = 24
    for line in text_lines:
        cv2.putText(
            frame,
            line,
            (12, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2,
            lineType=cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            line,
            (12, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (20, 20, 20),
            1,
            lineType=cv2.LINE_AA,
        )
        y += 22


def draw_detections(
    frame: np.ndarray,
    detections: list[Detection],
    target_bbox: Optional[BBox],
    match_result: Optional[MatchResult],
    zone_idx: Optional[int],
    signal_angle: Optional[int],
    payload: Optional[str],
    frame_idx: int,
    draw_all_boxes: bool = True,
) -> np.ndarray:
    canvas = frame.copy()
    draw_zone_lines(canvas, num_zones=7)

    if draw_all_boxes:
        for detection in detections:
            x1, y1, x2, y2 = detection.bbox_xyxy
            cv2.rectangle(canvas, (x1, y1), (x2, y2), (0, 180, 0), 2)
            cv2.putText(
                canvas,
                f"person {detection.confidence:.2f}",
                (x1, max(18, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.45,
                (0, 180, 0),
                1,
                lineType=cv2.LINE_AA,
            )

    center_x = None
    if target_bbox is not None:
        x1, y1, x2, y2 = target_bbox
        center = compute_bbox_center(target_bbox)
        center_x = center[0]
        cv2.rectangle(canvas, (x1, y1), (x2, y2), (0, 0, 255), 3)
        cv2.circle(canvas, (int(center[0]), int(center[1])), 6, (0, 0, 255), -1)

    status = "waiting"
    similarity_text = "None"
    distance_text = "None"
    if match_result is not None:
        status = match_result.status
        if match_result.similarity is not None:
            similarity_text = f"{match_result.similarity:.4f}"
        if match_result.center_distance is not None:
            distance_text = f"{match_result.center_distance:.2f}"

    angle_text = str(signal_angle) if signal_angle is not None else "None"
    zone_text = str(zone_idx) if zone_idx is not None else "None"
    zone_label_text = f"ZONE_{zone_idx + 1}" if zone_idx is not None else "None"
    payload_text = payload.strip() if payload else "None"
    bbox_text = str(target_bbox) if target_bbox is not None else "None"
    center_x_text = f"{center_x:.2f}" if center_x is not None else "None"

    if status.startswith("lost"):
        cv2.putText(
            canvas,
            "TARGET LOST",
            (12, canvas.shape[0] - 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.9,
            (0, 0, 255),
            2,
            lineType=cv2.LINE_AA,
        )

    _put_overlay_text(
        canvas,
        [
            f"frame_idx={frame_idx}",
            f"target_bbox={bbox_text}",
            f"center_x={center_x_text}",
            f"similarity={similarity_text}",
            f"center_distance={distance_text}",
            f"zone_idx={zone_text}",
            f"zone_label={zone_label_text}",
            f"signal_angle={angle_text}",
            f"payload={payload_text}",
            f"status={status}",
            "keys: q=quit, r=reselect",
        ],
    )
    return canvas


def select_target_by_click(
    frame: np.ndarray,
    detections: list[Detection],
    window_name: str,
) -> Optional[Detection]:
    if not detections:
        print("[WARN] No detections available for target selection.")
        return None

    clicked_detection: dict[str, Optional[Detection]] = {"value": None}

    def mouse_callback(event: int, x: int, y: int, _flags: int, _param: object) -> None:
        if event != cv2.EVENT_LBUTTONDOWN:
            return
        matched = []
        for detection in detections:
            x1, y1, x2, y2 = detection.bbox_xyxy
            if x1 <= x <= x2 and y1 <= y <= y2:
                matched.append(detection)
        if matched:
            clicked_detection["value"] = max(matched, key=lambda det: det.confidence)

    preview = frame.copy()
    for detection in detections:
        x1, y1, x2, y2 = detection.bbox_xyxy
        cv2.rectangle(preview, (x1, y1), (x2, y2), (0, 180, 0), 2)
        cv2.putText(
            preview,
            f"{detection.confidence:.2f}",
            (x1, max(18, y1 - 6)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 180, 0),
            1,
            lineType=cv2.LINE_AA,
        )

    instruction_lines = [
        "Click inside a detected person bbox to select target.",
        "Press q or ESC to cancel selection.",
    ]
    _put_overlay_text(preview, instruction_lines)

    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    cv2.setMouseCallback(window_name, mouse_callback)

    while True:
        cv2.imshow(window_name, preview)
        key = cv2.waitKey(20) & 0xFF
        if clicked_detection["value"] is not None:
            return clicked_detection["value"]
        if key in (27, ord("q")):
            return None


def wait_for_control_key(
    window_name: str,
    frame_to_show: Optional[np.ndarray],
    display_enabled: bool,
    delay_ms: int = 1,
) -> str:
    if display_enabled and frame_to_show is not None:
        cv2.imshow(window_name, frame_to_show)
    key = cv2.waitKey(delay_ms) & 0xFF
    if key == ord("q"):
        return "quit"
    if key == ord("r"):
        return "reselect"
    return "continue"
