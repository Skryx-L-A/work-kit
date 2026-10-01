"""Split a note body into chunks at Markdown headings."""

from __future__ import annotations

import re
from dataclasses import dataclass

HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")
MAX_CHARS = 1500


@dataclass
class Chunk:
    heading: str  # "H1 > H2" path, empty for text before the first heading
    text: str


def _split_long(text: str, max_chars: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]
    parts, cur = [], ""
    for para in re.split(r"\n\s*\n", text):
        while len(para) > max_chars:  # a single huge paragraph: hard cut
            if cur:
                parts.append(cur)
                cur = ""
            parts.append(para[:max_chars])
            para = para[max_chars:]
        if cur and len(cur) + len(para) + 2 > max_chars:
            parts.append(cur)
            cur = para
        else:
            cur = f"{cur}\n\n{para}" if cur else para
    if cur:
        parts.append(cur)
    return parts


def chunk(body: str, max_chars: int = MAX_CHARS) -> list[Chunk]:
    sections: list[tuple[str, list[str]]] = [("", [])]
    stack: list[tuple[int, str]] = []
    in_fence = False
    for line in body.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
        m = None if in_fence else HEADING.match(line)
        if m:
            level = len(m.group(1))
            while stack and stack[-1][0] >= level:
                stack.pop()
            stack.append((level, m.group(2)))
            sections.append((" > ".join(h for _, h in stack), []))
        else:
            sections[-1][1].append(line)
    chunks = []
    for heading, lines in sections:
        text = "\n".join(lines).strip()
        if not text:
            continue
        chunks.extend(Chunk(heading, part) for part in _split_long(text, max_chars))
    if not chunks:
        # Heading-only or empty note: keep one chunk so the title stays findable.
        chunks.append(Chunk(sections[-1][0], ""))
    return chunks
