# kit/install

Menu installer for `kit/modules/*/`. Python 3 standard library only, no network, no sudo.

```
kit/install                    # menu; shows failed, not selected and changed installed modules
kit/install --update           # reinstall exactly the installed modules changed in this kit
kit/install --all              # show every module
kit/install --select 00,20,71  # no menu: ids or numeric prefixes; 'all' = every module without a group
kit/install --uninstall 20,71  # remove installed modules (ids, numeric prefixes or 'all'), asks first on a terminal
kit/install --uninstall all --yes   # no question (needed without a terminal)
kit/install --permissions ask  # approval mode of the AI harnesses (bypass|ask); the menu asks once without it
kit/install --dry-run          # plan only
kit/install --status           # recorded state only
kit/install -v --timeout 9000  # show module output; limit per module in seconds (default 7200)
bash tests/installer/run-tests.sh
```

- Menu: `whiptail` or `dialog` on a terminal, plain prompts otherwise (`KIT_INSTALL_UI=plain|whiptail|dialog`).
  The box is sized to the terminal (`COLUMNS`/`LINES`, tty size, else 80x24), items read `71 delegate`,
  descriptions are cut at a word boundary to the width left.
- Modules of one `group` (orchestration: 70, 71, 72) are alternatives: pick one. The first member (70) is highlighted, so Enter takes it; `none` (whiptail: first entry, plain prompt: `0`) skips the group. A group with an installed member is hidden.
- Module options travel as environment variables. `--permissions` (or `KIT_PERMISSIONS`) becomes `KIT_PERMISSIONS`
  for `30-agent-setup`, which passes it to `kit-sync --permissions`. Without it, nothing is passed and kit-sync
  keeps its saved mode (`~/.config/work-kit/kit.conf`) or uses `bypass`.
- Missing dependencies are added to the run. A module whose dependency failed is not run (failed, step `dependency check`).
- Install order: dependencies first, then `after` neighbours, then folder name. An `after` cycle is warned about and ignored.
- Every run ends with the check report: the `check` of each installed module. A failing check marks it failed (step `check`).
- An installed module is marked `update available` when its module files or declared offline artifacts changed.
  It is shown and preselected in the menu; use `install --update` for the non-interactive daily update step.
- State: `~/.local/share/work-kit/install-state.json` (`installed`, `failed` with reason and step, `not_selected`).
  Logs: `~/.local/share/work-kit/install-logs/<module>.log` (previous run: `.log.prev`). `KIT_DATA_DIR` moves both.
- `--status` and the final report also list `<name>.bak-<timestamp>` files found directly in `$HOME` (left by
  older kit versions) and say where new backups go (`~/.local/share/work-kit/backups/<module>/`). They are never deleted.
- A module that has nothing to do on this machine prints a line `KIT_MODULE_SKIPPED: <reason>` and exits 0
  (95-desktop on Xfce, LXQt, MATE, Budgie, Cinnamon). The state is `skipped` with that reason, the report shows
  `skipped` and the reason, no check runs, the logout box is not shown, and the menu offers the module again.
- Exit code: 0 all selected modules installed or skipped, 1 a selected module failed, 2 bad arguments.

## Uninstall

`kit/install --uninstall LIST` runs `uninstall.sh` of the requested modules that are recorded as installed
(`all` = every installed module), in reverse install order: dependents first, `00-python` last.

- On a terminal it lists the modules and asks (`yes` to continue); `--yes` skips the question; without a terminal
  and without `--yes` it stops with exit code 2. `--dry-run` only prints the list.
- A module that an installed module outside the request depends on is kept, with a note.
- Success sets the module back to `not_selected` (the menu offers it again). A failing `uninstall.sh` leaves the
  state `installed`, prints reason and log (`install-logs/<module>.uninstall.log`) and the run exits 1.
- `30-agent-setup/uninstall.sh` runs `kit-sync --uninstall` (managed blocks, generated files, skill links) itself,
  so removing that module cleans the harness files.
- Notes and data folders stay (`~/work/brain`, meeting transcripts, worklog) and so does `~/work/kit`:
  hand them over or delete them by hand.

## module.conf

Every module folder has one. `key=value` lines, `#` comments, no quoting.

| key | meaning |
|---|---|
| `name` | short title |
| `description` | one line shown in the menu |
| `depends` | comma list of module folders that must be installed first (only `00-python` is allowed) |
| `after` | comma list of module folders that should run first when both are selected; ordering only, never adds the other module |
| `group` | alternatives share a group name; empty otherwise |
| `needs_sudo` | `yes` or `no`; a `yes` module is unchecked by default and needs cached sudo credentials |
| `default_on` | `no` = unchecked in the menu (plain prompt defaults to N, the entry says "ask IT first"); default `yes`. `--select` and `all` still install it |
| `check` | shell command, exit 0 = works; light and offline (`command -v tool`); run with `~/.local/bin` in `PATH` |
| `install` | script name, default `install.sh` |
| `offline` | space-separated paths or globs below `kit/offline`; their matching `SHA256SUMS` lines join the installed fingerprint |

The installer runs `bash install.sh` in the module folder with no stdin. A failure is a non-zero exit;
reason = last error-looking output line, step = last progress line (`2/7 ...`, `==> ...`) before it.

After `95-desktop` was installed in a run and the session is GNOME or KDE (`XDG_CURRENT_DESKTOP`), the run ends with a
"Log out and back in" box. In the menu, or with `--select` on a terminal, it asks; only `y`/`yes` logs out
(`gnome-session-quit --logout` or `qdbus org.kde.Shutdown /Shutdown logout`).
