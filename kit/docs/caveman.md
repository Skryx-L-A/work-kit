# 31-caveman: options, locations, tests

## Install options

```sh
bash install.sh --all                     # every harness, detected or not
bash install.sh --harness claude,codex
bash install.sh --dry-run                 # show changes, write nothing
bash install.sh --project DIR             # optional: AGENTS.md, .github/copilot-instructions.md, .cursor/rules
bash uninstall.sh --project DIR
```

Later, without the stick: `kit-caveman install --harness cursor` (also `--all`, `--harness LIST`,
`--dry-run`, `--project DIR`; `kit-caveman verify` checks the upstream copy).

## Locations

- Claude Code: hooks in `~/.claude/settings.json`, skill `caveman`, rule in `~/.claude/CLAUDE.md`.
- Without `node` the hooks fall back to shell (level full only).
- Cursor user rules cannot be written from outside: paste
  `~/.local/share/work-kit/generated/caveman-cursor-user-rule.md` into Cursor Settings > Rules.
- Level in Claude Code: `/caveman lite`, `/caveman full`, `/caveman ultra`; off: "stop caveman".

Decisions: `NOTES.md` in the module folder.

## Tests

`bash tests/run-tests.sh` (temp HOME, hook run directly, with and without node).
