# 19-enablement: install behavior, tests

Re-running `install.sh` is safe: files you edited stay as they are; only when the kit ships a
new version of a file you edited is yours kept first, as `<file>.bak-<timestamp>` below
`~/.local/share/work-kit/backups/19-enablement/` (same relative path, original recorded in
`.origin`). `ENABLEMENT_HOME` overrides the target folder (default `~/work/enablement`).

Tests: `bash tests/test-install.sh` in the module folder.
