# Stage gates, kill criteria and baseline

Stages: `intake` → `assessment` → `pilot` → `production` → `operations`; exits: `parked`,
`killed`, `retired`. Each gate is a written decision appended to the use-case note by the
person who funds the next stage. Budget and time are released one stage at a time.

| Gate | Enters | Must exist before the decision | Typical kill reasons |
|---|---|---|---|
| G0 triage | assessment | intake answered, no prohibited practice, not a duplicate, task well-defined | prohibited, duplicate, task not definable |
| G1 score | pilot | scores + composite ≥ 2.5, data class and destination allowed, **baseline**, **kill criteria**, pilot plan (≤ 12 weeks, fixed example set, pass criterion) | composite < 2.5, risk 1, data not allowed, no owner |
| G2 build | production | pilot results vs. baseline, human review defined and staffed, inventory entry (`ai-inventory`), tool approval, user training | pass criterion missed, review costs eat the saving, kill criterion hit |
| G3 operate | operations | production running, owner for monitoring, review date | – |
| Review | stays / retired | quarterly: value vs. baseline, incidents, cost, model or tool changes | value gone, tool retired, better route exists |

## Gate record

```
## Gate <YYYY-MM-DD>: <G0 | G1 | G2 | G3 | review>

- stage: <next stage, or parked / killed>
- stage_since: <YYYY-MM-DD>
- decision_by: <name>
- next_gate: <YYYY-MM-DD>
- decision: <one sentence with the deciding reason>
```

## Kill criteria (written before the pilot starts)

Concrete, measurable and agreed with the sponsor, for example:

- Reviewer accepts fewer than <x> % of outputs without substantial edits on the fixed set.
- Review plus correction takes more than <y> % of the baseline time.
- Any output with CUSTOMER or CONFIDENTIAL data would have to leave an approved destination.
- A critical error type (<describe>) occurs at all in the test set.
- Pilot not finished after 12 weeks.

Record as one line: `- kill_criteria: <criteria; separated by semicolons>`.
When a criterion is hit, the case is killed or re-scoped at the next gate; it is not extended
silently. Killed cases stay in the brain with the reason: they prevent repeats.

## Baseline (captured before building anything)

Measure the current process on the same fixed example set the pilot will use:

- time per item (median and range, from observation or logs, not from memory),
- error or rework rate, and how errors are found today,
- volume per month, and cost per item if known.

Record: `- baseline: <n items; median x min per item; error rate y %; source; date>`.
Without a baseline the pilot cannot show a benefit; the portfolio listing flags it.

Source: stage funnel, kill criteria per stage and the pre-build baseline follow the
Concept-LAB and dsstream descriptions (see `docs/governance.md` in the kit repository).
