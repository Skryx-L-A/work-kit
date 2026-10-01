---
name: characterization-tests
description: Pin down the current, observed behavior of legacy code with characterization (golden master / approval) tests before refactoring, rewriting a module or upgrading a dependency. Use when code must change but has few or no tests and the specification is unknown or unreliable. Do not use to specify new desired behavior (write normal tests), to test code that already has a trusted test suite covering the change, or as a substitute for fixing a known bug (record the bug, see debugging-protocol).
---

# Characterization Tests

A characterization test records what the code does today, not what it should do. It makes
change safe: after refactoring, any difference in output is either intended or a regression.

## Before you start

- Know which behavior the upcoming change can affect (from `legacy-code-analysis` or the
  refactoring plan). Characterize that area, not the whole system.
- Check the data class of any recorded inputs and outputs (`data-guard`). Never commit real
  customer data as test fixtures; use synthetic or properly anonymized data.
- Agree where the tests live and how they run (existing test framework, or a separate
  harness if the legacy stack has none).

## Procedure

1. **Choose the seam.** Find the smallest point where you can call the code and observe its
   output without changing production behavior: a public function, a CLI, an HTTP endpoint,
   a batch job with file input/output, a stored procedure. If no seam exists, create one with
   the smallest safe edit (extract method, parameterize a dependency) and note it.
2. **Control nondeterminism.** Identify time, random numbers, generated IDs, environment,
   locale, ordering of unordered collections, floating-point formatting and external calls.
   Fix them (inject a clock, seed, sort) or scrub them from the output before comparing.
3. **Collect inputs.** Combine: typical cases from real usage patterns (synthetic copies),
   boundaries (empty, zero, max length, negative, null, special characters, umlauts and other
   encodings), and every branch you saw in the code. A coverage tool helps find unreached
   branches; use one if the stack has it.
4. **Record the output.** Write a test that calls the seam and asserts on the actual output.
   Two common forms:
   - *Assertion form:* start with a deliberately wrong expected value, run, copy the actual
     value into the test. Good for few, small outputs.
   - *Golden master / approval form:* serialize the full output (text, JSON, file, DB rows)
     to an approved file and diff against it on every run. Good for large or many outputs.
     Approval-testing libraries exist for most languages; a plain file diff also works.
5. **Include side effects.** If the code writes to a database, file or queue, capture that
   state after the call (use a disposable local database or a test double, never a shared one).
6. **Label surprises.** When the recorded behavior looks wrong, keep the test as is, name it
   clearly (`test_rounding_currently_truncates`) and file the suspected bug separately.
   Changing behavior and changing structure in the same step hides regressions.
7. **Prove the tests bite.** Make a small deliberate change in the characterized code
   (flip a condition, change a constant), confirm at least one test fails, then revert.
   Mutation-testing tools automate this where available.
8. **Run twice.** The suite must pass twice in a row on a clean checkout, with no manual steps,
   before anyone relies on it.

## Done when

- Every behavior the planned change can touch is covered by at least one characterization
  test, including side effects.
- The tests are deterministic (two clean runs, same result) and run with one documented command.
- A deliberate small code change makes at least one test fail.
- Suspicious recorded behavior is listed separately as open questions or bug reports.
- No real customer data is in the fixtures.

## Pitfalls

- "Fixing" odd behavior while writing the tests. Record first, change later, in separate commits.
- Golden files so large that nobody reads the diff. Split by case, keep outputs readable,
  and scrub volatile fields so diffs show only real changes.
- Approving a new golden file without reviewing the diff. An approval is a review decision.
- Tests coupled to internals (private fields, call order of helpers) that break under a pure
  refactoring. Observe at the seam's output, not inside it.
- Flaky tests from time, ordering or shared state. Fix the cause, do not add retries.
- Characterizing everything. Coverage should follow the planned change and the risk.

## Related skills

`legacy-code-analysis` (find seams and flows), `refactoring-plan`, `test-strategy`,
`verification`, `data-guard`. Details and sources: references/sources.md.
Modernization chain (`modernization-workflow`): next step is `modernization-spec`.
