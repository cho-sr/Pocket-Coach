from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import torch


class OSNetReIDExtractor:
    def __init__(
        self,
        model_name: str,
        device: str,
        min_crop_width: int,
        min_crop_height: int,
        weights_path: Optional[Path] = None,
    ) -> None:
        # torchreid downloads pretrained OSNet weights through torch's cache.
        # Keep that cache inside the repo so sandboxed runs do not write to ~/.cache.
        repo_torch_home = Path(__file__).resolve().parents[2] / ".cache" / "torch"
        repo_torch_home.mkdir(parents=True, exist_ok=True)
        os.environ.setdefault("TORCH_HOME", str(repo_torch_home))

        try:
            import torchreid
        except ModuleNotFoundError as exc:
            missing_module = exc.name or "unknown"
            if missing_module != "torchreid":
                raise RuntimeError(
                    f"torchreid is installed, but one of its import-time dependencies is missing: {missing_module}.\n"
                    f"Install it with:\n"
                    f"  ./.venv/bin/pip install {missing_module}"
                ) from exc
            raise RuntimeError(
                "torchreid is not installed. Install it before running this pipeline.\n"
                "Example:\n"
                "  ./.venv/bin/pip install torchreid\n"
                "If pip install is not enough, install from the official repo:\n"
                "  git clone https://github.com/KaiyangZhou/deep-person-reid.git\n"
                "  cd deep-person-reid && ./.venv/bin/python setup.py develop"
            ) from exc

        self.torchreid = torchreid
        self.model_name = model_name
        self.device = torch.device(device)
        self.min_crop_width = min_crop_width
        self.min_crop_height = min_crop_height
        self.weights_path = Path(weights_path) if weights_path is not None else None
        self.input_width = 128
        self.input_height = 256

        try:
            model = self.torchreid.models.build_model(
                name=self.model_name,
                num_classes=1000,
                loss="softmax",
                pretrained=True,
                use_gpu=device == "cuda",
            )
        except Exception as exc:
            raise RuntimeError(
                "Failed to initialize OSNet with pretrained weights. "
                "If the environment cannot download or locate pretrained weights, "
                "set --osnet-weights to a local checkpoint."
            ) from exc

        if self.weights_path is not None:
            if not self.weights_path.exists():
                raise FileNotFoundError(f"OSNet weights not found: {self.weights_path}")
            try:
                self.torchreid.utils.load_pretrained_weights(model, str(self.weights_path))
            except Exception as exc:
                raise RuntimeError(
                    f"Failed to load OSNet weights from {self.weights_path}. "
                    "Check the checkpoint format and torchreid compatibility."
                ) from exc

        self.model = model.to(self.device)
        self.model.eval()
        print(
            f"[INFO] Loaded OSNet reid model={self.model_name} device={self.device} "
            f"weights={self.weights_path if self.weights_path else 'pretrained'}"
        )

    def preprocess_crop(self, crop: np.ndarray) -> torch.Tensor:
        if crop.size == 0 or crop.ndim != 3:
            raise ValueError("Empty or invalid crop passed to OSNet preprocessing.")

        height, width = crop.shape[:2]
        if width < self.min_crop_width or height < self.min_crop_height:
            raise ValueError(
                f"Crop too small for reid: width={width}, height={height}, "
                f"required>={self.min_crop_width}x{self.min_crop_height}"
            )

        rgb_crop = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        resized_crop = cv2.resize(rgb_crop, (self.input_width, self.input_height), interpolation=cv2.INTER_LINEAR)
        normalized_crop = resized_crop.astype(np.float32) / 255.0

        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        normalized_crop = (normalized_crop - mean) / std

        tensor = torch.from_numpy(normalized_crop.transpose(2, 0, 1)).unsqueeze(0)
        return tensor.to(self.device)

    def extract_embedding(self, crop: np.ndarray) -> np.ndarray:
        tensor = self.preprocess_crop(crop)
        with torch.no_grad():
            feature = self.model(tensor)

        if isinstance(feature, (tuple, list)):
            feature = feature[0]
        if not isinstance(feature, torch.Tensor):
            raise RuntimeError(f"Unexpected OSNet output type: {type(feature)}")

        feature = feature.detach().float().cpu().view(-1)
        norm = torch.linalg.norm(feature)
        if float(norm) == 0.0:
            raise RuntimeError("OSNet returned a zero-norm embedding.")
        feature = feature / norm
        return feature.numpy()

    def extract_embeddings(self, crops: list[np.ndarray]) -> list[Optional[np.ndarray]]:
        embeddings: list[Optional[np.ndarray]] = []
        for crop_index, crop in enumerate(crops):
            try:
                embeddings.append(self.extract_embedding(crop))
            except ValueError as exc:
                print(f"[WARN] Skipping crop index={crop_index}: {exc}")
                embeddings.append(None)
        return embeddings
