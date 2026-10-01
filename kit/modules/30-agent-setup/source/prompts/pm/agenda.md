---
id: pm/agenda
title: Meeting agenda
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [pm, office, management]
data_class: INTERNAL
variables: [duration, participants, goal]
updated: 2026-09-25
---
# Meeting agenda

Use for: Preparing a meeting that must end in a decision or a clear outcome.

Do not use for: Routine stand-ups (no agenda needed).

## Prompt

```text
Draft an agenda for a {{duration}} meeting with {{participants}}.
Goal: {{goal}}
Give each item a time box, an owner and the question it must answer. End with 5 minutes to
confirm decisions and action items.
```

## Review before use

- Time boxes add up to the duration.
- Every item serves the goal.

## Changelog

- 1.0.0 (2026-09-25): first version.
