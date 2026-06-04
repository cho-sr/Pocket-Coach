import argparse
import yaml
from pathlib import Path


def filter_labels(label_dir, keep_and_map):
    """
    Reads all YOLO label .txt files in label_dir, filters out unwanted classes,
    remaps the target classes to new IDs, and overwrites the files.
    """
    label_dir = Path(label_dir)
    if not label_dir.exists():
        print(f"Warning: Label directory {label_dir} does not exist. Skipping.")
        return

    txt_files = list(label_dir.glob("*.txt"))
    modified_count = 0

    for txt_file in txt_files:
        with open(txt_file, "r") as f:
            lines = f.readlines()

        new_lines = []
        for line in lines:
            parts = line.strip().split()
            if not parts:
                continue

            old_class_id = int(parts[0])
            # If the class is in our mapping dict, remap it and save
            if old_class_id in keep_and_map:
                new_class_id = keep_and_map[old_class_id]
                new_line = f"{new_class_id} " + " ".join(parts[1:])
                new_lines.append(new_line)

        # Overwrite file with filtered annotations
        with open(txt_file, "w") as f:
            f.write("\n".join(new_lines) + "\n")
        modified_count += 1

    print(f"Processed {modified_count} label files in {label_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Filter and remap YOLO classes from downloaded datasets."
    )
    parser.add_argument(
        "--dataset-dir",
        required=True,
        help="Path to the dataset root folder (containing images/ and labels/)",
    )
    parser.add_argument(
        "--keep-classes",
        required=True,
        help="Comma-separated class IDs to KEEP (e.g. '0,1' where 0=player, 1=goalkeeper)",
    )
    parser.add_argument(
        "--target-class-id",
        type=int,
        default=0,
        help="The unified target class ID to assign to kept classes (default is 0 for player)",
    )
    args = parser.parse_args()

    dataset_dir = Path(args.dataset_dir)
    labels_dir = dataset_dir / "labels"

    # Define which classes to keep and map to target class ID
    keep_list = [int(x.strip()) for x in args.keep_classes.split(",")]
    # Map old class IDs -> new target class ID (0)
    keep_and_map = {old_id: args.target_class_id for old_id in keep_list}

    print(f"Class filtering rule: Keep {keep_list} -> Remap to {args.target_class_id}")

    # Process all subdirectories (train, val, test) inside labels/
    subdirs = ["train", "val", "test"]
    has_labels = False

    for subdir in subdirs:
        target_path = labels_dir / subdir
        if target_path.exists():
            filter_labels(target_path, keep_and_map)
            has_labels = True

    # If labels are directly in the labels/ directory (flat structure)
    if not has_labels:
        filter_labels(labels_dir, keep_and_map)

    # Automatically update/create data.yaml to reflect single class
    yaml_path = dataset_dir / "data.yaml"
    if yaml_path.exists():
        try:
            with open(yaml_path, "r") as f:
                data = yaml.safe_load(f)

            # Rewrite configuration for single player class
            data["names"] = {args.target_class_id: "player"}
            # Remove nc (number of classes) and force it to 1
            data["nc"] = 1

            with open(yaml_path, "w") as f:
                yaml.safe_dump(data, f, default_flow_style=False)
            print("Successfully updated data.yaml to single class configuration.")
        except Exception as e:
            print(f"Failed to update data.yaml: {e}")


if __name__ == "__main__":
    main()
