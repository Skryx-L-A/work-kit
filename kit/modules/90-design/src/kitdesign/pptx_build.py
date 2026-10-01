"""Build a PPTX from a parsed deck, either with the kit's clean default look or inside a
company template (.pptx or .potx) whose layouts and placeholders are reused."""

from __future__ import annotations

import io
import math
import zipfile
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, PP_PLACEHOLDER
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

from .deck import Block, Deck, Slide, runs
from .refs import Theme, hex_to_rgb

W, H = 13.333, 7.5  # 16:9 in inches
MARGIN = 0.75
BODY_TOP, BODY_H = 1.9, 4.8


def build(deck: Deck, out: Path, theme: Theme, template: Path | None = None) -> list[str]:
    """Write the PPTX; returns warnings (missing images, overflow risk)."""
    warnings: list[str] = []
    if template:
        prs = Presentation(_open_template(template))
        _drop_slides(prs)
        builder = _TemplateBuilder(prs, theme, warnings)
    else:
        prs = Presentation()
        prs.slide_width, prs.slide_height = Inches(W), Inches(H)
        builder = _CleanBuilder(prs, theme, warnings)
    total = len(deck.slides)
    for i, s in enumerate(deck.slides, 1):
        slide = builder.add(s, deck, i, total)
        if s.notes:
            slide.notes_slide.notes_text_frame.text = s.notes
    cp = prs.core_properties
    cp.title = deck.meta.get("title", deck.slides[0].title)
    if deck.meta.get("author"):
        cp.author = deck.meta["author"]
    out.parent.mkdir(parents=True, exist_ok=True)
    prs.save(str(out))
    return warnings


# --- helpers ---------------------------------------------------------------------------

def _open_template(path: Path) -> io.BytesIO:
    """python-pptx refuses .potx; rewrite its content type to a presentation in memory."""
    data = path.read_bytes()
    if path.suffix.lower() != ".potx":
        return io.BytesIO(data)
    src, buf = zipfile.ZipFile(io.BytesIO(data)), io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as dst:
        for item in src.infolist():
            body = src.read(item.filename)
            if item.filename == "[Content_Types].xml":
                body = body.replace(
                    b"presentationml.template.main+xml", b"presentationml.presentation.main+xml"
                )
            dst.writestr(item, body)
    buf.seek(0)
    return buf


def _drop_slides(prs) -> None:
    ids = prs.slides._sldIdLst
    for sld in list(ids):
        prs.part.drop_rel(sld.get(qn("r:id")))
        ids.remove(sld)


def _rgb(h: str) -> RGBColor:
    return RGBColor(*hex_to_rgb(h))


def _fit_pt(texts: list[tuple[str, float]], width_in: float, height_in: float, base: float, floor: float = 12) -> float:
    """Largest size <= base (step 2pt) whose rough line estimate fits the box.
    texts: (text, relative size) pairs, one per paragraph."""
    pt = base
    while pt > floor:
        need = 0.0
        for t, rel in texts:
            size = pt * rel
            per_line = max(1, int(width_in * 72 / (size * 0.52)))
            need += max(1, math.ceil(len(t) / per_line)) * size * 1.2 / 72 + size * 0.45 / 72
        if need <= height_in:
            return pt
        pt -= 2
    return floor


def _add_runs(par, text: str, theme: Theme, size: float, color: str, bold: bool = False, font: str | None = None) -> None:
    for style, t in runs(text):
        r = par.add_run()
        r.text = t
        f = r.font
        f.size = Pt(size)
        f.name = "Courier New" if style == "code" else (font or theme.body_font)
        f.bold = bold or style == "b"
        f.italic = style == "i"
        f.color.rgb = _rgb(color)


def _bullet(par, level: int, size: float, color: str) -> None:
    pPr = par._p.get_or_add_pPr()
    indent = int(Pt(size * 0.9))
    pPr.set("marL", str(indent * (level + 1) + int(Inches(0.05))))
    pPr.set("indent", str(-indent))
    for tag in ("a:buNone", "a:buChar", "a:buClr", "a:buAutoNum"):
        for el in pPr.findall(qn(tag)):
            pPr.remove(el)
    buClr = pPr.makeelement(qn("a:buClr"), {})
    clr = buClr.makeelement(qn("a:srgbClr"), {"val": color.lstrip("#").upper()})
    buClr.append(clr)
    pPr.append(buClr)
    pPr.append(pPr.makeelement(qn("a:buChar"), {"char": "•" if level == 0 else "–"}))


