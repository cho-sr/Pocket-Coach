import argparse
import os
import sys
from pathlib import Path


def build_arg_parser() -> argparse.ArgumentParser:
    project_root = Path(__file__).resolve().parents[3]

    parser = argparse.ArgumentParser(description="Fine-tune YOLO after replacing SiLU activations with ReLU.")
    parser.add_argument(
        "--weights",
        default=str(project_root / "yolo26n.pt"),
        help="Path to the starting YOLO .pt weights file. Defaults to repo-root yolo26n.pt.",
    )
    parser.add_argument(
        "--data",
        required=True,
        help="Path to an Ultralytics dataset YAML file.",
    )
    parser.add_argument("--epochs", type=int, default=50, help="Fine-tuning epochs.")
    parser.add_argument("--batch", type=int, default=16, help="Batch size. Use -1 for Ultralytics auto-batch.")
    parser.add_argument(
        "--imgsz",
        type=int,
        default=1024,
        help="Training image size. Use 1024 to match the app export width, with --rect enabled.",
    )
    parser.add_argument("--device", default="0", help="CUDA device, for example 0 or 0,1.")
    parser.add_argument("--workers", type=int, default=8, help="DataLoader workers.")
    parser.add_argument("--project", default=str(project_root / "runs/relu_finetune"), help="Training output directory.")
    parser.add_argument("--name", default="yolo26n_relu", help="Training run name.")
    parser.add_argument("--lr0", type=float, default=0.001, help="Initial learning rate for fine-tuning.")
    parser.add_argument("--lrf", type=float, default=0.01, help="Final learning rate fraction.")
    parser.add_argument("--patience", type=int, default=20, help="Early-stopping patience.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume an interrupted Ultralytics run.",
    )
    parser.add_argument(
        "--no-rect",
        action="store_true",
        help="Disable rectangular training batches.",
    )
    parser.add_argument(
        "--freeze",
        type=int,
        default=None,
        help="Optional number of early layers to freeze. Leave unset for ReLU adaptation.",
    )
    return parser


def configure_environment(project_root: Path) -> None:
    ultralytics_dir = project_root / ".ultralytics"
    ultralytics_dir.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("YOLO_CONFIG_DIR", str(ultralytics_dir))


def replace_silu_with_relu(model) -> int:
    import torch

    replacements = 0
    for child_name, child in model.named_children():
        if isinstance(child, torch.nn.SiLU):
            setattr(model, child_name, torch.nn.ReLU(inplace=child.inplace))
            replacements += 1
        else:
            replacements += replace_silu_with_relu(child)
    return replacements


def train(args: argparse.Namespace) -> None:
    from ultralytics import YOLO

    model = YOLO(args.weights)
    replacements = replace_silu_with_relu(model.model)
    print(f"activation override: replaced {replacements} SiLU modules with ReLU")

    train_kwargs = {
        "data": args.data,
        "epochs": args.epochs,
        "batch": args.batch,
        "imgsz": args.imgsz,
        "device": args.device,
        "workers": args.workers,
        "project": args.project,
        "name": args.name,
        "lr0": args.lr0,
        "lrf": args.lrf,
        "patience": args.patience,
        "seed": args.seed,
        "pretrained": False,
        "rect": not args.no_rect,
        "cos_lr": True,
        "close_mosaic": 10,
        "save": True,
        "plots": True,
        "resume": args.resume,
    }

    if args.freeze is not None:
        train_kwargs["freeze"] = args.freeze

    results = model.train(**train_kwargs)
    trainer = getattr(model, "trainer", None)
    save_dir = Path(
        getattr(
            trainer,
            "save_dir",
            getattr(results, "save_dir", Path(args.project) / args.name),
        )
    )

    print("")
    print(f"training output: {save_dir}")
    print(f"best weights: {save_dir / 'weights' / 'best.pt'}")
    print(f"last weights: {save_dir / 'weights' / 'last.pt'}")
    print("Next on Mac:")
    print(
        ".venv/bin/python Cho/yolo_fix/tools/export_yolo_executorch.py "
        f"--weights {save_dir / 'weights' / 'best.pt'} "
        "--imgsz 1024 576 --activation relu "
        "--coreml-compute-unit all --coreml-target iOS18 --coreml-precision float16"
    )


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[3]
    configure_environment(project_root)
    args = build_arg_parser().parse_args()

    sys.exit(train(args))
