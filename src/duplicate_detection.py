"""Exact + near-duplicate detection and duplicate/group clustering.

Nothing here deletes or modifies images. Near duplicates are only ever flagged for MANUAL REVIEW.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

import numpy as np
import pandas as pd

from .utils import IMAGEHASH_INSTALL_HINT

REVIEW_STATUS = "manual review required"

_M1 = np.uint64(0x5555555555555555)
_M2 = np.uint64(0x3333333333333333)
_M4 = np.uint64(0x0F0F0F0F0F0F0F0F)
_H01 = np.uint64(0x0101010101010101)


def require_imagehash() -> None:
    try:
        import imagehash  # noqa: F401
    except ImportError as exc:
        raise ImportError("The 'imagehash' package is required for near-duplicate detection.\n"
                          f"Install it with:  {IMAGEHASH_INSTALL_HINT}") from exc


def popcount64(x: np.ndarray) -> np.ndarray:
    """Vectorised population count for uint64 arrays."""
    x = x.astype(np.uint64, copy=True)
    x = x - ((x >> np.uint64(1)) & _M1)
    x = (x & _M2) + ((x >> np.uint64(2)) & _M2)
    x = (x + (x >> np.uint64(4))) & _M4
    return (x * _H01) >> np.uint64(56)


def hex_to_uint64(h: str) -> int:
    return int(h, 16)


def hamming_hex(a: str, b: str) -> int:
    return bin(int(a, 16) ^ int(b, 16)).count("1")


# --------------------------------------------------------------------------- exact duplicates
EXACT_COLUMNS = ["sha256_hash", "n_files", "kind", "classes", "source_groups", "relative_paths"]


def find_exact_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    """One row per set of byte-identical files. kind: 'across_classes' (CRITICAL label conflict),
    'within_class_across_groups', or 'within_class_same_group'."""
    d = df[df["sha256_hash"] != ""]
    rows = []
    for sha, g in d.groupby("sha256_hash"):
        if len(g) < 2:
            continue
        classes = sorted(g["class_label"].unique())
        groups = sorted(g["source_group"].unique())
        if len(classes) > 1:
            kind = "across_classes"
        elif len(groups) > 1:
            kind = "within_class_across_groups"
        else:
            kind = "within_class_same_group"
        rows.append({"sha256_hash": sha, "n_files": len(g), "kind": kind, "classes": ";".join(classes),
                     "source_groups": ";".join(groups), "relative_paths": ";".join(sorted(g["relative_path"]))})
    return pd.DataFrame(rows, columns=EXACT_COLUMNS)


# --------------------------------------------------------------------------- near duplicates
NEAR_COLUMNS = ["image_id_a", "relative_path_a", "class_a", "source_group_a",
                "image_id_b", "relative_path_b", "class_b", "source_group_b",
                "hamming_distance", "cross_class", "cross_group", "status"]


def near_duplicate_index_pairs(hashes: List[str], threshold: int, chunk: int = 256) -> List[Tuple[int, int, int]]:
    """All index pairs (i<j) whose perceptual hashes are within `threshold` bits. Exact O(n^2), chunked."""
    valid_idx = [i for i, h in enumerate(hashes) if h]
    if len(valid_idx) < 2:
        return []
    arr = np.array([hex_to_uint64(hashes[i]) for i in valid_idx], dtype=np.uint64)
    idx = np.array(valid_idx)
    out: List[Tuple[int, int, int]] = []
    n = len(arr)
    for start in range(0, n, chunk):
        block = arr[start:start + chunk]
        x = block[:, None] ^ arr[None, :]
        dist = popcount64(x)
        rows, cols = np.nonzero(dist <= threshold)
        for r, c in zip(rows, cols):
            gi = start + r
            if c > gi:  # upper triangle only
                out.append((int(idx[gi]), int(idx[c]), int(dist[r, c])))
    return out


def find_near_duplicates(df: pd.DataFrame, threshold: int) -> pd.DataFrame:
    """Near-identical pairs by perceptual hash (excluding byte-identical pairs, which are reported as exact)."""
    require_imagehash()
    d = df.reset_index(drop=True)
    pairs = near_duplicate_index_pairs(d["perceptual_hash"].tolist(), threshold)
    rows = []
    for i, j, dist in pairs:
        a, b = d.iloc[i], d.iloc[j]
        if a["sha256_hash"] == b["sha256_hash"]:
            continue
        rows.append({
            "image_id_a": a["image_id"], "relative_path_a": a["relative_path"], "class_a": a["class_label"],
            "source_group_a": a["source_group"], "image_id_b": b["image_id"], "relative_path_b": b["relative_path"],
            "class_b": b["class_label"], "source_group_b": b["source_group"], "hamming_distance": dist,
            "cross_class": a["class_label"] != b["class_label"], "cross_group": a["source_group"] != b["source_group"],
            "status": REVIEW_STATUS})
    return pd.DataFrame(rows, columns=NEAR_COLUMNS)


# --------------------------------------------------------------------------- label conflicts
CONFLICT_COLUMNS = ["conflict_type", "severity", "image_id", "relative_path", "class_label", "other_ids",
                    "other_classes", "detail", "status"]


def find_label_conflicts(df: pd.DataFrame, exact: pd.DataFrame, near: pd.DataFrame) -> pd.DataFrame:
    """Candidates for label conflicts: identical files with different labels (CRITICAL) and
    near-identical images with different labels (needs review)."""
    path_to = df.set_index("relative_path")
    rows = []
    for _, r in exact[exact["kind"] == "across_classes"].iterrows():
        paths = r["relative_paths"].split(";")
        for p in paths:
            me = path_to.loc[p]
            others = [q for q in paths if q != p]
            rows.append({"conflict_type": "identical_file_different_labels", "severity": "CRITICAL",
                         "image_id": me["image_id"], "relative_path": p, "class_label": me["class_label"],
                         "other_ids": ";".join(path_to.loc[q]["image_id"] for q in others),
                         "other_classes": ";".join(path_to.loc[q]["class_label"] for q in others),
                         "detail": f"sha256={r['sha256_hash'][:16]}...", "status": REVIEW_STATUS})
    if len(near):
        for _, r in near[near["cross_class"]].iterrows():
            for me_id, me_p, me_c, ot_id, ot_c in (
                    (r.image_id_a, r.relative_path_a, r.class_a, r.image_id_b, r.class_b),
                    (r.image_id_b, r.relative_path_b, r.class_b, r.image_id_a, r.class_a)):
                rows.append({"conflict_type": "near_identical_image_different_labels", "severity": "WARNING",
                             "image_id": me_id, "relative_path": me_p, "class_label": me_c, "other_ids": ot_id,
                             "other_classes": ot_c, "detail": f"hamming={r.hamming_distance}",
                             "status": REVIEW_STATUS})
    return pd.DataFrame(rows, columns=CONFLICT_COLUMNS)


# --------------------------------------------------------------------------- clustering
class UnionFind:
    def __init__(self, items):
        self.parent = {i: i for i in items}

    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[max(ra, rb)] = min(ra, rb)  # deterministic root


def build_clusters(df: pd.DataFrame, near_pairs: pd.DataFrame) -> Dict[str, str]:
    """Map image_id -> cluster_id. Images are linked (and so must share a split) when they share a
    source_group, are byte-identical, or are near-duplicates."""
    ids = df["image_id"].tolist()
    uf = UnionFind(ids)
    for col in ("source_group", "sha256_hash"):
        for _, g in df[df[col] != ""].groupby(col):
            members = g["image_id"].tolist()
            for m in members[1:]:
                uf.union(members[0], m)
    if near_pairs is not None and len(near_pairs):
        valid = set(ids)
        for _, r in near_pairs.iterrows():
            if r.image_id_a in valid and r.image_id_b in valid:
                uf.union(r.image_id_a, r.image_id_b)
    return {i: "cluster_" + uf.find(i)[4:] for i in ids}
