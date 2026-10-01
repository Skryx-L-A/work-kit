# 11-legacy-toolbox

Code-analysis CLIs in `~/.local/bin`: `ctags` `readtags` `scc` `tree-sitter` `semgrep`
`kit-semgrep` `kit-depgraph`. Offline, no sudo. Needs `kit/offline/legacy-toolbox`;
`semgrep` needs `00-python`. Every tool works alone.

```sh
cd ~/work/kit/modules/11-legacy-toolbox && bash install.sh      # all
bash install.sh ctags scc                                       # only these
bash uninstall.sh
```

Open a new terminal.

```sh
scc .                                   # size and languages
ctags -R --output-format=json .         # symbols
tree-sitter parse File.java             # syntax tree
kit-semgrep src/                        # scan with the local rules, offline
kit-depgraph . --format d2 > deps.d2
```

The Semgrep rules are for internal analysis only (their license): do not offer them
as a service to customers.

Languages, build host and tests: `~/work/kit/docs/legacy-toolbox.md`.
