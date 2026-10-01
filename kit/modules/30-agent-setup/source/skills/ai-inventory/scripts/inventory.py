#!/usr/bin/env python3
"""List the AI system inventory from brain notes tagged `ai-system`.

  python3 inventory.py [--brain DIR] [--status S] [--json]

Reads Markdown notes under $BRAIN_HOME (default ~/work/brain). A note belongs to the
inventory when its frontmatter tags contain `ai-system`. Fields are `- key: value` lines in
the body; the last value of a key wins, so appended "## Change" sections update the record.
Flags: review date passed or missing, no owner, risk tier unknown / high / prohibited,
in use without approval, data class or EU AI Act role missing. Standard library only, read-only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

STATUSES = ["requested", "approved", "pilot", "production", "suspended", "retired"]
IN_USE = ("pilot", "production")
CLASSES = ("PUBLIC", "INTERNAL", "CONFIDENTIAL", "CUSTOMER")
FIELD = re.compile(r"^\s*-\s+([a-z_]+):\s*(.*?)\s*$")
SKIP = {".git", ".brain", "node_modules", ".venv"}


def frontmatter(text: str) -> tuple[dict, str]:
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n?", text, re.S)
    if not m:
        return {}, text
    meta = {}
    lines = m.group(1).splitlines()
    for i, line in enumerate(lines):
        kv = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if not kv:
            continue
        key, val = kv.group(1), kv.group(2).strip()
        if key == "tags":
            if val.startswith("["):
                meta[key] = [t.strip().strip("'\"") for t in val.strip("[]").split(",") if t.strip()]
            else:  # block list: the "- item" lines right below
                meta[key] = []
                for ln in lines[i + 1:]:
                    if not ln.strip().startswith("- "):
                        break
                    meta[key].append(ln.strip()[2:].strip().strip("'\""))
        else:
            meta[key] = val.strip("'\"")
    return meta, text[m.end():]


def fields(body: str) -> dict:
    out = {}
    for line in body.splitlines():
        m = FIELD.match(line)
        if m and m.group(2) and not (m.group(2).startswith("<") and m.group(2).endswith(">")):
            out[m.group(1)] = m.group(2)
    return out


def notes(home: Path, tag: str):
    for path in sorted(home.rglob("*.md")):
        if SKIP.intersection(path.relative_to(home).parts):
            continue
        try:
            meta, body = frontmatter(path.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
        if tag in (meta.get("tags") or []):
            yield path, meta, fields(body)


def _date(v):
    try:
        return dt.date.fromisoformat(str(v)[:10])
    except ValueError:
        return None


def assess(path: Path, meta: dict, f: dict, home: Path, today: dt.date) -> dict:
    status = f.get("status", "requested").split()[0].lower()
    tier = f.get("risk_tier", "unknown").split()[0].lower()
    flags = []
    if status != "retired":
        review = _date(f.get("review_by"))
        if review is None:
            flags.append("no review date")
        elif review < today:
            flags.append(f"review overdue since {review}")
        if not f.get("owner") or "TODO" in f.get("owner", ""):
            flags.append("no owner")
        if tier == "prohibited":
            flags.append("PROHIBITED tier: stop use, report")
        elif tier == "high":
            flags.append("high-risk tier: deployer duties, escalate")
        elif tier not in ("limited", "minimal"):
            flags.append("risk tier unknown")
        if status in IN_USE and (not f.get("approved_by") or "TODO" in f.get("approved_by", "")):
            flags.append("in use without recorded approval")
        if f.get("data_class", "").split()[:1] and f["data_class"].split()[0].upper() not in CLASSES:
            flags.append("data class not one of " + "/".join(CLASSES))
        if not f.get("data_class"):
            flags.append("no data class")
        if not f.get("eu_ai_act_role"):
            flags.append("no EU AI Act role")
    return {
        "system": f.get("system") or str(meta.get("title") or path.stem).removeprefix("AI system: "),
        "path": str(path.relative_to(home)), "status": status, "provider": f.get("provider", ""),
        "model": f.get("model", ""), "data_class": f.get("data_class", ""), "risk_tier": tier,
        "owner": f.get("owner", ""), "review_by": f.get("review_by", ""), "flags": flags,
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--brain", default=os.environ.get("BRAIN_HOME") or str(Path.home() / "work" / "brain"))
    p.add_argument("--status", help="only this status")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    home = Path(a.brain).expanduser()
    if not home.is_dir():
        print(f"no brain at {home}; set BRAIN_HOME or pass --brain", file=sys.stderr)
        return 2
    today = dt.date.today()
    rows = [assess(pth, m, f, home, today) for pth, m, f in notes(home, "ai-system")]
    if a.status:
        rows = [r for r in rows if r["status"] == a.status]
    order = {s: i for i, s in enumerate(STATUSES)}
    rows.sort(key=lambda r: (order.get(r["status"], 99), r["system"].lower()))
    if a.json:
        print(json.dumps(rows, indent=2))
        return 0
    if not rows:
        print("no inventory notes (tag ai-system) found")
        return 0
    print("| System | Status | Provider | Model | Data class | Risk tier | Owner | Review by | Flags |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['system']} | {r['status']} | {r['provider']} | {r['model']} | {r['data_class']} | "
              f"{r['risk_tier']} | {r['owner']} | {r['review_by']} | {'; '.join(r['flags'])} |")
    print(f"\n{len(rows)} system(s); flagged: {sum(bool(r['flags']) for r in rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
