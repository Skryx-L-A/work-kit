---
name: verification
description: Decide how much checking a result needs and then prove it with observed evidence before calling work done, handing it over or merging. Use before claiming a task is complete, before merge or release, after a fix, and when reporting test results to others. Do not use as a reason for repeated review rounds on routine low-risk changes, and do not use it to design a test suite (use test-strategy) or to review someone else's diff (use code-review).
---

# Verification

Rule: report only what you observed. "Should work" is not a result. A claim is verified when
you can name the command or check, the exact state it ran against, and the outcome.

## Choose the level

Match effort to risk. Do not add checks out of habit, and do not skip required ones.

| Situation | Required check |
|---|---|
| Routine, low-risk change (docs, small local code change with existing tests) | Read your own diff; run the directly affected tests if they exist |
| Bug fix | The reproducing test fails before and passes after; nearby tests pass |
| Critical change: permissions, secrets, money, data deletion or migration, customer data, shared runtime, wide impact | Targeted tests for the risk, plus a second person's review before it takes effect |
| Merge to the main branch or release | Full test suite of the project for that exact commit, green build |
| Explicit validation request | Everything requested, fully |

One valid piece of evidence is enough. A passing run for the same commit, dependencies and
environment does not need to be repeated because work changed hands. It becomes invalid when
the code, dependencies or relevant configuration change.

## Procedure

1. **Restate the done criterion.** What must be true, in checkable terms? If there is none,
   agree on one with the requester before verifying.
2. **Pick the checks** from the table. For each claim you intend to make, name how it will
   be shown: automated test, command output, screenshot, manual step with observed result,
   log line, query result.
3. **Run against the real state.** Clean working tree or known commit, correct branch,
   dependencies installed as in CI. Record the commit hash.
4. **Observe, do not infer.** Read the actual output. A green exit code with skipped tests,
   zero tests collected, or a cached result is not a pass.
5. **Check the negative.** For fixes and guards, confirm that the check would fail without
   the change (revert temporarily, or use a known bad input).
6. **Isolate side effects.** Run tests with your own temporary files, ports, databases and
   processes. Never verify against production, shared databases or someone else's session.
   Stop every process you started and confirm it ended.
7. **Report** in the format below. State what was not verified and why.

## Report format

```
Claim: <what is done>
Evidence: <command or check> on <commit/state> -> <observed result>
Not verified: <item> (<reason>), residual risk: <short>
```

Example:
```
Claim: invoice rounding fixed for negative amounts
Evidence: `pytest tests/test_invoice.py -q` on a1b2c3d -> 42 passed; new test
  test_negative_rounding fails on parent commit 9f8e7d6
Not verified: batch export path (needs customer test system), risk: low, same function
```

## Done when

- Every claim in the handover or pull request has evidence from the current state.
- Required checks for the risk level ran and their outcome is recorded with the commit.
- Gaps are named explicitly instead of left out.
- All processes and temporary resources started for verification are stopped or removed.

## Pitfalls

- Declaring success from a partial run ("the tests I ran pass") without saying which ran.
- Verifying an older build, a different branch, or with stale dependencies.
- Counting skipped, ignored or quarantined tests as passing.
- Rerunning a flaky test until it passes. Flakiness is a finding.
- Letting an AI tool's statement "all tests pass" stand without the actual output.
- Piling up review rounds on trivial changes while a critical migration gets none.

## Related skills

`test-strategy`, `code-review`, `debugging-protocol`, `characterization-tests`.
Sources: references/sources.md.
