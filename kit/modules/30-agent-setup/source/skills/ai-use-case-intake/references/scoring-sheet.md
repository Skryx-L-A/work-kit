# Scoring sheet: four dimensions, 1 to 5

Score in a short session (about 60 to 90 minutes) with the owner, one person who does the
task today, and someone who knows the data and systems. Every score gets a one-line reason.
Unknown is scored 2 and marked `(estimate)`; it is never scored high to keep a case alive.

| Score | Value | Feasibility | Risk (5 = low risk) | Reusability |
|---|---|---|---|---|
| 5 | > 20 h/month saved or a clear quality/revenue effect, measurable | approved tool exists, data available and allowed, reviewable in minutes | PUBLIC/INTERNAL data, no people decisions, errors caught by review | pattern or components serve 3+ teams or customers |
| 4 | 10–20 h/month or a clear quality effect | small integration work, data mostly ready | INTERNAL data, minor errors reach nobody outside | 2 teams |
| 3 | 3–10 h/month or moderate quality effect | new tool approval or data preparation needed | CONFIDENTIAL data with an approved local route, or output reaches a customer after review | reusable with adaptation |
| 2 | < 3 h/month, or benefit unclear | unclear if models handle the task; data scattered | CUSTOMER data, contract unclear; or review is hard | one-off |
| 1 | no measurable benefit | not feasible with allowed tools and data | prohibited practice, people decisions, or unreviewable output | none |

## Record lines to append

```
## Gate <YYYY-MM-DD>: assessment

- value: <1-5>  (<reason>)
- feasibility: <1-5>  (<reason>)
- risk: <1-5>  (<reason>)
- reusability: <1-5>  (<reason>)
- composite: <mean of the four, two decimals>
```

## Rules

- Composite = mean of the four. Below **2.5**: does not advance (park or kill).
- Risk **1** is a stop, whatever the composite. Risk 2 needs an explicit mitigation and a
  named approver before the pilot.
- Compare only cases scored the same way; re-score when facts change, and append the new
  scores instead of editing the old ones.
- A detailed business case for one case comes from the `ai-use-case-assessment` skill.

Source: four dimensions, 5-point scale and the 2.5 threshold follow the Concept-LAB AI use
case portfolio description (see `docs/governance.md` in the kit repository); the anchor
texts per score are the kit's own and must be calibrated with the company.