def _textbox(slide, x, y, w, h, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    return tf


def _rect(slide, x, y, w, h, color: str):
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    shp.fill.solid()
    shp.fill.fore_color.rgb = _rgb(color)
    shp.line.fill.background()
    shp.shadow.inherit = False
    return shp


def _picture(slide, path: Path, x, y, w, h, warnings: list[str]):
    """Place an image centred in the box, keeping its aspect ratio."""
    if not path.is_file():
        warnings.append(f"image not found: {path}")
        tf = _textbox(slide, x, y, w, h, MSO_ANCHOR.MIDDLE)
        tf.paragraphs[0].text = f"[missing image: {path.name}]"
        tf.paragraphs[0].alignment = PP_ALIGN.CENTER
        return None
    pic = slide.shapes.add_picture(str(path), Inches(x), Inches(y))
    ratio = min(Inches(w) / pic.width, Inches(h) / pic.height)
    pic.width, pic.height = int(pic.width * ratio), int(pic.height * ratio)
    pic.left = int(Inches(x) + (Inches(w) - pic.width) / 2)
    pic.top = int(Inches(y) + (Inches(h) - pic.height) / 2)
    return pic


def _fill_blocks(tf, blocks: list[Block], theme: Theme, size: float, color: str | None = None) -> None:
    color = color or theme.text
    first = True
    for b in blocks:
        if b.kind == "img":
            continue
        entries = [(0, b.text, False)] if b.kind == "p" else [(lvl, t, True) for lvl, t in b.items]
        for lvl, text, is_bullet in entries:
            par = tf.paragraphs[0] if first else tf.add_paragraph()
            first = False
            s = size if lvl == 0 else size * 0.85
            _add_runs(par, text, theme, s, color)
            par.space_after = Pt(s * 0.45)
            par.line_spacing = 1.1
            if is_bullet:
                _bullet(par, lvl, s, theme.accent)


def _text_weights(blocks: list[Block]) -> list[tuple[str, float]]:
    out = []
    for b in blocks:
        if b.kind == "p":
            out.append((b.text, 1.0))
        elif b.kind == "ul":
            out += [(t, 1.0 if lvl == 0 else 0.85) for lvl, t in b.items]
    return out


# --- clean default look ----------------------------------------------------------------

class _CleanBuilder:
    def __init__(self, prs, theme: Theme, warnings: list[str]):
        self.prs, self.t, self.w = prs, theme, warnings
        self.blank = prs.slide_layouts[6]

    def add(self, s: Slide, deck: Deck, i: int, total: int):
        slide = self.prs.slides.add_slide(self.blank)
        bg = slide.background.fill
        bg.solid()
        bg.fore_color.rgb = _rgb(self.t.accent if s.layout == "section" else self.t.background)
        getattr(self, "_" + s.layout.replace("-", "_"))(slide, s, deck)
        if s.layout not in ("title", "section"):
            self._chrome(slide, deck, i, total)
        return slide

    def _chrome(self, slide, deck: Deck, i: int, total: int) -> None:
        footer = deck.meta.get("footer") or deck.meta.get("title", "")
        tf = _textbox(slide, MARGIN, H - 0.5, 9, 0.3)
        _add_runs(tf.paragraphs[0], footer, self.t, 10, self.t.muted)
        tf = _textbox(slide, W - MARGIN - 2, H - 0.5, 2, 0.3)
        tf.paragraphs[0].alignment = PP_ALIGN.RIGHT
        _add_runs(tf.paragraphs[0], f"{i} / {total}", self.t, 10, self.t.muted)
        if self.t.logo:
            pic = slide.shapes.add_picture(str(self.t.logo), 0, Inches(0.35), height=Inches(0.4))
            pic.left = int(Inches(W - MARGIN) - pic.width)

    def _title_box(self, slide, s: Slide) -> None:
        _rect(slide, MARGIN, 0.5, 0.6, 0.07, self.t.accent)
        size = _fit_pt([(s.title, 1.0)], W - 2 * MARGIN - 1.2, 1.1, 30, 22)
        tf = _textbox(slide, MARGIN, 0.7, W - 2 * MARGIN - 1.2, 1.1, MSO_ANCHOR.TOP)
        _add_runs(tf.paragraphs[0], s.title, self.t, size, self.t.text, bold=True, font=self.t.heading_font)
        tf.paragraphs[0].line_spacing = 1.0

    def _title(self, slide, s: Slide, deck: Deck) -> None:
        _rect(slide, 0, 0, 0.28, H, self.t.accent)
        title = s.title or deck.meta.get("title", "")
        size = _fit_pt([(title, 1.0)], W - 2.5, 2.2, 44, 28)
        tf = _textbox(slide, 1.2, 1.6, W - 2.5, 2.4, MSO_ANCHOR.BOTTOM)
        _add_runs(tf.paragraphs[0], title, self.t, size, self.t.text, bold=True, font=self.t.heading_font)
        tf.paragraphs[0].line_spacing = 1.0
        tf = _textbox(slide, 1.2, 4.3, W - 2.5, 1.6)
        _fill_blocks(tf, s.blocks, self.t, 22, self.t.muted)
        byline = " · ".join(v for v in (deck.meta.get("author"), deck.meta.get("date")) if v)
        if byline:
            tf = _textbox(slide, 1.2, H - 1.0, W - 2.5, 0.4)
            _add_runs(tf.paragraphs[0], byline, self.t, 14, self.t.muted)
        if self.t.logo:
            pic = slide.shapes.add_picture(str(self.t.logo), 0, Inches(0.6), height=Inches(0.6))
            pic.left = int(Inches(W - MARGIN) - pic.width)

    def _section(self, slide, s: Slide, deck: Deck) -> None:
        tf = _textbox(slide, 1.2, 2.2, W - 2.4, 1.8, MSO_ANCHOR.BOTTOM)
        _add_runs(tf.paragraphs[0], s.title, self.t, 40, self.t.background, bold=True, font=self.t.heading_font)
        tf = _textbox(slide, 1.2, 4.2, W - 2.4, 1.5)
        _fill_blocks(tf, s.blocks, self.t, 22, self.t.background)

    def _bullets(self, slide, s: Slide, deck: Deck) -> None:
        self._title_box(slide, s)
        blocks = [b for b in s.blocks if b.kind != "img"]
        imgs = [b for b in s.blocks if b.kind == "img"]
        width = W - 2 * MARGIN if not imgs else (W - 2 * MARGIN) * 0.55
        size = _fit_pt(_text_weights(blocks), width, BODY_H, 24, 14)
        tf = _textbox(slide, MARGIN, BODY_TOP, width, BODY_H)
        _fill_blocks(tf, blocks, self.t, size)
        if imgs:
            x = MARGIN + width + 0.4
            _picture(slide, imgs[0].path, x, BODY_TOP, W - MARGIN - x, BODY_H, self.w)

    def _two_column(self, slide, s: Slide, deck: Deck) -> None:
        self._title_box(slide, s)
        cols = s.columns[:2] if len(s.columns) > 1 else [s.columns[0], []]
        cw = (W - 2 * MARGIN - 0.6) / 2
        size = min(_fit_pt(_text_weights(c), cw, BODY_H, 20, 14) for c in cols)
        for n, col in enumerate(cols):
            x = MARGIN + n * (cw + 0.6)
            imgs = [b for b in col if b.kind == "img"]
            if imgs and not any(b.kind != "img" for b in col):
                _picture(slide, imgs[0].path, x, BODY_TOP, cw, BODY_H, self.w)
            else:
                _fill_blocks(_textbox(slide, x, BODY_TOP, cw, BODY_H), col, self.t, size)

    def _big_number(self, slide, s: Slide, deck: Deck) -> None:
        self._title_box(slide, s)
        texts = [b for b in s.blocks if b.kind == "p"]
        if not texts:
            self.w.append(f"big-number slide {s.title!r} has no number line")
            return
        tf = _textbox(slide, MARGIN, BODY_TOP + 0.3, W - 2 * MARGIN, 1.9, MSO_ANCHOR.BOTTOM)
        _add_runs(tf.paragraphs[0], texts[0].text, self.t, 96, self.t.accent, bold=True, font=self.t.heading_font)
        tf = _textbox(slide, MARGIN, BODY_TOP + 2.4, W - 2 * MARGIN, 2.0)
        _fill_blocks(tf, texts[1:], self.t, 24, self.t.muted)

    def _image(self, slide, s: Slide, deck: Deck) -> None:
        imgs = [b for b in s.blocks if b.kind == "img"]
        top = BODY_TOP if s.title else 0.6
        if s.title:
            self._title_box(slide, s)
        if not imgs:
            self.w.append(f"image slide {s.title!r} has no image")
            return
        caption = imgs[0].text
        h = (H - 0.8 - top) - (0.45 if caption else 0)
        _picture(slide, imgs[0].path, MARGIN, top, W - 2 * MARGIN, h, self.w)
        if caption:
            tf = _textbox(slide, MARGIN, top + h + 0.1, W - 2 * MARGIN, 0.35)
            tf.paragraphs[0].alignment = PP_ALIGN.CENTER
            _add_runs(tf.paragraphs[0], caption, self.t, 12, self.t.muted)

    def _quote(self, slide, s: Slide, deck: Deck) -> None:
        texts = [b for b in s.blocks if b.kind == "p"]
        quote = texts[0].text if texts else s.title
        size = _fit_pt([(quote, 1.0)], W - 3.2, 3.4, 34, 20)
        lines = max(1, math.ceil(len(quote) / max(1, int((W - 3.2) * 72 / (size * 0.52)))))
        h = min(3.4, lines * size * 1.2 / 72 + 0.1)
        top = (H - h) / 2 - 0.4
        _rect(slide, 1.2, top, 0.08, h, self.t.accent)
        tf = _textbox(slide, 1.6, top, W - 3.2, h, MSO_ANCHOR.MIDDLE)
        _add_runs(tf.paragraphs[0], quote, self.t, size, self.t.text, font=self.t.heading_font)
        rest = texts[1:] if texts else []
        if rest:
            tf = _textbox(slide, 1.6, top + h + 0.3, W - 3.2, 0.8)
            _fill_blocks(tf, rest, self.t, 18, self.t.muted)


# --- company template ------------------------------------------------------------------

_TITLE_TYPES = {PP_PLACEHOLDER.TITLE, PP_PLACEHOLDER.CENTER_TITLE}
_BODY_TYPES = {PP_PLACEHOLDER.BODY, PP_PLACEHOLDER.OBJECT}


def _ph_types(layout) -> set:
    return {ph.placeholder_format.type for ph in layout.placeholders}


class _TemplateBuilder:
    """Use the template's own layouts; text inherits the template's fonts and colours."""

    def __init__(self, prs, theme: Theme, warnings: list[str]):
        self.prs, self.t, self.w = prs, theme, warnings
        layouts = list(prs.slide_layouts)
        by_name = {lay.name.lower(): lay for lay in layouts}

        def pick(pred, *names):
            for n in names:
                for key, lay in by_name.items():
                    if n in key:
                        return lay
            for lay in layouts:
                if pred(_ph_types(lay)):
                    return lay
            return layouts[0]

        self.title = pick(lambda t: PP_PLACEHOLDER.CENTER_TITLE in t or PP_PLACEHOLDER.SUBTITLE in t, "title slide", "titelfolie")
        self.content = pick(lambda t: bool(t & _TITLE_TYPES) and bool(t & _BODY_TYPES), "title and content", "titel und inhalt")
        self.section = pick(lambda t: False, "section", "abschnitt")
        if self.section is layouts[0]:
            self.section = self.title
        self.title_only = pick(lambda t: t == {PP_PLACEHOLDER.TITLE} or t <= _TITLE_TYPES | {PP_PLACEHOLDER.DATE, PP_PLACEHOLDER.FOOTER, PP_PLACEHOLDER.SLIDE_NUMBER} and bool(t & _TITLE_TYPES), "title only", "nur titel")
        body = next((ph for ph in self.content.placeholders if ph.placeholder_format.type in _BODY_TYPES), None)
        sw, sh = prs.slide_width, prs.slide_height
        if body is not None:
            self.box = (body.left, body.top, body.width, body.height)
        else:
            self.box = (int(sw * 0.06), int(sh * 0.25), int(sw * 0.88), int(sh * 0.62))

    def add(self, s: Slide, deck: Deck, i: int, total: int):
        layout = {"title": self.title, "section": self.section, "bullets": self.content,
                  "two-column": self.title_only, "quote": self.title_only}.get(s.layout, self.title_only)
        slide = self.prs.slides.add_slide(layout)
        title_ph = next((ph for ph in slide.placeholders if ph.placeholder_format.type in _TITLE_TYPES), None)
        title = s.title or (deck.meta.get("title", "") if s.layout == "title" else "")
        if title_ph is not None:
            title_ph.text_frame.text = ""
            p = title_ph.text_frame.paragraphs[0]
            for style, t in runs(title):
                r = p.add_run()
                r.text = t
                r.font.bold = True if style == "b" else None
        blocks = [b for b in s.blocks if b.kind != "img"]
        imgs = [b for b in s.blocks if b.kind == "img"]
        body_ph = next((ph for ph in slide.placeholders if ph.placeholder_format.type in _BODY_TYPES | {PP_PLACEHOLDER.SUBTITLE}), None)
        x, y, w, h = (Emu(v) for v in self.box)
        if s.layout in ("title", "section", "bullets") and body_ph is not None:
            self._fill_placeholder(body_ph, blocks)
            if s.layout == "bullets" and imgs:
                body_ph.width = int(w * 0.55)
                _picture(slide, imgs[0].path, (x + w * 0.6) / 914400, y / 914400, w * 0.4 / 914400, h / 914400, self.w)
        elif s.layout == "big-number" and blocks:
            tf = _textbox(slide, x / 914400, y / 914400, w / 914400, h * 0.45 / 914400, MSO_ANCHOR.BOTTOM)
            _add_runs(tf.paragraphs[0], blocks[0].text, self.t, 96, self.t.accent, bold=True, font=self.t.heading_font)
            tf = _textbox(slide, x / 914400, (y + h * 0.5) / 914400, w / 914400, h * 0.5 / 914400)
            _fill_blocks(tf, blocks[1:], self.t, 24, self.t.muted)
        elif s.layout == "image" and imgs:
            _picture(slide, imgs[0].path, x / 914400, y / 914400, w / 914400, h / 914400, self.w)
        elif s.layout == "two-column":
            cols = s.columns[:2] if len(s.columns) > 1 else [s.columns[0], []]
            cw = (w - Inches(0.5)) / 2
            for n, col in enumerate(cols):
                cx = (x + n * (cw + Inches(0.5))) / 914400
                ci = [b for b in col if b.kind == "img"]
                if ci and not any(b.kind != "img" for b in col):
                    _picture(slide, ci[0].path, cx, y / 914400, cw / 914400, h / 914400, self.w)
                else:
                    size = _fit_pt(_text_weights(col), cw / 914400, h / 914400, 20, 12)
                    _fill_blocks(_textbox(slide, cx, y / 914400, cw / 914400, h / 914400), col, self.t, size)
        elif s.layout == "quote" and blocks:
            tf = _textbox(slide, x / 914400, y / 914400, w / 914400, h * 0.6 / 914400, MSO_ANCHOR.MIDDLE)
            size = _fit_pt([(blocks[0].text, 1.0)], w / 914400, h * 0.6 / 914400, 32, 18)
            _add_runs(tf.paragraphs[0], blocks[0].text, self.t, size, self.t.text)
            tf = _textbox(slide, x / 914400, (y + h * 0.65) / 914400, w / 914400, h * 0.3 / 914400)
            _fill_blocks(tf, blocks[1:], self.t, 18, self.t.muted)
        elif blocks:
            tf = _textbox(slide, x / 914400, y / 914400, w / 914400, h / 914400)
            _fill_blocks(tf, blocks, self.t, _fit_pt(_text_weights(blocks), w / 914400, h / 914400, 22, 12))
        for ph in list(slide.placeholders):
            if ph.has_text_frame and not ph.text_frame.text.strip():
                ph._element.getparent().remove(ph._element)
        return slide

    def _fill_placeholder(self, ph, blocks: list[Block]) -> None:
        tf = ph.text_frame
        tf.text = ""
        first = True
        for b in blocks:
            entries = [(0, b.text)] if b.kind == "p" else list(b.items)
            for lvl, text in entries:
                par = tf.paragraphs[0] if first else tf.add_paragraph()
                first = False
                par.level = lvl
                for style, t in runs(text):
                    r = par.add_run()
                    r.text = t
                    if style == "b":
                        r.font.bold = True
                    elif style == "i":
                        r.font.italic = True
