# 90-design

Design references and offline tools for decks, documents and web prototypes. No sudo.
Needs `00-python` and `kit/offline/wheels` for the `kit-design` CLI; the reference folders
install without it. PDF output uses the bundled `kit-chrome-headless` (x86_64, no sudo) or any
Chromium-family browser; DOCX needs `pandoc` (12-docs-tools).

```sh
cd ~/work/kit/modules/90-design && bash install.sh   # ~/work/design-refs/{brand,web,slides,documents,diagrams} + kit-design
bash install.sh --refs-only                          # only the folders
bash uninstall.sh                                    # removes kit-design; your reference files stay
```

Open a new terminal.

Add your reference files to `~/work/design-refs/<folder>/` (each folder has a README). The design
skills read it first when a folder is not empty.

```sh
kit-design refs                          # what is in design-refs
kit-design new deck talk/                # sample deck.md; also: new doc, new web
kit-design deck talk/deck.md             # -> deck.pptx + deck.html (template: design-refs/slides)
kit-design doc report.md -o report.pdf   # also .html, .docx
kit-design theme                         # colours/fonts in use (design-refs/brand/theme.json)
```

Deck syntax and tests: `~/work/kit/docs/design.md`.
