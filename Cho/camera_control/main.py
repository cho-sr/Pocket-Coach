from __future__ import annotations

import argparse
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from config import CameraControlConfig
from detector import YOLOPersonDetector
from matcher import match_target
from reid import OSNetReIDExtractor
from signal_generator import build_serial_payload
from utils import (
    Detection,
    MatchResult,
    TargetState,
    compute_bbox_center,
    create_video_writer,
    crop_bbox,
    draw_detections,
    is_crop_valid,
    select_target_by_click,
    wait_for_control_key,
)
from zone_mapper import compute_signal_angle, compute_zone_index, zone_label


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="YOLO26n + OSNet camera control pipeline")
    parser.add_argument("--video-path", type=Path, default=None, help="Path to input video")
    parser.add_argument("--yolo-weights", type=Path, default=None, help="Path to YOLO26n weights")
    parser.add_argument("--osnet-weights", type=Path, default=None, help="Optional local OSNet weights")
    parser.add_argument("--detector-conf-threshold", type=float, default=None, help="YOLO confidence threshold")
    parser.add_argument("--similarity-threshold", type=float, default=None, help="Cosine similarity threshold")
    parser.add_argument("--max-center-distance", type=float, default=None, help="Center distance gate")
    parser.add_argument("--output-video-path", type=Path, default=None, help="Output video path")
    parser.add_argument("--no-display", action="store_true", help="Disable per-frame preview window")
    return parser


def apply_cli_overrides(config: CameraControlConfig, args: argparse.Namespace) -> CameraControlConfig:
    if args.video_path is not None:
        config.video_path = args.video_path
    if args.yolo_weights is not None:
        config.yolo_weights_path = args.yolo_weights
    if args.osnet_weights is not None:
        config.osnet_weights_path = args.osnet_weights
    if args.detector_conf_threshold is not None:
        config.detector_conf_threshold = args.detector_conf_threshold
    if args.similarity_threshold is not None:
        config.similarity_threshold = args.similarity_threshold
    if args.max_center_distance is not None:
        config.max_center_distance = args.max_center_distance
    if args.output_video_path is not None:
        config.output_video_path = args.output_video_path
    return config


def print_frame_metadata(cap: cv2.VideoCapture, frame: np.ndarray) -> tuple[int, int, float, int]:
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"[INFO] video_width={width}")
    print(f"[INFO] video_height={height}")
    print(f"[INFO] video_fps={fps}")
    print(f"[INFO] video_frame_count={frame_count}")
    print(f"[INFO] first_frame_shape={frame.shape}")
    print(f"[INFO] first_frame_dtype={frame.dtype}")

    assert width > 0 and height > 0, "Invalid frame size"
    assert fps > 0, "Invalid FPS"
    assert frame.ndim == 3 and frame.shape[2] == 3, "Expected BGR frame with 3 channels"
    assert frame.dtype == np.uint8, "Expected uint8 frame"

    return width, height, fps, frame_count


def choose_target_detection(
    frame: np.ndarray,
    detections: list[Detection],
    config: CameraControlConfig,
    no_display: bool,
) -> Detection:
    if no_display:
        selected_detection = max(detections, key=lambda detection: detection.confidence)
        print(
            "[INFO] no_display=True, auto-selecting highest-confidence target "
            f"bbox={selected_detection.bbox_xyxy} conf={selected_detection.confidence:.4f}"
        )
        return selected_detection

    selected_detection = select_target_by_click(frame, detections, config.display_window_name)
    if selected_detection is None:
        raise RuntimeError("Target selection canceled before initialization.")
    return selected_detection


def build_reference_feature(
    frame: np.ndarray,
    selected_detection: Detection,
    reid_extractor: OSNetReIDExtractor,
    config: CameraControlConfig,
) -> np.ndarray:
    crop = crop_bbox(frame, selected_detection.bbox_xyxy)
    if not is_crop_valid(crop, config.min_crop_width, config.min_crop_height):
        raise ValueError(
            "Selected target crop is too small. "
            f"crop_shape={crop.shape}, required>={config.min_crop_width}x{config.min_crop_height}"
        )
    reference_feature = reid_extractor.extract_embedding(crop)
    print(
        f"[INFO] target_initialized bbox={selected_detection.bbox_xyxy} "
        f"center={selected_detection.center_xy} feature_dim={reference_feature.shape[0]}"
    )
    return reference_feature


