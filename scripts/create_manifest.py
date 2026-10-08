#!/usr/bin/env python
"""CLI entry point: thin wrapper around src.manifest.main()."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.manifest import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
