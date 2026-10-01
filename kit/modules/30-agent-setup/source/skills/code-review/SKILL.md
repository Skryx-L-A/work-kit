---
name: code-review
description: Review a finished change (diff, branch or pull request) for correctness, behavior preservation, security, data handling, tests and maintainability, and report concrete, verified findings ranked by severity. Use when asked to review a change, before merging your own non-trivial change, or when checking AI-generated code. Do not use to search for the cause of a known bug (use debugging-protocol), for a dedicated security audit of a whole system (use security-review), or for style nits that a formatter or linter should enforce.
---

# Code Review

A review answers one question: can this change be merged safely, and if not, what exactly
must change? Findings must be concrete (file, line, scenario) and checked, not speculative.

## Before you start

- Get the exact change: `git diff <base>...<head>`, `git log <base>..<head>`, or the pull
  request. Know the base branch and the commit you are reviewing.
- Read the stated intent: ticket, pull request description, commit messages. If the intent is
  missing, ask for it; a review without intent can only check mechanics.
- Check `data-guard` before sending customer code to an AI reviewer.
- Look for project conventions and known pitfalls: repository `AGENTS.md` or `CONTRIBUTING`,
  and `brain search "<module> pitfalls" --project <slug>` if `brain` is installed.

## Procedure

1. **Understand the change.** Summarize in two sentences what it does. If you cannot, the
   change is too large or unclear; say so as the first finding.
2. **Check scope.** Does the diff match the intent? Flag unrelated changes, mixed refactoring
   and behavior changes, generated files, debug leftovers, commented-out code.
3. **Correctness.** Read every changed hunk with its surrounding code. Look for:
   - wrong conditions, off-by-one, null or empty handling, error paths, resource cleanup;
   - concurrency and transaction boundaries, partial failure, retries, idempotency;
   - callers and consumers of changed functions, APIs, schemas and file formats
     (`rg "<symbol>"`), including reports, jobs and other systems;
   - date, time zone, locale, encoding, rounding and currency handling.
4. **Behavior preservation (legacy work).** For refactorings: is observable behavior
   unchanged? Are characterization tests in place and unchanged, or are golden-file updates
   explained? Any intended behavior change must be named in the description.
5. **Security and data.** Input validation, injection (SQL, command, path), authorization
   checks, secrets in code or config, logging of personal or customer data, new dependencies
   and their licenses. For deeper checks use `security-review`.
6. **Tests.** Do tests cover the change, including the failure case? Would they fail if the
   change were reverted? Run them if you can, and say whether you did.
7. **Maintainability.** Naming, duplication, needless complexity, missing comments where
   the reason is non-obvious. Keep this short and after the substantive findings.
8. **Verify each finding** before reporting it: reread the code, trace the call, or write a
   quick test. Drop findings you cannot support. Mark the rest as confirmed (demonstrated)
   or plausible (reasoned, not demonstrated).
9. **Report** in the format below, most severe first.

## Report format

```
Verdict: approve | approve with minor changes | changes required | cannot assess (why)
Reviewed: <base>..<head> (<sha>), tests run: <command and result | not run>

[blocker|major|minor|nit] path/file.ext:123 (confirmed|plausible)
  Problem: <what is wrong>
  Scenario: <concrete input or sequence that fails>
  Suggestion: <smallest fix>
```

Severity guide: *blocker* = data loss, security hole, broken build or core flow;
*major* = wrong behavior in a realistic case; *minor* = edge case or maintainability risk;
*nit* = optional polish (keep few).

## Done when

- Every changed file was read, and callers of changed interfaces were checked.
- Each finding has a location, a concrete scenario and a suggestion, and is verified or
  marked plausible.
- The verdict and whether tests were run are stated.
- No finding is a matter of taste presented as a defect.

## Pitfalls

- Reviewing only the diff lines and missing the broken caller two files away.
- Long lists of style comments that bury the one real bug.
- Approving because tests are green when the tests do not exercise the change.
- Trusting AI-generated code or an AI review without checking: plausible-looking APIs may
  not exist, and edge cases are often skipped.
- Rewriting the author's solution in the review. Suggest the smallest fix.
- Reviewing a huge change in one pass. Ask to split it, or review commit by commit.

## Related skills

`security-review`, `verification`, `characterization-tests`, `data-guard`, `git-workflow`.
Sources: references/sources.md.
