"""Note files: frontmatter, placement by type, creation and appending."""

from __future__ import annotations

import datetime as dt
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import yaml

TYPES = ("note", "session", "decision", "howto", "reference", "kern", "person")
NEEDS_PROJECT = ("session", "kern")
FOLDERS = ("inbox", "projects", "decisions", "howto", "reference", "people")
SKIP_DIRS = {".git", ".brain", "node_modules", ".venv"}

BODIES = {
    "note": "",
    "session": "## Goal\n\n## Done\n\n## Open\n",
    "decision": "## Context\n\n## Decision\n\n## Consequences\n",
    "howto": "## Steps\n\n1. \n",
    "reference": "",
    "kern": "## Current decisions\n\n## Known pitfalls\n",
    "person": "## Role\n\n## Working with\n",
}


class NoteError(Exception):
    """User-facing error (bad path, unknown type, ambiguous title...)."""


@dataclass
class Note:
    path: Path
    meta: dict
    body: str

    @property
    def title(self) -> str:
        return str(self.meta.get("title") or self.path.stem)


def today() -> str:
    return dt.date.today().isoformat()


def slugify(text: str, max_len: int = 60) -> str:
    text = text.replace("ß", "ss")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return text[:max_len].rstrip("-") or "note"


def split_frontmatter(text: str) -> tuple[dict, str]:
    if text.startswith("---"):
        m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n?", text, re.S)
        if m:
            try:
                meta = yaml.safe_load(m.group(1)) or {}
            except yaml.YAMLError:
                meta = {}
            if isinstance(meta, dict):
                return meta, text[m.end():]
    return {}, text


def render(meta: dict, body: str) -> str:
    fm = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True, default_flow_style=None)
    body = body if body.endswith("\n") or not body else body + "\n"
    return f"---\n{fm}---\n\n{body}"


def load(path: Path) -> Note:
    meta, body = split_frontmatter(path.read_text(encoding="utf-8", errors="replace"))
    return Note(path=path, meta=meta, body=body)


def iter_notes(home: Path):
    """All Markdown files below home, excluding tool and VCS directories."""
    for p in sorted(home.rglob("*.md")):
        rel = p.relative_to(home)
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel.parts[:-1]):
            continue
        if p.is_file() and not p.is_symlink():
            yield p


def safe_path(home: Path, raw: str) -> Path:
    """Resolve a user-supplied path to a Markdown file inside home."""
    p = Path(raw).expanduser()
    if not p.is_absolute():
        p = home / p
    if p.suffix != ".md":
        p = p.with_name(p.name + ".md")
    p = p.resolve()
    try:
        rel = p.relative_to(home)
    except ValueError:
        raise NoteError(f"path is outside the brain: {raw}") from None
    if rel.parts and rel.parts[0] in SKIP_DIRS:
        raise NoteError(f"path is not a note: {raw}")
    return p


def target_path(home: Path, ntype: str, title: str, project: str | None) -> Path:
    slug = slugify(title)
    if ntype in NEEDS_PROJECT and not project:
        raise NoteError(f"type '{ntype}' needs --project")
    proj = slugify(project) if project else None
    if ntype == "kern":
        path = home / "projects" / proj / "KERN.md"
        if path.exists():
            raise NoteError(f"{path.relative_to(home)} already exists; use 'brain append'")
        return path
    if ntype == "session":
        folder, name = home / "projects" / proj / "sessions", f"{today()}-{slug}"
    elif ntype == "decision":
        folder = home / "decisions"
        nums = [int(m.group(1)) for f in folder.glob("*.md") if (m := re.match(r"(\d{4})-", f.name))]
        name = f"{max(nums, default=0) + 1:04d}-{slug}"
    elif ntype == "person":
        folder, name = home / "people", slug
    elif ntype in ("howto", "reference"):
        folder, name = home / ntype, slug
    else:
        folder, name = home / "inbox", slug
    path = folder / f"{name}.md"
    n = 2
    while path.exists():
        path = folder / f"{name}-{n}.md"
        n += 1
    return path


def create(home: Path, ntype: str, title: str, project: str | None = None,
           body: str | None = None, tags: list[str] | None = None) -> Path:
    if ntype not in TYPES:
        raise NoteError(f"unknown type '{ntype}' (one of: {', '.join(TYPES)})")
    if not title.strip():
        raise NoteError("title must not be empty")
    path = target_path(home, ntype, title, project)
    meta: dict = {"title": title.strip(), "type": ntype}
    if project:
        meta["project"] = slugify(project)
    meta["tags"] = tags or []
    meta["created"] = today()
    meta["updated"] = today()
    if ntype == "decision":
        meta["status"] = "proposed"
    text = body if body and body.strip() else BODIES[ntype]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render(meta, text), encoding="utf-8")
    return path


def append(path: Path, text: str) -> None:
    if not path.is_file():
        raise NoteError(f"no such note: {path}")
    if not text.strip():
        raise NoteError("nothing to append")
    raw = path.read_text(encoding="utf-8", errors="replace")
    # Touch only the `updated:` line so user formatting and comments survive.
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", raw, re.S)
    if m and re.search(r"^updated:.*$", m.group(1), re.M):
        fm = re.sub(r"^updated:.*$", f"updated: '{today()}'", m.group(1), count=1, flags=re.M)
        raw = raw[: m.start(1)] + fm + raw[m.end(1):]
    raw = raw.rstrip("\n") + "\n\n" + text.strip("\n") + "\n"
    path.write_text(raw, encoding="utf-8")
