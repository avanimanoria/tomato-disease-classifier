import shutil
from pathlib import Path

import pandas as pd

from src.config_loader import path_of, reports_path
from src.manifest import build_manifest
from src.split_dataset import FALLBACK_WARNING, run_split, split_dir
from tests.conftest import CLASSES, make_cfg, populate


def _sm(cfg):
    return pd.read_csv(reports_path(cfg, "split_manifest.csv"), dtype=str, keep_default_na=False)


def test_split_completes_and_source_groups_never_cross_splits(split_project):
    sm = _sm(split_project)
    sm = sm[sm["split"].isin(["train", "val", "test_locked"])]
    assert sm.groupby("source_group")["split"].nunique().max() == 1
    for c in CLASSES:
        for s in ("train", "val", "test_locked"):
            assert ((sm.split == s) & (sm.class_label == c)).sum() > 0
    for s in ("train", "val", "test_locked"):  # files really copied
        assert len(list(split_dir(split_project, s).rglob("*.png"))) == (sm.split == s).sum()
    assert (Path(split_project["_root"]) / "data/raw/healthy/group_00/img_00_00.png").exists()


def test_no_exact_hash_crosses_splits_even_for_duplicates_in_different_groups(project):
    root = Path(project["_root"]) / "data/raw"
    for g in (1, 2, 3):  # same bytes placed in 3 different groups of the same class
        shutil.copy(root / "healthy/group_00/img_00_00.png", root / f"healthy/group_0{g}/dup.png")
    build_manifest(project)
    res = run_split(project)
    assert res["status"] == "completed" and res["leakage"]["passed"]
    sm = _sm(project)
    sm = sm[sm["split"].isin(["train", "val", "test_locked"])]
    assert sm.groupby("sha256_hash")["split"].nunique().max() == 1
    # the duplicate-linked groups were merged into one cluster -> one split
    linked = sm[sm.source_group.isin([f"healthy/group_0{g}" for g in range(4)])]
    assert linked["split"].nunique() == 1


def test_split_fails_if_a_class_is_missing_from_a_split(tmp_path):
    cfg = make_cfg(tmp_path)
    populate(cfg, {"early_blight": 8, "healthy": 8, "late_blight": 1})  # one group can only live in ONE split
    build_manifest(cfg)
    res = run_split(cfg)
    assert res["status"] == "refused"
    assert any("missing" in r.lower() for r in res["refusal_reasons"])
    assert not list(split_dir(cfg, "train").rglob("*.png"))  # nothing copied


def test_fallback_groups_require_explicit_flag(tmp_path):
    cfg = make_cfg(tmp_path)
    populate(cfg, {c: 1 for c in CLASSES}, imgs_per_group=30, flat=True)
    build_manifest(cfg)
    res = run_split(cfg)
    assert res["status"] == "refused" and "FALLBACK" in res["refusal_reasons"][0]
    res = run_split(cfg, allow_fallback_groups=True)
    assert res["status"] == "completed" and res["summary"]["group_metadata_verified"] is False
    assert "not verified" in FALLBACK_WARNING


def test_dry_run_copies_nothing_but_writes_reports(project):
    build_manifest(project)
    res = run_split(project, dry_run=True)
    assert res["status"] == "dry_run"
    assert not list(split_dir(project, "train").rglob("*.png"))
    assert not path_of(project, "test_lock_manifest").exists()
    assert reports_path(project, "split_summary.json").exists() and reports_path(project, "split_leakage_check.md").exists()


def test_no_overwrite_without_force_rebuild(split_project):
    assert run_split(split_project)["status"] == "refused"
    assert run_split(split_project, force_rebuild=True)["status"] == "completed"


def test_small_test_set_refused_unless_allowed(tmp_path):
    cfg = make_cfg(tmp_path, min_test=20)
    populate(cfg, {c: 8 for c in CLASSES})
    build_manifest(cfg)
    res = run_split(cfg)
    assert res["status"] == "refused" and any("fewer than 20" in r for r in res["refusal_reasons"])
    assert run_split(cfg, allow_small_test_set=True)["status"] == "completed"


def test_label_conflict_candidates_are_excluded_not_split(project):
    root = Path(project["_root"]) / "data/raw"
    shutil.copy(root / "early_blight/group_00/img_00_00.png", root / "late_blight/group_01/dup.png")
    build_manifest(project)
    res = run_split(project)
    assert res["status"] == "completed"
    sm = _sm(project)
    assert (sm["split"] == "excluded_label_conflict_candidate").sum() == 2
