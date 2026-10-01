# 32-harness-profiles

Role prompts (lead or worker), guard hooks before shell commands, brain recall and project KERN
at session start, and a status line, for Claude Code, pi, Codex, Gemini CLI, Copilot (CLI and
VS Code), Cursor, opencode, Aider and Continue. Needs `python3` or the kit CPython (`01-prereqs`,
`00-python`). Uses `20-brain`, `31-caveman`, `40-data-guard`, `70-workbench`/`71-delegate` when
installed. Offline, no sudo.

```sh
cd ~/work/kit/modules/32-harness-profiles && bash install.sh    # detected harnesses, role lead
bash install.sh --role worker                                   # or none
bash uninstall.sh
```

Open a new terminal, then restart the harnesses.

```sh
KIT_AGENT_ROLE=worker pi            # one worker session (also Claude Code, Gemini, Copilot, Cursor)
codex --profile kit-worker          # worker session in Codex
kit-profiles status
```

Cursor: paste `~/.local/share/work-kit/generated/kit-role-cursor-user-rule.md` into User Rules.

Guard settings and tests: `~/work/kit/docs/harness-profiles.md`.
