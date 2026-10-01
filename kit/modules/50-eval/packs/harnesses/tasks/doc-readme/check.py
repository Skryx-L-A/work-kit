"""Pass when README.md has a Usage heading, an example code block with csvtool.py, every option,
and csvtool.py is unchanged."""
import os
import re
import sys
from pathlib import Path

task = Path(os.environ["EVAL_TASK_DIR"])
if Path("csvtool.py").read_bytes() != (task / "repo/csvtool.py").read_bytes():
    print("csvtool.py was changed"); sys.exit(1)
text = Path("README.md").read_text()
if not re.search(r"^#+\s*usage\b", text, re.I | re.M):
    print("no Usage heading"); sys.exit(1)
blocks = re.findall(r"```[^\n]*\n(.*?)```", text, re.S)
if not any("csvtool.py" in b for b in blocks):
    print("no example command in a code block"); sys.exit(1)
missing = [o for o in ("--input", "--limit", "--format", "--verbose") if o not in text]
if missing:
    print("options not documented: " + ", ".join(missing)); sys.exit(1)
print("usage section complete")
