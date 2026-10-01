---
name: modernization-workflow
description: Sequence the modernization skills into one gated chain - assess, characterize, specify with human validation, plan the migration, migrate incrementally with traceability - and track where a project stands. Use when starting or resuming a modernization engagement and you need to know which step and which skill comes next, or when someone asks to "just rewrite it" without the earlier steps. Do not use as a replacement for the individual skills (it only sequences them) or for a single refactoring or dependency bump.
---

# Modernization Workflow

The chain, with the gate after each step. A step is entered only when the previous gate is
closed. AI tools speed up extraction and drafting; the gates are human decisions.

| # | Step | Skill | Output | Gate to pass |
|---|---|---|---|---|
| 1 | Map | `legacy-code-analysis` | code map with commit hash | requester confirms scope |
| 2 | Assess | `modernization-assessment` | option per component, roadmap | expert review, requester decision |
| 3 | Characterize | `characterization-tests` | passing suite for the scope | two clean runs, a deliberate change is caught |
| 4 | Specify | `modernization-spec` | spec, traceability matrix | **validator signs the spec** |
| 5 | Plan | `migration-plan` | increments, data, cutover, rollback | expert review, requester agrees |
| 6 | Migrate | `refactoring-plan` patterns, `git-workflow`, `verification` | target code, matrix at `migrated` | per increment: tests, reconciliation, go/no-go |
| 7 | Retire | `migration-plan` (decommissioning) | legacy removed, matrix `retired` | exit criteria met |

Steps 2 and 3 may run in parallel per component. Small components may combine steps 1-2.

## Working rules

- **State file.** Keep `docs/modernization/STATUS.md` (or a `brain` note created with
  `brain new kern "<system>: modernization status" --project <slug>`): scope, current step,
  gate status with names and dates, spec version, matrix location, open questions. Update it
  whenever a gate closes.
- **No skipping.** No target code before gate 4; no cutover before its checklist.
  If asked to skip, name the gate, the risk and who can accept it, and continue with the
  allowed work meanwhile.
- **Traceability everywhere.** Spec IDs appear in target tests, commits (`Refs: BR-001`) and the
  matrix. `bash ~/.agents/skills/modernization-spec/scripts/trace-check.sh spec.md traceability.csv`
  must pass before each pull request that touches migrated behavior.
- **Behavior first, structure second.** Behavior changes are spec `change` items with their
  own validation, never a side effect of migrating.
- **Data class before every AI call** (`data-guard`); customer code and data stay inside
  approved locations. Say in the STATUS which model or tool touched which artifact.
- **Save results** at each gate (`brain new ...`; without `brain`, in the repository).
- **Stop and ask** when the validator is unknown, the safety net cannot be built, or the
  customer's constraints contradict the plan.

## Resuming

Read `STATUS.md`, check that the code map commit still matches `git log -1`, and re-run the
characterization suite. If the legacy code moved on, update the map and the affected spec
items and re-open their gate before continuing.

## Related skills

All chain skills above, plus `test-strategy`, `dependency-upgrade`, `decision-record`,
`brain`, `session-end`.
