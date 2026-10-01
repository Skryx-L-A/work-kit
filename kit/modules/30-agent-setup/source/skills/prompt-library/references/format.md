# Prompt file format

Copy of the format in the kit prompt library README, for use when the library folder is not
installed.

```markdown
---
id: office/reply-draft          # = path; never reused for a different prompt
title: Draft a reply to a request
version: 1.2.0                  # MAJOR.MINOR.PATCH
status: active                  # draft | active | deprecated | retired
owner: Team Office              # who answers for it and approves changes
roles: [office, pm]             # office, pm, developer, management, all
data_class: INTERNAL            # most sensitive input class the prompt is meant for
variables: [goal, message]      # every {{name}} in the prompt block, nothing else
updated: 2026-09-25
replaced_by: office/reply-v2    # deprecated/retired only
retired: 2026-10-01             # retired only
---
# Title

Use for: ...
Do not use for: ...

## Prompt
(one fenced block with {{variables}})

## Review before use
(what the user checks in the output)

## Changelog
- 1.2.0 (2026-09-25): what changed and why.
```

`data_class` does not approve a tool: the user still checks the tool is approved for the
data they paste (data classes in `40-data-guard`).

