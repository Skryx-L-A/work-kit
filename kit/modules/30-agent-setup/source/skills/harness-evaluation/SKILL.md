---
name: harness-evaluation
description: 'Compare AI coding CLIs (Claude Code, Codex CLI, opencode, Copilot CLI, Aider, Gemini CLI, or others) on the same small coding and documentation tasks, each in a fresh temporary git repo with a script check. Use when choosing which approved harness a team should use, after a harness or model upgrade, or to back a tool recommendation with numbers. Do not use for comparing raw models behind one API (model-evaluation) or inference engines (engine-evaluation).'
---

# Harness evaluation

A harness is the model plus its agent loop, tools and defaults. Compare them the way a
developer uses them: a task in a repo, judged by whether the result works.

## Tools

- Pack: `~/work/kit/modules/50-eval/packs/harnesses/` with five synthetic tasks
  (`fix-bug`, `add-tests` with planted-bug check, `rename`, `doc-readme`, `legacy-explain`),
  `harness_run.py`, `harnesses.conf.example`, `suite.yaml` and `run.sh`.
- `evalkit` (module 50-eval) runs the suite; `llm-usage` (module 14-llm-usage, optional)
  records each harness call when `HARNESS_LLM_USAGE=1`.

## Procedure

1. **Scope**: only harnesses IT approved, each logged in with the account and model the team
   would use. Write down harness version (`<tool> --version`) and model per harness.
2. **Data**: the shipped tasks are synthetic. If you add tasks, use synthetic or public code
   only; every cloud harness sends the repo content to its provider.
3. **Config**: `cp harnesses.conf.example harnesses.conf`, keep the approved lines and check
   each command with `<tool> --help` (flags change between versions). Commands run with
   stdin closed and must not wait for confirmation; use each tool's edit-permission flag,
   never a flag that disables its sandbox.
4. **Dry run**: `bash run.sh --harnesses fake-good,fake-noop` must give 100 % and 0 %.
5. **Run**: `bash run.sh --harnesses claude,codex -n 2` (`--tasks fix-bug,rename` for a
   subset, `--keep` to inspect the temp repos). Each task runs in a new temp git repo with
   a baseline commit and git hooks disabled; `check.py` decides pass or fail.
6. **Inspect**: in the evalkit JSON, `runs[].output` holds the runner's JSON line: check
   result and reason, harness exit code, duration, changed files. Look at failures with
   `--keep`: wrong fix, files changed that should not be, harness asked a question and
   stopped, timeout (`HARNESS_TIMEOUT`, default 600 s).
7. **Report**: pass rate per harness and task, median duration, cost if known (`llm-usage
   summary --by tag` or the provider's usage page), plus qualitative notes (asked for
   confirmation, edited tests, touched unrelated files). Save to the brain with versions.

## Adding a task

`tasks/<id>/prompt.md` (what a developer would type), `repo/` (starting files),
`solution/` (a known good result, used by `fake-good`), `check.py` (runs in the repo, exit 0 =
pass, last line = reason; compare protected files against `$EVAL_TASK_DIR/repo`). Add a case
to `suite.yaml` and confirm fake-good passes and fake-noop fails.

## When a tool is missing

- No `evalkit`: `echo fix-bug | python3 harness_run.py --harness claude` runs one task and
  prints the JSON line; loop over tasks by hand.
- A harness not installed: remove it from the run; do not install tools IT did not approve.

## Done when

- Every harness ran every task with the same repetitions; `comparison.md` exists.
- Versions, models, date and machine are recorded next to the numbers.
- Failures were inspected, not only counted.

## Pitfalls

- Running a harness in your real repo instead of the temp copy (always go through the runner).
- Flags that auto-approve everything including shell commands outside the repo.
- Five tasks separate "works" from "does not work", not two good harnesses; add tasks from
  the team's real work (synthetic copies) before a close call.
- Counting a pass when the harness edited the check's protected files: `check.py` must
  compare them with the originals.
