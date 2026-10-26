#!/usr/bin/env python
"""CLI entry point: thin wrapper around src.evaluate.main()."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.evaluate import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