def compute_tracking_outputs(
    target_bbox: tuple[int, int, int, int],
    frame_width: int,
) -> tuple[float, int, str, int, str]:
    center_x = compute_bbox_center(target_bbox)[0]
    zone_idx = compute_zone_index(center_x, frame_width, num_zones=7)
    zone_name = zone_label(zone_idx)
    signal_angle = compute_signal_angle(zone_idx)
    payload = build_serial_payload(signal_angle)
    return center_x, zone_idx, zone_name, signal_angle, payload


def log_tracking_state(
    frame_idx: int,
    target_bbox: Optional[tuple[int, int, int, int]],
    center_x: Optional[float],
    match_result: MatchResult,
    zone_idx: Optional[int],
    signal_angle: Optional[int],
    payload: Optional[str],
) -> None:
    print(
        "[TRACK] "
        f"frame_idx={frame_idx} "
        f"bbox={target_bbox} "
        f"center_x={None if center_x is None else f'{center_x:.2f}'} "
        f"similarity={None if match_result.similarity is None else f'{match_result.similarity:.4f}'} "
        f"center_distance={None if match_result.center_distance is None else f'{match_result.center_distance:.2f}'} "
        f"zone_idx={zone_idx} "
        f"signal_angle={signal_angle} "
        f"payload={repr(payload)} "
        f"status={match_result.status}"
    )


