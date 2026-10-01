---
name: session-end
description: 'Close a work session when the user says they are done, asks to wrap up, or hands over. Save durable knowledge to the brain, stop processes this session started, and report the exact state and open work. Do not use in the middle of a task, for a single quick question, or as a reason to start new tests or reviews.'
---

# Session end

Close the work so that the next session (yours, a colleague's or an agent's) can continue
without asking. Record only what actually happened.

## Procedure

1. **Collect.** From this session list:
   - what was done (files, commits, tickets, documents),
   - decisions made and their reasons,
   - evidence: which checks ran, with the observed result,
   - open points, blockers and the next concrete step,
   - pitfalls found (something that cost time and will again).
2. **Check the repository state** of every repo touched: `git status --short`,
   `git log --oneline -5`, unpushed commits (`git log @{u}.. 2>/dev/null`). Do not commit
   or push only because the session ends; do it if the task or the user asked for it.
3. **Stop owned resources.** Background jobs, dev servers, containers, watchers, test
   databases started in this session: stop them and confirm they are gone
   (`jobs`, `ps -o pid,cmd -u "$USER" | grep <name>`, `docker ps`). Never stop processes
   you did not start. If something cannot be stopped, list it as an open point with its PID.
4. **Save knowledge** (see the `brain` skill):
   - Session note: `brain new session "<project>: <what was achieved>" --project <slug> --body -`
   - A new pitfall or changed decision: update `projects/<slug>/KERN.md`.
   - A decision with real alternatives: write an ADR (`decision-record` skill).
   - A reusable procedure: `brain new howto "<title>"`.
   Skip what is already in commit messages, tickets or the code itself.
5. **Report** to the user in a short block (template below).

## Session note template

```markdown
## Result
<one or two sentences: what works now that did not before>

## Changes
- <repo/path or document>: <what changed> (<commit hash>)

## Evidence
- `<command>`: <observed result>

## Decisions
- <decision>: <reason> (ADR: <link>, if written)

## Open
- <open point> — next step: <concrete action>, owner: <who>

## Pitfalls
- <what went wrong and how to avoid it>
```

## When `brain` is missing

Write the same note as `~/work/brain/projects/<slug>/sessions/<yyyy-mm-dd>-<topic>.md`
(create folders if needed) and commit it if the folder is a git repo. If no notes folder
exists and the user has not set one up, put the note into the final chat message and say
where it could be saved.

## Done when

- Every durable result is saved in one place, or the user was told why not.
- Every process started by this session is stopped, or listed as open with its PID.
- The report names repo state (clean / uncommitted / unpushed) for every repo touched.
- Open points each have a next step.

## Pitfalls

- Claiming "tests pass" from memory. Report only checks that ran in this session, with
  their output, or say "not re-checked".
- Running a full test suite or new review only because the session ends. Reuse evidence.
- Writing a diary. The note is for someone who continues the work, not a log of the chat.
- Secrets or customer data in the session note: summarize without them.
- Rewriting an older session note. Add a new one that corrects it.
