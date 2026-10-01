---
id: office/action-items
title: Extract action items and decisions
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [office, pm]
data_class: INTERNAL
variables: [notes]
updated: 2026-09-25
---
# Extract action items and decisions

Use for: Turning meeting notes or a long thread into a list of who does what by when.

Do not use for: Recordings or transcripts you have no consent to process.

## Prompt

```text
From the notes below, list every action item as a table with the columns: what, who, due
date. Write "not stated" where the notes do not say. Then list the decisions separately, and
then the open questions. Do not turn an open question into a decision.

Notes:
{{notes}}
```

## Review before use

- Every action item in the notes appears once.
- Open questions did not become decisions.
- Dates and owners match the notes.

## Changelog

- 1.0.0 (2026-09-25): first version.
