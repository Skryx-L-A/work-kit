"""Offline baseline for extraction.yaml: plain regexes, no model.

Reads the prompt on stdin, prints a JSON object. Only understands 1,234.50 style numbers.
"""
import json
import re
import sys

text = sys.stdin.read().split("Document:", 1)[-1]
out = {}
if m := re.search(r"\b([A-Z]{2,4}-\d+)\b", text):
    out["invoice_number"] = m.group(1)
if m := re.search(r"\b(\d{4}-\d{2}-\d{2})\b", text):
    out["date"] = m.group(1)
if m := re.search(r"(EUR|USD|GBP)\s*([\d,]+\.\d{2})", text):
    out["currency"] = m.group(1)
    out["total"] = float(m.group(2).replace(",", ""))
print(json.dumps(out))
