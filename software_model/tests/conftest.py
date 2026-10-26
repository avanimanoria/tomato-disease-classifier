"""Shared fixtures. All data is SYNTHETIC and lives in pytest tmp dirs; it is used only to test the software
(plumbing), never for training a real model."""
from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Optional

import numpy as np
import pytest
from PIL import Image

from src.config_loader import load_config, with_root

CLASSES = ["early_blight", "healthy", "late_blight"]


def smooth_random_image(seed: int, size: int = 64) -> Image.Image:
    """Distinct, low-frequency random image (so perceptual hashes of different seeds are far apart)."""
    rng = np.random.RandomState(seed)
    small = (rng.rand(8, 8, 3) * 255).astype("uint8")
    return Image.fromarray(small).resize((size, size), Image.BICUBIC)


def make_cfg(root: Path, min_test: int = 2, **split_over) -> dict:
    cfg = with_root(load_config(), root)
    cfg["split"]["minimum_test_images_per_class"] = min_test
    cfg["split"].update(split_over)
    for sub in ("data/raw", "data/metadata", "data/processed", "models", "logs", "reports"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    for c in CLASSES:
        (root / "data/raw" / c).mkdir(parents=True, exist_ok=True)
        for s in ("train", "val", "test_locked"):
            (root / "data/processed" / s / c).mkdir(parents=True, exist_ok=True)
    return cfg


def populate(cfg: dict, groups_per_class: Dict[str, int], imgs_per_group: int = 5, flat: bool = False,
             start_seed: int = 0) -> int:
    """Create synthetic raw images. Sub-folders (group_xx) give verified 'folder_subdir' source groups;
    flat=True puts files directly in the class folder (=> fallback groups)."""
    root = Path(cfg["_root"])
    seed = start_seed
    for c, n_groups in groups_per_class.items():
        for g in range(n_groups):
            d = root / "data/raw" / c / ("" if flat else f"group_{g:02d}")
            d.mkdir(parents=True, exist_ok=True)
            for i in range(imgs_per_group):
                smooth_random_image(seed).save(d / f"img_{g:02d}_{i:02d}.png")
                seed += 1
    return seed


@pytest.fixture
def project(tmp_path):
    cfg = make_cfg(tmp_path)
    populate(cfg, {c: 8 for c in CLASSES})
    return cfg


@pytest.fixture
def split_project(project):
    """A project that has been manifest-ed and split successfully."""
    from src.manifest import build_manifest
    from src.split_dataset import run_split
    build_manifest(project)
    res = run_split(project)
    assert res["status"] == "completed", res.get("refusal_reasons")
    return project
