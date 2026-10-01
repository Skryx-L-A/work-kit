"""Render a parsed deck as one self-contained HTML file (CSS, JS and images inline)."""

from __future__ import annotations

import base64
import html
import mimetypes
from importlib import resources
from pathlib import Path

from .deck import Block, Deck, Slide, runs
from .refs import Theme


def _tpl(name: str) -> str:
    return resources.files("kitdesign").joinpath("templates/deck", name).read_text(encoding="utf-8")


def inline(text: str) -> str:
    out = []
    for style, t in runs(text):
        t = html.escape(t)
        out.append({"b": f"<strong>{t}</strong>", "i": f"<em>{t}</em>", "code": f"<code>{t}</code>"}.get(style, t))
    return "".join(out)


def _data_uri(path: Path, warnings: list[str]) -> str:
    if not path.is_file():
        warnings.append(f"image not found: {path}")
        return ""
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def _blocks(blocks: list[Block], warnings: list[str]) -> str:
    out = []
    for b in blocks:
        if b.kind == "p":
            out.append(f"<p>{inline(b.text)}</p>")
        elif b.kind == "ul":
            items = "".join(f'<li class="l{lvl}">{inline(t)}</li>' for lvl, t in b.items)
            out.append(f"<ul>{items}</ul>")
        elif b.kind == "img":
            src = _data_uri(b.path, warnings)
            cap = f"<figcaption>{inline(b.text)}</figcaption>" if b.text else ""
            img = f'<img src="{src}" alt="{html.escape(b.text)}">' if src else f"<p>[missing image: {html.escape(b.path.name)}]</p>"
            out.append(f"<figure>{img}{cap}</figure>")
    return "".join(out)


def _slide(s: Slide, deck: Deck, i: int, total: int, logo: str, warnings: list[str]) -> str:
    title = s.title or (deck.meta.get("title", "") if s.layout == "title" else "")
    h1 = f"<h1>{inline(title)}</h1>" if title else ""
    if s.layout == "big-number":
        ps = [b for b in s.blocks if b.kind == "p"]
        num = f'<div class="number">{inline(ps[0].text)}</div>' if ps else ""
        inner = h1 + num + f'<div class="body">{_blocks(ps[1:], warnings)}</div>'
    elif s.layout == "quote":
        ps = [b for b in s.blocks if b.kind == "p"]
        quote = ps[0].text if ps else title
        attr = "".join(f'<p class="attribution">{inline(b.text)}</p>' for b in ps[1:])
        inner = f"<blockquote>{inline(quote)}</blockquote>{attr}"
    else:
        cols = s.columns if s.layout == "two-column" else [s.blocks]
        body = "".join(f'<div class="col">{_blocks(c, warnings)}</div>' for c in cols)
        inner = h1 + f'<div class="body">{body}</div>'
    if s.layout == "title":
        byline = " &middot; ".join(html.escape(v) for v in (deck.meta.get("author"), deck.meta.get("date")) if v)
        if byline:
            inner += f'<div class="byline">{byline}</div>'
    elif s.layout != "section":
        footer = html.escape(deck.meta.get("footer") or deck.meta.get("title", ""))
        inner += f'<div class="footer"><span>{footer}</span><span>{i} / {total}</span></div>'
    if logo and s.layout != "section":
        inner += f'<img class="logo" src="{logo}" alt="">'
    notes = f'<aside class="notes">{html.escape(s.notes)}</aside>' if s.notes else ""
    return f'<section class="slide layout-{s.layout}" data-n="{i}">{inner}{notes}</section>'


def build(deck: Deck, out: Path, theme: Theme) -> list[str]:
    warnings: list[str] = []
    logo = _data_uri(theme.logo, warnings) if theme.logo else ""
    total = len(deck.slides)
    sections = "\n".join(_slide(s, deck, i, total, logo, warnings) for i, s in enumerate(deck.slides, 1))
    css = _tpl("deck.css").replace("/*TOKENS*/", theme.css_vars())
    title = html.escape(deck.meta.get("title") or deck.slides[0].title)
    page = (
        f'<!doctype html>\n<html lang="{html.escape(deck.meta.get("lang", "en"))}">\n<head>\n<meta charset="utf-8">\n'
        f'<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>{title}</title>\n'
        f"<style>\n{css}</style>\n</head>\n<body>\n<div class=\"deck\">\n{sections}\n</div>\n"
        f"<script>\n{_tpl('deck.js')}</script>\n</body>\n</html>\n"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    return warnings
