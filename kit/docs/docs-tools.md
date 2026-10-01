# 12-docs-tools: examples, build host, tests

- Dependency graph of a repository (module 11):
  `kit-depgraph . --format d2 > deps.d2 && d2 deps.d2 deps.svg`.
- `d2` writes one format per call, selected by the output extension. The shipped v0.9.0 binary
  has a built-in renderer, so SVG, PNG and PDF work offline without a browser:
  `d2 deps.d2 deps.svg`, `d2 deps.d2 deps.png`, or `d2 deps.d2 deps.pdf`.
- `pandoc notes.md -o notes.docx` converts md, html, docx, pptx, odt; PDF needs a TeX or Typst
  engine (not shipped).
- `dot -Tsvg deps.dot -o deps.svg` needs Graphviz: `bash apt.sh` (sudo, offline apt repository
  of 01-prereqs) or `01-prereqs/install.sh --sudo graphviz`. Graphviz has no static build, so
  this is the only route; nothing else in the kit needs it.

## Build host

`bash fetch.sh` fills `kit/offline/docs-tools` (pins and sha256 inside).

## Tests

`bash tests/test-install.sh`.
