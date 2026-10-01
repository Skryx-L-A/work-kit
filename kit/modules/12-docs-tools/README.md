# 12-docs-tools

Diagram and document converters in `~/.local/bin`: `d2` and `pandoc` (static Linux x86_64
binaries). Offline, no sudo. Needs `kit/offline/docs-tools`. No other module needed.

```sh
cd ~/work/kit/modules/12-docs-tools && bash install.sh      # both
bash install.sh d2                                          # only this one
bash uninstall.sh
```

Open a new terminal.

```sh
d2 deps.d2 deps.svg                 # one output format per call; works offline, no browser
d2 deps.d2 deps.png                 # PNG also works offline with the shipped d2 v0.9.0
d2 deps.d2 deps.pdf                 # PDF also works offline with the shipped d2 v0.9.0
pandoc notes.md -o notes.docx       # md, html, docx, pptx, odt; PDF needs TeX or Typst (not shipped)
```

Optional Graphviz `dot`, needs sudo and the offline apt repository of 01-prereqs:

```sh
bash apt.sh
dot -Tsvg deps.dot -o deps.svg
```

Dependency-graph example and build host: `~/work/kit/docs/docs-tools.md`.
