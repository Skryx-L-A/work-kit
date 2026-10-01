#!/usr/bin/env python3
"""List the AI use-case portfolio from brain notes tagged `ai-use-case`.

  python3 portfolio.py [--brain DIR] [--stage S] [--json]

Reads Markdown notes under $BRAIN_HOME (default ~/work/brain). A note belongs to the
portfolio when its frontmatter tags contain `ai-use-case`. Fields are `- key: value` lines
in the body; the last value of a key wins, so appended gate sections update the record.
Flags: overdue gate, missing baseline or kill criteria after intake, composite below 2.5
beyond assessment, pilot running longer than 12 weeks. Standard library only, read-only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

STAGES = ["intake", "assessment", "pilot", "production", "operations", "parked", "killed", "retired"]
DIMENSIONS = ("value", "feasibility", "risk", "reusability")
MIN_COMPOSITE = 2.5
PILOT_WEEKS = 12
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


def _num(v):
    try:
        return float(str(v).split()[0])
    except (ValueError, IndexError):
        return None


def _date(v):
    try:
        return dt.date.fromisoformat(str(v)[:10])
    except ValueError:
        return None


def assess(path: Path, meta: dict, f: dict, home: Path, today: dt.date) -> dict:
    stage = f.get("stage", "intake").split()[0].lower()
    scores = {d: _num(f.get(d)) for d in DIMENSIONS}
    composite = _num(f.get("composite"))
    if composite is None and all(v is not None for v in scores.values()):
        composite = round(sum(scores.values()) / len(scores), 2)
    flags = []
    active = stage in ("assessment", "pilot", "production", "operations")
    gate = _date(f.get("next_gate"))
    if gate and gate < today and stage not in ("killed", "retired", "parked"):
        flags.append(f"gate overdue since {gate}")
    if stage in ("pilot", "production", "operations"):
        if not f.get("baseline"):
            flags.append("no baseline")
        if composite is not None and composite < MIN_COMPOSITE:
            flags.append(f"composite {composite} < {MIN_COMPOSITE}")
    if active and not f.get("kill_criteria"):
        flags.append("no kill criteria")
    since = _date(f.get("stage_since"))
    if stage == "pilot" and since and (today - since).days > PILOT_WEEKS * 7:
        flags.append(f"pilot > {PILOT_WEEKS} weeks (decide: build or kill)")
    if scores["risk"] is not None and scores["risk"] <= 1 and stage not in ("killed", "parked"):
        flags.append("risk score 1: stop or escalate")
    return {
        "title": str(meta.get("title") or path.stem).removeprefix("Use case: "),
        "path": str(path.relative_to(home)), "stage": stage,
        "composite": composite, **{d: scores[d] for d in DIMENSIONS},
        "owner": f.get("owner", ""), "next_gate": f.get("next_gate", ""), "flags": flags,
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--brain", default=os.environ.get("BRAIN_HOME") or str(Path.home() / "work" / "brain"))
    p.add_argument("--stage", help="only this stage")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    home = Path(a.brain).expanduser()
    if not home.is_dir():
        print(f"no brain at {home}; set BRAIN_HOME or pass --brain", file=sys.stderr)
        return 2
    today = dt.date.today()
    rows = [assess(pth, m, f, home, today) for pth, m, f in notes(home, "ai-use-case")]
    if a.stage:
        rows = [r for r in rows if r["stage"] == a.stage]
    order = {s: i for i, s in enumerate(STAGES)}
    rows.sort(key=lambda r: (order.get(r["stage"], 99), -(r["composite"] or 0), r["title"]))
    if a.json:
        print(json.dumps(rows, indent=2))
        return 0
    if not rows:
        print("no use-case notes (tag ai-use-case) found")
        return 0
    fmt = lambda v: "-" if v is None else f"{v:g}"
    print("| Use case | Stage | V | F | R | Re | Composite | Owner | Next gate | Flags |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['title']} | {r['stage']} | {fmt(r['value'])} | {fmt(r['feasibility'])} | "
              f"{fmt(r['risk'])} | {fmt(r['reusability'])} | {fmt(r['composite'])} | {r['owner']} | "
              f"{r['next_gate']} | {'; '.join(r['flags'])} |")
    counts = {s: sum(r["stage"] == s for r in rows) for s in STAGES}
    print("\n" + ", ".join(f"{s}: {n}" for s, n in counts.items() if n) +
          f"; flagged: {sum(bool(r['flags']) for r in rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
