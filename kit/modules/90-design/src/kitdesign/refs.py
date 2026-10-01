"""Design reference folders (~/work/design-refs/<category>) and the brand theme."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

CATEGORIES = ("brand", "web", "slides", "documents", "diagrams")
# Files that belong to the kit, not to the user's references.
IGNORED = {"README.md", ".DS_Store", ".gitkeep"}


def refs_home() -> Path:
    return Path(os.environ.get("DESIGN_REFS", Path.home() / "work" / "design-refs")).expanduser()


def ref_files(category: str) -> list[Path]:
    """User-supplied files in one category (README.md and hidden files excluded)."""
    base = refs_home() / category
    if not base.is_dir():
        return []
    out = []
    for p in sorted(base.rglob("*")):
        rel = p.relative_to(base)
        if p.is_file() and p.name not in IGNORED and not any(s.startswith(".") for s in rel.parts):
            out.append(p)
    return out


def find_template(category: str, suffixes: tuple[str, ...]) -> list[Path]:
    return [p for p in ref_files(category) if p.suffix.lower() in suffixes]


@dataclass
class Theme:
    text: str = "#1d232b"
    background: str = "#ffffff"
    accent: str = "#0f5f8c"
    muted: str = "#5c6670"
    surface: str = "#eef2f5"
    heading_font: str = "Arial"
    body_font: str = "Arial"
    web_font: str = 'system-ui, "Segoe UI", Ubuntu, "Liberation Sans", Arial, sans-serif'
    logo: Path | None = None
    source: str = "kit default"
    warnings: list[str] = field(default_factory=list)

    def css_vars(self) -> str:
        return (
            f"  --text: {self.text};\n  --bg: {self.background};\n  --accent: {self.accent};\n"
            f"  --muted: {self.muted};\n  --surface: {self.surface};\n"
            f"  --font-heading: {_css_font(self.heading_font, self.web_font)};\n"
            f"  --font-body: {_css_font(self.body_font, self.web_font)};\n"
        )


def _css_font(name: str, fallback_stack: str) -> str:
    if name in ("", "Arial"):
        return fallback_stack
    return f'"{name}", {fallback_stack}'


def _is_hex(v: object) -> bool:
    return isinstance(v, str) and len(v) == 7 and v.startswith("#") and all(
        c in "0123456789abcdefABCDEF" for c in v[1:]
    )


def load_theme(path: Path | None = None) -> Theme:
    """Kit defaults, overridden by design-refs/brand/theme.json when it exists."""
    t = Theme()
    path = path or refs_home() / "brand" / "theme.json"
    if not path.is_file():
        return t
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        t.warnings.append(f"ignored {path}: {e}")
        return t
    colors = data.get("colors", {}) or {}
    for key in ("text", "background", "accent", "muted", "surface"):
        v = colors.get(key)
        if v is None:
            continue
        if _is_hex(v):
            setattr(t, key, v.lower())
        else:
            t.warnings.append(f"theme.json colors.{key} must be #rrggbb, got {v!r}")
    fonts = data.get("fonts", {}) or {}
    if isinstance(fonts.get("heading"), str):
        t.heading_font = fonts["heading"]
    if isinstance(fonts.get("body"), str):
        t.body_font = fonts["body"]
    logo = data.get("logo")
    if isinstance(logo, str) and logo:
        lp = (path.parent / logo).expanduser()
        if lp.is_file():
            t.logo = lp
        else:
            t.warnings.append(f"theme.json logo not found: {lp}")
    t.source = str(path)
    return t


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
