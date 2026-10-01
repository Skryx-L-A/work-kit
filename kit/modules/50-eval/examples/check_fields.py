"""Example script grader: the response JSON must contain the expected fields.

Usage in a suite:  command: "{python} check_fields.py '{\"total\": 1234.5}'"
Numbers are compared with a tolerance of 0.005, everything else exactly.
"""
import json
import re
import sys

expected = json.loads(sys.argv[1])
text = sys.stdin.read()
match = re.search(r"\{.*\}", text, re.S)
try:
    data = json.loads(match.group(0)) if match else {}
except json.JSONDecodeError:
    data = {}
bad = []
for key, want in expected.items():
    got = data.get(key)
    if isinstance(want, (int, float)) and isinstance(got, (int, float)):
        ok = abs(got - want) <= 0.005
    else:
        ok = got == want
    if not ok:
        bad.append(f"{key}: got {got!r}, want {want!r}")
if bad:
    print("; ".join(bad))
    sys.exit(1)
print("fields match")
