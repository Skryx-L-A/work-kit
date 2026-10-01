# Workbench hooks (Claude Code)

Installed to `~/.claude/hooks/`; `install.sh` registers them in `~/.claude/settings.json` (a backup
is written first). Other harnesses have no hook interface of this kind; for them the same rules
are in the role files. Tests: `bash tests/test-hooks.sh` and the other `tests/test-*.sh`.

| File | Event | What it does |
|---|---|---|
| `bash-guard.py` | PreToolUse Bash | One process for all Bash guards below plus the question stage. Refuses: `.env` and key files in `git add`/`git commit`, secrets in a staged command, overly broad `pkill`/`killall`/`tmux kill-server`/`kill-session`, `git push` or `gh pr create` from a worker pane, typing into another agent's pane, changing pane roles, touching the approval store, destructive commands without a snapshot, commit messages with an agent co-author trailer. Holds risky commands (`sudo`, `chmod -R`, force push, publish) as a question for a human (`wb-freigabe`). The same guards and the question stage also read a local script that a command starts (`bash x.sh`, `sh x.sh`, `zsh x.sh`, `./x.sh`, `source x.sh`, `. x.sh`; text files up to 256 KiB, one level deep) and name script and line in the answer; an approval binds to the command plus a hash of the script. A variable as the target of `rm`, `mv`, `>` or `kill` inside a script cannot be judged and does not count. Scripts to leave out: globs in `~/.config/work-kit/guard-exceptions.conf`. |
| `bash-guard-*.sh` | (library) | The single guards as separate scripts; `bash-guard.py` is registered, these stay for tests and manual runs. |
| `bash-guard-live-config.sh` | PreToolUse Write/Edit | Warns before test-like writes into the live workbench settings or a live tmux session. |
| `configchange-guard.sh` | ConfigChange | Logs every change to the Claude settings files. |
| `precompact-handoff-gate.sh` | PreCompact | Blocks a compaction when no fresh `HANDOFF-<name>.md` (worker) or `SESSION-STATE.md` / sentinel (orchestrator) exists. |
| `sessionstart-baseline.sh` | SessionStart | Records open ports and processes at session start. |
| `sessionend-orphan-check.sh` | SessionEnd | Lists what the session started and did not stop. |
| `sessionstart-claude-session.sh` | SessionStart | Writes the conversation id into the workbench session state, so `wb-revive` can resume it. |
| `sessionstart-testsuite-status.sh`, `sessionstart-hygiene-status.sh` | SessionStart | Report a red or overdue test / hygiene run (only when their timers are enabled, see `shell/systemd/`). |
| `sessionstart-belegung-ueberfaellig.sh` | SessionStart | Reports an overdue memory booking of a local model server. Silent otherwise. |
| `sessionstart-limit-budget.sh` | SessionStart | Daily budget of a Claude subscription's weekly limit. Not registered by default. |
| `ergebnis-beleg-gate.sh`, `testschutz-gate.sh`, `reviewer-sperre.sh`, `profil-sperre.sh`, `skills-sperre.sh`, `stop-aufgabe-zugende.sh` | PreToolUse / Stop | Enforce the rules of workbench tasks (`wb-aufgabe`): evidence before a result file, no weakened tests, tool locks of a role profile. Silent when no task is active. `*.settings-snippet.json` shows each registration. |

`snapshot-guard-exempt.conf` lists paths that never need a snapshot;
`guard-secrets-content-exceptions.conf` lists accepted secret-like test strings.
Settings of single guards: `wb-state settings` key `guards` (each guard can be switched off with a
reason; the switch-off is logged).
