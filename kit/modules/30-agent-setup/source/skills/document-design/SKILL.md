---
name: document-design
description: 'Design and produce a fixed-page document people will read, print or file: report, concept paper, proposal, handbook, one-pager, as PDF or editable DOCX/ODT. Use when layout and typography matter for the reader. Do not use for slide decks (presentation-design), web UIs (ui-prototype-design), charts alone (dataviz), or plain Markdown notes where formatting is irrelevant.'
---

# Document design

A document is defined by how it is read, not by its file format. Decide the genre first;
every layout choice follows from it. Works with open tools only: Markdown, HTML/CSS,
LibreOffice, Pandoc if installed.

## Design references first

Before any design decision, look into `~/work/design-refs/documents/` and
`~/work/design-refs/brand/` (`DESIGN_REFS` overrides `~/work/design-refs`). List them with
`kit-design refs` or `ls -A`; the kit's `README.md` in each folder does not count.

- **Not empty:** open every file that applies before designing (view images and PDFs, read
  guides) and follow them over the defaults in this skill: a `.docx` template is the style
  reference, an example document sets genre conventions, the brand guide or `brand/theme.json`
  sets colours, fonts and logo. If a reference would break legibility or accessibility, use
  the closest compliant variant and name the conflict. List the references you used in the
  handover.
- **Empty or missing:** use this skill's defaults. Do not invent a company look, logo or brand
  colours. Say in the handover that no references were found and that files put into
  `~/work/design-refs/documents/` and `~/work/design-refs/brand/` will be used next time. For
  a document that leaves the team, ask once whether a company template exists.

## Procedure

1. **Name the genre** (details in `references/layout.md`):
   - *Read front to back* (report, study, concept): calm text column, consistent pages.
   - *Look things up* (handbook, spec, process description): numbered headings, running
     heads, table of contents, version and date on every page.
   - *Decide* (proposal, business case, one-pager): recommendation, cost and date on page 1;
     one claim per section; readable in three minutes.
   - *Fill in / sign* (form, checklist): fields, clear order, room to write.
2. **Choose the format** for the recipient:
   - they only read it: PDF,
   - they must edit it or a company template exists: DOCX/ODT built from that template,
   - it lives in a repository or wiki: Markdown.
   With a company template: use its styles and placeholders; do not draw a competing layout.
3. **Write layout decisions down before styling**: page size, margins, text width, fonts,
   sizes, spacing unit, colours, how tables and figures look. Starting values are in
   `references/layout.md`.
4. **Build with one toolchain** and keep content separate from styling:

| Route | Tools | Command |
|---|---|---|
| Markdown to PDF/DOCX, kit look | `kit-design` (module 90-design) | `kit-design new doc <dir>`, then `kit-design doc in.md -o out.pdf -o out.docx` |
| Markdown to PDF via HTML | Pandoc + browser, or Pandoc + WeasyPrint | `pandoc in.md -s -c print.css -o out.html`, then print to PDF |
| Markdown to DOCX with styles | Pandoc | `pandoc in.md --reference-doc=template.docx -o out.docx` |
| Office document | LibreOffice Writer with paragraph styles | `soffice --headless --convert-to pdf out.docx` |
| Programmatic | Python (`python-docx`) if installed | script + template |

   Use styles (paragraph/character styles, CSS classes), never manual formatting per line.
5. **Render and inspect every page** as images (`pdftoppm -png -r 60 out.pdf page` if
   poppler is installed, or the PDF viewer). Check against the defect list in
   `references/layout.md`. Fix at the source, render again. At most two fix rounds.
6. **Final checks**: date and version, author, page numbers, fonts embedded
   (`pdffonts out.pdf`), links work, no leftover placeholders (`grep -nEi "TODO|XXX|lorem" <source>`),
   data class label if required, file name `yyyy-mm-dd-<title>-v<n>.pdf`.

## Missing tools

Check with `command -v kit-design pandoc soffice pdftoppm`. `kit-design doc` needs a
Chromium-family browser for PDF and Pandoc for DOCX; its HTML output always works. Without Pandoc: write HTML directly with a
print stylesheet and print to PDF from the browser. Without LibreOffice: deliver PDF and say
that no editable version was produced. Do not install software without approval.

## Done when

- The genre is named and the layout decisions are written down.
- Every page was looked at after the last change; no defect from the list remains.
- Metadata (title, date, version, author) is correct; placeholders are gone.
- The recipient can open the format they need.

## Pitfalls

- Full-width body text on A4 (100+ characters per line). Narrow the column.
- Hierarchy only by size; five font sizes on a page.
- A cover with only a logo and title. Page 1 should carry the key fact or recommendation.
- Tables split across pages without repeated header rows.
- Screenshots with customer data or internal hostnames. Check the data class.
- Claiming the PDF looks fine without having rendered and viewed it.
