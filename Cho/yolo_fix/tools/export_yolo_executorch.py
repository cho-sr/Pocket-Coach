import argparse
import os
import shutil
import sys
from pathlib import Path


def build_arg_parser() -> argparse.ArgumentParser:
    project_root = Path(__file__).resolve().parents[3]

    parser = argparse.ArgumentParser(description="Export yolo26n to ExecuTorch for the standalone yolo_fix iOS app.")
    parser.add_argument(
        "--weights",
        default=str(project_root / "yolo26n.pt"),
        help="Path to a YOLO .pt weights file. Defaults to repo-root yolo26n.pt",
    )
    parser.add_argument("--imgsz", type=int, default=640, help="Square inference/export image size")
    parser.add_argument("--batch", type=int, default=1, help="Export batch size")
    parser.add_argument(
        "--backend",
        choices=("coreml", "xnnpack"),
        default="coreml",
        help="ExecuTorch backend to lower the model for. Defaults to CoreML delegate.",
    )
    parser.add_argument(
        "--coreml-compute-unit",
        choices=("all", "cpu_only", "cpu_and_gpu", "cpu_and_ne"),
        default="all",
        help="CoreML compute unit for delegated export. 'all' allows CoreML to use CPU/GPU/Neural Engine.",
    )
    parser.add_argument(
        "--coreml-target",
        default="iOS18",
        help="CoreML minimum deployment target enum, for example iOS18 or iOS26.",
    )
    parser.add_argument(
        "--coreml-precision",
        choices=("float16", "float32"),
        default="float16",
        help="CoreML compute precision for delegated export.",
    )
    parser.add_argument(
        "--bundle-dir",
        default=str(project_root / "Cho/yolo_fix/yolo_fix/yolo_fix"),
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


def install_coreml_executorch_exporter(
    compute_unit_name: str,
    target_name: str,
    precision_name: str,
) -> None:
    import coremltools as ct
    import torch
    from executorch import version as executorch_version
    from executorch.backends.apple.coreml.compiler import CoreMLBackend
    from executorch.backends.apple.coreml.partition import CoreMLPartitioner
    from executorch.exir import to_edge_transform_and_lower
    from ultralytics.utils import LOGGER, YAML
    import ultralytics.utils.export.executorch as executorch_export

    compute_units = {
        "all": ct.ComputeUnit.ALL,
        "cpu_only": ct.ComputeUnit.CPU_ONLY,
        "cpu_and_gpu": ct.ComputeUnit.CPU_AND_GPU,
        "cpu_and_ne": ct.ComputeUnit.CPU_AND_NE,
    }
    precisions = {
        "float16": ct.precision.FLOAT16,
        "float32": ct.precision.FLOAT32,
    }

    try:
        minimum_deployment_target = getattr(ct.target, target_name)
    except AttributeError as exc:
        valid_targets = ", ".join(name for name in dir(ct.target) if name.startswith("iOS"))
        raise ValueError(f"Unknown CoreML target '{target_name}'. Valid iOS targets: {valid_targets}") from exc

    compile_specs = CoreMLBackend.generate_compile_specs(
        compute_unit=compute_units[compute_unit_name],
        minimum_deployment_target=minimum_deployment_target,
        compute_precision=precisions[precision_name],
    )

    def torch2executorch_coreml(
        model: torch.nn.Module,
        file: Path | str,
        sample_input: torch.Tensor,
        metadata: dict | None = None,
        prefix: str = "",
    ) -> str:
        LOGGER.info(
            f"\n{prefix} starting export with ExecuTorch {executorch_version.__version__} "
            f"and CoreML delegate ({compute_unit_name}, {target_name}, {precision_name})..."
        )

        file = Path(file)
        output_dir = Path(str(file).replace(file.suffix, "_coreml_executorch_model"))
        output_dir.mkdir(parents=True, exist_ok=True)

        pte_file = output_dir / file.with_suffix(".pte").name
        partitioner = CoreMLPartitioner(compile_specs=compile_specs)
        et_program = to_edge_transform_and_lower(
            torch.export.export(model, (sample_input,)),
            partitioner=[partitioner],
        ).to_executorch()
        pte_file.write_bytes(et_program.buffer)

        if metadata is not None:
            exported_metadata = dict(metadata)
            exported_metadata["executorch_backend"] = "coreml"
            exported_metadata["coreml_compute_unit"] = compute_unit_name
            exported_metadata["coreml_target"] = target_name
            exported_metadata["coreml_precision"] = precision_name
            YAML.save(output_dir / "metadata.yaml", exported_metadata)

        return str(output_dir)

    executorch_export.torch2executorch = torch2executorch_coreml


def export_model(args: argparse.Namespace) -> Path:
    from ultralytics import YOLO

    if args.backend == "coreml":
        install_coreml_executorch_exporter(
            compute_unit_name=args.coreml_compute_unit,
            target_name=args.coreml_target,
            precision_name=args.coreml_precision,
        )

    model = YOLO(args.weights)
    exported_dir = Path(
        model.export(
            format="executorch",
            imgsz=args.imgsz,
            batch=args.batch,
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
    project_root = Path(__file__).resolve().parents[3]
    configure_environment(project_root)
    args = build_arg_parser().parse_args()

    exported_dir = export_model(args)

    target_pte, target_metadata = copy_bundle_artifacts(
        exported_dir=exported_dir,
        bundle_dir=Path(args.bundle_dir),
        bundle_name=args.bundle_name,
    )

    print(f"executorch backend: {args.backend}")
    print(f"executorch export: {exported_dir}")
    print(f"bundle pte: {target_pte}")
    if target_metadata is not None:
        print(f"bundle metadata: {target_metadata}")
