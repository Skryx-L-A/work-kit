# Safety rules of the workbench

These add to the kit `AGENTS.md`; they never relax it.

## Snapshot before deleting or overwriting

- Before you delete, move over or overwrite non-trivial data that is not committed to git, copy
  it to `~/.local/trash-snapshots/<date>-<name>/`:
  `mkdir -p ~/.local/trash-snapshots/<date>-<name> && cp -a <path> ~/.local/trash-snapshots/<date>-<name>/`.
  The bash guard refuses a destructive command when no snapshot of its target from the last
  120 minutes exists, and prints the command for the snapshot.
- A snapshot is mandatory whenever one is possible. When none is possible (for example a device
  or a medium without a readable file system), proceed without a snapshot and without asking;
  the bash guard does not block that case.

## Questions of the bash guard

- Some commands (for example `sudo`, `chmod -R`, `git push --force`, publishing) are held as a
  question for a human instead of running. The human answers with `wb-freigabe erteilen <pane>`;
  then repeat the command exactly as before.
- A waiting question does not block other commands. If you no longer need it, withdraw it with
  `wb-freigabe zurueckziehen` and continue; a different command is then evaluated on its own.

## Tests and live state

- Tests use their own files, ports, sockets (`tmux -L <name>`) and windows. Never write test data
  into the live workbench settings (`~/.claude/workbench/settings.json`) or type into a live
  session. Ask before any test that makes sound, uses the camera or is visible to others.
- Workers never `git push`, never open pull requests and never install into `~/.local/bin`; the
  bash guard blocks push from a worker pane.
- Commits carry no agent co-author trailer; the bash guard refuses one.
- Kill only processes you started, by PID. Broad `pkill`/`killall` patterns and
  `tmux kill-server` are refused.
