# 31-caveman: notes

Owner decision (2026-09-25): on the work laptop every chat answer to the human is caveman
style, level full, in every harness. Files, commits, code, docs and agent-to-agent text use
it only where nothing is lost. The same rule is in `30-agent-setup/source/AGENTS.md`
(Communication), so it also arrives through `kit-sync`; this module makes it stick per harness.

## What is written where

Locations are the ones `30-agent-setup` uses (`docs/adapters.md`, checked 2026-09-24). Blocks
carry the marker `work-kit-caveman:begin/end`, distinct from the `kit-sync` block, so both
modules can be installed, changed and removed independently.

| Harness | Written |
|---|---|
| Claude Code | hooks `SessionStart` + `UserPromptSubmit` in `settings.json`, statusline badge if none is set, link `~/.claude/skills/caveman`, block in `~/.claude/CLAUDE.md` (fallback when hooks are blocked) |
| Codex | block in `$CODEX_HOME/AGENTS.md`, skill via `~/.agents/skills/caveman` |
| Gemini CLI | block in `~/.gemini/GEMINI.md`, skill via `~/.agents/skills` |
| opencode | block in `~/.config/opencode/AGENTS.md`, skill via `~/.agents/skills` |
| Copilot (VS Code) | block in `~/.copilot/copilot-instructions.md`, skill via `~/.agents/skills` |
| Cursor | paste file `~/.local/share/work-kit/generated/caveman-cursor-user-rule.md`, skill via `~/.agents/skills`; `--project DIR` writes `.cursor/rules/caveman.mdc` |
| Aider | `generated/caveman-aider.md`, added to `read:` of `~/.aider.conf.yml` only if the file has no `read:` key |
| Continue | `~/.continue/rules/caveman.md`, `alwaysApply: true` |

Installed copy: `~/.local/share/work-kit/caveman/` (hooks and skill links point there, so
the stick can be removed). Command: `kit-caveman`.

## Decisions

- Claude Code gets the hooks directly in `settings.json`, not through `claude plugin install`:
  works with any Claude Code version, needs no `claude` binary at install time, no network.
  If the caveman plugin is enabled or a caveman hook exists, nothing is added (no double context).
- `caveman-hook.sh` runs the pinned upstream Node activation hook when `node` exists. Prompt
  tracking always uses a small shell path so it never starts Node per prompt; it emits the full
  reminder and handles the common explicit `stop caveman` phrases. Levels other than full and
  `/caveman-stats` need node.
- Other harnesses have no hook mechanism the kit relies on: always-on rules are the mechanism.
  The rule text is `rules/caveman-rule.md` (derived from upstream `src/rules/caveman-activate.md`,
  plus the scope statement above).
- Not shipped from upstream: stats, cavecrew agents, MCP shrink, Windows scripts, opencode
  plugin, Gemini extension. Not needed for the always-on chat style.
- The upstream copy is verified against `upstream/SHA256SUMS` before every install.
