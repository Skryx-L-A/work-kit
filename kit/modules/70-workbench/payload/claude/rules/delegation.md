# Delegation: spawning, tasks, results

Read before you start, reuse or close a worker.

## Spawn

```
claude-worker [--brain on|off] <name> <model>[:effort] <dir> "<task>"
pi-worker [--brain on|off] [--dod "<done criterion>"] <name> <model>[:effort] <dir> "<task>"
```

- `claude-worker` takes the Claude aliases `haiku`, `sonnet`, `opus` (newest enabled registered
  generation) and every model id in the registry. `pi-worker` takes any registry model of any
  harness. `wb-state models table` lists what is registered; `wb-state models list` the ids.
- The effort must not exceed the model's `maxEffort` in the registry. Pick the model by the
  capability the task needs first, then by cost.
- A name is letters, digits, `-` and `_`. The same name reuses the same pane and its context and
  gives the new task its own result path. Send a new task through the spawner again, never with
  `tmux send-keys`: only the spawner records the task and creates its result path. A correction of
  the running task is the exception: `pi-worker <name> --interrupt`, then type the correction.
- In a git repository every worker gets its own worktree
  `~/.pi-workers/worktrees/<name>` on branch `wb/<name>`, created from `HEAD`. Commit first.
  Fresh worktrees have no `node_modules`, `.venv` or build output: put the install step into the
  task. Switch off with `wb-state settings set workerWorktrees false`.
- At most `maxWorkers` (default 8) live workers per session: `wb-state settings get maxWorkers`.
- `--brain off` (or `wb-state settings set workerBrainStep off`) removes the knowledge-base step
  from the protocol. Default: on when the kit `brain` CLI is installed. A file `.wb-ohne-brain`
  in the project folder or a parent always forbids the brain for that project; `--brain on`
  does not override it.

## The task text

Four lines are mandatory: task, exclusively assigned paths, done criterion, context boundary
(what the worker must not know: other workers' areas, unrelated project context, secret paths,
the wider plan). Add the result path, the relevant safety rules, the test window or socket to use
for anything that touches a GUI, and the length of the report if it matters. Do not ask a worker
to "double-check" its result; name what has to run and that the real output belongs in the
result file.

## Result protocol

The spawner appends a `[Protocol]` line. The worker writes its result as Markdown to
`~/.pi-workers/results/<name>/<timestamp>.md` (WHAT / HOW-verified / OPEN) and ends its chat
answer with `DONE`. `latest.md` in the same folder points to a readable placeholder while the
worker runs and to the result once it exists.

- Wait on the dated path the spawn output prints, in the background, with a deadline:
  `timeout 3600 bash -c 'until [ -s <path> ]; do sleep 10; done'`.
- `wb-result <name>`: exit 0 = result on stdout, 1 = not finished or delivery failed.
- A failed delivery writes `<timestamp>.zustellung-fehlgeschlagen.md` instead of a result; read
  it and resend.
- `wb-dod <name>` checks the result against the done criterion given with `--dod`.
- Read the OPEN section completely: admitted problems stand there.

## Sub-worker requests

A worker never spawns. It may request a cheaper worker for a separable part with `wb-request`;
the request lands in `~/.pi-workers/requests/`. Decide with
`wb-decide <request-file> approve|reject [reason]`; on approve it prints the spawn command, which
you run yourself. Reject when: the target is not cheaper; the part is small
(fewer than 10 files and under 15 minutes) or not fully specifiable in writing; name, model,
directory, exclusive paths, task or done criterion are missing; the requester already has two
open requests or children.

## Close

`wb-close <name|pane>` is the only way to close a worker pane (never an orchestrator);
`wb-close --list` shows what can be closed. Save the worker's knowledge first.
`wb-session-close <session>` closes a whole session. `wb-revive <name>` restarts a dead
pane and resumes its conversation where the harness supports it.
