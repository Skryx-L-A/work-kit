# 71-delegate: harness table, tests

## Harness table

`agent-spawn harnesses` prints the built-in table; `~/.config/work-kit/harnesses.conf`
overrides it, lines `name = command` (shell text that can use `$AGENT_PROMPT`,
`$AGENT_PROMPT_FILE`, `$AGENT_TASK_FILE`, `$AGENT_RESULT_FILE`, `$AGENT_MODEL`).
Example entries: `harnesses.conf.example` in the module folder.

`agent-spawn start` options: `--dir DIR` (default: current), `--worktree` (new git worktree,
branch `agent/<name>`, next to the repository; `--base REF` start point), `--result FILE`,
`--model M`, `--session S` (own tmux window), `--close` (close the pane when the harness exits),
`--force` (replace a finished, stopped or lost worker of the same name). `agent-spawn peek
<name> [LINES]` shows recent output. A result is complete when its last non-empty line is
exactly `DONE`.

## Tests

`bash tests/run-tests.sh` (fake harness, private tmux server).
