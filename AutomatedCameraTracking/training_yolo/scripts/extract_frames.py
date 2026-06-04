import argparse
from pathlib import Path

import cv2


def main():
    parser = argparse.ArgumentParser(description="Extract frames from a video for YOLO labeling.")
    parser.add_argument("--video", required=True, help="Input video path")
    parser.add_argument("--out", default="../raw/frames", help="Output image directory")
    parser.add_argument("--every-sec", type=float, default=0.5, help="Save one frame every N seconds")
    parser.add_argument("--prefix", default="futsal", help="Output filename prefix")
    args = parser.parse_args()

    video_path = Path(args.video)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise SystemExit(f"Could not open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, int(round(fps * args.every_sec)))
    frame_index = 0
    saved = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % step == 0:
            output = out_dir / f"{args.prefix}_{saved:06d}.jpg"
            cv2.imwrite(str(output), frame)
            saved += 1
        frame_index += 1

    cap.release()
    print(f"Saved {saved} frames to {out_dir}")


if __name__ == "__main__":
    main()
