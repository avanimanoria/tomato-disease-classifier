"""Group-aware, duplicate-aware, stratified train/val/locked-test split + test-lock creation/verification.

Safety properties enforced in code:
  * raw data is never moved, modified or deleted (images are COPIED to data/processed);
  * processed data is never overwritten without --force-rebuild;
  * images that share a source_group, are byte-identical, or are near-duplicates always land in the SAME split;
  * label-conflict candidates are excluded and reported, never auto-resolved;
  * the split is refused if any leakage check fails.
"""
from __future__ import annotations

import logging
import shutil
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from PIL import Image

from .config_loader import load_config, path_of, reports_path, root_of
from .duplicate_detection import (build_clusters, find_exact_duplicates, find_label_conflicts, find_near_duplicates,
                                  require_imagehash)
from .manifest import SOURCE_TYPE_FALLBACK, load_manifest
from .utils import (canonical_json, list_files, posix_rel, read_json, setup_logging, sha256_file, sha256_text,
                    utc_now_iso, write_json, write_text)

log = logging.getLogger("tomato.split")

SPLITS = ("train", "val", "test_locked")
FALLBACK_WARNING = ("WARNING: Source-group metadata is not verified. This split prevents exact/near-duplicate overlap "
                    "where detected, but cannot guarantee independence by plant, field, or capture session. Final test "
                    "performance should be called preliminary internal performance.")
SMALL_TEST_WARNING = ("WARNING: The locked test set is smaller than 20 images per class. Final metrics will be "
                      "statistically unstable and must be presented as preliminary.")


def split_dir(cfg: Dict[str, Any], split: str) -> Path:
    return path_of(cfg, {"train": "train_dir", "val": "val_dir", "test_locked": "locked_test_dir"}[split])


# ----------------------------------------------------------------------------- assignment
def _score(assign: Dict[str, int], counts: np.ndarray, targets: np.ndarray, totals: np.ndarray,
           min_test: int) -> Tuple[float, np.ndarray]:
    cur = np.zeros((3, counts.shape[1]))
    for k, s in assign.items():
        cur[s] += counts[k]
    dev = np.abs(cur - targets) / np.maximum(totals, 1)
    penalty = 1e3 * float((cur == 0).sum()) + 10.0 * float((cur[2] < min_test).sum())
    return float(dev.sum()) + penalty, cur


