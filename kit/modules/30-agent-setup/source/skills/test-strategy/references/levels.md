# Test levels for legacy systems

| Level | Checks | Speed | Legacy entry point |
|---|---|---|---|
| Unit | one function or class, no I/O | milliseconds | after seams exist (extract method, inject dependency) |
| Integration | code plus a real database, file system or local service | seconds | stored procedures, repositories, file import/export |
| Contract | request/response shape between two systems | fast | interfaces to partner systems, APIs between teams |
| Characterization | recorded current behavior at a seam | varies | first step when nothing else exists |
| End-to-end | full flow through UI or API | slow | a few core business flows only |
| Data migration | completeness and correctness of moved data | batch | counts, checksums, samples, reconciliation of totals |
| Parallel run | old and new produce the same output | batch | replacing a component (strangler fig) |

Typical order for an untested legacy module:
1. Characterization tests at the outermost reachable seam (batch input/output, API, UI flow).
2. Integration tests around the database logic the change touches.
3. Refactor to create seams, then add unit tests for the logic being changed.
4. Keep a few end-to-end tests for the core flows; retire characterization tests that unit
   and integration tests now cover better.
