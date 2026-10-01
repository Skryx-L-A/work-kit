# AI incident report

Report to: `TODO(ask IT)` immediately; personal data also to the data protection officer.
Do not paste the leaked data, secret or customer content into this report: describe it.

- Reported by: <name> · Date and time: <YYYY-MM-DD HH:MM> · Noticed at: <...>
- AI system (inventory entry): <...> · Model / MCP server / version: <...>
- Kind: <data to wrong destination | secret in prompt or config | wrong output used |
  unintended agent action | suspected prompt injection | tool changed behavior | other>

## What happened

<Facts in order: what was done, what the system did, what was noticed. No guesses; mark
assumptions as such.>

## Impact

- Data involved (class, amount, whose): <...>
- Reached whom / where: <...>
- Customer affected: <yes / no / unknown> · Personal data: <yes / no / unknown>

## Immediate actions

- [ ] Affected use stopped (server disabled, session ended, access revoked)
- [ ] Secrets rotated (not only deleted)
- [ ] Owner of the affected system / data informed: <who, when>
- [ ] Data protection officer informed if personal data: <who, when>

## Follow-up (blameless review)

- Cause: <...>
- Changes: <guideline, inventory, allowlist, data-guard patterns, training>
- Closed by / on: <...>
