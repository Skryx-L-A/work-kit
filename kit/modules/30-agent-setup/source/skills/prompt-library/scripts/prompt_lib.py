#!/usr/bin/env python3
"""Versioned prompt library: list, show, render, check and scaffold prompt files.

Usage:
  prompt_lib.py list [--role R] [--class C] [--all]    active prompts (--all: every status)
  prompt_lib.py show ID                                 print the prompt file
  prompt_lib.py render ID [--var NAME=VALUE ...] [--var-file NAME=PATH ...] [--allow-retired]
                                                        prompt text with variables filled in
  prompt_lib.py check [--strict]                        lint every prompt file
  prompt_lib.py new ID --title T --class C [--role R ...]
                                                        scaffold a new prompt (first library dir)

Library directories, searched in order (first match of an id wins):
  --dir DIR (repeatable), else $PROMPTS_PATH (colon-separated), else the kit library
  (source/prompts next to this skill) followed by ~/work/prompts if it exists.

Exit codes: 0 ok, 1 check errors or unknown id / missing variable, 2 usage error.
Standard library only, works offline.
"""
import argparse
import os
import re
import sys
from datetime import date
from pathlib import Path

STATUSES = ("draft", "active", "deprecated", "retired")
CLASSES = ("PUBLIC", "INTERNAL", "CONFIDENTIAL", "CUSTOMER")
REQUIRED = ("id", "title", "version", "status", "owner", "roles", "data_class",
            "variables", "updated")
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*$")
VAR_RE = re.compile(r"\{\{(\w+)\}\}")
PROMPT_BLOCK = re.compile(r"^## Prompt\s*\n+```[a-z]*\n(.*?)\n```", re.S | re.M)


def default_dirs():
    if os.environ.get("PROMPTS_PATH"):
        return [Path(p).expanduser() for p in os.environ["PROMPTS_PATH"].split(":") if p]
    here = Path(__file__).resolve()
    dirs = [here.parents[3] / "prompts"]  # source/skills/prompt-library/scripts -> source/prompts
    personal = Path.home() / "work" / "prompts"
    if personal.is_dir():
        dirs.append(personal)
    return dirs


