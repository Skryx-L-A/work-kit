# Kit Workbench

Orchestrator and workers inside VS Code. Workers run as CLI agents in integrated terminals
(Claude Code, Codex, Gemini CLI, Copilot CLI, opencode, Aider, ...), as VS Code language models
(`vscode.lm`, e.g. GitHub Copilot), or as OpenAI-compatible APIs (Ollama, llama.cpp, OpenAI, ...).

- Chat view: `@workbench <goal>`; Copilot agent mode can use the `kit_*` tools.
- Command palette: `Kit Workbench: Open Orchestrator Panel`, `Start Orchestrator in Terminal`,
  `Spawn Worker`, `Spawn Worker from Template`, `Open Worker Overview`, `List Models`,
  `Discover Local Models`, `Set Provider API Key`.
- Activity bar: Workers (status, result view, task, stop, run again with another model) and
  Status (brain, skills, work rules, data guard, models). Worker overview: one card per run.
- Registry: `~/.config/work-kit/workbench/models.json`. Runs: `~/.local/share/work-kit/workbench/runs/`.
