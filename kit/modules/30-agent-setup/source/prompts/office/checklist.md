---
id: office/checklist
title: Turn a process description into a checklist
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [office, pm]
data_class: INTERNAL
variables: [description]
updated: 2026-09-25
---
# Turn a process description into a checklist

Use for: Making a repeatable procedure easy to follow for someone new.

Do not use for: Safety-critical procedures; those need the process owner's review before use.

## Prompt

```text
Turn this process description into a numbered checklist someone new can follow. Mark every
step where a decision or an approval is needed, and name who decides if the text says so.
List steps that the description leaves unclear at the end.

Description:
{{description}}
```

## Review before use

- No step was invented.
- Approvals match the description.
- Unclear steps are listed, not guessed.

## Changelog

- 1.0.0 (2026-09-25): first version.
