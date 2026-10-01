---
name: kit-maintenance
description: 'Maintain the installed work kit itself: edit the global agent rules (AGENTS.md source) and skills, regenerate harness adapters with kit-sync, add a project adapter, and keep the data-guard deny-list and data classes current. Use when the user wants to change agent rules or skills, a new AI tool was installed, adapters look stale, or a new customer name or internal host must be blocked. Do not use for normal project work or for changing a single repository''s own AGENTS.md content beyond generating it.'
---

# Kit maintenance

The kit keeps one source of truth and generates everything else. Edit the source, then
regenerate; never edit generated files directly, they are overwritten.

## Where things live

| What | Path |
|---|---|
| Kit copy on the laptop | `~/work/kit/` |
| Global rules (source) | `~/work/kit/modules/30-agent-setup/source/AGENTS.md` |
| Skills (source) | `~/work/kit/modules/30-agent-setup/source/skills/<name>/SKILL.md` |
| Canonical skills dir | `~/.agents/skills` (harness skill dirs link here) |
| Generated adapters | e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` |
| Deny-list for the pre-commit hook | `~/.config/work-kit/deny-patterns.txt` |
| Data classes policy | `~/work/kit/modules/40-data-guard/data-classes.md` |

## Before changing anything

1. Check tools: `command -v kit-sync brain gitleaks`.
2. Check history: if `~/work/kit` is a git repo (`git -C ~/work/kit status`), commit or note
   pending changes first. If it is not, copy the file you will edit to
   `<file>.bak-<yyyymmdd-HHMM>`. Suggest `git init` so later edits are traceable.
3. Read the file you will change in full.

## Change the rules (AGENTS.md)

1. Edit the source file. Keep it short (target under 120 lines); rules are imperative,
   testable and not duplicated in skills.
2. Preview: `kit-sync --dry-run`. Read which files would change.
3. Apply: `kit-sync`. It prints what it wrote; open one generated file and confirm the
   change is there.
4. Commit the source change with an English message, e.g. `rules: require data class check before upload`.

## Add or change a skill

1. Use the `skill-creator` skill for content and format.
2. Place it at `source/skills/<name>/SKILL.md`; `<name>` equals the frontmatter `name`.
3. Run `kit-sync` so `~/.agents/skills` and harness links include it; start a new agent
   session and check the skill is listed or triggers on a test request.

## New harness or project adapter

- New AI tool installed (its config dir now exists): run `kit-sync` again; it detects it.
  If it is not detected, check `~/work/kit/modules/30-agent-setup/README.md` for supported
  tools, and report it instead of hand-writing adapters.
- New repository without agent instructions: `kit-sync --project <dir>`. It writes
  `AGENTS.md` and the per-tool files only where none exist. Review and commit them in that
  repository.

## Deny-list and data classes

1. Add one entry per line to `~/.config/work-kit/deny-patterns.txt` in the format
   described in the file header or the data-guard README (customer names, internal host
   names, internal paths, project code names). Prefer specific patterns to avoid blocking
   normal words.
2. Test: in a scratch repo, stage a file containing the new term and run the hook (see the
   `data-guard` skill); it must block. Then check a normal commit still passes.
3. The deny-list itself is confidential: never commit it to a shared repository or paste
   it into an AI tool not approved for that class.
4. Data classes marked `TODO(ask IT)` stay at the strictest reading until IT answers. When
   an answer arrives, update `data-classes.md` with the answer, source and date, then run
   `kit-sync` if rules reference it.

## When a module is missing

- No `kit-sync`: re-run `~/work/kit/modules/30-agent-setup/install.sh`. If that is not
  possible, copy the changed skill folder to `~/.agents/skills/` by hand and tell the user
  that harness adapters were not regenerated.
- No deny-list file or no `gitleaks`: the data-guard module is not installed. Say so; do not
  create hook scripts by hand.

## Done when

- Source edited, not generated files; a backup or commit exists.
- `kit-sync` ran and printed the expected changes; one generated file was checked.
- For deny-list changes: the block test failed as intended and a clean commit passed.

## Pitfalls

- Editing `~/.claude/CLAUDE.md` or another generated file: lost on the next sync.
- Rules growing into a manual. Put procedures into skills, keep rules short.
- Duplicate rules in AGENTS.md and skills that drift apart.
- Weakening a data-guard check to get a commit through. Fix the content instead, or ask.
- Copying the kit's deny-list or policy answers from IT into public repositories.
