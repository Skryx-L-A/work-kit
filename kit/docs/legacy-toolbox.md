# 11-legacy-toolbox: languages, build host, tests

Installed in `~/.local/bin`: `ctags` `readtags` `scc` `tree-sitter` (Java, C#, C, C++, Python,
JavaScript, TypeScript, SQL, COBOL) `semgrep` `kit-semgrep` `kit-depgraph`. Every tool works alone.

- `tree-sitter` uses prebuilt parsers from `offline/legacy-toolbox/lib` (built on Ubuntu
  24.04 x86_64, glibc 2.14+); a C compiler is only needed for grammars without a prebuilt parser.
- `kit-semgrep [semgrep scan options] PATH ...` scans with the shipped local rules
  (C, C#, Java, JS/TS, Python, shell, Docker), offline; an own `--config` replaces them.
  The rules are for internal analysis only (their license), not as a service to customers.
  Re-running the installer leaves semgrep alone when its installed version equals the pinned wheel.
- `kit-depgraph [PATH] [--format dot|d2|tsv] [--level dir|file] [--depth N] [--external]
  [--exclude GLOB]... [--lang LANG] [-o FILE]`: dependency graph of a source tree
  (import / include / using / COPY statements; a static approximation, cycles highlighted).

## Build host

`bash fetch.sh` fills `kit/offline/legacy-toolbox` (pins and sha256 inside).

## Tests

`bash tests/test-depgraph.sh && bash tests/test-install.sh && bash tests/test-semgrep-rules.sh`
(the last one runs `semgrep --validate` on the shipped rules when semgrep is installed).
