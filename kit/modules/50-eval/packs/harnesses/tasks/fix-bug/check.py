"""Pass when the tests pass and test_pager.py is unchanged. Runs in the task repo."""
import os
import subprocess
import sys
from pathlib import Path

task = Path(os.environ["EVAL_TASK_DIR"])
if Path("test_pager.py").read_bytes() != (task / "repo/test_pager.py").read_bytes():
    print("test_pager.py was changed"); sys.exit(1)
r = subprocess.run([sys.executable, "-m", "unittest", "-q", "test_pager"], capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print("tests fail: " + (r.stderr.strip().splitlines() or ["?"])[-1]); sys.exit(1)
print("tests pass, test file untouched")
