---
id: dev/explain-code
title: Explain unfamiliar code
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [developer]
data_class: CUSTOMER
variables: [language, code]
updated: 2026-09-25
---
# Explain unfamiliar code

Use for: Understanding legacy or unfamiliar code as a starting point for your own reading.

Do not use for: Customer code in a tool not approved for CUSTOMER data.

## Prompt

```text
Explain what this {{language}} code does, for a developer new to the codebase: purpose,
inputs, outputs, side effects, error handling, and anything surprising. For each claim,
point to the line. Say what you cannot tell without seeing other files.

Code:
{{code}}
```

## Review before use

- Verify at least the surprising claims by running the code or a test.
- Claims about other files are marked as unknown.

## Changelog

- 1.0.0 (2026-09-25): first version.
