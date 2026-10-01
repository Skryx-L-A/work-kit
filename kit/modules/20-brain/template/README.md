---
title: Brain
type: reference
tags: [brain]
---

# Brain

Personal work notes. Markdown with YAML frontmatter, one git commit per change.

| Folder | Content |
|---|---|
| `inbox/` | Quick notes, sort later |
| `projects/<slug>/KERN.md` | Current decisions and known pitfalls of a project |
| `projects/<slug>/sessions/` | Session logs: goal, done, open |
| `decisions/` | Decision records (ADRs), numbered |
| `howto/` | Repeatable procedures |
| `reference/` | Facts, links, glossaries |
| `people/` | Work contacts only: role, how to work with them |

Frontmatter fields: `title`, `type` (note, session, decision, howto, reference, kern, person),
`project`, `tags`, `created`, `updated`, `status` (decisions).

Commands: `brain search "<query>"`, `brain new <type> "<title>"`, `brain append <path>`,
`brain read <path|title>`, `brain recent`, `brain doctor`.

Do not store secrets, passwords or customer data here.
