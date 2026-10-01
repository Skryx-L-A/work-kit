#!/usr/bin/env python3
"""Script graders for the model pack. Response on stdin; exit 0 = pass; last line = reason.
Usage: checks.py json-fields k=v ... | max-words N | bullets N | python-slugify | sql"""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import sys
import tempfile


def fail(msg: str) -> None:
    print(msg)
    sys.exit(1)


def extract_json(text: str):
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fence:
        text = fence.group(1)
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        fail("no JSON object")
    return json.loads(text[start:end + 1])


def code_block(text: str, lang: str) -> str:
    m = re.search(rf"```(?:{lang})?\s*\n(.*?)```", text, re.S | re.I)
    return (m.group(1) if m else text).strip()


def json_fields(text: str, pairs: list[str]) -> None:
    data = extract_json(text)
    for pair in pairs:
        key, _, want = pair.partition("=")
        got = data.get(key)
        try:
            ok = abs(float(got) - float(want)) < 1e-6
        except (TypeError, ValueError):
            ok = str(got).strip() == want
        if not ok:
            fail(f"{key}: expected {want}, got {got!r}")
    print("all fields match")


def max_words(text: str, n: int) -> None:
    words = len(text.split())
    if words > n:
        fail(f"{words} words, limit {n}")
    print(f"{words} words")


def bullets(text: str, n: int) -> None:
    lines = [l for l in text.strip().splitlines() if l.strip()]
    if len(lines) != n or not all(l.lstrip().startswith("- ") for l in lines):
        fail(f"expected {n} lines starting with '- ', got {len(lines)} lines")
    print(f"{n} bullet lines")


def python_slugify(text: str) -> None:
    code = code_block(text, "python")
    tests = '''
assert slugify("Hello, World!") == "hello-world"
assert slugify("  --Legacy  COBOL__Migration 2026--  ") == "legacy-cobol-migration-2026"
assert slugify("äöü") == ""
assert slugify("a") == "a"
print("tests passed")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(code + "\n" + tests)
    r = subprocess.run([sys.executable, fh.name], capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        fail("tests failed: " + (r.stderr.strip().splitlines() or ["?"])[-1])
    print("tests passed")


def sql(text: str) -> None:
    query = code_block(text, "sql").rstrip().rstrip(";")
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE orders(id INTEGER, customer TEXT, amount REAL, status TEXT)")
    db.executemany("INSERT INTO orders VALUES (?,?,?,?)", [
        (1, "Nord AG", 100.0, "paid"), (2, "Nord AG", 50.0, "open"), (3, "Sued KG", 300.0, "paid"),
        (4, "West GmbH", 80.0, "paid"), (5, "West GmbH", 90.0, "paid"), (6, "Ost eG", 999.0, "cancelled")])
    try:
        cur = db.execute(query)
    except sqlite3.Error as exc:
        fail(f"SQL error: {exc}")
    cols = [d[0].lower() for d in cur.description or []]
    rows = [tuple(r) for r in cur.fetchall()]
    want = [("Sued KG", 300.0), ("West GmbH", 170.0), ("Nord AG", 100.0)]
    if cols[:2] != ["customer", "total"]:
        fail(f"columns {cols}, expected customer, total")
    if [(r[0], float(r[1])) for r in rows] != want:
        fail(f"rows {rows}")
    print("query result matches")


def main() -> None:
    text = sys.stdin.read()
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "json-fields":
        json_fields(text, args)
    elif cmd == "max-words":
        max_words(text, int(args[0]))
    elif cmd == "bullets":
        bullets(text, int(args[0]))
    elif cmd == "python-slugify":
        python_slugify(text)
    elif cmd == "sql":
        sql(text)
    else:
        fail(f"unknown check {cmd}")


if __name__ == "__main__":
    main()
