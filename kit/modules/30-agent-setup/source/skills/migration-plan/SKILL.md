---
name: migration-plan
description: Turn a validated behavioral spec and a chosen modernization option into an executable migration plan - target architecture, incremental strangler steps traced to spec items, data migration, rollback per step, cutover and decommissioning. Use after modernization-assessment picked a path and modernization-spec is validated, before writing target code. Do not use for a small refactoring inside one module (use refactoring-plan), without a validated spec for the scope, or to decide whether to modernize at all (use modernization-assessment).
---

# Migration Plan

Goal: a plan a team can execute in small releasable increments, where every increment says
which spec items it moves, how it is verified against the legacy behavior, and how to undo it.
This skill builds on `refactoring-plan` (patterns, Mikado, step template) and adds the parts a
system-level migration needs: target architecture, data, cutover and traceability.

## Inputs you need

- Validated spec, traceability matrix and sign-off record (`modernization-spec`). If the
  status is not `validated` for the scope, stop and report the block.
- Assessment result (`modernization-assessment`): chosen option per component, drivers,
  constraints, budget frame.
- Characterization tests that run (`characterization-tests`); they are the acceptance
  suite for every increment.
- Constraints from the customer: freeze windows, hosting, allowed technology, who operates
  the target system, data residency (`data-guard`, ask IT where unknown).
- Earlier decisions: `brain search "<system> target architecture" --project <slug>`.

## Procedure

1. **State the target.** Capabilities, technology stack and hosting, integration points,
   what stays in the legacy system, and non-goals. One diagram is enough (`d2` if installed).
   Record each significant choice as a decision (`decision-record`), with the alternatives
   the assessment rejected.
2. **Partition the spec into increments.** Group spec IDs into slices that can move
   independently along seams found in the code map (module borders, routes, batch jobs,
   tables). Order: low risk and high learning first, shared data last, a thin vertical
   slice before broad ones. Every `keep` and `change` ID lands in exactly one increment;
   `drop` IDs get a retirement step; `unknown` IDs stay out until answered.
3. **Choose the routing mechanism** for coexistence (strangler facade, reverse proxy rules,
   feature flags, branch by abstraction; patterns in `refactoring-plan`). Say where the switch
   sits and who can flip it without a deployment.
4. **Plan the data** (references/data-migration.md): ownership per table, expand/migrate/
   contract for schema changes, initial load, sync direction during coexistence, reconciliation
   queries, and what happens to data written on the wrong side.
5. **Write each increment** with the template below. Each one is releasable alone, carries its
   spec IDs, has a verification (characterization tests run against legacy and target, plus
   reconciliation), and a rollback that was actually tried on a test environment.
6. **Plan the cutover** per increment (references/cutover-checklist.md): rehearsal, freeze,
   go/no-go criteria decided beforehand, monitoring, rollback trigger and time limit, who
   decides. Keep old and new running in parallel until the exit criteria hold.
7. **Plan decommissioning.** When a legacy part has no traffic and no data writes for an agreed
   period, remove it and set the matrix rows to `retired`. Unscheduled contract steps are a
   plan defect.
8. **Set the traceability rules.** Commits and pull requests name their spec IDs
   (`Refs: BR-001`); target tests reference the spec ID in name or comment; the matrix is
   updated in the same change (`bash ~/.agents/skills/modernization-spec/scripts/trace-check.sh spec.md
   traceability.csv --strict`). Set matrix status `planned` for all IDs in the plan.
9. **Review.** A human expert reviews the plan; a customer-facing plan also goes to the
   requester. Store it: `brain new decision "<system>: migration plan v1" --project <slug>
   --body -`, or `docs/modernization/migration-plan.md` without `brain`.

## Plan template

```
# <System> migration plan v<n> (<date>)
Spec version and sign-off: <ref>      Assessment: <ref>
Target architecture (diagram, stack, hosting, integrations):
Decisions taken (links) and rejected alternatives:
Routing / coexistence mechanism and who can switch it:
Data plan: <see references/data-migration.md>
Increments:
  I-01 <name> | spec IDs: BR-001, BR-004 | prerequisites: |
       change: <what moves> | verify: <tests + reconciliation> |
       rollback: <how, tried on: env/date> | exit criteria: | size: S/M/L
Cutover plan: <see references/cutover-checklist.md>
Decommissioning steps and conditions:
Traceability rules and matrix location:
Risks, assumptions, open questions (owner):
```

## Done when

- Every `keep`/`change` spec ID belongs to one increment; `drop` and `defer` IDs are listed.
- Each increment has verification, a tested rollback and exit criteria.
- The data plan names ownership, reconciliation and the coexistence rules.
- Cutover, rollback triggers and decommissioning are planned, not implied.
- The matrix shows all planned IDs as `planned`, and `trace-check.sh --strict` passes.
- A human expert has reviewed the plan.

## Pitfalls

- Planning increments that only work together. If two steps cannot be released separately,
  they are one step.
- Forgetting non-code consumers of legacy data: reports, exports, jobs, other systems.
- Untested rollback ("we would restore the backup"). Restore it once and time it.
- Migrating data last, in one weekend. Rehearse loads and reconciliation early.
- New behavior slipped into a migration increment. Behavior changes are separate, labeled
  spec `change` items with their own validation.
- Leaving the strangler facade and the old path in place forever. Schedule removal.
- Changing the spec inside the plan. Spec changes go back through the validation gate.

## Related skills

`modernization-spec`, `modernization-assessment`, `refactoring-plan`, `characterization-tests`,
`dependency-upgrade`, `decision-record`, `git-workflow`, `verification`, `data-guard`,
`modernization-workflow`. Templates: references/data-migration.md, references/cutover-checklist.md.
