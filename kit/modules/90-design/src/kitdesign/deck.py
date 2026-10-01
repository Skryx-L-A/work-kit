"""Parse a deck written in Markdown into slides.

Format (see templates/deck/sample-deck.md):
- optional front matter between two `---` lines at the very top: title, author, date, footer
- slides separated by a line that is exactly `---`
- `# Headline` is the slide title (write the message as a sentence)
- `<!-- layout: title|section|bullets|big-number|image|two-column|quote -->` picks a layout;
  without it: first slide = title, a slide with only an image = image, else bullets
- `- item` bullets (indent two spaces for a second level), plain lines are paragraphs
- `![caption](path/to/image.png)` an image, path relative to the deck file
- `<!-- column -->` splits a two-column slide
- `::: notes` ... `:::` speaker notes
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

LAYOUTS = ("title", "section", "bullets", "big-number", "image", "two-column", "quote")

_LAYOUT_RE = re.compile(r"^<!--\s*layout:\s*([\w-]+)\s*-->$")
_COLUMN_RE = re.compile(r"^<!--\s*column\s*-->$")
_IMG_RE = re.compile(r"^!\[(.*?)\]\((.+?)\)$")
_BULLET_RE = re.compile(r"^(\s*)[-*]\s+(.*)$")


@dataclass
class Block:
    kind: str  # "p" | "ul" | "img"
    text: str = ""
    items: list[tuple[int, str]] = field(default_factory=list)
    path: Path | None = None


@dataclass
class Slide:
    layout: str
    title: str = ""
    columns: list[list[Block]] = field(default_factory=lambda: [[]])
    notes: str = ""

    @property
    def blocks(self) -> list[Block]:
        return [b for col in self.columns for b in col]


@dataclass
class Deck:
    meta: dict[str, str]
    slides: list[Slide]
    base: Path


class DeckError(ValueError):
    pass


def parse_file(path: Path) -> Deck:
    return parse(path.read_text(encoding="utf-8"), path.parent)


def parse(text: str, base: Path) -> Deck:
    lines = text.replace("\r\n", "\n").split("\n")
    meta: dict[str, str] = {}
    if lines and lines[0].strip() == "---":
        try:
            end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
        except StopIteration:
            raise DeckError("front matter starts with --- but is never closed") from None
        for ln in lines[1:end]:
            if ":" in ln:
                k, v = ln.split(":", 1)
                meta[k.strip().lower()] = v.strip().strip("\"'")
        lines = lines[end + 1:]
    chunks: list[list[str]] = [[]]
    in_notes = False
    for ln in lines:
        s = ln.strip()
        if s.startswith(":::"):
            in_notes = s != ":::"
        if s == "---" and not in_notes:
            chunks.append([])
        else:
            chunks[-1].append(ln)
    slides = [_parse_slide(c, base, i == 0) for i, c in enumerate(c for c in chunks if any(x.strip() for x in c))]
    if not slides:
        raise DeckError("the deck has no slides")
    return Deck(meta, slides, base)


def _parse_slide(lines: list[str], base: Path, first: bool) -> Slide:
    slide = Slide(layout="")
    notes: list[str] = []
    in_notes = False
    for raw in lines:
        s = raw.strip()
        if in_notes:
            if s == ":::":
                in_notes = False
            else:
                notes.append(s)
            continue
        if s.startswith(":::") and s[3:].strip() == "notes":
            in_notes = True
            continue
        if not s:
            continue
        m = _LAYOUT_RE.match(s)
        if m:
            if m.group(1) not in LAYOUTS:
                raise DeckError(f"unknown layout {m.group(1)!r}; choose from {', '.join(LAYOUTS)}")
            slide.layout = m.group(1)
            continue
        if _COLUMN_RE.match(s):
            slide.columns.append([])
            continue
        if s.startswith("# ") and not slide.title:
            slide.title = s[2:].strip()
            continue
        if s.startswith("#"):
            s = s.lstrip("#").strip()
        col = slide.columns[-1]
        m = _IMG_RE.match(s)
        if m:
            p = Path(m.group(2))
            col.append(Block("img", text=m.group(1), path=p if p.is_absolute() else base / p))
            continue
        m = _BULLET_RE.match(raw.rstrip())
        if m:
            level = min(len(m.group(1).expandtabs(2)) // 2, 1)
            if col and col[-1].kind == "ul":
                col[-1].items.append((level, m.group(2).strip()))
            else:
                col.append(Block("ul", items=[(level, m.group(2).strip())]))
            continue
        if col and col[-1].kind == "p" and raw.startswith(("  ", "\t")):
            col[-1].text += " " + s
        else:
            col.append(Block("p", text=s))
    slide.notes = "\n".join(notes).strip()
    if not slide.layout:
        blocks = slide.blocks
        if first:
            slide.layout = "title"
        elif blocks and all(b.kind == "img" for b in blocks):
            slide.layout = "image"
        elif len(slide.columns) > 1:
            slide.layout = "two-column"
        else:
            slide.layout = "bullets"
    return slide


_INLINE_RE = re.compile(r"(\*\*.+?\*\*|`.+?`|\*.+?\*)")


def runs(text: str) -> list[tuple[str, str]]:
    """Split inline Markdown into (style, text) runs; style is '', 'b', 'i' or 'code'."""
    out = []
    for part in _INLINE_RE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**") and len(part) > 4:
            out.append(("b", part[2:-2]))
        elif part.startswith("`") and part.endswith("`") and len(part) > 2:
            out.append(("code", part[1:-1]))
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            out.append(("i", part[1:-1]))
        else:
            out.append(("", part))
    return out
