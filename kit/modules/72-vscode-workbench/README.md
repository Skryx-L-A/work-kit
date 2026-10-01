# 72-vscode-workbench

Kit Workbench: orchestrator and workers inside VS Code, no tmux. Workers: CLI agents in
terminals, VS Code language models (Copilot), or OpenAI-compatible APIs. Needs VS Code 1.101+
(install it first if missing: module 01-prereqs). Optional: `20-brain`, `30-agent-setup`, `40-data-guard`.

```sh
cd ~/work/kit/modules/72-vscode-workbench && bash install.sh    # installs the .vsix and kit-wb
bash uninstall.sh
```

Open VS Code: Command Palette > `Kit Workbench: Open Orchestrator Panel`.
Chat view: `@workbench Fix the failing login test`.

Commands, settings and development: `~/work/kit/docs/vscode-workbench.md`.