def stratified_group_assign(cluster_class_counts: pd.DataFrame, ratios: Tuple[float, float, float], seed: int,
                            min_test: int = 0, max_restarts: int = 50) -> Dict[str, str]:
    """Assign whole clusters to train/val/test_locked, approximating the per-class ratios.

    Greedy (largest cluster first, seeded random tie-breaks) with several seeded restarts; keeps the best.
    Deterministic for a given seed.
    """
    ids = list(cluster_class_counts.index)
    counts = cluster_class_counts.to_numpy(dtype=float)
    totals = counts.sum(axis=0)
    targets = np.array([r * totals for r in ratios])
    sizes = counts.sum(axis=1)
    n_restarts = int(min(max_restarts, max(1, 200_000 // max(len(ids), 1))))
    best, best_score = None, float("inf")
    for r in range(n_restarts):
        rng = np.random.RandomState(seed + 1009 * r)
        order = list(range(len(ids)))
        rng.shuffle(order)
        order.sort(key=lambda k: -sizes[k])  # stable: shuffle decides ties
        cur = np.zeros_like(targets)
        assign: Dict[int, int] = {}
        for k in order:
            add = counts[k]
            deltas = [float(((cur[s] + add - targets[s]) ** 2 - (cur[s] - targets[s]) ** 2).__truediv__(np.maximum(totals, 1) ** 2).sum())
                      for s in range(3)]
            s_best = int(np.argmin(deltas))
            assign[k] = s_best
            cur[s_best] += add
        score, _ = _score(assign, counts, targets, totals, min_test)
        if score < best_score:
            best, best_score = assign, score
        if best_score < 1e-9:
            break
    return {ids[k]: SPLITS[s] for k, s in best.items()}


# ----------------------------------------------------------------------------- leakage checks
def check_leakage(assign_df: pd.DataFrame, near_pairs: pd.DataFrame, classes: List[str], min_test: int,
                  allow_small_test: bool) -> Dict[str, Any]:
    """Independent post-assignment verification. `assign_df` needs: image_id, relative_path, class_label,
    split, source_group, sha256_hash."""
    failures: List[str] = []
    warnings: List[str] = []
    a = assign_df[assign_df["split"].isin(SPLITS)]

    exact_cross = []
    for sha, g in a.groupby("sha256_hash"):
        if g["split"].nunique() > 1:
            exact_cross.append({"sha256_hash": sha, "splits": sorted(g["split"].unique()),
                                "paths": g["relative_path"].tolist()})
    group_cross = []
    for grp, g in a.groupby("source_group"):
        if g["split"].nunique() > 1:
            group_cross.append({"source_group": grp, "splits": sorted(g["split"].unique())})
    split_of = dict(zip(a["image_id"], a["split"]))
    near_cross = []
    if near_pairs is not None and len(near_pairs):
        for _, r in near_pairs.iterrows():
            sa, sb = split_of.get(r.image_id_a), split_of.get(r.image_id_b)
            if sa and sb and sa != sb:
                near_cross.append({"a": r.relative_path_a, "b": r.relative_path_b, "split_a": sa, "split_b": sb,
                                   "hamming_distance": int(r.hamming_distance)})
    class_counts = {s: {c: int(((a["split"] == s) & (a["class_label"] == c)).sum()) for c in classes} for s in SPLITS}
    missing = [f"{c} missing from {s}" for s in SPLITS for c in classes if class_counts[s][c] == 0]

    if exact_cross:
        failures.append(f"{len(exact_cross)} exact-duplicate set(s) appear across splits.")
    if group_cross:
        failures.append(f"{len(group_cross)} source group(s) appear in more than one split.")
    if near_cross:
        failures.append(f"{len(near_cross)} near-duplicate pair(s) appear across splits.")
    if missing:
        failures.append("Class missing from a split: " + "; ".join(missing))
    small = [c for c in classes if class_counts["test_locked"][c] < min_test]
    if small:
        msg = f"Locked test set has fewer than {min_test} images for class(es): {small}."
        if allow_small_test:
            warnings.append(msg + " " + SMALL_TEST_WARNING)
        else:
            failures.append(msg + " Collect more images or pass --allow-small-test-set (results will be preliminary).")
    return {"passed": not failures, "failures": failures, "warnings": warnings, "class_counts": class_counts,
            "exact_duplicates_across_splits": exact_cross, "near_duplicates_across_splits": near_cross,
            "source_groups_in_multiple_splits": group_cross}


# ----------------------------------------------------------------------------- copying
def plan_processed_file(row: pd.Series) -> Tuple[str, bool]:
    """Name of the processed file and whether it needs conversion to RGB PNG.
    (WebP is not decodable by tf.io.decode_image; palette/CMYK/16-bit images are normalised.)"""
    ext = str(row["file_extension"]).lower()
    needs = ext not in (".jpg", ".jpeg", ".png") or row["image_mode"] not in ("RGB", "L")
    return (f"{row['image_id']}.png" if needs else f"{row['image_id']}{ext}"), needs


def _materialise(src: Path, dest: Path, convert: bool) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if convert:
        with Image.open(src) as im:
            im.convert("RGB").save(dest, format="PNG")
    else:
        shutil.copy2(src, dest)


def _processed_has_files(cfg: Dict[str, Any]) -> List[str]:
    found = []
    for s in SPLITS:
        found += [posix_rel(p, root_of(cfg)) for p in list_files(split_dir(cfg, s))]
    return found


def _clear_processed(cfg: Dict[str, Any]) -> None:
    """Delete files inside data/processed/{train,val,test_locked} ONLY (never raw)."""
    processed_root = (root_of(cfg) / "data" / "processed").resolve()
    for s in SPLITS:
        d = split_dir(cfg, s).resolve()
        if processed_root not in d.parents:
            raise RuntimeError(f"Refusing to clear {d}: not inside {processed_root}")
        for p in list_files(d):
            p.unlink()


# ----------------------------------------------------------------------------- main routine
def run_split(cfg: Dict[str, Any], seed: Optional[int] = None, dry_run: bool = False, force_rebuild: bool = False,
              allow_fallback_groups: bool = False, allow_small_test_set: bool = False) -> Dict[str, Any]:
    root = root_of(cfg)
    seed = int(cfg["seed"] if seed is None else seed)
    thr = int(cfg["split"]["duplicate_hamming_threshold"])
    classes = list(cfg["classes"]["expected"])
    ratios = (cfg["split"]["train_ratio"], cfg["split"]["val_ratio"], cfg["split"]["test_ratio"])
    min_test = int(cfg["split"]["minimum_test_images_per_class"])
    refusals: List[str] = []
    notes: List[str] = []

    df = load_manifest(cfg)
    valid = df[df["is_valid_image"] & df["class_label"].isin(classes)].copy()
    if valid.empty:
        return {"status": "refused", "refusal_reasons": ["No valid images in the manifest. Add images to data/raw/<class>/ "
                                                         "and run scripts/create_manifest.py."], "summary": None}
    require_imagehash()

    # -- duplicates / conflicts -------------------------------------------------
    exact = find_exact_duplicates(valid)
    near = find_near_duplicates(valid, thr)
    conflicts = find_label_conflicts(valid, exact, near)
    conflict_ids = set(conflicts["image_id"]) if len(conflicts) else set()
    cand = valid[~valid["image_id"].isin(conflict_ids)].copy()
    near_c = near[~(near.image_id_a.isin(conflict_ids) | near.image_id_b.isin(conflict_ids))] if len(near) else near
    if conflict_ids:
        notes.append(f"{len(conflict_ids)} image(s) are label-conflict candidates and were EXCLUDED from the split "
                     "(see reports/split_conflict_review.csv). Resolve them manually in data/raw and rebuild the manifest.")
        conflicts.to_csv(reports_path(cfg, "split_conflict_review.csv"), index=False)

    # -- group metadata gate ---------------------------------------------------
    n_fallback = int((cand["source_type"] == SOURCE_TYPE_FALLBACK).sum())
    if n_fallback and cfg["split"]["require_group_metadata"] and not allow_fallback_groups:
        refusals.append(f"{n_fallback} of {len(cand)} images have only FALLBACK source groups (no verified plant/"
                        "session/source information). Fill in source_group (and set source_type to 'manual') in "
                        "data/metadata/image_manifest.csv, or re-run with --allow-fallback-groups to accept a "
                        "duplicate-aware but NOT source-independent split.")
    if n_fallback and allow_fallback_groups:
        print("\n" + "#" * 78 + "\n" + FALLBACK_WARNING + "\n" + "#" * 78 + "\n")

    if refusals:
        return {"status": "refused", "refusal_reasons": refusals, "summary": None}

    # -- clustering + assignment ----------------------------------------------
    clusters = build_clusters(cand, near_c)
    cand["cluster_id"] = cand["image_id"].map(clusters)
    ccc = cand.groupby(["cluster_id", "class_label"]).size().unstack(fill_value=0).reindex(columns=classes, fill_value=0)
    cluster_split = stratified_group_assign(ccc, ratios, seed, min_test=min_test)
    cand["split"] = cand["cluster_id"].map(cluster_split)
    cand["group_verified"] = cand["source_type"] != SOURCE_TYPE_FALLBACK

    leak = check_leakage(cand, near_c, classes, min_test, allow_small_test_set)
    if allow_small_test_set and any(leak["class_counts"]["test_locked"][c] < min_test for c in classes):
        print("\n" + SMALL_TEST_WARNING + "\n")

    # processed file plan
    names = cand.apply(plan_processed_file, axis=1)
    cand["processed_file"] = [n for n, _ in names]
    cand["converted_to_png"] = [c for _, c in names]
    cand["processed_relative_path"] = [
        posix_rel(split_dir(cfg, s), root) + f"/{c}/{f}"
        for s, c, f in zip(cand["split"], cand["class_label"], cand["processed_file"])]
    cand["processed_sha256"] = ""

    # -- refusal conditions ----------------------------------------------------
    if not leak["passed"]:
        refusals += leak["failures"]
    existing = _processed_has_files(cfg)
    if existing and not dry_run and not force_rebuild:
        refusals.append(f"data/processed already contains {len(existing)} file(s). Re-run with --force-rebuild to "
                        "replace them (raw data is never touched). NOTE: a rebuild creates a NEW locked test set; "
                        "results measured on the previous one must not guide tuning on the new one.")

    summary = build_summary(cfg, cand, leak, seed, n_fallback, dry_run, notes, ratios, classes)
    status = "refused" if refusals else ("dry_run" if dry_run else "completed")

    if status == "completed":
        if existing and force_rebuild:
            log.warning("--force-rebuild: clearing %d processed file(s).", len(existing))
            _clear_processed(cfg)
        for i, r in cand.iterrows():
            src = root / r["relative_path"]
            dest = root / r["processed_relative_path"]
            _materialise(src, dest, bool(r["converted_to_png"]))
            cand.at[i, "processed_sha256"] = sha256_file(dest)
        create_lock_manifest(cfg, cand, seed)

    # -- reports (never let a dry run clobber a real, locked split's reports) ------
    protect = dry_run and path_of(cfg, "test_lock_manifest").exists()
    prefix = "dry_run_" if protect else ""
    out_cols = ["image_id", "relative_path", "class_label", "split", "source_group", "source_type", "group_verified",
                "cluster_id", "sha256_hash", "perceptual_hash", "processed_relative_path", "processed_sha256",
                "converted_to_png"]
    out = cand[out_cols].copy()
    if conflict_ids:
        exc = valid[valid["image_id"].isin(conflict_ids)][["image_id", "relative_path", "class_label", "source_group",
                                                          "source_type", "sha256_hash", "perceptual_hash"]].copy()
        exc["split"] = "excluded_label_conflict_candidate"
        out = pd.concat([out, exc], ignore_index=True)
    out.to_csv(reports_path(cfg, f"{prefix}split_manifest.csv"), index=False)
    summary["status"] = status
    summary["refusal_reasons"] = refusals
    write_json(reports_path(cfg, f"{prefix}split_summary.json"), summary)
    write_text(reports_path(cfg, f"{prefix}split_summary.md"), render_summary_md(summary))
    leak_report = {**leak, "seed": seed, "dry_run": dry_run, "generated_at": utc_now_iso(),
                   "result": "PASS" if leak["passed"] else "FAIL"}
    write_json(reports_path(cfg, f"{prefix}split_leakage_check.json"), leak_report)
    write_text(reports_path(cfg, f"{prefix}split_leakage_check.md"), render_leak_md(leak_report))
    if protect:
        notes.append("A locked split already exists; dry-run reports were written with the 'dry_run_' prefix so "
                     "they cannot overwrite the reports of the real split.")
    return {"status": status, "refusal_reasons": refusals, "summary": summary, "leakage": leak,
            "report_prefix": prefix, "notes": notes}


def build_summary(cfg, cand, leak, seed, n_fallback, dry_run, notes, ratios, classes) -> Dict[str, Any]:
    totals = cand.groupby("class_label").size().to_dict()
    deviation = {}
    for s, r in zip(SPLITS, ratios):
        deviation[s] = {}
        for c in classes:
            tot = max(totals.get(c, 0), 1)
            actual = leak["class_counts"][s][c] / tot
            deviation[s][c] = {"target_ratio": r, "actual_ratio": round(actual, 4),
                               "deviation_pct_points": round(100 * (actual - r), 2)}
    groups = {s: sorted(cand[cand["split"] == s]["source_group"].unique().tolist()) for s in SPLITS}
    return {
        "generated_at": utc_now_iso(), "seed": seed, "dry_run": dry_run,
        "target_ratios": dict(zip(SPLITS, ratios)), "total_images_split": int(len(cand)),
        "class_counts_by_split": leak["class_counts"], "group_count_by_split": {s: len(g) for s, g in groups.items()},
        "source_groups_by_split": groups, "fallback_group_images": n_fallback,
        "fallback_groups_used": n_fallback > 0,
        "group_metadata_verified": n_fallback == 0,
        "exact_duplicates_between_splits": len(leak["exact_duplicates_across_splits"]),
        "near_duplicates_between_splits": len(leak["near_duplicates_across_splits"]),
        "class_distribution_deviation": deviation,
        "max_abs_deviation_pct_points": max(abs(v["deviation_pct_points"]) for d in deviation.values() for v in d.values()),
        "result": "PASS" if leak["passed"] else "FAIL", "failures": leak["failures"], "warnings": leak["warnings"],
        "notes": notes,
    }


def render_summary_md(s: Dict[str, Any]) -> str:
    L = ["# Split summary", "", f"Generated: {s['generated_at']}  ", f"Seed: **{s['seed']}**  ",
         f"Status: **{s.get('status', '?')}** (leakage result: **{s['result']}**)  ",
         f"Dry run: {s['dry_run']}", "", "## Class counts by split", "", "| Split | " + " | ".join(
             next(iter(s["class_counts_by_split"].values())).keys()) + " | Groups |", "|---|" + "---|" * (
             len(next(iter(s["class_counts_by_split"].values()))) + 1)]
    for sp, cc in s["class_counts_by_split"].items():
        L.append(f"| {sp} | " + " | ".join(str(v) for v in cc.values()) + f" | {s['group_count_by_split'][sp]} |")
    L += ["", f"- Fallback-group images: {s['fallback_group_images']} (group metadata verified: "
          f"{'yes' if s['group_metadata_verified'] else 'NO'})",
          f"- Exact duplicates between splits: {s['exact_duplicates_between_splits']}",
          f"- Near duplicates between splits: {s['near_duplicates_between_splits']}",
          f"- Max class-distribution deviation from target: {s['max_abs_deviation_pct_points']} percentage points", ""]
    if not s["group_metadata_verified"]:
        L += ["> " + FALLBACK_WARNING, ""]
    L += ["## Deviation from target ratios", "", "| Split | Class | Target | Actual | Deviation (pp) |", "|---|---|---|---|---|"]
    for sp, d in s["class_distribution_deviation"].items():
        for c, v in d.items():
            L.append(f"| {sp} | {c} | {v['target_ratio']:.2f} | {v['actual_ratio']:.3f} | {v['deviation_pct_points']:+.2f} |")
    L += ["", "## Source groups per split", ""]
    for sp, g in s["source_groups_by_split"].items():
        shown = ", ".join(g[:50]) + (f", ... (+{len(g) - 50} more; full list in split_summary.json)" if len(g) > 50 else "")
        L.append(f"- **{sp}** ({len(g)}): {shown}")
    L += ["", "## Failures", ""] + ([f"- {x}" for x in s["failures"] + s.get("refusal_reasons", [])] or ["- none"])
    L += ["", "## Warnings / notes", ""] + ([f"- {x}" for x in s["warnings"] + s["notes"]] or ["- none"])
    return "\n".join(L) + "\n"


def render_leak_md(r: Dict[str, Any]) -> str:
    L = ["# Split leakage check", "", f"Result: **{r['result']}**  ", f"Seed: {r['seed']}  ", f"Dry run: {r['dry_run']}", "",
         f"- Exact duplicates across splits: {len(r['exact_duplicates_across_splits'])}",
         f"- Near duplicates across splits: {len(r['near_duplicates_across_splits'])}",
         f"- Source groups in more than one split: {len(r['source_groups_in_multiple_splits'])}", "",
         "## Failures", ""] + ([f"- {x}" for x in r["failures"]] or ["- none"]) + ["", "## Warnings", ""] + (
            [f"- {x}" for x in r["warnings"]] or ["- none"])
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------------------- test lock
def create_lock_manifest(cfg: Dict[str, Any], cand: pd.DataFrame, seed: int) -> Dict[str, Any]:
    test = cand[cand["split"] == "test_locked"].sort_values("processed_relative_path")
    entries = [{"relative_path": r.processed_relative_path, "image_id": r.image_id, "class_label": r.class_label,
                "source_group": r.source_group, "sha256_hash": r.processed_sha256, "raw_relative_path": r.relative_path,
                "raw_sha256": r.sha256_hash} for r in test.itertuples()]
    content = {"created_at": utc_now_iso(), "random_seed": seed, "total_test_images": len(entries),
               "class_counts": test.groupby("class_label").size().to_dict(),
               "n_source_groups": int(test["source_group"].nunique()), "entries": entries,
               "note": "Locked test set. Never use it for training, tuning or model selection."}
    content["manifest_checksum"] = sha256_text(canonical_json(content))
    write_json(path_of(cfg, "test_lock_manifest"), content)
    return content


def verify_test_lock(cfg: Dict[str, Any], write_report: bool = True) -> Dict[str, Any]:
    """Verify test files are intact and fully separated from train/val. Used by training, evaluation and the CLI."""
    root = root_of(cfg)
    failures: List[str] = []
    checks: Dict[str, Any] = {}
    lock_path = path_of(cfg, "test_lock_manifest")
    if not lock_path.exists():
        res = {"passed": False, "failures": [f"Test lock manifest not found at {lock_path}. "
                                              "Run: python scripts/split_dataset.py"], "checks": {},
               "generated_at": utc_now_iso()}
        return _finish_lock_report(cfg, res, write_report)
    lock = read_json(lock_path)

    body = {k: v for k, v in lock.items() if k != "manifest_checksum"}
    checks["manifest_checksum_ok"] = sha256_text(canonical_json(body)) == lock.get("manifest_checksum")
    if not checks["manifest_checksum_ok"]:
        failures.append("test_lock_manifest.json has been modified (checksum mismatch).")

    entries = lock["entries"]
    missing, changed = [], []
    for e in entries:
        p = root / e["relative_path"]
        if not p.exists():
            missing.append(e["relative_path"])
        elif sha256_file(p) != e["sha256_hash"]:
            changed.append(e["relative_path"])
    checks["test_files_expected"] = len(entries)
    checks["test_files_missing"], checks["test_files_hash_mismatch"] = missing, changed
    if missing:
        failures.append(f"{len(missing)} locked test file(s) are missing.")
    if changed:
        failures.append(f"{len(changed)} locked test file(s) no longer match their SHA-256 hash.")

    on_disk = {posix_rel(p, root) for p in list_files(split_dir(cfg, "test_locked"))}
    extra = sorted(on_disk - {e["relative_path"] for e in entries})
    checks["unexpected_files_in_test_dir"] = extra
    if extra:
        failures.append(f"{len(extra)} file(s) in the test folder are not in the lock manifest.")

    test_hashes = {e["sha256_hash"] for e in entries} | {e["raw_sha256"] for e in entries}
    test_groups = {e["source_group"] for e in entries}
    split_manifest = reports_path(cfg, "split_manifest.csv")
    group_of = {}
    if split_manifest.exists():
        sm = pd.read_csv(split_manifest, dtype=str, keep_default_na=False)
        group_of = dict(zip(sm["processed_relative_path"], sm["source_group"]))
    else:
        failures.append("reports/split_manifest.csv not found; cannot verify source-group separation.")

    overlap_hash, overlap_group, unknown = [], [], []
    for s in ("train", "val"):
        for p in list_files(split_dir(cfg, s)):
            rel = posix_rel(p, root)
            if sha256_file(p) in test_hashes:
                overlap_hash.append(rel)
            g = group_of.get(rel)
            if g is None:
                unknown.append(rel)
            elif g in test_groups:
                overlap_group.append(rel)
    checks["train_val_files_with_hash_in_test"] = overlap_hash
    checks["train_val_files_with_source_group_in_test"] = overlap_group
    checks["train_val_files_unknown_to_split_manifest"] = unknown
    if overlap_hash:
        failures.append(f"{len(overlap_hash)} train/val file(s) are byte-identical to a locked test file.")
    if overlap_group:
        failures.append(f"{len(overlap_group)} train/val file(s) share a source group with the locked test set.")
    if unknown:
        failures.append(f"{len(unknown)} train/val file(s) are not listed in split_manifest.csv "
                        "(cannot verify their source group). Rebuild the split.")
    res = {"passed": not failures, "failures": failures, "checks": checks, "generated_at": utc_now_iso(),
           "test_images": len(entries), "lock_created_at": lock.get("created_at"), "lock_seed": lock.get("random_seed")}
    return _finish_lock_report(cfg, res, write_report)


def _finish_lock_report(cfg, res, write_report):
    res["result"] = "PASS" if res["passed"] else "FAIL"
    if write_report:
        write_json(reports_path(cfg, "test_lock_verification.json"), res)
        L = ["# Test lock verification", "", f"Result: **{res['result']}**  ", f"Generated: {res['generated_at']}", ""]
        L += ["## Failures", ""] + ([f"- {f}" for f in res["failures"]] or ["- none"])
        c = res.get("checks", {})
        if c:
            L += ["", "## Checks", "", f"- Manifest checksum ok: {c.get('manifest_checksum_ok')}",
                  f"- Test files expected: {c.get('test_files_expected')}",
                  f"- Missing: {len(c.get('test_files_missing', []))}",
                  f"- Hash mismatch: {len(c.get('test_files_hash_mismatch', []))}",
                  f"- Unexpected files in test dir: {len(c.get('unexpected_files_in_test_dir', []))}",
                  f"- Train/val files byte-identical to test: {len(c.get('train_val_files_with_hash_in_test', []))}",
                  f"- Train/val files sharing a source group with test: {len(c.get('train_val_files_with_source_group_in_test', []))}"]
        write_text(reports_path(cfg, "test_lock_verification.md"), "\n".join(L) + "\n")
    return res


# ----------------------------------------------------------------------------- CLIs
def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Group-aware stratified split (70/15/15) with locked test set")
    ap.add_argument("--dry-run", action="store_true", help="produce reports but copy nothing")
    ap.add_argument("--force-rebuild", action="store_true", help="replace existing data/processed contents")
    ap.add_argument("--allow-fallback-groups", action="store_true",
                    help="accept unverified (per-image fallback) source groups")
    ap.add_argument("--allow-small-test-set", action="store_true",
                    help="allow fewer than the minimum images per class in the locked test set")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)
    setup_logging("tomato")
    cfg = load_config(args.config)
    try:
        res = run_split(cfg, seed=args.seed, dry_run=args.dry_run, force_rebuild=args.force_rebuild,
                        allow_fallback_groups=args.allow_fallback_groups, allow_small_test_set=args.allow_small_test_set)
    except (FileNotFoundError, ImportError) as exc:
        print(f"ERROR: {exc}")
        return 2
    for n in res.get("notes", []):
        print(f"NOTE: {n}")
    if res["status"] == "refused":
        print(banner_refused(res["refusal_reasons"]))
        return 1
    s = res["summary"]
    print(f"\nSplit {'DRY RUN' if res['status'] == 'dry_run' else 'COMPLETED'} (seed={s['seed']}, leakage check: {s['result']})")
    for sp, cc in s["class_counts_by_split"].items():
        print(f"  {sp:12s} {cc}  groups={s['group_count_by_split'][sp]}")
    for w in s["warnings"]:
        print(f"  warning: {w}")
    if res["status"] == "completed":
        print("\nImages COPIED to data/processed/. Test lock written to data/metadata/test_lock_manifest.json.")
        print("Next: python scripts/verify_locked_test.py")
    else:
        print("\nDry run only: nothing was copied. Reports are in reports/ (split_summary.md).")
    return 0


def banner_refused(reasons: List[str]) -> str:
    return "\nSPLIT REFUSED:\n" + "\n".join(f"  - {r}" for r in reasons) + "\n\nNothing was copied or modified."


def verify_main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Verify the locked test set")
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)
    setup_logging("tomato")
    res = verify_test_lock(load_config(args.config), write_report=True)
    print(f"\nTest lock verification: {res['result']}")
    for f in res["failures"]:
        print(f"  FAIL: {f}")
    print("Report: reports/test_lock_verification.md")
    return 0 if res["passed"] else 1
