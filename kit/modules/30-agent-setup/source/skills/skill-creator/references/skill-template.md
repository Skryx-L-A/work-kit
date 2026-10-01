# SKILL.md skeleton

Load when writing a new skill from scratch. Copy, replace every `<...>`, delete what does
not apply. Keep the result under 150 lines; move long material to `references/`.

```markdown
---
name: <folder-name>
description: '<What it does in one sentence>. Use when <situations and the words a user would say>. Do not use for <near miss> (use <other skill>).'
---

# <Title>

<One or two lines: purpose, and the company rule that matters most for it, if any.>

## Procedure

1. **<Verb phrase>.** <What to do, which kit CLI or skill to use, what to ask only if unknown.>
2. **<Verb phrase>.** <...>
3. **Save / hand over.** <Where the result goes: file, brain note, commit, message draft.>

## When a tool is missing

- No `<cli>`: <manual fallback>, and say so once.

## Done when

- <Observable criterion 1.>
- <Observable criterion 2; include what was verified and how.>

## Pitfalls

- <Real failure mode>: <better alternative>.
- <...>
```

Checks before committing:

- `python3 scripts/validate_skill.py <skill-dir>` passes.
- The description contains the trigger words and at least one "Do not use for".
- Every `references/...` or `scripts/...` path named in the body exists.
- No harness-, model- or person-specific paths; kit CLIs by contract name only.
