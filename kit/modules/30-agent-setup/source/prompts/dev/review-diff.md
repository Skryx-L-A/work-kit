---
id: dev/review-diff
title: Review a change
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [developer]
data_class: CUSTOMER
variables: [diff]
updated: 2026-09-25
---
# Review a change

Use for: A second pair of eyes on a diff before a human review.

Do not use for: Replacing the human reviewer.

## Prompt

```text
Review this diff for correctness, behavior changes, security, error handling and
readability. List findings by severity with the file and line and a concrete fix. For each
category with no findings, say "no findings". Do not comment on formatting.

Diff:
{{diff}}
```

## Review before use

- Check each finding against the code; drop false positives.
- A human reviewer still approves the change.

## Changelog

- 1.0.0 (2026-09-25): first version.
