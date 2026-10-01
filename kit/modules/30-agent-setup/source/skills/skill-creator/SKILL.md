---
name: skill-creator
description: 'Create, rewrite or shorten a reusable agent skill (SKILL.md in agentskills.io format) when a workflow repeats and should be done the same way every time. Use when the user asks to add, improve, split or check a skill. Do not use for one-off instructions (answer directly), for global rules that apply to every task (edit AGENTS.md via kit-maintenance), or for project facts (use the brain).'
---

# Skill creator

A skill is a folder with `SKILL.md` that an agent loads when its description matches the
task. Good skills are short procedures with a clear trigger, not manuals.

## Format

```
<name>/
  SKILL.md          required: frontmatter + procedure, under 150 lines
  references/       optional: long details, templates, loaded only when named
  scripts/          optional: deterministic helpers (standard library if possible)
```

```markdown
---
name: <name>            # lowercase, digits, hyphens; equals the folder name
description: '<what it does>. Use when <triggers>. Do not use for <near misses> (use <other skill>).'
---
```

Quote the description: an unquoted `: ` inside it is invalid YAML and some harnesses then
skip the skill silently.

The description is the only part an agent sees before deciding to load the skill. Put all
trigger words there, in the words a user would say. Keep it under about 500 characters.

## Procedure

1. **Establish the contract** from the conversation and existing skills: trigger, inputs,
   output, done criterion, safety boundary, and which tools are required, optional or
   absent. Ask only for a missing decision that changes the skill.
2. **Check for overlap**: list existing skills (`ls ~/.agents/skills` or the kit source) and
   read any with a similar name. Extend an existing skill rather than adding a near-duplicate.
3. **Write the body** in this order:
   - one or two lines: purpose,
   - procedure: numbered, imperative steps, the normal path first,
   - what to do when an optional tool or kit module is missing,
   - done when: observable criteria,
   - pitfalls: real failure modes, each with the better alternative.
4. **Keep it portable**: refer to capabilities ("use the available web search tool") and to
   kit CLIs by their contract names (`brain`, `evalkit`, `kit-sync`), not to one harness,
   model, account or personal path. No secrets, customer data or internal hostnames.
5. **Move detail out**: templates, long tables, examples and rare branches go into
   `references/` with a sentence saying when to load them. Scripts need defined input,
   output and exit codes, and must work offline.
6. **Validate**: `python3 scripts/validate_skill.py <skill-dir>` (checks frontmatter, name,
   description length, line count, required sections). Fix every error.
7. **Test the trigger** with two or three realistic requests: one that should load the
   skill, one near miss that should not. Adjust the description, not the body, for trigger
   problems. For important skills, run a short eval (`eval-design`) comparing results with
   and without the skill.
8. **Install**: put the folder in the kit source and run `kit-sync` (`kit-maintenance`).

## Done when

- The validator passes.
- The description names triggers and at least one near miss.
- Body has procedure, missing-tool fallback, done criterion and pitfalls, under 150 lines.
- A realistic request loaded the skill and a near miss did not, or the check is reported
  as not done.

## Pitfalls

- Vague descriptions ("helps with documents"): the skill never triggers, or always does.
- Copying a skill from the internet or another setup without reading and adapting it.
  Skills are instructions an agent follows: review them like code.
- Repeating global rules (secrets, verification) in every skill. Inherit them.
- Mandatory heavy steps (multiple agents, full reviews) for every run. Scale to the task.
- Scripts that need network access or packages not in the kit.
