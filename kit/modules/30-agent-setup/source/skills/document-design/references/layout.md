# Layout starting values and defect list

Starting points for a first render; the render then corrects them.

## Genre details

| Genre | Decides quality | Typical failure |
|---|---|---|
| Read front to back | a text column that does not tire; same rhythm on every page | designed like a brochure: boxes, pull quotes, three colours |
| Look things up | findability: numbered headings, running heads, TOC, version on every page | beautiful but no page numbers, headings that differ only by size |
| Decide | page 1: recommendation, cost, date, decider | argument buried in prose, price on page 7 |
| Fill in / sign | clear order, enough space, labels close to fields | fields too small, instructions far from fields |

## Page and text

- A4, margins 20 to 25 mm; 25 mm+ on the binding side if printed and bound.
- Measure: 60 to 75 characters per line for body text. At 11 pt this is about 100 to
  115 mm, not the full A4 width. Use the spare width for a margin column (notes, figures).
- Body 10 to 11.5 pt serif or humanist sans; line height 1.3 to 1.45.
- Headings: at most three levels; distinguish by weight and space, not only by size.
  More space above a heading than below it.
- One spacing unit (e.g. 6 pt or 4 mm); all vertical distances are multiples of it.
- Fonts: use installed, licensed fonts. Good open choices: Source Serif/Sans, IBM Plex,
  Noto, Liberation (metric-compatible with Arial/Times for Office files).
- Colour: near-black body text (#1a1a1a to #333). One accent colour for structure. Contrast
  at least 4.5:1 for any text.
- Numbers in tables right-aligned, tabular figures, units in the header.

## CSS print starter (HTML route)

```css
@page { size: A4; margin: 22mm 20mm 25mm 20mm;
  @bottom-right { content: counter(page) " / " counter(pages); } }
body { font: 10.5pt/1.4 "Source Serif 4", "Noto Serif", serif; color: #222; }
main { max-width: 110mm; }
h1, h2, h3 { font-family: "Source Sans 3", "Noto Sans", sans-serif; break-after: avoid; }
h2 { font-size: 13pt; margin: 18pt 0 6pt; }
table { border-collapse: collapse; } thead { display: table-header-group; }
td, th { padding: 3pt 6pt; border-bottom: 0.5pt solid #bbb; }
p { orphans: 3; widows: 3; }
```

(`@page` margin boxes and `counter(pages)` work in WeasyPrint and Chromium print, not in
every browser.)

## Defect list (check on the rendered pages)

1. Body lines longer than about 80 characters.
2. Default face by accident (fallback font, missing font warning, `pdffonts` shows Type 3).
3. More than three font sizes in the text area of one page.
4. Heading in the bottom 15 % of a page (orphaned heading).
5. A single line of a paragraph alone at the top or bottom of a page.
6. No page numbers in a document longer than four pages.
7. Logo on every page; horizontal rule between every section.
8. Everything centred.
9. Grey body text lighter than about #555.
10. Table continues on the next page without its header row.
11. Images blurry at 100 % zoom, or cropped text in screenshots.
12. Bold used as general emphasis in running text (use italics).
13. Inconsistent date formats or number formats.
14. Placeholder text, "TODO", or tracked changes left in.
