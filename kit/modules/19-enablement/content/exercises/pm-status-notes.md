# Project notes for a status report (synthetic)

Project: migration of the fictional "Orbit" order system from a mainframe batch job to a Java
service, fictional customer "Example Retail". Reporting week 14.

- Characterization tests: 212 of about 300 planned done. Found 3 behaviors nobody knew about
  (rounding of discounts, weekend cut-off, empty address line 2 handled as space).
- Customer still has not delivered the production data sample (asked 3 times). Blocks the
  performance test planned for week 16.
- Team: Priya on leave week 15. Mark joins from week 15 part-time.
- Batch interface spec v0.9 reviewed with customer on Tuesday, two open points: character
  encoding of file names, and who owns the retry after failure.
- Budget: 61 % used, 55 % of work done (by task count).
- Risk: the weekend cut-off rule may be a bug the customer wants kept. Needs decision.
- Next: finish tests, draft encoding proposal, meeting with customer ops on Thursday.

Task: a status report for the customer's project lead. Checks: Is the budget/progress gap
reported honestly? Is the weekend rule shown as a decision the customer must take, not as a
fact? Did the report invent a date for the data sample? Should internal staffing details
(leave) go to the customer at all?
