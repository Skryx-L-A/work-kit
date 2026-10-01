---
id: office/reply-draft
title: Draft a reply to a request
version: 1.0.0
status: active
owner: TODO(set owner)
roles: [office, pm]
data_class: INTERNAL
variables: [goal, must_include, must_not_promise, tone, max_sentences, message]
updated: 2026-09-25
---
# Draft a reply to a request

Use for: Drafting a reply to an internal or external message that you will read and send yourself.

Do not use for: Replies that commit the company legally or financially; those need the responsible person.

## Prompt

```text
Draft a reply to the message below.
Goal: {{goal}}
It must include: {{must_include}}
It must not promise: {{must_not_promise}}
Tone: {{tone}}. Length: at most {{max_sentences}} sentences.

Message:
{{message}}
```

## Review before use

- No promise beyond what you may promise.
- All required points included.
- No internal detail the recipient must not see.

## Changelog

- 1.0.0 (2026-09-25): first version.
