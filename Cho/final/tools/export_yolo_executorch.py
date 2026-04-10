import argparse
import os
import shutil
import sys
from pathlib import Path


def build_arg_parser() -> argparse.ArgumentParser:
    project_root = Path(__file__).resolve().parents[2]

    parser = argparse.ArgumentParser(description="Export yolo26n to ExecuTorch for the final iPhone Leonardo prototype.")
    parser.add_argument(
        "--weights",
        default=str(project_root / "yolo26n.pt"),
        help="Path to a YOLO .pt weights file. Defaults to repo-root yolo26n.pt",
    )
    parser.add_argument("--imgsz", type=int, default=640, help="Square inference/export image size")
    parser.add_argument("--batch", type=int, default=1, help="Export batch size")
    parser.add_argument(
        "--bundle-dir",
        default=str(project_root / "final/ios/RealtimeDetectionMVP/build"),
        help="Directory where detector.pte and metadata.yaml will be copied",
    )
    parser.add_argument(
        "--bundle-name",
        default="detector.pte",
        help="Filename to use inside the iOS app bundle",
    )
    return parser


def configure_environment(project_root: Path) -> None:
    ultralytics_dir = project_root / ".ultralytics"
    ultralytics_dir.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("YOLO_CONFIG_DIR", str(ultralytics_dir))

    if os.getenv("FLATC_EXECUTABLE"):
        return

    candidate_paths = [
        Path(sys.executable).with_name("flatc"),
        project_root / ".venv/bin/flatc",
        project_root / ".venv/lib/python3.12/site-packages/executorch/data/bin/flatc",
    ]

    for candidate in candidate_paths:
        if candidate.exists() and os.access(candidate, os.X_OK):
            os.environ["FLATC_EXECUTABLE"] = str(candidate)
            return


def export_model(weights: str, imgsz: int, batch: int) -> Path:
    from ultralytics import YOLO

    model = YOLO(weights)
    exported_dir = Path(
        model.export(
            format="executorch",
            imgsz=imgsz,
            batch=batch,
            device="cpu",
        )
    )
    return exported_dir


def copy_bundle_artifacts(exported_dir: Path, bundle_dir: Path, bundle_name: str) -> tuple[Path, Path | None]:
    bundle_dir.mkdir(parents=True, exist_ok=True)

    pte_file = next(exported_dir.rglob("*.pte"))
    target_pte = bundle_dir / bundle_name
    shutil.copy2(pte_file, target_pte)

    metadata_file = exported_dir / "metadata.yaml"
    target_metadata = None
    if metadata_file.exists():
        target_metadata = bundle_dir / "metadata.yaml"
        shutil.copy2(metadata_file, target_metadata)

    return target_pte, target_metadata


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[2]
    configure_environment(project_root)
    args = build_arg_parser().parse_args()

    exported_dir = export_model(
        weights=args.weights,
        imgsz=args.imgsz,
        batch=args.batch,
    )

    target_pte, target_metadata = copy_bundle_artifacts(
        exported_dir=exported_dir,
        bundle_dir=Path(args.bundle_dir),
        bundle_name=args.bundle_name,
    )

    print(f"executorch export: {exported_dir}")
    print(f"bundle pte: {target_pte}")
    if target_metadata is not None:
        print(f"bundle metadata: {target_metadata}")
