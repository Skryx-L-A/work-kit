# Prompt library

Versioned, role-based prompt templates. One Markdown file per prompt, in `<group>/<name>.md`;
the id is the path without `.md` (`office/reply-draft`). Git is the version history.
Tool: `skills/prompt-library/scripts/prompt_lib.py` (standard library Python).

```
P=~/.agents/skills/prompt-library/scripts/prompt_lib.py
python3 $P list [--role office] [--class INTERNAL] [--all]
python3 $P render pm/status-report --var audience="customer project lead" --var-file notes=notes.md
python3 $P check
python3 $P new team/weekly-mail --title "Weekly mail" --class INTERNAL --role office
```

Groups: `general`, `office`, `pm`, `dev`, `mgmt`. Personal or team prompts: `~/work/prompts/`
(same format, searched after this folder), or set `PROMPTS_PATH=dir1:dir2`.

## File format

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

## Add a prompt

1. `new <group>/<name>` creates a `draft` with version `0.1.0`.
2. Write the prompt, the review list and "Do not use for". No customer names, internal
   hostnames, personal data or secrets, not even as examples.
3. Test it on 3 to 5 realistic, non-confidential inputs; note one failure you fixed.
4. Set `status: active`, `version: 1.0.0`, a real `owner`, and add the changelog line.
5. `check` must pass. Commit with `prompts: add <id> 1.0.0`.

## Change a prompt

Bump the version and add a changelog line: PATCH for wording that keeps the output the same
kind, MINOR for new optional content or better instructions, MAJOR when variables change or
the output format changes (users' follow-up steps break). Re-run the test inputs; for
important prompts, compare old and new versions with an eval suite (`eval-design` skill).

## Retire a prompt

Never delete or reuse an id: old results must stay traceable to the prompt that made them.

1. `status: deprecated` plus `replaced_by` while people switch (or write "no replacement" in
   the body). `render` warns.
2. After the switch: `status: retired`, `retired: <date>`, a changelog line. `list` hides it;
   `render` refuses without `--allow-retired`.

Retire when a prompt produced a wrong result that reached someone, the tool or model it was
written for is gone, its data class is no longer approved, or nobody used it for six months.
