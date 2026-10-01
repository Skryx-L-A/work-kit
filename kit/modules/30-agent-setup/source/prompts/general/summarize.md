---
id: general/summarize
title: Summarize a text
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [all]
data_class: INTERNAL
variables: [max_points, reader, text]
updated: 2026-09-25
---
# Summarize a text

Use for: Summarizing a document, thread or notes that you paste in.

Do not use for: Questions the text does not answer (the model will guess); use a search or ask a person.

## Prompt

```text
Summarize the text below in at most {{max_points}} bullet points for {{reader}}. Then list
open questions, and every date and number exactly as it appears in the text. Do not add
anything that is not in the text; if something important is unclear, say so.

Text:
{{text}}
```

## Review before use

- Each bullet is backed by the text.
- Dates and numbers match the source.
- Nothing important from the source is missing.

## Changelog

- 1.0.0 (2026-09-25): first version.
