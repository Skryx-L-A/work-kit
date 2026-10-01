# Upstream copy

- Project: caveman, https://github.com/JuliusBrussee/caveman
- License: MIT, Copyright (c) 2026 Julius Brussee (file `LICENSE`, kept unchanged)
- Pinned: tag `v1.9.1`, commit `0d95a81d35a9f2d123a5e9430d1cfc43d55f1bb0` (2026-07-03)
- Files are byte-identical to that commit (checked against `git show <commit>:<path>`).
  Subset only: the SessionStart/UserPromptSubmit hooks, the statusline badge, the `caveman`
  skill and the always-on rule text. Not copied: stats, cavecrew agents, MCP shrink,
  Windows scripts, installers (this module has its own `caveman-setup`).
- Hashes: `SHA256SUMS` (verified by `install.sh` before anything is written).
  Manual check: `cd upstream && shasum -a 256 -c SHA256SUMS`.

Update: copy the same paths from a new upstream commit, run `shasum -a 256` to regenerate
`SHA256SUMS`, change tag and commit above, rerun `tests/run-tests.sh`.
