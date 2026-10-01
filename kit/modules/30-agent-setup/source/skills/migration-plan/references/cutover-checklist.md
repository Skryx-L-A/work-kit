# Cutover checklist (per increment)

Decide go/no-go criteria before the rehearsal, not during cutover.

Before
- [ ] Characterization tests pass against legacy and target; target tests pass.
- [ ] Reconciliation of data is within the agreed threshold on production-like data.
- [ ] Rehearsal done on a production-like environment; duration and problems recorded.
- [ ] Rollback rehearsed with timing; rollback trigger and time limit agreed.
- [ ] Monitoring and alerts for the new path exist; owner on call named.
- [ ] Users, operators and partner systems informed; freeze window agreed.
- [ ] Backups of affected data verified restorable.
- [ ] Runbook written: exact commands, order, who does what.

During
- [ ] Freeze writes if the plan requires it; note start time.
- [ ] Final sync and reconciliation; go/no-go decision recorded with name and time.
- [ ] Switch routing (flag, proxy rule, DNS); smoke test key flows on the new path.
- [ ] Watch errors, latency and business totals against the baseline for the agreed period.

After
- [ ] Exit criteria met for the agreed parallel period, then legacy path set read-only.
- [ ] Traceability matrix updated (`migrated`/`verified`), decision and result stored.
- [ ] Decommissioning date for the legacy part scheduled.
- [ ] Lessons noted in the project's KERN or session note.
