# Skill, prompt, script, workflow or rule?

Load when someone wants to "make this reusable" and it is not yet clear that a skill is the
right container. Pick the lightest artifact that makes the next repetition reliable.

| The thing to reuse is | Make it a | Where | Skill that helps |
|---|---|---|---|
| One instruction for one task a person pastes into a chat tool | prompt | prompt library (`source/prompts/` or `~/work/prompts/`) | `prompt-library` |
| A multi-step procedure an agent should follow, with judgement between steps | skill | `source/skills/<name>/` | this one |
| A deterministic sequence of commands with defined input and output | script | a skill's `scripts/`, or a project's `justfile` / tool | this one (scripts section) |
| A team process with AI steps, owners, human gates and metrics | workflow spec | project documentation or a brain note | `workflow-design` |
| A rule that applies to every task in every project | rule | `source/AGENTS.md` (keep it short) | `kit-maintenance` |
| A rule for one repository | project rule | the repository's `AGENTS.md` | `kit-maintenance` (`kit-sync --project`) |
| A fact, decision or pitfall of a project | note | brain (`KERN.md`, decision record) | `brain`, `decision-record` |

Signals that a skill is too heavy: the procedure has one step, it never needs judgement,
or only one person uses it once a month. Signals that a prompt is too light: people keep
adding "and then also check ..." by hand, or the task needs files, tools or several turns.

Combinations are normal: a workflow spec references prompts by id and version and skills by
name; a skill calls its own scripts; a rule points to a skill instead of repeating it.
