import argparse
import json
import shutil
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def load_coco(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def convert_box_xywh_to_yolo(box, image_width, image_height):
    x, y, w, h = box
    cx = (x + w / 2.0) / image_width
    cy = (y + h / 2.0) / image_height
    nw = w / image_width
    nh = h / image_height
    return cx, cy, nw, nh


def convert_split(source_root: Path, output_root: Path, source_split: str, output_split: str, keep_categories, merge_to_player):
    split_dir = source_root / source_split
    annotation_path = split_dir / "_annotations.coco.json"
    if not annotation_path.exists():
        print(f"skip {source_split}: no annotation file")
        return 0, 0

    coco = load_coco(annotation_path)
    images = {img["id"]: img for img in coco.get("images", [])}
    anns_by_image = {}
    for ann in coco.get("annotations", []):
        category_id = int(ann.get("category_id", -1))
        if category_id not in keep_categories:
            continue
        anns_by_image.setdefault(ann["image_id"], []).append(ann)

    image_out = output_root / "images" / output_split
    label_out = output_root / "labels" / output_split
    image_out.mkdir(parents=True, exist_ok=True)
    label_out.mkdir(parents=True, exist_ok=True)

    copied_images = 0
    copied_boxes = 0
    for image_id, image in images.items():
        file_name = image["file_name"]
        source_image = split_dir / file_name
        if not source_image.exists() or source_image.suffix.lower() not in IMAGE_EXTS:
            continue

        image_anns = anns_by_image.get(image_id, [])
        if not image_anns:
            continue

        shutil.copy2(source_image, image_out / source_image.name)
        lines = []
        for ann in image_anns:
            category_id = int(ann["category_id"])
            class_id = 0 if merge_to_player else keep_categories[category_id]
            cx, cy, w, h = convert_box_xywh_to_yolo(ann["bbox"], image["width"], image["height"])
            values = [max(0.0, min(1.0, v)) for v in (cx, cy, w, h)]
            lines.append(f"{class_id} {values[0]:.6f} {values[1]:.6f} {values[2]:.6f} {values[3]:.6f}")
            copied_boxes += 1

        (label_out / f"{source_image.stem}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        copied_images += 1

    print(f"{output_split}: {copied_images} images, {copied_boxes} boxes")
    return copied_images, copied_boxes


def main():
    parser = argparse.ArgumentParser(description="Convert the Roboflow football COCO dataset to YOLO player-only labels.")
    parser.add_argument("--source", default="dataset/football-players-detection.coco", help="COCO dataset root")
    parser.add_argument("--out", default="dataset", help="YOLO output dataset root")
    parser.add_argument("--include-referee", action="store_true", help="Also merge referee into player class")
    args = parser.parse_args()

    source_root = Path(args.source)
    output_root = Path(args.out)

    # COCO category ids observed in this dataset:
    # 1 ball, 2 goalkeeper, 3 player, 4 referee. Category 0 is a Roboflow project placeholder.
    keep_ids = [2, 3]
    if args.include_referee:
        keep_ids.append(4)
    keep_categories = {category_id: 0 for category_id in keep_ids}

    total_images = 0
    total_boxes = 0
    for source_split, output_split in (("train", "train"), ("valid", "val"), ("test", "test")):
        images, boxes = convert_split(source_root, output_root, source_split, output_split, keep_categories, True)
        total_images += images
        total_boxes += boxes

    data_yaml = output_root.parent / "data.yaml"
    data_yaml.write_text(
        "path: ./dataset\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n\n"
        "names:\n"
        "  0: player\n",
        encoding="utf-8",
    )
    print(f"done: {total_images} images, {total_boxes} boxes")
    print(f"updated {data_yaml}")


if __name__ == "__main__":
    main()
