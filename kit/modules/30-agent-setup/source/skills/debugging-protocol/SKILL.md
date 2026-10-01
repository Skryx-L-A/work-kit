---
name: debugging-protocol
description: Find the root cause of an unclear, intermittent or recurring failure through written falsifiable hypotheses, a smallest reproducing case and one change per iteration, and keep that case as a regression test. Use when the cause is not obvious after a first look, when a first fix did not hold, or when guessing is expensive (production, customer system, legacy code without tests). Do not use for an obvious typo or a fix you can see and verify in a minute, for reviewing a finished change (use code-review), or for design decisions.
---

# Debugging Protocol

Debugging is an experiment loop. Each loop tests one explicit hypothesis. Refuted hypotheses
are results too and stay recorded, so nobody walks the same dead end twice.

## Before you start

- Write down the symptom exactly: error text, where it appears, since when, how often, which
  environment and version (commit, build, configuration). Quote messages, do not paraphrase.
- Check whether it is known: `brain search "<error text or symptom>"` and the project's
  `KERN.md` pitfalls (via `brain read`). If `brain` is missing, search the ticket system and
  repository history (`git log -S "<string>"`, `git log --grep`).
- Logs, dumps and database rows from a customer system may be CONFIDENTIAL or CUSTOMER data.
  Check `data-guard` before pasting them into any AI tool; redact or reproduce synthetically.
- Do not debug on production or shared environments by changing things. Observe there,
  experiment on a local or dedicated copy.

## Procedure

Run every iteration through steps 1 to 4 in order.

1. **Hypothesis.** Write it: "I suspect X causes Y because Z." A vague hypothesis
   ("something with timing") means you need more evidence first: read the stack trace,
   logs and the code path, add logging, or compare a working and a failing case.
2. **Smallest reproducing case.** Reduce input, configuration and steps until the failure
   still appears and nothing unnecessary remains. Capture it as an automated test or script,
   not only as manual steps. For intermittent failures, loop it and record the failure rate.
   Useful reducers: `git bisect` for "it worked in version N", delta debugging (halve the
   input), toggling configuration one item at a time.
3. **Exactly one change.** Change one thing that follows from the hypothesis: add a probe,
   alter one input, apply one candidate fix. Several changes at once hide which one mattered.
4. **Verify and record.** Rerun the reproducing case. Record the result in the log below.
   - *Confirmed:* the failure disappears (or the probe shows the predicted value). Continue
     with the fix and step 5.
   - *Refuted:* record why it is ruled out, revert the change, and form a new hypothesis that
     takes the result into account.
5. **Fix and keep the regression test.** Turn the reproducing case into a permanent test in
   the project's suite that fails without the fix and passes with it. Do not add a second
   test with the same meaning. Run the surrounding tests too.

Keep the log visible in the conversation or the ticket while you work:

```
| # | Hypothesis                            | Test / change             | Result               |
|---|---------------------------------------|---------------------------|----------------------|
| 1 | Date parsing uses server locale       | run repro with LANG=C     | refuted: same error  |
| 2 | Null customer id from import file row | repro with row 17 only    | confirmed            |
```

## When nothing works

After about three refuted hypotheses in a row, step back:
- Question the assumptions: is it really the same version, configuration and data? Diff the
  working and failing environments systematically.
- Widen observation: more logging, tracing, a debugger, database query logs.
- Ask whether the problem is a design flaw rather than a local bug, and raise it with the
  team instead of patching symptoms.
- Ask a colleague who knows the system; explain the log. Explaining often reveals the gap.

## Done when

- The root cause is stated in one or two sentences and supported by the log.
- The fix addresses the cause, not only the symptom, and is minimal.
- A regression test that reproduces the original failure exists and passes with the fix.
- The hypothesis log (including refuted hypotheses) is saved with the ticket or with
  `brain new note "<symptom>: root cause" --project <slug> --body -`. If the failure is likely
  to recur, add it to the project's `KERN.md` pitfalls. Without `brain`, put it in the ticket.

## Pitfalls

- Fixing before reproducing. A fix that cannot be shown to change the failing case is a guess.
- Changing several things at once, then keeping all of them because "it works now".
- Treating an intermittent failure as fixed after one green run. Use the recorded failure rate.
- Deleting evidence (logs, failing inputs) before the cause is understood.
- Catching and swallowing the exception to make the symptom disappear.
- Trusting an AI explanation of a stack trace without checking it against the code.

## Related skills

`verification` (before claiming the fix works), `characterization-tests` (when the area has
no tests), `code-review`, `data-guard`. Sources: references/sources.md.
