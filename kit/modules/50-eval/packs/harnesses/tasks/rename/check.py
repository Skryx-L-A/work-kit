"""Pass when calc is gone, calculate_total exists and main.py prints the original output."""
import re
import subprocess
import sys
from pathlib import Path

expected = "Nord AG: 30.34 EUR\nSued KG: 14.88 EUR\ntotal 38.0\n"
for f in Path(".").rglob("*.py"):
    if ".git" in f.parts:
        continue
    if re.search(r"\bcalc\s*\(", f.read_text()):
        print(f"old name still used in {f}"); sys.exit(1)
if not re.search(r"^def calculate_total\(", Path("billing/calc.py").read_text(), re.M):
    print("calculate_total not defined in billing/calc.py"); sys.exit(1)
r = subprocess.run([sys.executable, "main.py"], capture_output=True, text=True, timeout=30)
if r.returncode != 0 or r.stdout != expected:
    detail = (r.stderr.strip().splitlines() or r.stdout.strip().splitlines() or ["no output"])[-1]
    print("main.py output changed or failed: " + detail[:120]); sys.exit(1)
print("renamed everywhere, output unchanged")