def run_pipeline(config: CameraControlConfig, no_display: bool) -> None:
    cap = cv2.VideoCapture(str(config.video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Failed to open video: {config.video_path}")

    ok, first_frame = cap.read()
    if not ok or first_frame is None:
        raise RuntimeError(f"Failed to read the first frame from video: {config.video_path}")

    frame_width, frame_height, fps, _frame_count = print_frame_metadata(cap, first_frame)

    detector = YOLOPersonDetector(
        weights_path=config.yolo_weights_path,
        conf_threshold=config.detector_conf_threshold,
        device=config.device,
        person_class_id=config.yolo_person_class_id,
    )
    reid_extractor = OSNetReIDExtractor(
        model_name=config.osnet_model_name,
        device=config.device,
        min_crop_width=config.min_crop_width,
        min_crop_height=config.min_crop_height,
        weights_path=config.osnet_weights_path,
    )

    first_detections = detector.detect_persons(first_frame)
    if not first_detections:
        raise RuntimeError("No person detections found in the first frame. Cannot select target.")

    selected_detection = choose_target_detection(first_frame, first_detections, config, no_display)
    reference_feature = build_reference_feature(first_frame, selected_detection, reid_extractor, config)

    target_state = TargetState(
        reference_feature=reference_feature,
        target_bbox=selected_detection.bbox_xyxy,
        prev_center=selected_detection.center_xy,
        is_lost=False,
    )

    writer = None
    if config.save_output:
        writer = create_video_writer(config.output_video_path, fps, frame_width, frame_height)

    initial_match = MatchResult(
        target_bbox=selected_detection.bbox_xyxy,
        similarity=1.0,
        center_distance=0.0,
        status="matched",
        detection_index=first_detections.index(selected_detection),
    )
    center_x, zone_idx, zone_name, signal_angle, payload = compute_tracking_outputs(
        selected_detection.bbox_xyxy,
        frame_width,
    )
    print(f"[SIGNAL] frame_idx=0 zone={zone_name} signal_angle={signal_angle} payload={repr(payload)}")
    log_tracking_state(
        frame_idx=0,
        target_bbox=selected_detection.bbox_xyxy,
        center_x=center_x,
        match_result=initial_match,
        zone_idx=zone_idx,
        signal_angle=signal_angle,
        payload=payload,
    )

    initial_overlay = draw_detections(
        frame=first_frame,
        detections=first_detections,
        target_bbox=selected_detection.bbox_xyxy,
        match_result=initial_match,
        zone_idx=zone_idx,
        signal_angle=signal_angle,
        payload=payload,
        frame_idx=0,
        draw_all_boxes=config.draw_all_boxes,
    )
    if writer is not None:
        writer.write(initial_overlay)

    if not no_display:
        control = wait_for_control_key(
            window_name=config.display_window_name,
            frame_to_show=initial_overlay,
            display_enabled=True,
            delay_ms=1,
        )
        if control == "quit":
            cap.release()
            if writer is not None:
                writer.release()
            cv2.destroyAllWindows()
            return

    frame_idx = 1
    while True:
        ok, frame = cap.read()
        if not ok or frame is None:
            print("[INFO] End of video reached.")
            break

        detections = detector.detect_persons(frame)
        crops = [crop_bbox(frame, detection.bbox_xyxy) for detection in detections]
        embeddings = reid_extractor.extract_embeddings(crops)

        center_x = None
        zone_idx = None
        zone_name = None
        signal_angle = None
        payload = None

        if detections and target_state.reference_feature is not None:
            match_result = match_target(
                reference_feature=target_state.reference_feature,
                detections=detections,
                embeddings=embeddings,
                prev_center=target_state.prev_center,
                similarity_threshold=config.similarity_threshold,
                max_center_distance=config.max_center_distance,
            )
        else:
            status = "lost_no_detection" if not detections else "lost_no_reference"
            match_result = MatchResult(
                target_bbox=None,
                similarity=None,
                center_distance=None,
                status=status,
                detection_index=None,
            )

        if match_result.status == "matched" and match_result.target_bbox is not None:
            target_state.target_bbox = match_result.target_bbox
            target_state.prev_center = compute_bbox_center(match_result.target_bbox)
            target_state.is_lost = False
            center_x, zone_idx, zone_name, signal_angle, payload = compute_tracking_outputs(
                match_result.target_bbox,
                frame_width,
            )
            print(
                f"[SIGNAL] frame_idx={frame_idx} zone={zone_name} "
                f"signal_angle={signal_angle} payload={repr(payload)}"
            )
        else:
            target_state.target_bbox = None
            target_state.is_lost = True
            print(f"[WARN] target_lost frame_idx={frame_idx} reason={match_result.status}")

        log_tracking_state(
            frame_idx=frame_idx,
            target_bbox=target_state.target_bbox,
            center_x=center_x,
            match_result=match_result,
            zone_idx=zone_idx,
            signal_angle=signal_angle,
            payload=payload,
        )

        overlay = draw_detections(
            frame=frame,
            detections=detections,
            target_bbox=target_state.target_bbox,
            match_result=match_result,
            zone_idx=zone_idx,
            signal_angle=signal_angle,
            payload=payload,
            frame_idx=frame_idx,
            draw_all_boxes=config.draw_all_boxes,
        )

        if writer is not None:
            writer.write(overlay)

        control = wait_for_control_key(
            window_name=config.display_window_name,
            frame_to_show=overlay,
            display_enabled=not no_display,
            delay_ms=1,
        )
        if control == "quit":
            break
        if control == "reselect":
            print(f"[INFO] Reselect requested at frame_idx={frame_idx}")
            selected_detection = select_target_by_click(frame, detections, config.display_window_name)
            if selected_detection is None:
                print("[WARN] Reselect canceled. Keeping current target state.")
            else:
                try:
                    target_state.reference_feature = build_reference_feature(
                        frame,
                        selected_detection,
                        reid_extractor,
                        config,
                    )
                    target_state.target_bbox = selected_detection.bbox_xyxy
                    target_state.prev_center = selected_detection.center_xy
                    target_state.is_lost = False
                    print(
                        f"[INFO] target_reselected frame_idx={frame_idx} "
                        f"bbox={selected_detection.bbox_xyxy}"
                    )
                except ValueError as exc:
                    print(f"[WARN] Reselect failed: {exc}")

        frame_idx += 1

    cap.release()
    if writer is not None:
        writer.release()
    cv2.destroyAllWindows()

    if writer is not None:
        print(f"[INFO] Saved output video to {config.output_video_path}")


def main() -> None:
    args = build_arg_parser().parse_args()
    config = apply_cli_overrides(CameraControlConfig.create_default(), args)
    print(
        "[INFO] config "
        f"video_path={config.video_path} "
        f"yolo_weights_path={config.yolo_weights_path} "
        f"osnet_weights_path={config.osnet_weights_path} "
        f"detector_conf_threshold={config.detector_conf_threshold} "
        f"similarity_threshold={config.similarity_threshold} "
        f"max_center_distance={config.max_center_distance} "
        f"device={config.device}"
    )
    run_pipeline(config=config, no_display=args.no_display)


if __name__ == "__main__":
    main()
