---
name: test-strategy
description: 'Design a risk-based test strategy for a project, module or modernization effort: what to test at which level (unit, integration, contract, end-to-end, characterization, data migration), with which tools and data, and in which order. Use when starting work on a system with weak or unknown tests, planning tests for a refactoring or migration, or when asked "how should we test this". Do not use to write a single test for a clear change (just write it), to pin down existing behavior in detail (use characterization-tests), or to check whether a specific result is done (use verification).'
---

# Test Strategy

The strategy decides where testing effort goes. Aim for the smallest set of tests that makes
the planned changes safe, not for a coverage number.

## Inputs you need

- What will change in the coming months (refactoring plan, modernization roadmap, backlog).
- Risk: which flows matter most for the business, where defects occurred, hotspots from
  `legacy-code-analysis`, regulatory or financial correctness needs.
- Current state: existing tests, how long they run, whether they pass and are trusted,
  CI setup, available test environments and test data.
- Constraints: legacy stack tooling, access to databases and external systems, data rules
  for test data (see `data-guard`).

## Procedure

1. **List risks.** For each important flow or component: what could go wrong, how likely,
   how bad. Rank them. Include non-functional risks (performance, security, data migration
   correctness, interfaces with partner systems).
2. **Assess existing tests.** Run them; record count, duration, failures, flakiness.
   Decide which to keep, fix, quarantine with an owner, or delete. Untrusted tests are
   worse than none because people learn to ignore them.
3. **Choose levels per risk.** Default shape: many fast unit tests for logic, fewer
   integration tests for database, file and service boundaries, few end-to-end tests for
   core flows. For legacy code without seams, start from the outside: characterization tests
   at a seam you can reach (see references/levels.md), then push tests inward as refactoring
   creates seams.
4. **Plan special test types when relevant:**
   - *Contract tests* for interfaces between teams or systems that change separately.
   - *Data migration tests:* row counts, checksums, sampled record comparison, referential
     integrity, reconciliation of totals between old and new systems.
   - *Parallel run / shadow comparison* when replacing a component: feed both old and new
     the same input and diff outputs before switching.
   - *Performance baseline* before a change that might affect it.
5. **Test data.** Synthetic data by default; generate it with scripts under version control.
   Use anonymized production samples only if allowed for the data class, and never commit
   real customer data. Keep a small, deterministic dataset for fast tests.
6. **Environments and tools.** Pick tools the team can maintain on the legacy stack.
   Prefer disposable local databases (containers, embedded databases) over shared test
   databases. Decide what runs on every commit, nightly and before release.
7. **Order the work.** First: tests protecting the next planned change and the top risks.
   Then broaden. Each step should make a concrete upcoming change safer.
8. **Write it down** (template below) and store it with the project documentation, or
   `brain new reference "<system>: test strategy" --project <slug> --body -` if `brain` is
   installed.

## Template

```
Scope and planned changes:
Top risks (ranked) -> test level and type for each:
Existing tests: count, runtime, pass rate, trust, keep/fix/delete decisions:
Test data approach and data-class constraints:
Environments and tools; what runs per commit / nightly / pre-release:
First steps (ordered, each tied to an upcoming change):
Exit criteria for releases:
Open questions:
```

## Done when

- Every top risk maps to a test level and type, or is explicitly accepted with a reason.
- Existing tests have a decision (keep, fix, quarantine with owner, delete).
- Test data follows the data rules and is reproducible.
- The first steps are concrete and tied to planned changes.
- The team or requester agreed to the strategy.

## Pitfalls

- Chasing a coverage percentage instead of covering the risks of planned changes.
- Relying mainly on slow, brittle end-to-end UI tests.
- Shared test databases that make tests order-dependent and flaky.
- Using copies of production data without checking whether that is allowed.
- Planning tests for the target architecture only and leaving the migration itself untested.
- Forgetting the database: stored procedures, triggers and batch jobs need tests too.

## Related skills

`characterization-tests`, `verification`, `refactoring-plan`, `legacy-code-analysis`,
`data-guard`. Sources: references/sources.md.
