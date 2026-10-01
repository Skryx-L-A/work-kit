---
name: prompt-library
description: 'Find, fill in, add, version and retire prompt templates in the versioned prompt library (role-based, with data-class labels, owners and retirement markers). Use when someone asks for a good prompt for a recurring task, wants to save or share a prompt that worked, change a team prompt, or clean up old prompts. Do not use for agent skills or instructions (use skill-creator), for designing a whole workflow (use workflow-design) or for measuring prompt quality in depth (use eval-design).'
---

# Prompt library

Recurring prompts live as versioned files, one per prompt, with an owner, a data class and
a status. The library ships in `30-agent-setup/source/prompts/`; the format and the rules for
adding, changing and retiring are in its `README.md`. Tool: `scripts/prompt_lib.py`.

```
P=<this skill>/scripts/prompt_lib.py      # e.g. ~/.agents/skills/prompt-library/scripts/prompt_lib.py
python3 $P list --role office             # active prompts for a role
python3 $P render <id> --var k=v --var-file notes=notes.md
python3 $P check                          # lint the whole library
python3 $P new <group>/<name> --title "..." --class INTERNAL --role pm
```

## Procedure: someone needs a prompt

1. Ask for the task, the reader of the output and the data the prompt will see (only if
   unclear). Classify the data (`data-guard` skill). If the class is higher than the tool is
   approved for, stop and say so.
2. `list --role <role>` and pick the closest active prompt. Read it with `show`: check "Use
   for", "Do not use for" and `data_class`.
3. `render` it with the user's values. Missing variables fail on purpose: ask for them
   rather than inventing content.
4. Hand over the prompt together with its "Review before use" list. The user runs it in
   the approved tool and checks the output.
5. No fitting prompt: write one ad hoc with task, context, material, format, constraints
   and a check. If the user will reuse it, continue with "add".

## Procedure: add or change a prompt

1. Check for overlap with `list --all`; extend an existing prompt rather than adding a
   near-duplicate.
2. New: `new <group>/<name>` (draft 0.1.0). Change: edit the file and bump the version
   (PATCH wording, MINOR better or optional content, MAJOR changed variables or output
   format) with a changelog line.
3. Test on 3 to 5 realistic, non-confidential inputs. Record one failure found and fixed in
   the changelog. For prompts used by many people or in a workflow, compare old and new
   with a short eval (`eval-design`, `evalkit` if installed).
4. Set `status: active`, a real `owner`, `updated`. Run `check`; fix every error.
5. Commit only the prompt file: `prompts: add|update <id> <version>`. In the kit source
   run `kit-sync` afterwards so installed copies update (`kit-maintenance`).

## Procedure: retire

Never delete or reuse an id. Set `deprecated` plus `replaced_by` while people switch, then
`retired` with a date and changelog line. Retire after a harmful wrong output, when the
tool or data class is no longer approved, or after six months without use.

## Where prompts go

| Prompt is | Put it in |
|---|---|
| Useful for several teams, reviewed | kit library `source/prompts/<group>/` |
| For one team or only you | `~/work/prompts/<group>/` (same format; searched second) |
| A multi-step procedure an agent follows | a skill (`skill-creator`), not a prompt |
| A company registry exists (e.g. MLflow Prompt Registry) | there; keep this library as the offline copy |

## When a tool is missing

- No Python: open the files directly; fill `{{variables}}` by hand; check the frontmatter
  fields against the README.
- Library folder missing (30-agent-setup not installed): use `~/work/prompts/` with the
  format from `references/format.md`.

## Done when

- The user has a rendered prompt, its data class and its review list, or
- a new or changed prompt passes `check`, has a version bump, changelog line, owner, and
  was tried on realistic non-confidential input, and only its file is committed.

## Pitfalls

- Prompts with real customer names, hostnames or personal data as "examples": use invented ones.
- Changing a shared prompt silently: always bump the version, so earlier results stay explainable.
- Treating `data_class` as permission: it says what the prompt was designed for, the tool
  approval decides what may be sent.
- One giant prompt for everything: one task per prompt, variables for what changes.
- Copying prompts from the internet without reading them: prompts are instructions; review
  them like code.
