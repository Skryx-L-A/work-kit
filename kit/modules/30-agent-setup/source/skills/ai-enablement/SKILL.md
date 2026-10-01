---
name: ai-enablement
description: 'Plan, prepare and follow up AI training for staff, most of them non-technical: literacy baseline session (EU AI Act Art. 4), role-based tracks for office staff, project managers, developers and management, AI champions (train-the-trainer), completion check, starter prompts, handouts and adoption metrics. Use when asked to prepare a workshop, training, prompt guide or AI onboarding for a team. Do not use for evaluating a single AI use case (use ai-use-case-assessment) or for writing the company AI policy itself.'
---

# AI enablement

Adoption fails more often than models do. This skill turns the enablement pack (module
`19-enablement`) into a concrete session or program for a specific team, with the company's
real rules and the team's real tasks.

Material: `~/work/enablement/` (or `$ENABLEMENT_HOME`), installed by module 19. Start with its
`README.md`. If it is missing, use `references/session-outline.md` and say that the full pack
is not installed.

## Procedure: prepare a session or track

1. **Clarify** (ask only what is unknown): target group and size, role track (office,
   project management, developers, management, champions), date and length, the approved
   AI tool participants will use, and what the team already knows.
2. **Check the company values.** Every `TODO(ask IT)` in the material shown (approved tools
   per data class, contact, incident route, meeting policy) is either filled with a
   confirmed value or shown as "not decided yet, strict rule applies". Never invent a value
   and never present a placeholder as a rule.
3. **Pick the plan**: `art4-literacy-session.md` for everyone new, then the track table in
   `curriculum.md`. Keep the rules section identical to other sessions.
4. **Adapt the examples** to the team's recurring tasks (from the invitation answers or the
   requester). Use the synthetic exercises in `exercises/` or write new synthetic ones.
   Real team material only if it is cleared for the tool (`data-guard` skill); never
   customer or HR data.
5. **Try every exercise** in the approved tool, or state that the facilitator must, and note
   one failure to show live (invented fact, missed item, wrong number).
6. **Produce the handouts**: role section of `handouts/starter-prompt-pack.md` (or
   `prompt-library` renders), data classes card, review card, one-pager. For slides or PDF
   use `presentation-design` / `document-design`, or `pandoc` from module 12.
7. **Hand over a facilitator packet**: agenda with times, exercises with facilitator notes,
   handouts, the attendance list from `templates/literacy-record.md`, open `TODO(ask IT)`
   items with who can answer them.

## Procedure: set up a program

1. Fill `templates/program-plan.md` with the requester: owner, sponsor, target groups,
   time budget, where records are kept. Mark unknowns.
2. Plan champions first (`train-the-trainer.md`): one per 10 to 15 people.
3. Schedule baseline sessions before first tool use, then tracks, then the assessment.
4. Define the adoption metrics (`templates/adoption-metrics.md`) and the review cadence.

## Procedure: follow up

1. Draft the follow-up mail: prompts used, answers to parked questions, next date.
2. Summarize feedback forms; propose material changes where two or more people struggled.
3. Aggregate adoption metrics per team. Count review time in time saved; mark estimates.
4. Pass task ideas from participants to `ai-use-case-assessment`, good prompts to
   `prompt-library`.
5. If `brain` is installed, save a session note without personal data:
   `brain new note "Enablement: <team> <session>" --project ai-enablement` (what was taught,
   material version, counts, lessons, changes). Attendance with names stays in the
   literacy record, which is personal data and not a brain note.

## Done when

- The facilitator packet exists, every company value is confirmed or visibly open with an
  owner, and all exercises use synthetic or cleared material.
- For a program: the plan names owner, sponsor, groups, schedule, records and metrics.
- For a follow-up: mail drafted, material changes listed, metrics aggregated, ideas and
  prompts handed on.

## Pitfalls

- Tool tours instead of the team's own tasks: people forget features, not their work.
- Legal statements beyond the material: Art. 4 questions go to the DPO or legal. The pack
  is not legal advice.
- Asking participants to paste their real data "to see what happens".
- Measuring success by attendance only. Track use, confidence and time saved including review.
- Treating one session as done: the law expects measures that fit the risk; plan follow-ups
  and yearly review.
- Overselling. Show a failure in every demo; trust grows from honest limits.
