# 30-agent-setup

One set of work rules and skills for every AI harness (Claude Code, Codex, Gemini CLI,
opencode, pi, Copilot, Cursor, Aider, Continue). CLI: `kit-sync`. Needs `python3` or the kit
CPython (`00-python`). Offline.

```sh
cd ~/work/kit/modules/30-agent-setup && bash install.sh          # installs kit-sync, syncs detected harnesses
bash install.sh --permissions ask                                # harnesses ask before acting (default: bypass)
bash uninstall.sh
```

Open a new terminal.

```sh
kit-sync --dry-run                   # show what would change
kit-sync --harness claude,codex      # or --all
kit-sync --permissions ask
kit-sync --permissions bypass
kit-sync --project ~/work/my-repo    # project files: AGENTS.md, CLAUDE.md, copilot, cursor
```

kit-sync also turns off agent co-author attribution, self-update and telemetry (Aider:
auto-commits), registers the installed MCP servers `brain` and `doc-qa` (only those on the
13-ai-governance allowlist, if present) and sets global git hooks that strip `Co-authored-by:`
lines and then run each repository's own hooks.

Edit rules in `source/AGENTS.md`, skills in `source/skills/<name>/SKILL.md`, then run
`bash install.sh` again. Skills land in `~/.agents/skills`. Details and tests: `~/work/kit/docs/adapters.md`.
