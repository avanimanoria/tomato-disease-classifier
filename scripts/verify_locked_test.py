#!/usr/bin/env python
"""CLI entry point: verify the locked test set (hashes, overlap, group separation)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.split_dataset import verify_main  # noqa: E402

if __name__ == "__main__":
    sys.exit(verify_main())
