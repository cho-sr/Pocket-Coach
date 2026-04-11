from __future__ import annotations

from typing import Optional

import numpy as np

from utils import Detection, MatchResult


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    denominator = float(np.linalg.norm(a) * np.linalg.norm(b))
    if denominator == 0.0:
        return -1.0
    return float(np.dot(a, b) / denominator)


def compute_center_distance(center_a: tuple[float, float], center_b: tuple[float, float]) -> float:
    return float(np.linalg.norm(np.asarray(center_a, dtype=np.float32) - np.asarray(center_b, dtype=np.float32)))


def match_target(
    reference_feature: np.ndarray,
    detections: list[Detection],
    embeddings: list[Optional[np.ndarray]],
    prev_center: Optional[tuple[float, float]],
    similarity_threshold: float,
    max_center_distance: float,
) -> MatchResult:
    if len(detections) != len(embeddings):
        raise ValueError("detections and embeddings must have the same length")

    valid_candidates: list[tuple[int, Detection, np.ndarray, float]] = []
    for detection_index, (detection, embedding) in enumerate(zip(detections, embeddings)):
        if embedding is None:
            continue
        center_distance = 0.0
        if prev_center is not None:
            center_distance = compute_center_distance(prev_center, detection.center_xy)
            if center_distance > max_center_distance:
                continue
        valid_candidates.append((detection_index, detection, embedding, center_distance))

    if not valid_candidates:
        return MatchResult(
            target_bbox=None,
            similarity=None,
            center_distance=None,
            status="lost_gate",
            detection_index=None,
        )

    best_index = None
    best_detection = None
    best_similarity = -1.0
    best_distance = None
    for detection_index, detection, embedding, center_distance in valid_candidates:
        similarity = cosine_similarity(reference_feature, embedding)
        print(
            f"[MATCH_CANDIDATE] idx={detection_index} bbox={detection.bbox_xyxy} "
            f"similarity={similarity:.4f} center_distance={center_distance:.2f}"
        )
        if similarity > best_similarity:
            best_index = detection_index
            best_detection = detection
            best_similarity = similarity
            best_distance = center_distance

    if best_detection is None:
        return MatchResult(
            target_bbox=None,
            similarity=None,
            center_distance=None,
            status="lost_gate",
            detection_index=None,
        )

    if best_similarity < similarity_threshold:
        return MatchResult(
            target_bbox=None,
            similarity=best_similarity,
            center_distance=best_distance,
            status="lost_similarity",
            detection_index=best_index,
        )

    return MatchResult(
        target_bbox=best_detection.bbox_xyxy,
        similarity=best_similarity,
        center_distance=best_distance,
        status="matched",
        detection_index=best_index,
    )
