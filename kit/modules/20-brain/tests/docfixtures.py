"""Build small office, PDF and HTML documents for tests without any office library."""

import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def _core(title="", keywords=""):
    return (f'{CT}<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/'
            f'metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
            f'<dc:title>{escape(title)}</dc:title><cp:keywords>{escape(keywords)}</cp:keywords>'
            f'</cp:coreProperties>')


def _custom(label):
    return (f'{CT}<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/'
            f'custom-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/'
            f'docPropsVTypes"><property fmtid="{{D5CDD505-2E9C-101B-9397-08002B2CF9AE}}" pid="2" '
            f'name="MSIP_Label_1234_Name"><vt:lpwstr>{escape(label)}</vt:lpwstr></property>'
            f'</Properties>')


def docx(path: Path, title="", label=None, paras=(), table=None) -> Path:
    """paras: list of (style, text); style '' | 'Heading1' | 'Heading2' | 'List'."""
    body = []
    for style, text in paras:
        ppr = ""
        if style == "List":
            ppr = '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>'
        elif style:
            ppr = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>'
        body.append(f'<w:p>{ppr}<w:r><w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>')
    if table:
        rows = "".join("<w:tr>" + "".join(
            f"<w:tc><w:p><w:r><w:t>{escape(c)}</w:t></w:r></w:p></w:tc>" for c in r) + "</w:tr>"
            for r in table)
        body.append(f"<w:tbl>{rows}</w:tbl>")
    styles = (f'{CT}<w:styles {W}>'
              '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>'
              '</w:styles>')
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("[Content_Types].xml", f"{CT}<Types/>")
        z.writestr("word/document.xml", f'{CT}<w:document {W}><w:body>{"".join(body)}</w:body></w:document>')
        z.writestr("word/styles.xml", styles)
        z.writestr("docProps/core.xml", _core(title))
        if label:
            z.writestr("docProps/custom.xml", _custom(label))
    return path


def pptx(path: Path, slides, notes=None, label=None) -> Path:
    """slides: list of (title, [bullets])."""
    P = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
         'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
         'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
    REL = "http://schemas.openxmlformats.org/package/2006/relationships"
    with zipfile.ZipFile(path, "w") as z:
        ids = "".join(f'<p:sldId id="{256 + i}" r:id="rId{i + 1}"/>' for i in range(len(slides)))
        z.writestr("ppt/presentation.xml", f"{CT}<p:presentation {P}><p:sldIdLst>{ids}</p:sldIdLst></p:presentation>")
        rels = "".join(f'<Relationship Id="rId{i + 1}" Type="x" Target="slides/slide{i + 1}.xml"/>'
                       for i in range(len(slides)))
        z.writestr("ppt/_rels/presentation.xml.rels", f'{CT}<Relationships xmlns="{REL}">{rels}</Relationships>')
        for i, (title, bullets) in enumerate(slides, 1):
            paras = "".join(f"<a:p><a:r><a:t>{escape(b)}</a:t></a:r></a:p>" for b in bullets)
            xml = (f"{CT}<p:sld {P}><p:cSld><p:spTree>"
                   f'<p:sp><p:nvSpPr><p:cNvPr id="1" name="t"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
                   f"<p:txBody><a:p><a:r><a:t>{escape(title)}</a:t></a:r></a:p></p:txBody></p:sp>"
                   f'<p:sp><p:nvSpPr><p:cNvPr id="2" name="b"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>'
                   f"<p:txBody>{paras}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>")
            z.writestr(f"ppt/slides/slide{i}.xml", xml)
            if notes and i in notes:
                z.writestr(f"ppt/slides/_rels/slide{i}.xml.rels",
                           f'{CT}<Relationships xmlns="{REL}"><Relationship Id="rId9" Type="n" '
                           f'Target="../notesSlides/notesSlide{i}.xml"/></Relationships>')
                z.writestr(f"ppt/notesSlides/notesSlide{i}.xml",
                           f'{CT}<p:notes {P}><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="3" name="n"/>'
                           f'<p:cNvSpPr/><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody>'
                           f"<a:p><a:r><a:t>{escape(notes[i])}</a:t></a:r></a:p></p:txBody></p:sp>"
                           f"</p:spTree></p:cSld></p:notes>")
        z.writestr("docProps/core.xml", _core(""))
        if label:
            z.writestr("docProps/custom.xml", _custom(label))
    return path


def xlsx(path: Path, sheets) -> Path:
    """sheets: list of (name, rows); strings go to sharedStrings, numbers stay numbers."""
    S = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    R = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    REL = "http://schemas.openxmlformats.org/package/2006/relationships"
    shared: list[str] = []
    with zipfile.ZipFile(path, "w") as z:
        sh = "".join(f'<sheet name="{escape(n)}" sheetId="{i}" r:id="rId{i}"/>'
                     for i, (n, _) in enumerate(sheets, 1))
        z.writestr("xl/workbook.xml", f"{CT}<workbook {S} {R}><sheets>{sh}</sheets></workbook>")
        rels = "".join(f'<Relationship Id="rId{i}" Type="x" Target="worksheets/sheet{i}.xml"/>'
                       for i in range(1, len(sheets) + 1))
        z.writestr("xl/_rels/workbook.xml.rels", f'{CT}<Relationships xmlns="{REL}">{rels}</Relationships>')
        for i, (_, rows) in enumerate(sheets, 1):
            xml_rows = []
            for r, row in enumerate(rows, 1):
                cells = []
                for c, val in enumerate(row):
                    ref = f"{chr(65 + c)}{r}"
                    if val is None:
                        continue
                    if isinstance(val, (int, float)):
                        cells.append(f'<c r="{ref}"><v>{val}</v></c>')
                    else:
                        shared.append(val)
                        cells.append(f'<c r="{ref}" t="s"><v>{len(shared) - 1}</v></c>')
                xml_rows.append(f'<row r="{r}">{"".join(cells)}</row>')
            z.writestr(f"xl/worksheets/sheet{i}.xml",
                       f"{CT}<worksheet {S}><sheetData>{''.join(xml_rows)}</sheetData></worksheet>")
        sst = "".join(f"<si><t>{escape(s)}</t></si>" for s in shared)
        z.writestr("xl/sharedStrings.xml", f"{CT}<sst {S}>{sst}</sst>")
    return path


def pdf(path: Path, pages, title="", keywords="") -> Path:
    """Minimal valid PDF with one Helvetica text line per entry of each page."""
    objs = ["<< /Type /Catalog /Pages 2 0 R >>", None,
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    kids = []
    for lines in pages:
        ops = ["BT /F1 12 Tf 72 720 Td 14 TL"]
        for ln in lines:
            ops.append("(" + ln.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ") Tj T*")
        ops.append("ET")
        stream = "\n".join(ops)
        objs.append(f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream")
        content_id = len(objs)
        objs.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                    f"/Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>")
        kids.append(f"{len(objs)} 0 R")
    objs[1] = f"<< /Type /Pages /Kids [{' '.join(kids)}] /Count {len(kids)} >>"
    objs.append(f"<< /Title ({title}) /Keywords ({keywords}) >>")
    info = len(objs)
    out = b"%PDF-1.4\n"
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n".encode("latin-1")
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(out)
    return path
