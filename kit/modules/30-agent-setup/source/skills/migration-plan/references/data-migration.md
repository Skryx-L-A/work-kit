# Data migration plan

Fill in per data store. One page per store is enough. Use synthetic or anonymized data outside
the customer's approved environment (`data-guard`).

```
Store: <name, engine, version>       Owner (team/person):
Tables / files in scope:             Consumers (apps, reports, jobs, partners):
Business rules living in the store (triggers, procedures, views): <spec IDs>
Direction during coexistence: legacy-only | dual write | one-way sync legacy->target | target-only
Schema change pattern: expand (add) -> migrate (backfill, move readers) -> contract (drop)
Initial load: method, volume, duration estimate, tested on: <env/date>
Ongoing sync: mechanism (CDC, batch, triggers, application dual write), latency budget
Reconciliation: row counts, checksums per table, business totals, sample comparisons;
                who reviews the report and the acceptance threshold
Data quality issues found (nulls, duplicates, encodings, orphaned rows) and treatment
Retention, deletion and personal data handling (ask IT / data protection):
Rollback: how target writes flow back or are discarded; point after which rollback is lossy
Cutover freeze: what stops writing, for how long
```

Rules of thumb:

- One writer per table at any time. If two sides must write, name the conflict rule.
- Backfills are idempotent and resumable; record progress.
- Reconciliation runs before, during and after cutover, not only once.
- Character encoding, time zones, decimal precision and collation differences are the usual
  silent breakers; test them with dedicated cases.
