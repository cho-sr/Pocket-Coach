import argparse
import random
import shutil
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def copy_pair(image_path: Path, label_path: Path, image_out: Path, label_out: Path):
    image_out.mkdir(parents=True, exist_ok=True)
    label_out.mkdir(parents=True, exist_ok=True)
    shutil.copy2(image_path, image_out / image_path.name)
    if label_path.exists():
        shutil.copy2(label_path, label_out / label_path.name)
    else:
        (label_out / f"{image_path.stem}.txt").write_text("", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Split YOLO images/labels into train/val/test folders.")
    parser.add_argument("--images", required=True, help="Directory containing labeled images")
    parser.add_argument("--labels", required=True, help="Directory containing YOLO .txt labels")
    parser.add_argument("--out", default="../dataset", help="Output YOLO dataset directory")
    parser.add_argument("--train", type=float, default=0.7)
    parser.add_argument("--val", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    image_dir = Path(args.images)
    label_dir = Path(args.labels)
    out_dir = Path(args.out)

    images = [p for p in image_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS]
    if not images:
        raise SystemExit(f"No images found in {image_dir}")

    random.seed(args.seed)
    random.shuffle(images)

    train_end = int(len(images) * args.train)
    val_end = train_end + int(len(images) * args.val)
    splits = {
        "train": images[:train_end],
        "val": images[train_end:val_end],
        "test": images[val_end:],
    }

    for split, split_images in splits.items():
        for image_path in split_images:
            label_path = label_dir / f"{image_path.stem}.txt"
            copy_pair(
                image_path,
                label_path,
                out_dir / "images" / split,
                out_dir / "labels" / split,
            )
        print(f"{split}: {len(split_images)} images")


if __name__ == "__main__":
    main()
