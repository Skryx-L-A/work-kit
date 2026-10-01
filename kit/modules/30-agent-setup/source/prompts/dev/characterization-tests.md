---
id: dev/characterization-tests
title: Draft characterization tests
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [developer]
data_class: CUSTOMER
variables: [framework, code]
updated: 2026-09-25
---
# Draft characterization tests

Use for: Pinning the current behavior of code before you change it.

Do not use for: Specifying the intended behavior (that is a spec, not a characterization).

## Prompt

```text
Write characterization tests in {{framework}} for the code below that pin its current
behavior, including edge cases, boundary values and error paths. Do not fix bugs; mark
suspicious behavior with a comment. Each test name says the behavior it pins.

Code:
{{code}}
```

## Review before use

- Run the tests against the unchanged code: all must pass.
- Assertions come from observed behavior, not from what the code should do.

## Changelog

- 1.0.0 (2026-09-25): first version.
