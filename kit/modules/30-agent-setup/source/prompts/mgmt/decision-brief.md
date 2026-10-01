---
id: mgmt/decision-brief
title: One-page decision brief
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [management, pm]
data_class: INTERNAL
variables: [question, facts]
updated: 2026-09-25
---
# One-page decision brief

Use for: Preparing a decision with options, costs, risks and a recommendation.

Do not use for: Decisions about individual people.

## Prompt

```text
Write a one-page decision brief on: {{question}}
Cover the options, the costs and benefits of each, the risks, what we would need to believe
for each option to be right, and a recommendation. Use only the facts below; mark every
assumption as an assumption.

Facts:
{{facts}}
```

## Review before use

- Every number traces to the facts.
- Assumptions are marked.
- The recommendation follows from the analysis.

## Changelog

- 1.0.0 (2026-09-25): first version.
