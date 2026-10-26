"""True SHA-256 integrity verification script.

Reads integration_bridge/file_manifest_checksums.csv and recomputes the SHA-256
hash and file size for every file across software_model/ and drone_simu/.
Reports all hash mismatches, size differences, added files, deleted files,
and unreadable files.
"""
from __future__ import annotations

import csv
import hashlib
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Ensure bytecode is never written to protected directories
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "integration_bridge" / "file_manifest_checksums.csv"
PROTECTED_DIRS = [REPO_ROOT / "drone_simu", REPO_ROOT / "software_model"]


def compute_sha256(path: Path) -> str:
    """Compute true SHA-256 checksum of a file in 1MB chunks."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1048576):
            h.update(chunk)
    return h.hexdigest()


def verify_file(rel_path: str, expected_hash: str, expected_size: int) -> dict:
    full_path = REPO_ROOT / rel_path
    if not full_path.exists():
        return {"status": "DELETED", "path": rel_path, "detail": "File missing on disk"}

    try:
        actual_size = full_path.stat().st_size
    except Exception as exc:
        return {"status": "UNREADABLE", "path": rel_path, "detail": f"Stat error: {exc}"}

    if actual_size != expected_size:
        return {
            "status": "MODIFIED_SIZE",
            "path": rel_path,
            "detail": f"Size changed: expected {expected_size}, got {actual_size}"
        }

    try:
        actual_hash = compute_sha256(full_path)
    except Exception as exc:
        return {"status": "UNREADABLE", "path": rel_path, "detail": f"Read error: {exc}"}

    if actual_hash != expected_hash:
        return {
            "status": "MODIFIED_HASH",
            "path": rel_path,
            "detail": f"Hash mismatch: expected {expected_hash[:12]}..., got {actual_hash[:12]}..."
        }

    return {"status": "OK", "path": rel_path, "detail": None}


def main():
    if not MANIFEST_PATH.exists():
        print(f"ERROR: Baseline manifest not found at {MANIFEST_PATH}", file=sys.stderr)
        return 1

    print(f"Loading baseline manifest from {MANIFEST_PATH}...")
    baseline = {}
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)  # Header
        for row in reader:
            if len(row) >= 3:
                baseline[row[0]] = (row[1], int(row[2]))

    print(f"Loaded {len(baseline)} entries from baseline manifest.")

    # 1. Scan current files on disk in protected directories
    current_files = set()
    for pdir in PROTECTED_DIRS:
        if pdir.exists():
            for p in pdir.rglob("*"):
                if p.is_file():
                    current_files.add(p.relative_to(REPO_ROOT).as_posix())

    print(f"Discovered {len(current_files)} files currently in protected directories.")

    # 2. Check for added files (files on disk not in manifest)
    added = current_files - set(baseline.keys())

    # 3. Check all baseline files with multithreading
    tasks = [(rel, baseline[rel][0], baseline[rel][1]) for rel in baseline]

    print("Computing true SHA-256 hashes across all baseline files...")
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda t: verify_file(*t), tasks))

    duration = time.time() - t0

    # Tally results
    counts = {"OK": 0, "MODIFIED_HASH": 0, "MODIFIED_SIZE": 0, "DELETED": 0, "UNREADABLE": 0}
    violations = []

    for r in results:
        status = r["status"]
        counts[status] = counts.get(status, 0) + 1
        if status != "OK":
            violations.append(r)

    for add_path in added:
        violations.append({"status": "ADDED", "path": add_path, "detail": "Untracked file added to protected dir"})

    counts["ADDED"] = len(added)

    print("\n=======================================================")
    print("PROTECTED DIRECTORY INTEGRITY VERIFICATION SUMMARY")
    print("=======================================================")
    print(f"Execution time:     {duration:.1f} s")
    print(f"Baseline files:     {len(baseline)}")
    print(f"Unmodified (OK):    {counts['OK']}")
    print(f"Hash mismatches:    {counts['MODIFIED_HASH']}")
    print(f"Size mismatches:    {counts['MODIFIED_SIZE']}")
    print(f"Deleted files:      {counts['DELETED']}")
    print(f"Added files:        {counts['ADDED']}")
    print(f"Unreadable files:   {counts['UNREADABLE']}")
    print("=======================================================")

    if violations:
        print(f"\nINTEGRITY VIOLATION DETECTED ({len(violations)} issues):")
        for v in violations[:20]:
            print(f"  [{v['status']}] {v['path']} - {v.get('detail')}")
        if len(violations) > 20:
            print(f"  ... and {len(violations) - 20} more.")
        return 1

    print("RESULT: SUCCESS - All protected files match their baseline SHA-256 hashes exactly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
