---
id: general/challenge
title: Challenge my plan
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [all]
data_class: INTERNAL
variables: [plan]
updated: 2026-09-25
---
# Challenge my plan

Use for: Finding weak points in a plan, proposal or decision before you commit to it.

Do not use for: Plans that contain customer or personal data; describe them without it.

## Prompt

```text
Here is my plan:

{{plan}}

Ask me up to five questions that expose its weakest points, one question at a time. Wait for
my answer before asking the next. Do not propose a new plan until I have answered all of them.
```

## Review before use

- The questions address this plan, not generic project risks.

## Changelog

- 1.0.0 (2026-09-25): first version.
