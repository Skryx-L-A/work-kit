"""Pass when test_duration.py exists and passes, duration.py is unchanged, and the tests catch
two planted bugs (each mutant must make the tests fail). Runs in the task repo."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

task = Path(os.environ["EVAL_TASK_DIR"])
orig = (task / "repo/duration.py").read_text()
if not Path("test_duration.py").is_file():
    print("test_duration.py missing"); sys.exit(1)
if Path("duration.py").read_text() != orig:
    print("duration.py was changed"); sys.exit(1)


def tests_pass():
    r = subprocess.run([sys.executable, "-m", "unittest", "-q", "test_duration"], capture_output=True, text=True, timeout=60)
    return r.returncode == 0


if not tests_pass():
    print("new tests fail on the original code"); sys.exit(1)
mutants = {
    "minutes counted as seconds": orig.replace('"m": 60', '"m": 1'),
    "trailing garbage accepted": orig.replace("    if pos != len(text):\n        raise ValueError(f\"bad duration: {text!r}\")\n", ""),
}
shutil.copy("duration.py", "duration.py.orig")
caught = []
try:
    for name, code in mutants.items():
        Path("duration.py").write_text(code)
        caught.append((name, not tests_pass()))
finally:
    shutil.move("duration.py.orig", "duration.py")
missed = [n for n, c in caught if not c]
if missed:
    print("tests miss planted bug(s): " + ", ".join(missed)); sys.exit(1)
print("tests pass and catch both planted bugs")
