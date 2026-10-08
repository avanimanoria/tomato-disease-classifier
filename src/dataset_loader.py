"""tf.data loading. Class order ALWAYS comes from the TensorFlow loader (never hard-coded) and is saved to
models/class_names.json. The locked test set can only be loaded through load_locked_test_dataset(), which
requires an explicit confirmation flag from the final-evaluation code path."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from .config_loader import models_path, path_of
from .utils import read_json, write_json


@dataclass
class LoadedDataset:
    ds: Any                    # batched, prefetched tf.data.Dataset of (images[0..255 float32], int labels)
    class_names: List[str]
    file_paths: List[str]      # in dataset order (valid for shuffle=False datasets)
    num_samples: int


def image_size(cfg: Dict[str, Any]) -> Tuple[int, int]:
    return int(cfg["image"]["height"]), int(cfg["image"]["width"])


def _load_directory(directory: Path, cfg: Dict[str, Any], shuffle: bool, batch_size: int, cache: bool) -> LoadedDataset:
    import tensorflow as tf
    directory = Path(directory)
    ds = tf.keras.utils.image_dataset_from_directory(
        str(directory), labels="inferred", label_mode="int", class_names=None,  # None => TF decides the order
        color_mode="rgb", batch_size=batch_size, image_size=image_size(cfg), shuffle=shuffle,
        seed=int(cfg["seed"]) if shuffle else None, interpolation="bilinear")
    class_names = list(ds.class_names)
    expected = set(cfg["classes"]["expected"])
    if set(class_names) != expected:
        raise ValueError(f"Classes found in {directory} {class_names} differ from expected {sorted(expected)}.")
    file_paths = list(ds.file_paths)
    if cache:
        ds = ds.cache()
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return LoadedDataset(ds, class_names, file_paths, len(file_paths))


def save_class_names(cfg: Dict[str, Any], class_names: List[str]) -> Path:
    p = models_path(cfg, "class_names.json")
    write_json(p, list(class_names))
    return p


def load_class_names(cfg: Dict[str, Any]) -> List[str]:
    p = models_path(cfg, "class_names.json")
    if not p.exists():
        raise FileNotFoundError(f"{p} not found. Train a model first (python scripts/train_model.py).")
    return list(read_json(p))


def _assert_not_locked(directory: Path, cfg: Dict[str, Any]) -> None:
    if Path(directory).resolve() == path_of(cfg, "locked_test_dir").resolve():
        raise PermissionError("The locked test set cannot be loaded through the training/validation loaders.")


def load_train_dataset(cfg: Dict[str, Any], batch_size: Optional[int] = None) -> LoadedDataset:
    """TRAIN split only: shuffle=True, deterministic seed, saves the TensorFlow class order."""
    d = path_of(cfg, "train_dir")
    _assert_not_locked(d, cfg)
    loaded = _load_directory(d, cfg, True, batch_size or int(cfg["training"]["batch_size"]),
                             bool(cfg["training"]["cache_dataset"]))
    save_class_names(cfg, loaded.class_names)
    return loaded


def load_val_dataset(cfg: Dict[str, Any], batch_size: Optional[int] = None) -> LoadedDataset:
    """VALIDATION split only: shuffle=False, no augmentation."""
    d = path_of(cfg, "val_dir")
    _assert_not_locked(d, cfg)
    return _load_directory(d, cfg, False, batch_size or int(cfg["training"]["batch_size"]),
                           bool(cfg["training"]["cache_dataset"]))


def load_train_val(cfg: Dict[str, Any], batch_size: Optional[int] = None) -> Tuple[LoadedDataset, LoadedDataset]:
    tr = load_train_dataset(cfg, batch_size)
    va = load_val_dataset(cfg, batch_size)
    if tr.class_names != va.class_names:
        raise ValueError(f"Class order differs between train {tr.class_names} and val {va.class_names}.")
    return tr, va


def load_locked_test_dataset(cfg: Dict[str, Any], final_evaluation_confirmed: bool,
                             batch_size: Optional[int] = None) -> LoadedDataset:
    """ONLY for final evaluation. Refuses unless the caller passes the explicit confirmation."""
    if final_evaluation_confirmed is not True:
        raise PermissionError("Locked test set access denied: final evaluation was not explicitly confirmed "
                              "(--final-evaluation).")
    return _load_directory(path_of(cfg, "locked_test_dir"), cfg, False,
                           batch_size or int(cfg["training"]["batch_size"]), False)


def load_image_array(path: Path, cfg: Dict[str, Any]) -> np.ndarray:
    """Single image -> float32 array (H, W, 3) in [0, 255], using the SAME decode + resize as training
    (tf.io.decode_image + bilinear resize). WebP/other formats fall back to Pillow."""
    import tensorflow as tf
    path = Path(path)
    h, w = image_size(cfg)
    if path.suffix.lower() in (".jpg", ".jpeg", ".png"):
        img = tf.io.decode_image(tf.io.read_file(str(path)), channels=3, expand_animations=False)
        img = tf.image.resize(tf.cast(img, tf.float32), (h, w), method="bilinear")
        return img.numpy().astype("float32")
    from PIL import Image
    with Image.open(path) as im:
        arr = np.asarray(im.convert("RGB"), dtype="float32")
    return tf.image.resize(arr, (h, w), method="bilinear").numpy().astype("float32")
