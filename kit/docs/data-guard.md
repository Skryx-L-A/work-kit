# 40-data-guard: hook mechanics, files, tests

## Hook mechanics

- With `30-agent-setup` installed, its git hooks in `~/.config/work-kit/git-hooks` run
  data-guard: `--global-hooks` only sets a flag there and `install-hook` lists the repository
  in `~/.config/work-kit/hooked-repos.list`.
- `uninstall.sh` keeps policy, deny-list and hooked-repos.list; `install.sh` restores the hooks.
- `data-guard enable-global` / `disable-global` set or remove `core.hooksPath` (the same opt-in
  as `install.sh --global-hooks`); `remove-hook` removes a per-repository hook and restores a
  chained older one.

## Files

- Policy to edit: `~/.config/work-kit/data-classes.md` (`TODO(ask IT)` items) and
  `~/.config/work-kit/deny-patterns.txt`.
- `data-guard deny list` shows the deny-list, `data-guard deny path` its location.

## Missing scanner: fail closed (security review 2026-09-26)

Without `gitleaks` the guard cannot look for secrets, so it stops instead of letting the commit
pass unseen:

- `data-guard staged` (the pre-commit hook), `check` and `scan` print `BLOCKED: gitleaks not
  found` and exit 2; the commit is refused. The message names the fix (install module
  10-base-tools) and the one-line override.
- The plain hook stub and the kit-sync dispatcher (`30-agent-setup/git-hooks/dispatch`) do the same
  when the `data-guard` binary itself is missing while data-guard is enabled for the repository.
- Override, for one command only: `DATA_GUARD_ALLOW_UNSCANNED=1 git commit ...`. It prints a
  warning; the deny-list still applies. There is no persistent switch on purpose.
  `DATA_GUARD_STRICT=1` refuses even that override (for scripts).
- `data-guard status` shows the missing scanner in red (`NOT FOUND - commits are BLOCKED`); red
  needs a terminal and `NO_COLOR` unset, `DATA_GUARD_COLOR=always` forces it. `install.sh` warns
  the same way.
- This does not replace server-side secret scanning: a hook runs on the laptop and can be skipped
  (`--no-verify`, another tool). Repositories that hold no hook are not covered.

## Tests

`bash tests/test-hook.sh` (needs gitleaks), `bash tests/test-dispatcher.sh` (deny-list only, runs
with the override), `bash tests/test-cli.sh`, `bash tests/test-fail-closed.sh` (no gitleaks: blocked
commit, override, status in red, stub, dispatcher).
