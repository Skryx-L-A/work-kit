#!/usr/bin/env python3
"""Stand-in harness for testing the pack without an AI tool.
Usage: fake_harness.py good|noop   good = copy tasks/<task>/solution into the repo; noop = do nothing."""
import os
import shutil
import sys
from pathlib import Path

if sys.argv[1] == "good":
    src = Path(os.environ["EVAL_TASK_DIR"]) / "solution"
    shutil.copytree(src, Path.cwd(), dirs_exist_ok=True)
print(f"fake harness ({sys.argv[1]}) done")
