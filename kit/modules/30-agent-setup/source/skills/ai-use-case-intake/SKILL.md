---
name: ai-use-case-intake
description: 'Run the AI use-case portfolio: take in ideas with a short intake form, triage them, score them on four dimensions (value, feasibility, risk, reusability), move them through stage gates with written kill criteria and a pre-build baseline, and list the portfolio from brain notes. Use when someone submits an AI idea, when preparing a gate decision or a portfolio review, or when asked "what AI use cases do we have and where do they stand". Do not use for the detailed business case of one idea (use ai-use-case-assessment) or for designing the pilot test suite (use eval-design).'
---

# AI use-case intake and portfolio

Turns scattered "we could use AI for X" ideas into a portfolio where every case has an owner,
a stage, scores, a baseline and a written kill rule. Each use case is one brain note tagged
`ai-use-case` in project `ai-use-cases`; gate decisions are appended to the note, never
overwritten, so the history stays.

Templates: `references/intake-form.md`, `references/scoring-sheet.md`,
`references/stage-gates.md`. Listing: `scripts/portfolio.py`.

## Procedure

1. **Intake (form, not meeting).** Create the note from the form:
   `brain new note "Use case: <short name>" --project ai-use-cases --tags ai-use-case --body - < references/intake-form.md`,
   then fill in the submitter's answers (edit the file, then commit in the brain repo, or
   append with `brain append`). Six questions are enough; do not ask for a business case yet.
   Set `next_gate` to at most two weeks later. Search first: `brain search "<task>" --project ai-use-cases`
   to find duplicates and killed predecessors.
2. **Triage (G0).** Stop at once if the idea is a prohibited practice or decides about
   people (escalate per the AI usage guideline, skill `ai-policy`). Link duplicates. If the
   correct result cannot be stated, clarify with the submitter (`grill-me`) before scoring.
3. **Score (assessment).** Use the scoring sheet with the owner and a person who does the
   task today. Every score has a reason; unknown scores 2. Append the scores and composite.
   For promising cases, write the detailed business case with `ai-use-case-assessment`.
4. **Gate G1 to pilot.** Only with composite ≥ 2.5, risk > 1, an allowed data route
   (`data-guard`), a **baseline** measured on the fixed example set, written **kill criteria**
   and a pilot plan of at most 12 weeks. Pilot test suite: `eval-design`.
5. **Gate G2 to production.** Pilot results against baseline and kill criteria; staffed
   human review; tool approval and an inventory entry (`ai-inventory`); training for users.
6. **Operate and review.** Quarterly: value against baseline, incidents, costs, model or tool
   changes. Retire cases that no longer pay off; mark them `retired`.
7. **Portfolio listing.** `python3 scripts/portfolio.py` (optional `--stage pilot`, `--json`,
   `--brain DIR`) prints a Markdown table sorted by stage and composite, with flags for
   overdue gates, missing baselines or kill criteria, composites below 2.5 beyond
   assessment, and pilots older than 12 weeks. Put the table into the review note or report.

Every gate is one appended block (see `references/stage-gates.md`):
`brain append <note path> --body -` with `## Gate <date>: G1` and the changed `- key: value`
lines (`stage`, `stage_since`, `decision_by`, `next_gate`, `decision`, scores, `baseline`,
`kill_criteria`). The last value of a key counts.

## When a tool is missing

- No `brain`: keep the same notes as Markdown files with the same frontmatter (`tags:
  [ai-use-case]`) in any folder and pass it with `--brain DIR`.
- No Python: read the notes by hand; the flags above are the checklist.

## Done when

- Every submitted idea has a note, an owner, a stage and a next gate date within two weeks.
- Every case beyond intake has four scored dimensions with reasons and a composite.
- Every pilot has a baseline and written kill criteria from before it started.
- Gate decisions name who decided and why; killed cases keep their reason.
- `portfolio.py` shows no flags, or each flag has an owner and a date.

## Pitfalls

- Pilot purgatory: pilots that never reach a build-or-kill decision. The 12-week flag exists
  for this; a missed gate is a decision to kill unless the sponsor extends it in writing.
- Scoring optimistically to keep a favourite alive. Unknown is 2, not 4.
- Measuring the baseline after the pilot, or from memory.
- Starting from a tool ("what can Copilot do?") instead of a task.
- Rewriting old scores. Append; the change history is the audit trail.
- Real CONFIDENTIAL or CUSTOMER data in the intake note. Describe the data, do not paste it.

## Related skills

`ai-use-case-assessment`, `eval-design`, `ai-inventory`, `ai-policy`, `data-guard`,
`decision-record`, `grill-me`.
