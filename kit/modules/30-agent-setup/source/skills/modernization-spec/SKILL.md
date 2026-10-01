---
name: modernization-spec
description: Write a behavioral specification of a legacy system or module from its code and characterization tests, get it validated by a human who knows the business, and keep a traceability matrix linking code, spec items and tests. Use after the code map and characterization tests exist and before a migration plan or any target-system code is written. Do not use to specify new features (use technical-writing or a normal design doc), to document code you only skimmed, or when nobody who knows the business can validate the result (stop and escalate instead).
---

# Modernization Spec

Goal: a reviewable statement of what the legacy system does and why, precise enough that a
rebuilt or migrated part can be checked against it. Extraction from code is machine-friendly;
validation is a human decision. No target-system code is generated from an unvalidated spec.

## Inputs you need

- A code map (`legacy-code-analysis`) with commit hash, scope and traced flows.
- Characterization tests (`characterization-tests`) for the scope, passing twice in a row.
- A named validator: someone who knows the business rules (domain expert, product owner,
  long-time maintainer). Get the name before you start; without one the gate cannot close.
- Data class of code and samples (`data-guard`) before sending anything to an AI model.
  Customer code is usually not PUBLIC. Use a locally approved model or work by hand.
- Earlier notes: `brain search "<system> spec" --project <slug>` (skip if `brain` is missing).

## Procedure

1. **Fix the scope.** One capability set per spec (for example "invoice calculation and
   dunning"), tied to the code map's commit. State what is out of scope.
2. **Extract candidate items.** Walk each traced flow and each characterization test. For each
   observable behavior write one item: ID, plain-language statement (inputs, rules, outputs,
   side effects, error cases), and evidence (`file:line`, test name, or `[told by <role>]`).
   Business logic in SQL, triggers, reports, config and batch scripts counts. An AI tool may
   draft items; every item still needs its evidence link, or it is dropped.
3. **Classify each item.** Exactly one of: `intended` (a rule someone can explain),
   `accidental` (works that way, nobody knows why), `defect` (contradicts docs or common
   sense), `unknown` (cannot tell). Only the validator can move an item out of `unknown`.
4. **Collect the open questions.** One question per unclear item, addressed to a role, with
   the evidence that raised it. Do not answer them by guessing.
5. **Decide the target for each item.** `keep` (target must reproduce it), `change` (target
   differs on purpose, needs a rationale), `drop` (feature retired), `defer`. Defects and
   accidental items default to `keep` until the validator says otherwise, so no behavior is
   lost silently.
6. **Build the traceability matrix** (references/traceability-matrix.md): one row per spec
   ID linking code, characterization tests and, later, target code and target tests.
   Check it: `bash ~/.agents/skills/modernization-spec/scripts/trace-check.sh spec.md traceability.csv`.
7. **Run the validation gate** (below). Store the spec, matrix and sign-off record:
   `brain new decision "<system>: behavioral spec v1" --project <slug> --body -`, or in the
   repository (`docs/modernization/`) without `brain`.

## Validation gate

The spec has a status: `draft` -> `in-review` -> `validated` (or `rejected`). Only
`validated` unlocks `migration-plan` and any target-system code.

- The validator reads the spec, not a summary of it, and answers each open question.
- Every item ends as validated, corrected or dropped. Unresolved `unknown` items stay listed
  and block only the parts of the plan that depend on them.
- The sign-off record (references/signoff-record.md) names the validator, date, spec version
  and code-map commit. An agent never signs and never marks the spec `validated` on its own.
- Any later spec change bumps the version and re-opens the gate for the changed items.
- If the validator cannot be found or does not respond, report the block to the requester.
  Do not proceed on an assumed approval.

## Done when

- Every in-scope behavior traced in the code map has a spec item with evidence.
- Every item is classified, has a target decision, and appears in the matrix with at least
  one characterization test (or an explicit `no test: <reason>` that the validator accepted).
- `trace-check.sh` passes; open questions are answered or listed with an owner.
- The sign-off record exists and the status is `validated`.

## Pitfalls

- Writing what the code should do instead of what it does. Record first, judge later.
- Specifying from the AI's summary of the code. Each item needs a checkable evidence link.
- "Cleaning up" accidental behavior in the spec. Downstream systems and reports may depend
  on it; only the validator drops it.
- Skipping the human gate because the spec looks plausible. Plausible is not validated.
- Spec items without a test. They cannot be checked after migration.
- Leaking real customer data into examples. Use synthetic values.

## Related skills

`legacy-code-analysis`, `characterization-tests`, `migration-plan`, `modernization-workflow`,
`technical-writing`, `data-guard`. Templates: references/spec-template.md,
references/traceability-matrix.md, references/signoff-record.md.
