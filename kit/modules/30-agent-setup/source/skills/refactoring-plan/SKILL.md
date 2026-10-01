---
name: refactoring-plan
description: Plan a structural change to existing code as a sequence of small, safe, individually shippable steps (Mikado graph, strangler fig, branch by abstraction, parallel change). Use before a refactoring that touches more than a few files, replaces a module, or must happen while the system stays in production. Do not use for a local cleanup you can finish and verify in one small commit, for deciding whether to modernize at all (use modernization-assessment), or for feature design.
---

# Refactoring Plan

A refactoring changes structure without changing observable behavior. The plan's job is to
keep the system working and releasable after every step, so that work can stop at any point.

## Inputs you need

- The goal in one sentence and why (for example "move invoice calculation out of the UI form
  so it can be tested and reused by the new API").
- A code map of the affected area (`legacy-code-analysis`), or at least its entry points,
  data access and callers.
- Safety net status: which behavior is covered by tests or characterization tests. If the
  area has no net, step 1 of the plan is `characterization-tests`.
- Constraints: release cadence, freeze windows, other teams touching the same code, database
  ownership, whether old and new versions must run side by side.
- Earlier decisions: `brain search "<module> refactoring" --project <slug>` (skip if `brain`
  is not installed and ask the team instead).

## Procedure

1. **Define done and non-goals.** Observable end state (what exists, what is gone) and what
   will explicitly not change (behavior, public interfaces, schema, unless stated).
2. **Discover prerequisites with the Mikado method.** Try the goal change naively in a
   throwaway branch. Note what breaks (compile errors, failing tests). Each break becomes a
   prerequisite node. Revert, then try one prerequisite, repeat. Stop when you reach leaves
   that can be done safely on their own. The result is a dependency graph of small changes.
3. **Pick a migration pattern for anything larger than a function:**
   - *Parallel change (expand, migrate, contract)* for interfaces and schemas: add the new
     form, move callers, remove the old form in a later release.
   - *Branch by abstraction* for replacing an implementation in place: introduce an
     abstraction, route callers through it, build the new implementation behind it, switch,
     delete the old one.
   - *Strangler fig* for replacing a module or system: put a routing facade in front,
     move one capability at a time to the new code, retire the old part when nothing routes
     to it.
4. **Order the steps.** Leaves of the Mikado graph first. Each step: one intent, small diff,
   builds, tests pass, can be merged and released alone. Mark steps that change behavior
   on purpose; they are not refactorings and need their own review.
5. **Plan verification per step.** Which tests or characterization tests prove it, and which
   manual checks if any. Add missing tests as explicit earlier steps.
6. **Plan data and rollout.** For schema or data moves: backward-compatible migrations,
   backfill strategy, how both versions coexist, rollback for each step. Use feature flags
   or routing switches for the switch-over steps.
7. **Estimate and mark checkpoints.** Rough size per step, and points where the work can
   pause with the system in a coherent state.
8. **Record the plan** where the team sees it (ticket, repository `docs/`, or
   `brain new note "<module>: refactoring plan" --project <slug> --body -`). Significant
   pattern choices go into a decision record.

## Plan template

```
Goal / why:
Done state:            Non-goals:
Safety net today:      Missing tests (become first steps):
Pattern(s):            Why this pattern:
Steps (each releasable):
  1. <change>  | verify: <tests/check> | rollback: <how> | size: S/M/L
Mikado graph: <link or indented list>
Data / schema steps and coexistence:
Checkpoints where work can stop:
Risks and open questions:
```

## Done when

- Every step is small, has one intent, a verification method and a rollback path.
- The system is buildable and releasable after each step.
- Behavior-changing steps are separated and labeled.
- Missing safety net is scheduled before the steps that need it.
- The plan is stored where the team works and the requester has agreed to it.

## Pitfalls

- Big-bang rewrite disguised as a refactoring. If a step cannot be released alone, split it.
- Mixing refactoring with bug fixes or features in one commit or pull request.
- Long-lived refactoring branches that drift from main. Prefer small merges behind flags.
- Forgetting non-code consumers: reports, database jobs, other systems reading the same tables,
  file formats exchanged with partners.
- Leaving the "contract" phase undone, so old and new paths live forever. Schedule the removal.
- Planning from memory of the code instead of from the Mikado experiment and a current map.

## Related skills

`legacy-code-analysis`, `characterization-tests`, `modernization-assessment`,
`test-strategy`, `git-workflow`, `verification`. Sources: references/sources.md.
Modernization chain (`modernization-workflow`): for a whole-system migration use `migration-plan`.
