"""Image manifest: one row per file in data/raw, with validity checks, hashes and source-group metadata.

The raw dataset is only ever READ. Manual edits to source_group / plant_id / capture_session /
capture_date / camera_or_source / notes / source_type are preserved when the manifest is regenerated.
"""
from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd
from PIL import Image, UnidentifiedImageError

from .config_loader import load_config, path_of, root_of
from .utils import (IMAGEHASH_INSTALL_HINT, list_files, posix_rel, setup_logging, sha256_file, sha256_text)

log = logging.getLogger("tomato.manifest")

MANIFEST_COLUMNS = [
    "image_id", "relative_path", "filename", "class_label", "file_extension", "file_size_bytes",
    "image_width", "image_height", "image_mode", "is_valid_image", "sha256_hash", "perceptual_hash",
    "source_group", "source_type", "leaf_id", "plant_id", "capture_session", "capture_date", "camera_or_source",
    "notes", "invalid_reason",
]
# Columns a human may edit; they survive regeneration if the image path is unchanged.
PRESERVED_COLUMNS = ["source_group", "source_type", "leaf_id", "plant_id", "capture_session", "capture_date",
                     "camera_or_source", "notes"]

SOURCE_TYPE_FOLDER = "folder_subdir"
SOURCE_TYPE_TOKEN = "filename_token"
SOURCE_TYPE_FALLBACK = "fallback_group"
SOURCE_TYPE_MANUAL = "manual"
SOURCE_TYPE_LEAF_MAP = "leaf_map"
VERIFIED_SOURCE_TYPES = {SOURCE_TYPE_FOLDER, SOURCE_TYPE_TOKEN, SOURCE_TYPE_MANUAL, SOURCE_TYPE_LEAF_MAP}

# Conservative filename tokens that explicitly name a source (e.g. plant12_leaf3.jpg, session-2_img9.png).
# Generic prefixes such as "image (12).jpg" are deliberately NOT treated as sources.
_TOKEN_RE = re.compile(
    r"(?i)(?:^|[_\-\s.])((?:plant|plot|field|farm|session|sess|tree|batch|site)[_\-]?\d+)(?=$|[_\-\s.])")


def _import_imagehash():
    try:
        import imagehash  # noqa: F401
        return imagehash
    except ImportError:
        return None


def inspect_image(path: Path, min_side: int, imagehash_mod=None) -> Dict[str, Any]:
    """Open an image defensively. Never raises; reports problems via is_valid_image / invalid_reason."""
    info: Dict[str, Any] = {"image_width": "", "image_height": "", "image_mode": "", "is_valid_image": False,
                            "perceptual_hash": "", "invalid_reason": ""}
    try:
        size = path.stat().st_size
        if size == 0:
            info["invalid_reason"] = "zero_byte_file"
            return info
        with Image.open(path) as im:
            im.verify()  # structural check
        with Image.open(path) as im:  # verify() invalidates the handle, so reopen and fully decode
            im.load()
            info["image_width"], info["image_height"] = im.size
            info["image_mode"] = im.mode
            if min(im.size) < min_side:
                info["invalid_reason"] = f"image_too_small(<{min_side}px)"
                return info
            if imagehash_mod is not None:
                info["perceptual_hash"] = str(imagehash_mod.phash(im))
        info["is_valid_image"] = True
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError) as exc:
        info["invalid_reason"] = f"corrupt_or_unreadable({type(exc).__name__})"
    return info


