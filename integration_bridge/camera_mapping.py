"""Camera input mapping for mission simulation.

Assigns validated dataset images from software_model/data/processed/val/
to virtual plants according to configured mission proportions:
- 75% Healthy
- 10% Early Blight
- 10% Late Blight
- 5% Explicitly injected camera-unavailable simulation faults

Strictly excludes data/processed/test_locked/.
Input proportions control assigned image pool only; model predictions
are evaluated independently by the classifier.
"""
from __future__ import annotations

import json
import logging
import random
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image

logger = logging.getLogger("camera_mapping")

REPO_ROOT = Path(__file__).resolve().parent.parent
VAL_DIR = REPO_ROOT / "software_model" / "data" / "processed" / "val"
LOCKED_TEST_DIR = REPO_ROOT / "software_model" / "data" / "processed" / "test_locked"

SUPPORTED_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def get_validated_candidate_images() -> Dict[str, List[Path]]:
    """Enumerate and verify decodable validation images per class.
    
    Strictly excludes test_locked.
    Returns sorted lists of valid paths for deterministic sampling.
    """
    candidates: Dict[str, List[Path]] = {
        "healthy": [],
        "early_blight": [],
        "late_blight": []
    }

    if not VAL_DIR.is_dir():
        raise FileNotFoundError(f"Validation directory not found: {VAL_DIR}")

    for class_name in candidates.keys():
        class_folder = VAL_DIR / class_name
        if not class_folder.is_dir():
            continue
        
        valid_files: List[Path] = []
        for p in class_folder.iterdir():
            if p.suffix.lower() in SUPPORTED_EXTS and not p.name.startswith("."):
                # Ensure the file is inside val and NOT in test_locked
                if str(LOCKED_TEST_DIR) in str(p.resolve()):
                    raise RuntimeError(f"Locked test image detected and rejected: {p}")
                # Verify readability
                try:
                    with Image.open(p) as img:
                        img.verify()
                    valid_files.append(p)
                except Exception as exc:
                    logger.warning(f"Skipping unreadable validation image {p}: {exc}")

        # Deterministic sort
        candidates[class_name] = sorted(valid_files, key=lambda x: x.name)
        if not candidates[class_name]:
            raise RuntimeError(f"No readable validation images found for class: {class_name}")

    return candidates


def compute_integer_proportions(total_plants: int) -> Tuple[int, int, int, int]:
    """Calculate integer allocation preserving total count sum == N with no negative counts.
    
    Returns (n_healthy, n_early_blight, n_late_blight, n_camera_fault).
    """
    if total_plants < 0:
        raise ValueError(f"total_plants must be non-negative, got {total_plants}")
    if total_plants == 0:
        return 0, 0, 0, 0

    n_healthy = int(round(0.75 * total_plants))
    n_eb = int(round(0.10 * total_plants))
    n_lb = int(round(0.10 * total_plants))
    n_err = total_plants - (n_healthy + n_eb + n_lb)

    # Edge case adjustment for very small total_plants (e.g. 1..3)
    counts = [n_healthy, n_eb, n_lb, n_err]
    while any(c < 0 for c in counts):
        for i in range(len(counts)):
            if counts[i] < 0:
                # Borrow from largest positive count
                max_idx = max(range(len(counts)), key=lambda k: counts[k])
                counts[max_idx] -= 1
                counts[i] += 1

    assert sum(counts) == total_plants, f"Allocation sum {sum(counts)} != {total_plants}"
    assert all(c >= 0 for c in counts), f"Negative counts in allocation: {counts}"
    return counts[0], counts[1], counts[2], counts[3]


def generate_mission_camera_mapping(
    plant_ids: List[str],
    seed: Optional[int] = None,
    output_path: Optional[Path] = None
) -> Dict[str, Any]:
    """Assign candidate images to every plant ID deterministically from seed.
    
    Saves mapping with audit metadata.
    """
    if seed is None:
        seed = random.randint(100000, 999999)

    rng = random.Random(seed)
    n_plants = len(plant_ids)
    n_h, n_eb, n_lb, n_err = compute_integer_proportions(n_plants)

    candidates = get_validated_candidate_images()

    # Build pool of input specs
    input_pool: List[Dict[str, Any]] = []

    # Healthy
    h_choices = [candidates["healthy"][i % len(candidates["healthy"])] for i in range(n_h)]
    for p in h_choices:
        input_pool.append({
            "input_class": "healthy",
            "image_path": str(p.resolve()),
            "relative_path": p.relative_to(REPO_ROOT).as_posix(),
            "image_name": p.name,
            "is_injected_fault": False
        })

    # Early Blight
    eb_choices = [candidates["early_blight"][i % len(candidates["early_blight"])] for i in range(n_eb)]
    for p in eb_choices:
        input_pool.append({
            "input_class": "early_blight",
            "image_path": str(p.resolve()),
            "relative_path": p.relative_to(REPO_ROOT).as_posix(),
            "image_name": p.name,
            "is_injected_fault": False
        })

    # Late Blight
    lb_choices = [candidates["late_blight"][i % len(candidates["late_blight"])] for i in range(n_lb)]
    for p in lb_choices:
        input_pool.append({
            "input_class": "late_blight",
            "image_path": str(p.resolve()),
            "relative_path": p.relative_to(REPO_ROOT).as_posix(),
            "image_name": p.name,
            "is_injected_fault": False
        })

    # Injected Camera Faults (5%)
    for i in range(n_err):
        fault_path = REPO_ROOT / "integration_bridge" / "io" / f"INJECTED_FAULT_CAMERA_TIMEOUT_{i+1:03d}.jpg"
        input_pool.append({
            "input_class": "camera_unavailable",
            "image_path": str(fault_path.resolve()),
            "relative_path": fault_path.relative_to(REPO_ROOT).as_posix(),
            "image_name": fault_path.name,
            "is_injected_fault": True
        })

    # Shuffle pool deterministically using mission seed
    rng.shuffle(input_pool)

    # Assign 1:1 to sorted plant IDs
    sorted_ids = sorted(plant_ids)
    mapping: Dict[str, Any] = {}
    for pid, spec in zip(sorted_ids, input_pool):
        mapping[pid] = {
            "plant_id": pid,
            **spec
        }

    result = {
        "seed": seed,
        "total_plants": n_plants,
        "proportions": {
            "target": {"healthy": 0.75, "early_blight": 0.10, "late_blight": 0.10, "camera_unavailable": 0.05},
            "actual_counts": {
                "healthy": n_h,
                "early_blight": n_eb,
                "late_blight": n_lb,
                "camera_unavailable": n_err
            },
            "actual_percentages": {
                "healthy": round(100.0 * n_h / max(1, n_plants), 1),
                "early_blight": round(100.0 * n_eb / max(1, n_plants), 1),
                "late_blight": round(100.0 * n_lb / max(1, n_plants), 1),
                "camera_unavailable": round(100.0 * n_err / max(1, n_plants), 1)
            }
        },
        "disclaimer": "Controlled input proportions; not model prediction proportions. Image re-used for Pass 2 reassessment.",
        "mapping": mapping
    }

    if output_path is not None:
        out_p = Path(output_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        with out_p.open("w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)

    return result