def parse(path: Path):
    """Return (frontmatter dict, body). Supports `key: value` and `key: [a, b]` only."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n") or "\n---\n" not in text[3:]:
        return None, text
    head, body = text[4:].split("\n---\n", 1)
    fm = {}
    for line in head.splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if value.startswith("[") and value.endswith("]"):
            fm[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            fm[key] = value
    return fm, body


def load(dirs):
    prompts, seen = [], set()
    for d in dirs:
        if not d.is_dir():
            continue
        for f in sorted(d.rglob("*.md")):
            if f.name == "README.md" or f.parent == d:
                continue
            fm, body = parse(f)
            pid = (fm or {}).get("id") or f.relative_to(d).with_suffix("").as_posix()
            if pid in seen:
                continue
            seen.add(pid)
            prompts.append({"path": f, "dir": d, "fm": fm, "body": body, "id": pid})
    return prompts


def find(prompts, pid):
    for p in prompts:
        if p["id"] == pid:
            return p
    return None


def prompt_text(body):
    m = PROMPT_BLOCK.search(body)
    return m.group(1) if m else None


def lint(p):
    errors, warnings = [], []
    fm, body = p["fm"], p["body"]
    if fm is None:
        return ["no YAML frontmatter"], warnings
    for key in REQUIRED:
        if key not in fm or fm[key] in ("", []) and key != "variables":
            errors.append(f"missing field '{key}'")
    rel = p["path"].relative_to(p["dir"]).with_suffix("").as_posix()
    if fm.get("id") and fm["id"] != rel:
        errors.append(f"id '{fm['id']}' differs from path '{rel}'")
    if fm.get("id") and not ID_RE.match(fm["id"]):
        errors.append(f"id '{fm['id']}' must be <group>/<name>, lowercase and hyphens")
    if fm.get("version") and not SEMVER.match(fm["version"]):
        errors.append(f"version '{fm['version']}' is not MAJOR.MINOR.PATCH")
    status = fm.get("status")
    if status and status not in STATUSES:
        errors.append(f"status '{status}' not in {', '.join(STATUSES)}")
    if fm.get("data_class") and fm["data_class"] not in CLASSES:
        errors.append(f"data_class '{fm['data_class']}' not in {', '.join(CLASSES)}")
    if status in ("deprecated", "retired") and not fm.get("replaced_by") \
            and "no replacement" not in body.lower():
        errors.append(f"{status} prompt needs 'replaced_by' or the words 'no replacement' in the body")
    if status == "retired" and not fm.get("retired"):
        errors.append("retired prompt needs a 'retired' date")
    text = prompt_text(body)
    if text is None:
        errors.append("no '## Prompt' section with a fenced block")
    else:
        used = set(VAR_RE.findall(text))
        declared = set(fm.get("variables") or [])
        if used - declared:
            errors.append(f"variables used but not declared: {', '.join(sorted(used - declared))}")
        if declared - used:
            errors.append(f"variables declared but not used: {', '.join(sorted(declared - used))}")
    if fm.get("version") and f"- {fm['version']} (" not in body:
        errors.append(f"no changelog entry '- {fm['version']} (...)'")
    if "TODO" in str(fm.get("owner", "")):
        warnings.append("owner is a placeholder")
    if not re.search(r"^Do not use for:", body, re.M):
        warnings.append("no 'Do not use for:' line")
    return errors, warnings


def cmd_list(prompts, a):
    rows = []
    for p in prompts:
        fm = p["fm"] or {}
        if not a.all and fm.get("status") != "active":
            continue
        if a.role and a.role not in fm.get("roles", []) and "all" not in fm.get("roles", []):
            continue
        if a.data_class and fm.get("data_class") != a.data_class:
            continue
        rows.append((p["id"], fm.get("version", "?"), fm.get("status", "?"),
                     fm.get("data_class", "?"), fm.get("title", "")))
    for r in rows:
        print("{:<32} {:<7} {:<10} {:<12} {}".format(*r))
    if not rows:
        print("no prompts match", file=sys.stderr)
    return 0


def cmd_show(prompts, a):
    p = find(prompts, a.id)
    if not p:
        print(f"unknown prompt id: {a.id}", file=sys.stderr)
        return 1
    sys.stdout.write(p["path"].read_text(encoding="utf-8"))
    return 0


def cmd_render(prompts, a):
    p = find(prompts, a.id)
    if not p:
        print(f"unknown prompt id: {a.id}", file=sys.stderr)
        return 1
    fm = p["fm"] or {}
    status, repl = fm.get("status"), fm.get("replaced_by") or "another prompt"
    if status == "retired" and not a.allow_retired:
        print(f"{a.id} is retired; use {repl} (or --allow-retired to reproduce an old result)",
              file=sys.stderr)
        return 1
    if status in ("deprecated", "retired", "draft"):
        print(f"warning: {a.id} is {status}" + (f"; use {repl}" if status != "draft" else ""),
              file=sys.stderr)
    values = {}
    for item in a.var or []:
        k, _, v = item.partition("=")
        values[k] = v
    for item in a.var_file or []:
        k, _, path = item.partition("=")
        values[k] = sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")
    text = prompt_text(p["body"])
    if text is None:
        print(f"{a.id}: no prompt block", file=sys.stderr)
        return 1
    missing = sorted(set(VAR_RE.findall(text)) - set(values))
    if missing:
        print(f"missing variables: {', '.join(missing)}", file=sys.stderr)
        return 1
    print(VAR_RE.sub(lambda m: values[m.group(1)], text))
    print(f"[data class: {fm.get('data_class', '?')} - check your tool is approved for it]",
          file=sys.stderr)
    return 0


def cmd_check(prompts, a):
    failed, count = False, 0
    for p in prompts:
        count += 1
        errors, warnings = lint(p)
        if a.strict:
            errors, warnings = errors + warnings, []
        print(f"{'FAIL' if errors else 'OK'} {p['id']}")
        for e in errors:
            print(f"  error: {e}")
        for w in warnings:
            print(f"  warning: {w}")
        failed |= bool(errors)
    print(f"{count} prompts checked")
    return 1 if failed else 0


def cmd_new(dirs, prompts, a):
    if not ID_RE.match(a.id):
        print("id must be <group>/<name>, lowercase letters, digits and hyphens", file=sys.stderr)
        return 2
    if a.data_class not in CLASSES:
        print(f"--class must be one of {', '.join(CLASSES)}", file=sys.stderr)
        return 2
    if find(prompts, a.id):
        print(f"{a.id} exists already; bump its version instead", file=sys.stderr)
        return 1
    target = dirs[0] / f"{a.id}.md"
    today = date.today().isoformat()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(f"""---
id: {a.id}
title: {a.title}
version: 0.1.0
status: draft
owner: TODO(set owner)
roles: [{', '.join(a.role or ['all'])}]
data_class: {a.data_class}
variables: [input]
updated: {today}
---
# {a.title}

Use for: TODO

Do not use for: TODO

## Prompt

```text
TODO: task, context, format, constraints.

{{{{input}}}}
```

## Review before use

- TODO: what the user checks in the output.

## Changelog

- 0.1.0 ({today}): first draft.
""", encoding="utf-8")
    print(target)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description="Versioned prompt library.")
    ap.add_argument("--dir", action="append", type=Path, help="library directory (repeatable)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("list")
    s.add_argument("--role")
    s.add_argument("--class", dest="data_class", choices=CLASSES)
    s.add_argument("--all", action="store_true")
    s = sub.add_parser("show")
    s.add_argument("id")
    s = sub.add_parser("render")
    s.add_argument("id")
    s.add_argument("--var", action="append", metavar="NAME=VALUE")
    s.add_argument("--var-file", action="append", metavar="NAME=PATH", help="PATH '-' reads stdin")
    s.add_argument("--allow-retired", action="store_true")
    s = sub.add_parser("check")
    s.add_argument("--strict", action="store_true", help="treat warnings as errors")
    s = sub.add_parser("new")
    s.add_argument("id")
    s.add_argument("--title", required=True)
    s.add_argument("--class", dest="data_class", required=True)
    s.add_argument("--role", action="append")
    a = ap.parse_args(argv)
    dirs = [d.expanduser() for d in a.dir] if a.dir else default_dirs()
    prompts = load(dirs)
    if a.cmd == "new":
        return cmd_new(dirs, prompts, a)
    if not prompts:
        print(f"no prompts found in: {', '.join(str(d) for d in dirs)}", file=sys.stderr)
        return 1
    return {"list": cmd_list, "show": cmd_show, "render": cmd_render, "check": cmd_check}[a.cmd](prompts, a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
