# Traceability matrix

File `traceability.csv` next to `spec.md`. One row per spec ID, one line each, comma separated,
no commas or quotes inside cells (the check script does not parse CSV quoting). Multiple values in a cell are joined with `;`.

```
spec_id,code,tests,target_code,target_tests,status
BR-001,src/billing/Fee.java:88;db/fee_trigger.sql:12,FeeCharTest.test_cap,,,specified
```

Columns:

- `code`: legacy locations (`file:line`) that implement the behavior.
- `tests`: characterization tests that pin it. `no test: <reason>` only if the validator
  accepted the gap.
- `target_code`, `target_tests`: filled during migration, one increment at a time.
- `status`: `specified` -> `planned` (in a migration step) -> `migrated` (target code exists
  and target tests pass) -> `verified` (legacy and target agree on the characterization
  cases) -> `retired` (legacy code removed). Also `dropped` for items the validator removed.

Rules:

- Every spec ID has exactly one row; every row has an ID that exists in `spec.md`.
- No row reaches `migrated` without `target_code` and `target_tests`.
- Migration commits and pull requests name the spec IDs they touch (`Refs: BR-001, BR-004`),
  and update the matrix in the same change.
- Check with `bash ~/.agents/skills/modernization-spec/scripts/trace-check.sh spec.md traceability.csv`; add `--strict` when
  planning or migrating to also require `target_code` on rows with status `planned`.
