import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

from src.duplicate_detection import (NEAR_COLUMNS, REVIEW_STATUS, build_clusters, find_exact_duplicates,
                                     find_label_conflicts, find_near_duplicates, popcount64)
from src.manifest import build_manifest


def test_popcount():
    assert popcount64(np.array([0, 1, 3, 2**64 - 1], dtype=np.uint64)).tolist() == [0, 1, 2, 64]


def test_exact_duplicates_detected_within_and_across_classes(project):
    root = Path(project["_root"]) / "data/raw"
    shutil.copy(root / "healthy/group_00/img_00_00.png", root / "healthy/group_03/copy_same_class.png")
    shutil.copy(root / "early_blight/group_00/img_00_00.png", root / "late_blight/group_01/copy_other_class.png")
    df = build_manifest(project)
    exact = find_exact_duplicates(df)
    kinds = sorted(exact["kind"])
    assert kinds == ["across_classes", "within_class_across_groups"]
    assert (exact["n_files"] == 2).all()


def test_near_duplicate_report_format_and_no_deletion(project):
    root = Path(project["_root"]) / "data/raw"
    src = root / "healthy/group_00/img_00_00.png"
    with Image.open(src) as im:
        ImageEnhance.Brightness(im).enhance(1.03).save(root / "healthy/group_05/near_copy.jpg", quality=90)
    df = build_manifest(project)
    near = find_near_duplicates(df[df.is_valid_image], threshold=6)
    assert list(near.columns) == NEAR_COLUMNS
    pair = near[near["relative_path_b"].str.contains("near_copy") | near["relative_path_a"].str.contains("near_copy")]
    assert len(pair) == 1 and pair.iloc[0]["status"] == REVIEW_STATUS
    assert pair.iloc[0]["hamming_distance"] <= 6 and bool(pair.iloc[0]["cross_group"])
    assert (root / "healthy/group_05/near_copy.jpg").exists() and src.exists()


def test_label_conflicts_and_clusters(project):
    root = Path(project["_root"]) / "data/raw"
    shutil.copy(root / "early_blight/group_00/img_00_00.png", root / "late_blight/group_01/dup.png")
    df = build_manifest(project)
    exact = find_exact_duplicates(df)
    conflicts = find_label_conflicts(df, exact, find_near_duplicates(df, 6))
    assert len(conflicts) == 2 and (conflicts["severity"] == "CRITICAL").all()
    clusters = build_clusters(df, find_near_duplicates(df, 6))
    # same folder group => same cluster
    g0 = df[df.source_group == "healthy/group_00"]["image_id"]
    assert len({clusters[i] for i in g0}) == 1