def _load_leaf_map(metadata_dir: Path) -> Dict[str, List[str]]:
    lmp = metadata_dir / "leaf_map.json"
    if lmp.exists():
        try:
            import json
            with open(lmp, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as exc:
            log.warning("Could not read leaf_map.json (%s)", exc)
    return {}


def infer_source_group(rel_to_class: Path, class_label: str, sha256: str,
                       leaf_map: Optional[Dict[str, List[str]]] = None) -> Dict[str, str]:
    """Infer a source group. Returns {source_group, source_type, leaf_id, plant_id}.

    1. Check leaf_map (from PlantVillage metadata) matching class_label:
       PlantVillage mapping: token in leaf_map has value '<PV_Class>:::<leaf_id>'
       -> source_group: 'plant_village/<class>/leaf_<leaf_id>' (source_type = 'leaf_map')
       Note: leaf_id is a leaf identifier, NOT a plant identifier. plant_id is left empty.
    2. Sub-folder inside the class folder  -> '<class>/<subfolder>'   (folder_subdir)
    3. Explicit filename token (plant12...) -> '<class>/<token>'       (filename_token)
    4. Otherwise a per-image fallback group 'fallback_<sha256[:12]>'    (fallback_group)
       Fallback groups do NOT claim that images come from different plants; exact duplicates share one.
    """
    if leaf_map:
        parts = rel_to_class.stem.split("___")
        token = parts[-1].strip().lower() if len(parts) > 1 else rel_to_class.stem.lower()
        if token in leaf_map:
            pv_labels = {
                "early_blight": "Tomato___Early_blight",
                "healthy": "Tomato___healthy",
                "late_blight": "Tomato___Late_blight",
            }
            target_pv = pv_labels.get(class_label, f"Tomato___{class_label}")
            class_vals = [v for v in leaf_map[token] if v.startswith(target_pv + ":::")]
            if len(class_vals) == 1:
                leaf_id = class_vals[0].split(":::")[-1]
                return {
                    "source_group": f"plant_village/{class_label}/leaf_{leaf_id}",
                    "source_type": SOURCE_TYPE_LEAF_MAP,
                    "leaf_id": leaf_id,
                    "plant_id": "",
                }

    parts = rel_to_class.parts
    if len(parts) > 1:
        return {"source_group": f"{class_label}/{parts[0]}", "source_type": SOURCE_TYPE_FOLDER, "leaf_id": "", "plant_id": ""}
    m = _TOKEN_RE.search(rel_to_class.stem)
    if m:
        token = m.group(1).lower()
        return {"source_group": f"{class_label}/{token}", "source_type": SOURCE_TYPE_TOKEN,
                "leaf_id": "", "plant_id": token if token.startswith("plant") else ""}
    return {"source_group": f"fallback_{sha256[:12]}", "source_type": SOURCE_TYPE_FALLBACK, "leaf_id": "", "plant_id": ""}


def _load_existing(manifest_path: Path) -> Optional[pd.DataFrame]:
    if manifest_path.exists():
        try:
            return pd.read_csv(manifest_path, dtype=str, keep_default_na=False)
        except Exception as exc:  # pragma: no cover
            log.warning("Could not read existing manifest (%s); manual metadata cannot be preserved.", exc)
    return None


def build_manifest(cfg: Dict[str, Any], write: bool = True) -> pd.DataFrame:
    root = root_of(cfg)
    raw_dir = path_of(cfg, "raw_data_dir")
    manifest_path = path_of(cfg, "manifest_path")
    expected = list(cfg["classes"]["expected"])
    exts = {e.lower() for e in cfg["image"]["supported_extensions"]}
    min_side = int(cfg["image"]["min_side_pixels"])

    imagehash_mod = _import_imagehash()
    if imagehash_mod is None:
        log.warning("ImageHash is not installed: perceptual hashes will be EMPTY and near-duplicate "
                    "detection will not work. Install with:  %s", IMAGEHASH_INSTALL_HINT)

    existing = _load_existing(manifest_path)
    existing_by_path = {} if existing is None else {r["relative_path"]: r for r in existing.to_dict("records")}

    # Sibling directory check: report all excluded sibling folders under raw_dir
    excluded_siblings: List[str] = []
    if raw_dir.is_dir():
        for item in raw_dir.iterdir():
            if item.is_dir() and item.name not in expected:
                excluded_siblings.append(item.name)
    if excluded_siblings:
        log.info("Excluding unrelated sibling folders under %s: %s", raw_dir, excluded_siblings)
        print(f"NOTE: Excluded {len(excluded_siblings)} unrelated dataset folder(s) under data/raw: {', '.join(sorted(excluded_siblings))}")

    leaf_map = _load_leaf_map(manifest_path.parent)

    files: List[Path] = []
    for c in expected:
        class_folder = raw_dir / c
        if class_folder.is_dir():
            files.extend(list_files(class_folder))
    log.info("Scanning %d files across expected classes %s under %s", len(files), expected, raw_dir)

    rows: List[Dict[str, Any]] = []
    for p in files:
        rel_raw = p.relative_to(raw_dir)
        rel_project = posix_rel(p, root)
        ext = p.suffix.lower()
        size = p.stat().st_size
        class_label = rel_raw.parts[0] if len(rel_raw.parts) > 1 else ""
        sha = sha256_file(p) if size > 0 else sha256_text("")
        row: Dict[str, Any] = {
            "image_id": "img_" + sha256_text(rel_project)[:12], "relative_path": rel_project,
            "filename": p.name, "class_label": class_label, "file_extension": ext,
            "file_size_bytes": size, "sha256_hash": sha,
        }
        if ext not in exts:
            row.update({"image_width": "", "image_height": "", "image_mode": "", "is_valid_image": False,
                        "perceptual_hash": "", "invalid_reason": f"unsupported_extension({ext or 'none'})"})
        else:
            row.update(inspect_image(p, min_side, imagehash_mod))
        if not class_label:
            row["is_valid_image"], row["invalid_reason"] = False, "not_inside_a_class_folder"
        elif class_label not in expected:
            row["is_valid_image"], row["invalid_reason"] = False, f"class_folder_not_expected({class_label})"

        inferred = infer_source_group(Path(*rel_raw.parts[1:]) if class_label else rel_raw, class_label or "unknown", sha, leaf_map=leaf_map)
        row.update(inferred)
        row.update({"capture_session": "", "capture_date": "", "camera_or_source": "", "notes": ""})

        old = existing_by_path.get(rel_project)
        if old:  # preserve manual metadata
            for col in PRESERVED_COLUMNS:
                if col in old and old[col] != "":
                    row[col] = old[col]
            if old.get("source_group", "") not in ("", inferred["source_group"]) \
                    and old.get("source_type") != SOURCE_TYPE_MANUAL:
                row["source_type"] = SOURCE_TYPE_MANUAL  # user changed the group by hand
            if old.get("source_group", "") == "" or old.get("source_type", "") == "":
                row["source_group"], row["source_type"] = inferred["source_group"], inferred["source_type"]
        rows.append(row)

    df = pd.DataFrame(rows, columns=MANIFEST_COLUMNS)
    if not df.empty:
        df = df.sort_values("relative_path").reset_index(drop=True)
    if write:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(manifest_path, index=False)
        log.info("Manifest written: %s (%d rows)", manifest_path, len(df))
    return df


def load_manifest(cfg: Dict[str, Any]) -> pd.DataFrame:
    mp = path_of(cfg, "manifest_path")
    if not mp.exists():
        raise FileNotFoundError(f"Manifest not found at {mp}. Run: python scripts/create_manifest.py")
    df = pd.read_csv(mp, dtype=str, keep_default_na=False)
    df["is_valid_image"] = df["is_valid_image"].str.lower().isin(["true", "1", "yes"])
    for c in ("file_size_bytes", "image_width", "image_height"):
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Scan data/raw and create data/metadata/image_manifest.csv")
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)
    setup_logging("tomato")
    cfg = load_config(args.config)
    df = build_manifest(cfg)
    n_valid = int(df["is_valid_image"].sum()) if len(df) else 0
    print(f"\nImages scanned : {len(df)}\nValid images   : {n_valid}\nInvalid/other  : {len(df) - n_valid}")
    if len(df):
        print("\nPer-class valid counts:")
        print(df[df.is_valid_image].groupby("class_label").size().to_string())
        n_fb = int((df.source_type == SOURCE_TYPE_FALLBACK).sum())
        print(f"\nRows with fallback (per-image) source groups: {n_fb} / {len(df)}")
        if n_fb:
            print("NOTE: fallback groups do NOT represent real plants/sessions. Edit source_group (and set "
                  "source_type to 'manual') in the CSV if you know the true sources.")
    else:
        print("\nNo files found. Place real images in data/raw/<class_name>/ and re-run.")
    print("\nNext: python scripts/audit_dataset.py")
    return 0
