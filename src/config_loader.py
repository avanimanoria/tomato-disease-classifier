"""Configuration loading. All paths in config.yaml are relative to the project root."""
from __future__ import annotations

import copy
import os
from pathlib import Path
from typing import Any, Dict, Optional

import yaml

PROJECT_ROOT = Path(os.environ.get("TOMATO_PROJECT_ROOT", Path(__file__).resolve().parent.parent))
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "config" / "config.yaml"


def load_config(config_path: Optional[Path] = None, root: Optional[Path] = None) -> Dict[str, Any]:
    """Load config.yaml and attach the project root as cfg['_root']."""
    config_path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    cfg["_root"] = str(Path(root) if root else PROJECT_ROOT)
    validate_config(cfg)
    return cfg


def validate_config(cfg: Dict[str, Any]) -> None:
    s = cfg["split"]
    total = s["train_ratio"] + s["val_ratio"] + s["test_ratio"]
    if abs(total - 1.0) > 1e-6:
        raise ValueError(f"split ratios must sum to 1.0, got {total}")
    if not cfg["classes"]["expected"]:
        raise ValueError("classes.expected must not be empty")
    if cfg["model"]["architecture"] not in ("MobileNetV3Small", "MobileNetV2"):
        raise ValueError("model.architecture must be 'MobileNetV3Small' or 'MobileNetV2'")


def with_root(cfg: Dict[str, Any], root: Path) -> Dict[str, Any]:
    """Return a deep copy of cfg re-rooted at `root` (used heavily by tests)."""
    new = copy.deepcopy(cfg)
    new["_root"] = str(root)
    return new


def root_of(cfg: Dict[str, Any]) -> Path:
    return Path(cfg["_root"])


def path_of(cfg: Dict[str, Any], key: str) -> Path:
    """Absolute path for a key in cfg['paths']."""
    return root_of(cfg) / cfg["paths"][key]


def reports_path(cfg: Dict[str, Any], name: str) -> Path:
    p = path_of(cfg, "reports_dir") / name
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def logs_path(cfg: Dict[str, Any], name: str) -> Path:
    p = path_of(cfg, "logs_dir") / name
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def models_path(cfg: Dict[str, Any], name: str) -> Path:
    p = path_of(cfg, "models_dir") / name
    p.parent.mkdir(parents=True, exist_ok=True)
    return p
