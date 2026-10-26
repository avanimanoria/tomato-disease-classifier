"""Read-only audit of the raw dataset + manifest. Never modifies, moves or deletes raw images."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd

from .config_loader import load_config, path_of, reports_path, root_of
from .duplicate_detection import (find_exact_duplicates, find_label_conflicts, find_near_duplicates,
                                  require_imagehash)
from .manifest import SOURCE_TYPE_FALLBACK, load_manifest
from .utils import setup_logging, utc_now_iso, write_json, write_text

log = logging.getLogger("tomato.audit")

ASPECT_BINS = [(0, 0.75, "portrait (<0.75)"), (0.75, 0.9, "slightly portrait (0.75-0.9)"),
               (0.9, 1.1, "square-ish (0.9-1.1)"), (1.1, 1.34, "slightly landscape (1.1-1.34)"),
               (1.34, 1e9, "landscape (>1.34)")]


def assess_group_metadata(valid: pd.DataFrame, cfg: Dict[str, Any]) -> Dict[str, Any]:
    """Is the source_group metadata good enough for a scientifically meaningful group-wise split?"""
    min_groups = int(cfg["split"]["min_groups_per_class_for_group_split"])
    reasons: List[str] = []
    n_fb = int((valid["source_type"] == SOURCE_TYPE_FALLBACK).sum())
    if n_fb:
        reasons.append(f"{n_fb} of {len(valid)} valid images only have a FALLBACK group (one group per image). "
                       "Fallback groups do not prove independence by plant, field or capture session.")
    verified = valid[valid["source_type"] != SOURCE_TYPE_FALLBACK]
    per_class_groups = {}
    for c in cfg["classes"]["expected"]:
        g = verified[verified["class_label"] == c]["source_group"].nunique()
        per_class_groups[c] = int(g)
        if g < min_groups:
            reasons.append(f"class '{c}' has only {g} verified source group(s); at least {min_groups} are "
                           "recommended so each split can receive whole groups.")
    for c, g in valid.groupby("class_label"):
        sizes = g["source_group"].value_counts()
        if len(sizes) and sizes.iloc[0] / len(g) > 0.5 and len(g) > 0 and sizes.index[0] and \
                not str(sizes.index[0]).startswith("fallback_"):
            reasons.append(f"class '{c}': group '{sizes.index[0]}' holds {sizes.iloc[0] / len(g):.0%} of the class; "
                           "group-wise splitting cannot balance the splits.")
    return {"sufficient": len(reasons) == 0, "fallback_group_images": n_fb,
            "verified_groups_per_class": per_class_groups, "reasons": reasons}


def run_audit(cfg: Dict[str, Any]) -> Dict[str, Any]:
    root = root_of(cfg)
    df = load_manifest(cfg)
    thr = int(cfg["split"]["duplicate_hamming_threshold"])
    expected = list(cfg["classes"]["expected"])
    rec_min = int(cfg["image"]["recommended_min_side_pixels"])
    blockers: List[str] = []
    warnings: List[str] = []

    # stale manifest?
    missing = [p for p in df["relative_path"] if not (root / p).exists()]
    if missing:
        warnings.append(f"{len(missing)} manifest rows point to files that no longer exist. "
                        "Re-run scripts/create_manifest.py.")

    valid = df[df["is_valid_image"]].copy()
    invalid = df[~df["is_valid_image"]]
    if len(valid) == 0:
        blockers.append("No valid images found in data/raw. Add real labelled tomato leaf images.")

    per_class = {c: int((valid["class_label"] == c).sum()) for c in expected}
    for c, n in per_class.items():
        if n == 0:
            blockers.append(f"Class '{c}' has no valid images.")
    nonzero = [n for n in per_class.values() if n > 0]
    balance_ratio = (max(nonzero) / min(nonzero)) if nonzero else None
    if balance_ratio and balance_ratio > float(cfg["training"]["class_imbalance_ratio_threshold"]):
        warnings.append(f"Class imbalance ratio {balance_ratio:.2f} exceeds "
                        f"{cfg['training']['class_imbalance_ratio_threshold']}; class weights will be used in training.")

    # dimensions
    dims: Dict[str, Any] = {}
    if len(valid):
        w, h = valid["image_width"].astype(float), valid["image_height"].astype(float)
        ar = w / h
        dims = {"width_min": int(w.min()), "width_median": float(w.median()), "width_max": int(w.max()),
                "height_min": int(h.min()), "height_median": float(h.median()), "height_max": int(h.max()),
                "aspect_ratio_distribution": {lab: int(((ar >= lo) & (ar < hi)).sum()) for lo, hi, lab in ASPECT_BINS},
                "image_modes": valid["image_mode"].value_counts().to_dict()}
        small = valid[(w < rec_min) | (h < rec_min)]
        dims["small_image_count"] = int(len(small))
        if len(small):
            warnings.append(f"{len(small)} images have a side below {rec_min}px (low detail for 224x224 input).")
        non_rgb = valid[valid["image_mode"] != "RGB"]
        if len(non_rgb):
            warnings.append(f"{len(non_rgb)} images are not RGB (modes: {non_rgb['image_mode'].unique().tolist()}). "
                            "They are converted to RGB when loaded/copied; raw files are untouched.")

    # duplicates
    exact = find_exact_duplicates(valid)
    imagehash_ok = True
    try:
        require_imagehash()
        near = find_near_duplicates(valid, thr)
    except ImportError as exc:
        imagehash_ok = False
        near = pd.DataFrame(columns=["image_id_a", "hamming_distance", "cross_class", "cross_group"])
        blockers.append(str(exc).replace("\n", " "))
    conflicts = find_label_conflicts(valid, exact, near) if imagehash_ok else find_label_conflicts(
        valid, exact, pd.DataFrame(columns=["cross_class"]))

    n_exact_cross_class = int((exact["kind"] == "across_classes").sum()) if len(exact) else 0
    if n_exact_cross_class:
        blockers.append(f"CRITICAL: {n_exact_cross_class} set(s) of byte-identical images carry DIFFERENT labels. "
                        "Resolve manually (see reports/label_conflict_candidates.csv).")
    if len(exact):
        warnings.append(f"{len(exact)} exact-duplicate set(s) found; they are kept together in one split.")
    if len(near):
        warnings.append(f"{len(near)} near-duplicate pair(s) (Hamming <= {thr}) need MANUAL REVIEW; "
                        "they are kept together in one split.")
    if len(near) and int(near["cross_class"].sum()):
        warnings.append(f"{int(near['cross_class'].sum())} near-duplicate pair(s) span different classes (possible label noise).")

    # group metadata
    group_dist = {c: valid[valid["class_label"] == c]["source_group"].nunique() for c in expected}
    gm = assess_group_metadata(valid, cfg) if len(valid) else {"sufficient": False, "reasons": ["no valid images"],
                                                                "fallback_group_images": 0,
                                                                "verified_groups_per_class": {}}
    if not gm["sufficient"]:
        warnings.append("Source-group metadata is NOT sufficient for a verified group-wise split "
                        "(see group_metadata section).")

    min_test = int(cfg["split"]["minimum_test_images_per_class"])
    expected_test = {c: round(n * cfg["split"]["test_ratio"]) for c, n in per_class.items()}
    for c, n in expected_test.items():
        if n < min_test:
            warnings.append(f"Class '{c}': only ~{n} images expected in the locked test set "
                            f"(minimum recommended {min_test}). Collect more images.")

    audit = {
        "generated_at": utc_now_iso(), "read_only": True, "total_files_in_manifest": int(len(df)),
        "valid_images": int(len(valid)), "invalid_images": int(len(invalid)),
        "invalid_reasons": invalid["invalid_reason"].value_counts().to_dict() if len(invalid) else {},
        "images_per_class": per_class, "class_balance_ratio_max_over_min": balance_ratio,
        "dimensions": dims, "exact_duplicate_sets": int(len(exact)),
        "exact_duplicate_sets_across_classes": n_exact_cross_class,
        "exact_duplicate_sets_across_source_groups": int((exact["kind"] == "within_class_across_groups").sum()) if len(exact) else 0,
        "exact_duplicate_sets_within_class": int(exact["kind"].str.startswith("within_class").sum()) if len(exact) else 0,
        "near_duplicate_pairs": int(len(near)), "near_duplicate_hamming_threshold": thr,
        "imagehash_available": imagehash_ok, "label_conflict_candidates": int(len(conflicts)),
        "source_groups_per_class": {k: int(v) for k, v in group_dist.items()}, "group_metadata": gm,
        "blockers": blockers, "warnings": warnings,
        "verdict": "BLOCKED" if blockers else ("PROCEED_WITH_CAUTION" if warnings else "OK"),
    }

    exact.to_csv(reports_path(cfg, "exact_duplicates.csv"), index=False)
    near.to_csv(reports_path(cfg, "near_duplicates.csv"), index=False)
    conflicts.to_csv(reports_path(cfg, "label_conflict_candidates.csv"), index=False)
    write_json(reports_path(cfg, "raw_dataset_audit.json"), audit)
    write_text(reports_path(cfg, "raw_dataset_audit.md"), render_markdown(audit))
    return audit


def render_markdown(a: Dict[str, Any]) -> str:
    L = ["# Raw dataset audit", "", f"Generated: {a['generated_at']}  ", "Read-only: no raw file was modified.", "",
         f"**Verdict: {a['verdict']}**", "", "## Counts", "",
         f"- Files in manifest: {a['total_files_in_manifest']}", f"- Valid images: {a['valid_images']}",
         f"- Invalid / unsupported: {a['invalid_images']}"]
    for k, v in a["invalid_reasons"].items():
        L.append(f"  - {k}: {v}")
    L += ["", "| Class | Valid images | Source groups |", "|---|---|---|"]
    for c, n in a["images_per_class"].items():
        L.append(f"| {c} | {n} | {a['source_groups_per_class'].get(c, 0)} |")
    r = a["class_balance_ratio_max_over_min"]
    L += ["", f"Class balance ratio (max/min): {r:.2f}" if r else "Class balance ratio: n/a", "", "## Image dimensions", ""]
    d = a["dimensions"]
    if d:
        L += [f"- Width  min/median/max: {d['width_min']} / {d['width_median']:.0f} / {d['width_max']}",
              f"- Height min/median/max: {d['height_min']} / {d['height_median']:.0f} / {d['height_max']}",
              f"- Small images (below recommended size): {d['small_image_count']}", "- Aspect ratios:"]
        L += [f"  - {k}: {v}" for k, v in d["aspect_ratio_distribution"].items()]
        L += [f"- Modes: {d['image_modes']}"]
    L += ["", "## Duplicates", "",
          f"- Exact-duplicate sets: {a['exact_duplicate_sets']} (across classes: {a['exact_duplicate_sets_across_classes']}, "
          f"across source groups: {a['exact_duplicate_sets_across_source_groups']}, within class: {a['exact_duplicate_sets_within_class']})",
          f"- Near-duplicate pairs (Hamming <= {a['near_duplicate_hamming_threshold']}): {a['near_duplicate_pairs']} — **manual review required**, nothing was deleted",
          f"- Label-conflict candidates: {a['label_conflict_candidates']}", "",
          "## Source-group metadata", "",
          f"Sufficient for verified group-wise splitting: **{'YES' if a['group_metadata']['sufficient'] else 'NO'}**", ""]
    L += [f"- {x}" for x in a["group_metadata"]["reasons"]]
    L += ["", "> Group-wise splitting is only scientifically meaningful if `source_group` represents a true independent "
          "source, such as a plant ID, farm plot, capture session, date/camera session, or original dataset source. "
          "File names alone may not be enough.", "", "## Blockers", ""]
    L += [f"- {x}" for x in a["blockers"]] or ["- none"]
    L += ["", "## Warnings", ""] + ([f"- {x}" for x in a["warnings"]] or ["- none"])
    L += ["", "Reports: `exact_duplicates.csv`, `near_duplicates.csv`, `label_conflict_candidates.csv`."]
    return "\n".join(L) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Read-only audit of data/raw and the manifest")
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)
    setup_logging("tomato")
    cfg = load_config(args.config)
    try:
        audit = run_audit(cfg)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 2
    print(f"\nAudit verdict: {audit['verdict']}")
    print(f"Valid images: {audit['valid_images']}  |  per class: {audit['images_per_class']}")
    for b in audit["blockers"]:
        print(f"  BLOCKER: {b}")
    for w in audit["warnings"]:
        print(f"  warning: {w}")
    print("\nReports written to reports/ (raw_dataset_audit.md is the human-readable one).")
    return 1 if audit["blockers"] else 0
