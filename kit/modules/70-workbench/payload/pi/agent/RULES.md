# Workbench: shared instructions for pi

These rules apply to every harness and model. The kit work rules (`AGENTS.md`, installed by the
kit module 30-agent-setup) are the base; the paths below are real locations.

Your role comes from the current task or the injected role prompt. Without a delegated task you
are the human's contact. Read only the fitting role: `~/.claude/roles/orchestrator.md` or
`~/.claude/roles/agent.md`. Safety rules and explicit decisions of the human always apply; rules
of the running harness take precedence.

Skills live in `~/.agents/skills` (kit module 30-agent-setup). Report a missing tool plainly;
never invent commands, model names or paths.

Workbench adapter: `pi`. The start command, role path and capabilities come from
`~/.claude/workbench/models.json`; `wb-state models get <model-id>` shows an entry. A registered
harness is not a successful run: check the tools and limits of the current session.
