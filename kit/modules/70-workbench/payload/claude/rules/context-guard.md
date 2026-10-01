# Context guard

Read before you start, check or stop the guard, and before you judge a pane's context load.

## What it does

`context-guard` watches the orchestrator and every worker of one workbench session every 60 s.

- Worker at 80 %: it asks the worker to write a complete handoff to `HANDOFF-<name>.md`, then
  types the harness' compaction command and afterwards a resume prompt that points at the handoff.
- Orchestrator at 75 %: it asks you to save your state (see below) and to create the sentinel file
  whose path is in the warning. As soon as the sentinel exists and is newer than the warning, it
  compacts you and sends a resume prompt. At 80 % it compacts without waiting.
- Nobody compacts themselves: a compaction without a resume prompt leaves a pane without a task.

## Operating it

- The spawners start it: `pi-worker` and `claude-worker` run `context-guard --ensure <pane>`
  after every spawn, which starts exactly one guard per session. Start it by hand only in a
  session that never spawns: `context-guard --ensure "$TMUX_PANE"`.
- Your own pane is `$TMUX_PANE`, not `tmux display -p` without a target (that is the pane of the
  attached client).
- Check whether a guard runs by the interpreter that runs the script, not with `pgrep -f`
  (every pattern also matches agent sessions whose prompt contains the word):
  `ps -eo pid,comm,args | awk '$2 ~ /^(bash|zsh|sh)$/ && /bin\/context-guard/'`.
- Stop: `context-guard --stop [<pane|session>]` (no target = this session), `--stop --all` for
  every session. It sees the stop file at its next poll. Delete the stop file only after the
  guard is really gone.
- After installing a new version: stop the running guard with the old version first, then
  install, then start again. The guard's log is the truth about what it did, not pane text.

## Saving state before a compaction (orchestrator)

1. Update `SESSION-STATE.md` in the project: goals, measured state, solved core problems, process
   rules, running workers with pane ids, next steps.
2. Save durable knowledge in the kit brain if it is installed (`brain new` / `brain append`).
3. Check the context of all workers; those above 80 % get a handoff and are compacted by the guard.
4. Then create the sentinel: `touch <path from the warning>`
   (`$PROJECT/.wb-knowledge-saved-<tmux-session>`). Create it only after the guard started; an
   older sentinel is ignored.

## Measuring the load

- For Claude Code the source is the pair `<used>/<total>` in the status line (for example
  `485k/1.0M`); the workbench installs a status line that prints it. For other harnesses the
  registry field `contextPattern` says how to read it.
- In a narrow pane the status line is cut and the load is UNKNOWN, not 0 %. Unknown never means
  "fine": widen the pane or close workers.
- A foreign harness may compact itself; the guard then sends the resume prompt once if a handoff
  was written after its warning and the pane waits empty.
