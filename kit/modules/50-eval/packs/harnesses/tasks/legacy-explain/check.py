"""Pass when docs/overview.md has the four sections, names both files and states the overtime
rule (40 hours, factor 1.5), and PAYROLL.cbl is unchanged."""
import os
import re
import sys
from pathlib import Path

task = Path(os.environ["EVAL_TASK_DIR"])
if Path("PAYROLL.cbl").read_bytes() != (task / "repo/PAYROLL.cbl").read_bytes():
    print("PAYROLL.cbl was changed"); sys.exit(1)
doc = Path("docs/overview.md")
if not doc.is_file():
    print("docs/overview.md missing"); sys.exit(1)
text = doc.read_text()
for sec in ("Purpose", "Inputs", "Outputs", "Business rules"):
    if not re.search(rf"^#+\s*{sec}\b", text, re.I | re.M):
        print(f"section missing: {sec}"); sys.exit(1)
if not re.search(r"EMPLOYEES\.DAT|EMPLOYEE-FILE", text) or not re.search(r"PAYROLL\.RPT|PAYROLL-REPORT", text):
    print("input or output file not named"); sys.exit(1)
if "40" not in text or not re.search(r"1[.,]5|150\s*%|time and a half", text, re.I):
    print("overtime rule (over 40 hours at 1.5x) not stated"); sys.exit(1)
print("overview complete")
