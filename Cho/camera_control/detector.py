from __future__ import annotations

from pathlib import Path

import numpy as np
from ultralytics import YOLO

from utils import Detection, compute_bbox_center


class YOLOPersonDetector:
    def __init__(self, weights_path: Path, conf_threshold: float, device: str, person_class_id: int) -> None:
        self.weights_path = Path(weights_path)
        self.conf_threshold = conf_threshold
        self.device = device
        self.person_class_id = person_class_id

        if not self.weights_path.exists():
            raise FileNotFoundError(f"YOLO weights not found: {self.weights_path}")

        print(
            f"[INFO] Loading YOLO detector from {self.weights_path} "
            f"(device={self.device}, conf_threshold={self.conf_threshold:.2f})"
        )
        self.model = YOLO(str(self.weights_path))

    def detect_persons(self, frame: np.ndarray) -> list[Detection]:
        if frame.size == 0:
            print("[WARN] Empty frame passed to detector.")
            return []

        results = self.model.predict(
            source=frame,
            conf=self.conf_threshold,
            classes=[self.person_class_id],
            device=self.device,
            verbose=False,
        )

        detections: list[Detection] = []
        if not results:
            print("[INFO] Detector returned no results.")
            return detections

        result = results[0]
        if result.boxes is None:
            print("[INFO] No boxes found in detector output.")
            return detections

        boxes_xyxy = result.boxes.xyxy.cpu().numpy()
        confidences = result.boxes.conf.cpu().numpy()
        classes = result.boxes.cls.cpu().numpy()

        for bbox_array, confidence, cls_idx in zip(boxes_xyxy, confidences, classes):
            if int(cls_idx) != self.person_class_id:
                continue
            x1, y1, x2, y2 = [int(round(value)) for value in bbox_array.tolist()]
            bbox_xyxy = (x1, y1, x2, y2)
            detection = Detection(
                bbox_xyxy=bbox_xyxy,
                confidence=float(confidence),
                center_xy=compute_bbox_center(bbox_xyxy),
            )
            detections.append(detection)

        print(f"[INFO] detector_person_count={len(detections)}")
        for detection_index, detection in enumerate(detections):
            print(
                f"[DETECT] idx={detection_index} "
                f"bbox={detection.bbox_xyxy} conf={detection.confidence:.4f} center={detection.center_xy}"
            )
        return detections
