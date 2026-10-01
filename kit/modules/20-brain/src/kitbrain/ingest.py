"""Convert documents to Markdown: PDF, DOCX, PPTX, XLSX, HTML, Markdown and plain text.

Office formats are read directly from their ZIP/XML parts with the standard library, PDF with
pypdf (pure Python). Nothing here needs network, a converter binary or an office suite.
Classification labels found in document properties are returned so callers (18-doc-qa) can gate.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import html
import re
import zipfile
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET

from . import notes

FORMATS = {
    ".pdf": "pdf", ".docx": "docx", ".pptx": "pptx", ".xlsx": "xlsx",
    ".html": "html", ".htm": "html", ".md": "markdown", ".markdown": "markdown", ".txt": "text",
}
MAX_UNZIPPED = 300 * 1024 * 1024  # refuse archives that expand beyond this (zip bombs)
MAX_SHEET_ROWS = 1000

NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
    "cp": "http://schemas.openxmlformats.org/package/2006/metadata/core-properties",
    "dc": "http://purl.org/dc/elements/1.1/",
    "op": "http://schemas.openxmlformats.org/officeDocument/2006/custom-properties",
    "vt": "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes",
}
W = "{%s}" % NS["w"]


class IngestError(notes.NoteError):
    pass


@dataclass
class Document:
    markdown: str
    title: str
    format: str
    labels: list[str] = field(default_factory=list)  # classification labels from properties
    pages: int | None = None


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def detect_format(path: Path) -> str:
    fmt = FORMATS.get(path.suffix.lower())
    if not fmt:
        raise IngestError(f"unsupported file type '{path.suffix}' "
                          f"(supported: {', '.join(sorted(set(FORMATS)))})")
    return fmt


def convert(path: Path) -> Document:
    if not path.is_file():
        raise IngestError(f"no such file: {path}")
    fmt = detect_format(path)
    try:
        doc = {"pdf": _pdf, "docx": _docx, "pptx": _pptx, "xlsx": _xlsx, "html": _html,
               "markdown": _markdown, "text": _text}[fmt](path)
    except (zipfile.BadZipFile, ET.ParseError, KeyError) as exc:
        raise IngestError(f"cannot read {path.name} as {fmt}: {exc}") from None
    doc.title = (doc.title or "").strip() or path.stem.replace("_", " ").strip()
    doc.markdown = _tidy(doc.markdown)
    return doc


def _tidy(md: str) -> str:
    md = re.sub(r"[ \t]+\n", "\n", md)
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip() + "\n"


# -- plain formats ---------------------------------------------------------------------------
def _text(path: Path) -> Document:
    return Document(path.read_text(encoding="utf-8", errors="replace"), "", "text")


def _markdown(path: Path) -> Document:
    meta, body = notes.split_frontmatter(path.read_text(encoding="utf-8", errors="replace"))
    title = str(meta.get("title") or "")
    if not title:
        m = re.search(r"^#\s+(.+)$", body, re.M)
        title = m.group(1).strip() if m else ""
    return Document(body, title, "markdown")


class _HtmlToMd(HTMLParser):
    SKIP = {"script", "style", "noscript", "template", "svg", "head"}
    BLOCK = {"p", "div", "section", "article", "header", "footer", "main", "aside", "blockquote",
             "table", "ul", "ol", "dl", "figure", "form", "nav"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.skip = 0
        self.title = ""
        self.in_title = False
        self.pre = 0
        self.lists: list[list] = []  # [kind, counter]
        self.href: str | None = None
        self.link_text: list[str] = []
        self.row: list[str] | None = None
        self.cell: list[str] | None = None
        self.rows: list[list[str]] = []

    def _emit(self, text: str) -> None:
        if self.cell is not None:
            self.cell.append(text)
        elif self.href is not None:
            self.link_text.append(text)
        else:
            self.out.append(text)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self.in_title = True
        if tag in self.SKIP:
            self.skip += 1
            return
        if self.skip:
            return
        if re.fullmatch(r"h[1-6]", tag):
            self._emit("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in self.BLOCK:
            self._emit("\n\n")
        elif tag == "br":
            self._emit("\n")
        elif tag == "pre":
            self.pre += 1
            self._emit("\n\n```\n")
        elif tag in ("ul", "ol"):
            self.lists.append([tag, 0])
        elif tag == "li":
            indent = "  " * max(len(self.lists) - 1, 0)
            if self.lists and self.lists[-1][0] == "ol":
                self.lists[-1][1] += 1
                self._emit(f"\n{indent}{self.lists[-1][1]}. ")
            else:
                self._emit(f"\n{indent}- ")
        elif tag == "a" and a.get("href") and self.cell is None:
            self.href = a["href"]
            self.link_text = []
        elif tag in ("strong", "b"):
            self._emit("**")
        elif tag in ("em", "i"):
            self._emit("*")
        elif tag == "code" and not self.pre:
            self._emit("`")
        elif tag == "tr":
            self.row = []
        elif tag in ("td", "th"):
            self.cell = []
        if tag in ("ul", "ol"):
            self._emit("\n")

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        if tag in self.SKIP:
            self.skip = max(self.skip - 1, 0)
            return
        if self.skip:
            return
        if re.fullmatch(r"h[1-6]", tag) or tag in self.BLOCK or tag == "p":
            self._emit("\n\n")
        elif tag == "pre":
            self.pre = max(self.pre - 1, 0)
            self._emit("\n```\n\n")
        elif tag in ("ul", "ol") and self.lists:
            self.lists.pop()
            self._emit("\n")
        elif tag == "a" and self.href is not None:
            text = "".join(self.link_text).strip()
            href, self.href = self.href, None
            self._emit(f"[{text}]({href})" if text and not href.startswith("javascript:") else text)
        elif tag in ("strong", "b"):
            self._emit("**")
        elif tag in ("em", "i"):
            self._emit("*")
        elif tag == "code" and not self.pre:
            self._emit("`")
        elif tag in ("td", "th") and self.cell is not None:
            if self.row is not None:
                self.row.append(" ".join("".join(self.cell).split()).replace("|", "\\|"))
            self.cell = None
        elif tag == "tr" and self.row is not None:
            if self.row:
                self.rows.append(self.row)
            self.row = None
        if tag == "table":
            self._emit(_md_table(self.rows) + "\n\n")
            self.rows = []

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.skip:
            return
        if not self.pre:
            data = re.sub(r"\s+", " ", data)
        self._emit(data)


def _html(path: Path) -> Document:
    p = _HtmlToMd()
    p.feed(path.read_text(encoding="utf-8", errors="replace"))
    p.close()
    md = "".join(p.out)
    md = "\n".join(line.strip() if not line.startswith("  ") else line.rstrip()
                   for line in md.splitlines())
    title = " ".join(html.unescape(p.title).split())
    if not title:
        m = re.search(r"^#\s+(.+)$", md, re.M)
        title = m.group(1).strip() if m else ""
    return Document(md, title, "html")


def _md_table(rows: list[list[str]]) -> str:
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    lines = ["| " + " | ".join(rows[0]) + " |", "|" + "---|" * width]
    lines += ["| " + " | ".join(r) + " |" for r in rows[1:]]
    return "\n".join(lines)


# -- office (OOXML) --------------------------------------------------------------------------
def _open_zip(path: Path) -> zipfile.ZipFile:
    z = zipfile.ZipFile(path)
    if sum(i.file_size for i in z.infolist()) > MAX_UNZIPPED:
        z.close()
        raise IngestError(f"{path.name} expands to more than {MAX_UNZIPPED // 2**20} MB; refused")
    return z


def _xml(z: zipfile.ZipFile, name: str) -> ET.Element | None:
    try:
        return ET.fromstring(z.read(name))
    except KeyError:
        return None


def _rels(z: zipfile.ZipFile, part: str) -> dict[str, str]:
    """Relationship id -> target part path, for the given part."""
    pp = PurePosixPath(part)
    root = _xml(z, str(pp.parent / "_rels" / (pp.name + ".rels")))
    out = {}
    if root is None:
        return out
    for rel in root.findall("rel:Relationship", NS):
        target = rel.get("Target", "")
        if rel.get("TargetMode") == "External":
            continue
        resolved = PurePosixPath(target.lstrip("/")) if target.startswith("/") else pp.parent / target
        parts: list[str] = []
        for seg in resolved.parts:
            if seg == "..":
                if parts:
                    parts.pop()
            elif seg != ".":
                parts.append(seg)
        out[rel.get("Id")] = "/".join(parts)
    return out


def _office_meta(z: zipfile.ZipFile) -> tuple[str, list[str]]:
    """Title from core properties, classification labels from core and custom properties."""
    title, labels = "", []
    core = _xml(z, "docProps/core.xml")
    if core is not None:
        t = core.find("dc:title", NS)
        title = (t.text or "") if t is not None else ""
        for tag in ("cp:keywords", "cp:category", "cp:contentStatus", "dc:subject"):
            el = core.find(tag, NS)
            if el is not None and el.text:
                labels.extend(_label_candidates(el.text))
    custom = _xml(z, "docProps/custom.xml")
    if custom is not None:
        for prop in custom.findall("op:property", NS):
            name = prop.get("name", "")
            value = "".join(prop.itertext()).strip()
            # Microsoft Purview / MIP sensitivity labels: MSIP_Label_<guid>_Name = "Internal"
            if re.fullmatch(r"MSIP_Label_.*_Name", name) and value:
                labels.append(value)
            elif re.search(r"classification|sensitivity|confidential|label|vertraulich", name, re.I) \
                    and value:
                labels.append(value)
    return title, _dedupe(labels)


def _label_candidates(text: str) -> list[str]:
    return [t.strip() for t in re.split(r"[;,]", text) if t.strip()]


def _dedupe(items: list[str]) -> list[str]:
    seen, out = set(), []
    for i in items:
        if i.lower() not in seen:
            seen.add(i.lower())
            out.append(i)
    return out


def _docx(path: Path) -> Document:
    with _open_zip(path) as z:
        title, labels = _office_meta(z)
        doc = _xml(z, "word/document.xml")
        if doc is None:
            raise IngestError(f"{path.name}: no word/document.xml")
        styles = _docx_styles(z)
        body = doc.find(f"{W}body")
        out: list[str] = []
        for el in list(body) if body is not None else []:
            if el.tag == f"{W}p":
                out.append(_docx_para(el, styles))
            elif el.tag == f"{W}tbl":
                out.append(_docx_table(el, styles))
        md = "\n\n".join(x for x in out if x.strip())
    return Document(md, title, "docx", labels)


def _docx_styles(z: zipfile.ZipFile) -> dict[str, str]:
    root = _xml(z, "word/styles.xml")
    out = {}
    if root is None:
        return out
    for st in root.findall("w:style", NS):
        name = st.find("w:name", NS)
        out[st.get(f"{W}styleId", "")] = (name.get(f"{W}val", "") if name is not None else "").lower()
    return out


def _docx_text(el: ET.Element) -> str:
    parts = []
    for node in el.iter():
        if node.tag == f"{W}t":
            parts.append(node.text or "")
        elif node.tag == f"{W}tab":
            parts.append("\t")
        elif node.tag in (f"{W}br", f"{W}cr"):
            parts.append("\n")
    return "".join(parts)


def _docx_para(p: ET.Element, styles: dict[str, str]) -> str:
    text = _docx_text(p).strip()
    if not text:
        return ""
    ppr = p.find(f"{W}pPr")
    style_id = ""
    if ppr is not None:
        ps = ppr.find(f"{W}pStyle")
        style_id = ps.get(f"{W}val", "") if ps is not None else ""
        outline = ppr.find(f"{W}outlineLvl")
    else:
        outline = None
    name = styles.get(style_id, style_id.lower())
    m = re.search(r"(?:heading|überschrift|berschrift)\s*(\d)", name) or \
        re.fullmatch(r"(?:heading|berschrift|überschrift)(\d)", style_id.lower())
    if m:
        return "#" * min(int(m.group(1)) + 1, 6) + " " + text.replace("\n", " ")
    if name in ("title", "titel"):
        return "# " + text.replace("\n", " ")
    if outline is not None and outline.get(f"{W}val", "").isdigit():
        return "#" * min(int(outline.get(f"{W}val")) + 2, 6) + " " + text.replace("\n", " ")
    if ppr is not None and ppr.find(f"{W}numPr") is not None or "list" in name:
        return "- " + text
    return text


def _docx_table(tbl: ET.Element, styles) -> str:
    rows = []
    for tr in tbl.findall("w:tr", NS):
        cells = [" ".join(_docx_text(tc).split()).replace("|", "\\|") for tc in tr.findall("w:tc", NS)]
        rows.append(cells)
    return _md_table(rows)


def _pptx(path: Path) -> Document:
    with _open_zip(path) as z:
        title, labels = _office_meta(z)
        pres = _xml(z, "ppt/presentation.xml")
        if pres is None:
            raise IngestError(f"{path.name}: no ppt/presentation.xml")
        rels = _rels(z, "ppt/presentation.xml")
        slides = [rels[s.get(f"{{{NS['r']}}}id")] for s in pres.findall("p:sldIdLst/p:sldId", NS)
                  if s.get(f"{{{NS['r']}}}id") in rels]
        out = []
        for n, part in enumerate(slides, 1):
            root = _xml(z, part)
            if root is None:
                continue
            stitle, lines = "", []
            for sp in root.iter(f"{{{NS['p']}}}sp"):
                ph = sp.find("p:nvSpPr/p:nvPr/p:ph", NS)
                paras = []
                for para in sp.iter(f"{{{NS['a']}}}p"):
                    t = "".join(x.text or "" for x in para.iter(f"{{{NS['a']}}}t")).strip()
                    if t:
                        lvl = int((para.find("a:pPr", NS).get("lvl", "0")
                                   if para.find("a:pPr", NS) is not None else "0") or 0)
                        paras.append(("  " * lvl, t))
                if ph is not None and ph.get("type") in ("title", "ctrTitle") and not stitle:
                    stitle = " ".join(t for _, t in paras)
                    continue
                lines.extend(f"{ind}- {t}" for ind, t in paras)
            for tbl in root.iter(f"{{{NS['a']}}}tbl"):
                rows = [[" ".join("".join(x.text or "" for x in tc.iter(f"{{{NS['a']}}}t")).split())
                         for tc in tr.findall("a:tc", NS)] for tr in tbl.findall("a:tr", NS)]
                lines.append("\n" + _md_table(rows) + "\n")
            notes_part = next((t for rid, t in _rels(z, part).items() if "notesSlide" in t), None)
            if notes_part:
                nroot = _xml(z, notes_part)
                if nroot is not None:
                    ntext = []
                    for sp in nroot.iter(f"{{{NS['p']}}}sp"):
                        ph = sp.find("p:nvSpPr/p:nvPr/p:ph", NS)
                        if ph is not None and ph.get("type") == "body":
                            ntext += ["".join(x.text or "" for x in para.iter(f"{{{NS['a']}}}t"))
                                      for para in sp.iter(f"{{{NS['a']}}}p")]
                    ntext = [t for t in ntext if t.strip()]
                    if ntext:
                        lines.append("\nSpeaker notes: " + " ".join(ntext))
            head = f"## Slide {n}" + (f": {stitle}" if stitle else "")
            out.append(head + "\n\n" + "\n".join(lines))
            if n == 1 and not title:
                title = stitle
    return Document("\n\n".join(out), title, "pptx", labels, pages=len(slides))


def _col_index(ref: str) -> int:
    letters = re.match(r"[A-Z]+", ref or "A")
    n = 0
    for ch in letters.group(0) if letters else "A":
        n = n * 26 + ord(ch) - 64
    return n - 1


def _xlsx(path: Path) -> Document:
    with _open_zip(path) as z:
        title, labels = _office_meta(z)
        shared = []
        sst = _xml(z, "xl/sharedStrings.xml")
        if sst is not None:
            for si in sst.findall("s:si", NS):
                shared.append("".join(t.text or "" for t in si.iter(f"{{{NS['s']}}}t")))
        wb = _xml(z, "xl/workbook.xml")
        if wb is None:
            raise IngestError(f"{path.name}: no xl/workbook.xml")
        rels = _rels(z, "xl/workbook.xml")
        out = []
        for sheet in wb.findall("s:sheets/s:sheet", NS):
            if sheet.get("state") in ("hidden", "veryHidden"):
                continue
            part = rels.get(sheet.get(f"{{{NS['r']}}}id"))
            root = _xml(z, part) if part else None
            if root is None:
                continue
            rows, truncated = [], False
            for row in root.iter(f"{{{NS['s']}}}row"):
                if len(rows) >= MAX_SHEET_ROWS:
                    truncated = True
                    break
                cells: dict[int, str] = {}
                for c in row.findall("s:c", NS):
                    cells[_col_index(c.get("r", ""))] = _xlsx_value(c, shared)
                if any(v.strip() for v in cells.values()):
                    width = max(cells) + 1
                    rows.append([cells.get(i, "").replace("|", "\\|").replace("\n", " ")
                                 for i in range(width)])
            text = f"## Sheet: {sheet.get('name', '')}\n\n" + _md_table(rows)
            if truncated:
                text += f"\n\n(first {MAX_SHEET_ROWS} rows only)"
            out.append(text)
    return Document("\n\n".join(out), title, "xlsx", labels)


def _xlsx_value(c: ET.Element, shared: list[str]) -> str:
    t = c.get("t")
    if t == "inlineStr":
        return "".join(x.text or "" for x in c.iter(f"{{{NS['s']}}}t"))
    v = c.find("s:v", NS)
    raw = v.text if v is not None and v.text is not None else ""
    if t == "s":
        try:
            return shared[int(raw)]
        except (ValueError, IndexError):
            return ""
    if t == "b":
        return "TRUE" if raw == "1" else "FALSE"
    return raw


# -- PDF -------------------------------------------------------------------------------------
def _pdf(path: Path) -> Document:
    try:
        from pypdf import PdfReader
        from pypdf.errors import PdfReadError
    except ImportError:  # pragma: no cover - dependency is declared
        raise IngestError("pypdf is not installed") from None
    try:
        reader = PdfReader(str(path))
        if reader.is_encrypted:
            try:
                reader.decrypt("")
            except Exception:
                raise IngestError(f"{path.name} is encrypted") from None
        meta = reader.metadata or {}
        title = str(meta.get("/Title") or "")
        labels = []
        for key in ("/Keywords", "/Subject", "/Classification"):
            if meta.get(key):
                labels.extend(_label_candidates(str(meta.get(key))))
        pages = []
        for n, page in enumerate(reader.pages, 1):
            text = (page.extract_text() or "").strip()
            if text:
                pages.append(f"## Page {n}\n\n{text}")
    except PdfReadError as exc:
        raise IngestError(f"cannot read {path.name} as pdf: {exc}") from None
    if not pages:
        raise IngestError(f"{path.name}: no extractable text (scanned PDF? OCR is not included)")
    return Document("\n\n".join(pages), title, "pdf", _dedupe(labels), pages=len(reader.pages))


# -- into the brain --------------------------------------------------------------------------
def build_note(src: Path, doc: Document, sha: str, ntype: str, title: str | None,
               project: str | None, tags: list[str] | None) -> tuple[dict, str]:
    meta: dict = {"title": (title or doc.title).strip(), "type": ntype}
    if project:
        meta["project"] = notes.slugify(project)
    meta["tags"] = tags or []
    meta["created"] = notes.today()
    meta["updated"] = notes.today()
    source = {"path": str(src), "file": src.name, "format": doc.format, "sha256": sha,
              "ingested": dt.datetime.now().isoformat(timespec="seconds")}
    if doc.pages:
        source["pages"] = doc.pages
    if doc.labels:
        source["labels"] = doc.labels
    meta["source"] = source
    return meta, doc.markdown


def find_by_source(home: Path, sha: str | None = None, path: str | None = None) -> Path | None:
    for p in notes.iter_notes(home):
        text = p.read_text(encoding="utf-8", errors="replace")
        if "source:" not in text[:4000]:
            continue
        src = notes.split_frontmatter(text)[0].get("source")
        if isinstance(src, dict) and ((sha and src.get("sha256") == sha)
                                      or (path and src.get("path") == path)):
            return p
    return None
