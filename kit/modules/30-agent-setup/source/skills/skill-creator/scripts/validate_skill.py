#!/usr/bin/env python3
"""Validate agent skill folders (agentskills.io format plus kit conventions).

Usage: validate_skill.py SKILL_DIR [SKILL_DIR ...]
Errors (exit 1): missing SKILL.md or frontmatter, unquoted ": " in a value,
bad name, name != folder,
missing/too long description, SKILL.md with 150 lines or more.
Warnings: description without a "when not" clause, missing "Done when" or "Pitfalls"
section, references to files that do not exist.
Standard library only.
"""
import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MAX_LINES = 150
MAX_DESC = 1024


def parse_frontmatter(text: str):
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end == -1:
        return None, text
    fields, unquoted_colon = {}, []
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m:
            value = m.group(2).strip()
            if value[:1] not in ("'", '"', "|", ">") and ": " in value:
                unquoted_colon.append(m.group(1))
            if value[:1] == "'" and value.endswith("'"):
                value = value[1:-1].replace("''", "'")
            elif value[:1] == '"' and value.endswith('"'):
                value = value[1:-1]
            fields[m.group(1)] = value
    fields["_unquoted_colon"] = unquoted_colon
    return fields, text[end + 4:]


def check(skill_dir: Path):
    errors, warnings = [], []
    path = skill_dir / "SKILL.md"
    if not path.is_file():
        return [f"{path}: missing"], warnings
    text = path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    if fm is None:
        return [f"{path}: no YAML frontmatter"], warnings
    for key in fm.pop("_unquoted_colon"):
        errors.append(f"'{key}' contains ': ' unquoted (invalid YAML); quote the value")
    name, desc = fm.get("name", ""), fm.get("description", "")
    if not NAME_RE.match(name) or len(name) > 64:
        errors.append(f"name '{name}' must be lowercase letters, digits, hyphens (max 64)")
    if name != skill_dir.name:
        errors.append(f"name '{name}' differs from folder '{skill_dir.name}'")
    if not desc:
        errors.append("description missing")
    elif len(desc) > MAX_DESC:
        errors.append(f"description has {len(desc)} characters (max {MAX_DESC})")
    elif not re.search(r"\b(do not|don't|not for|skip)\b", desc, re.I):
        warnings.append("description has no 'when not to use' clause")
    lines = text.count("\n") + (0 if text.endswith("\n") else 1)
    if lines >= MAX_LINES:
        errors.append(f"SKILL.md has {lines} lines (limit: under {MAX_LINES})")
    for section in ("Done when", "Pitfalls"):
        if not re.search(rf"^#+\s+{section}", body, re.M):
            warnings.append(f"no '{section}' section")
    for ref in set(re.findall(r"`((?:references|scripts)/[^`\s]+)`", body)):
        if not (skill_dir / ref).exists():
            warnings.append(f"referenced file not found: {ref}")
    return errors, warnings


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    failed = False
    for arg in argv:
        d = Path(arg).resolve()
        errors, warnings = check(d)
        status = "FAIL" if errors else "OK"
        print(f"{status} {d.name}")
        for e in errors:
            print(f"  error: {e}")
        for w in warnings:
            print(f"  warning: {w}")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
