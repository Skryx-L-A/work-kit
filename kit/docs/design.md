# Module 90-design: design notes

## What it provides

- `~/work/design-refs/{brand,web,slides,documents,diagrams}/`: empty folders, each with a
  README that says what to put there. The kit ships no references: company material is added
  on the laptop by the user.
- `kit-design` (Python CLI, installed from `offline/wheels` via `00-python`):
  - `refs`: lists what the folders contain (README.md and hidden files do not count).
  - `deck`: one Markdown source to PPTX (python-pptx) and to a single-file HTML deck.
  - `doc`: Markdown to print HTML, PDF (headless Chromium-family browser) and DOCX (Pandoc).
  - `new deck|doc|web`: starting points; `theme`: shows the colours and fonts in use.
- The skills `document-design`, `presentation-design`, `ui-prototype-design` and `dataviz`
  check the matching folders first and follow their content over the skill defaults.

## How references reach the output

1. Skills: every design skill opens the non-empty folders before designing. This works
   without `kit-design` (plain `ls`), so the rule holds even when the CLI is not installed.
2. `brand/theme.json` (colours, fonts, logo) is read by `kit-design` for PPTX, HTML decks,
   documents and web tokens. Invalid values are ignored with a warning.
3. `slides/`: exactly one `.pptx` or `.potx` is used automatically as the PPTX base; with
   several, `kit-design` lists them and asks for `--template`. `.potx` is opened by
   rewriting its content type in memory (python-pptx cannot open templates directly).
4. `documents/`: exactly one `.docx` is used as Pandoc `--reference-doc` for DOCX output.

## Decisions

- **Own HTML deck engine instead of vendored reveal.js.** The deck is one HTML file with
  inline CSS, JS and images (data URIs): about 5 KB of code, no fetch step, no third-party
  license file, opens from `file://`, prints one slide per page. reveal.js would add a
  download pin and several hundred KB for features (plugins, transitions) the use case does
  not need. Speaker notes (`n`), fullscreen (`f`) and slide URLs (`#3`) are covered.
- **Markdown as the single deck source.** Agents write Markdown reliably; the same file gives
  the editable PPTX colleagues expect in a Microsoft 365 company and the HTML version for
  quick sharing. Layouts: title, section, bullets, big-number, image, two-column, quote.
- **Clean default look drawn on blank slides**, not python-pptx's 4:3 default template:
  16:9, Arial (metric-compatible Liberation Sans on Linux, present in Office everywhere),
  one accent colour, message titles, footer with slide numbers. Font sizes shrink in 2 pt
  steps by a rough line estimate so long text does not overflow; the render check stays
  mandatory.
- **Company template mode reuses the template's layouts and placeholders** (found by name,
  also German names, then by placeholder types), so text inherits its fonts and colours.
- **PDF via a Chromium-family browser**, not WeasyPrint or LaTeX: no extra native libraries,
  good CSS paged-media support (page counters, running footer). Ubuntu ships Firefox by
  default, so PDF needs Chromium, Chrome or Edge; without one, the HTML output is printed
  from any browser. `KIT_DESIGN_BROWSER` selects a binary. Some Chrome builds stay alive
  after writing the PDF; `kit-design` waits for a stable file, then ends the process group.
- **Python-Markdown for documents**, Pandoc only for DOCX: document HTML/PDF works without
  module 12-docs-tools.
- **Document title from content.** The print header uses front matter `title:` first, then the
  first Markdown heading; it uses the file name only when neither exists.
- **Web prototype template runs from `file://`**: data in `data.js`, not fetched JSON.
  States (loading, empty, error) are reachable with `?state=` for reviews.

## Offline artifacts

The wheel step of `build/build-offline.sh` picks the module up through its `pyproject.toml`.
Linux x86_64 / CPython 3.12 dependencies, resolved on 2026-09-25: python-pptx 1.0.2,
lxml 6.1.3, pillow 12.3.0, xlsxwriter 3.2.9, typing-extensions 4.16.0, markdown 3.10.3
(about 12 MB of wheels).

## Verification

`uv run --with pytest pytest tests` (parser, PPTX clean and template/potx mode, HTML
self-containment, theme, CLI template choice, document HTML) and
`TEST_BUILD_WHEELS=1 bash tests/test-install.sh` (folders, README backup, full offline install
from a wheel directory, uninstall keeps user files). Visual check: render the sample deck
(PPTX via LibreOffice to PDF, HTML deck via the browser to PDF), the sample document and the
web template at desktop and phone width, and look at the PNGs.

## Deck syntax

Sample deck: `src/kitdesign/templates/deck/sample-deck.md`; the header keys are parsed by
`src/kitdesign/deck.py`. `kit-design new deck|doc|web DIR` copies the matching template.
