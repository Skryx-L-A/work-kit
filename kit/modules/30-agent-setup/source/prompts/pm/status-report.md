---
id: pm/status-report
title: Status report from notes
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [pm]
data_class: INTERNAL
variables: [audience, notes]
updated: 2026-09-25
---
# Status report from notes

Use for: Weekly or milestone status reports from your own notes.

Do not use for: Numbers you have not checked (budget, effort); fill those in yourself.

## Prompt

```text
Write a status report for {{audience}} from the notes below. Sections: summary (three
sentences), progress, risks and issues, decisions needed (with who must decide), next steps.
Use only information from the notes; mark gaps as "to confirm". Report bad news plainly.

Notes:
{{notes}}
```

## Review before use

- Budget and progress figures match the notes.
- Risks are not softened.
- Decisions needed name the decider.
- No internal-only details for an external audience.

## Changelog

- 1.0.0 (2026-09-25): first version.
