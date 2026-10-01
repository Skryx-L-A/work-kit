---
id: pm/pre-mortem
title: Pre-mortem of a work package
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [pm, management]
data_class: INTERNAL
variables: [description]
updated: 2026-09-25
---
# Pre-mortem of a work package

Use for: Finding risks before a work package starts.

Do not use for: A replacement for the project's risk register; add the results there.

## Prompt

```text
Imagine this work package has failed six months from now:

{{description}}

List the ten most likely reasons, most likely first. For each, give an early warning sign
and one preventive action. Mark reasons that are generic to any project.
```

## Review before use

- Remove generic filler; keep risks specific to this work package.
- Add obvious misses from your own knowledge.

## Changelog

- 1.0.0 (2026-09-25): first version.
