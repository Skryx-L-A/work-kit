---
name: decision-record
description: 'Write an architecture or decision record (ADR) when a choice between real alternatives was made or must be proposed: a framework, a migration path, a model or tool, a data flow, a process rule. Use when the reason will matter later or others must agree. Do not use for choices without alternatives, reversible trivia (naming, formatting), or to document code behaviour (use technical-writing).'
---

# Decision record

An ADR preserves why something was chosen so that nobody has to reconstruct it later, and
so that a changed situation can be recognized. Short and specific beats complete.

## Procedure

1. **Search first.** `brain search "<topic>" --type decision -k 5`. If an ADR exists, update
   or supersede it instead of writing a parallel one.
2. **State the decision question** in one line: "Which approach do we use to migrate the
   Delphi client to the web?"
3. **Collect the context**: constraints, requirements, who is affected, deadlines, what
   forces the decision now. Facts with sources; assumptions marked.
4. **List at least two real options** (doing nothing counts when it is viable). For each:
   what it is, pros, cons, cost/effort estimate, risk, and evidence (measurement, spike,
   documentation). Do not invent a strawman to make the favourite look good.
5. **Decide or recommend.** Name the option and the deciding reasons. If a person with
   authority must decide, set `status: proposed` and name them.
6. **Consequences**: what becomes easier, harder, what must be done next, and the signal
   that would make us revisit the decision.
7. **Save**: `brain new decision "<short decision title>" --project <slug> --body -` with the
   template from `references/adr-template.md`. In a code repository that keeps ADRs (e.g.
   `docs/adr/NNNN-title.md`), write it there too, following its numbering.
8. **Link**: add one line to `projects/<slug>/KERN.md` under decisions, pointing to the ADR.

## Status values

`proposed` → `accepted` | `rejected`; later `superseded by <ADR>` or `deprecated`.
Never rewrite an accepted ADR's reasoning. Write a new ADR that supersedes it and link both
ways.

## When `brain` is missing

Save as `~/work/brain/decisions/<yyyy-mm-dd>-<slug>.md` with the same frontmatter, or in the
repository's ADR folder.

## Done when

- The question, at least two options with evidence, the decision (or proposal and decider)
  and the consequences are written.
- Status is set; the decider and date are named.
- A revisit trigger is stated.
- The ADR is findable (brain or repo) and linked from `KERN.md` for project decisions.

## Pitfalls

- Writing the ADR after the fact to justify a choice. Record the real reasons, including
  "deadline" or "team knows it", which are legitimate.
- Options without evidence. A spike result or a benchmark beats three paragraphs of opinion.
- Too long. One to two screens. Put benchmark data in a linked note.
- Hidden cost: licensing, operations, training, data protection, vendor lock-in.
- Missing data-protection impact for AI or cloud decisions: which data class leaves the
  company, to whom, under which agreement.
