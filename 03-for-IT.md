# For your company's IT: what the work kit installs

Purpose: work tools for one user on a company Ubuntu x86_64 laptop.
Everything installs per user under `$HOME` (`~/.local/bin`, `~/.local/share/work-kit/`,
`~/.config/work-kit/`, `~/work/`). No module needs sudo; the few optional root steps are marked
below and are never run by the menu. Each module can be refused on its own; the others still work.
The fetch needs network access and about 15 GB of storage. Installation then uses the fetched, SHA-256-checked files without network access.

## Check the files

```sh
cd ~/work-kit/kit/offline && sha256sum -c SHA256SUMS
```

`setup/install-kit.sh` runs the same check after copying to `~/work/kit` and stops on any mismatch.
Design notes per module: `kit/docs/`.

## Modules

Uninstall: `bash ~/work/kit/modules/<module>/uninstall.sh` (flags in the table). "Loopback" = 127.0.0.1 only.
"Not recorded" = the kit does not record the licence; see the upstream project.

| Module | What it does | Network on the laptop | Listens on | sudo / root | Third-party licences | Uninstall |
|---|---|---|---|---|---|---|
| 00-python | uv and CPython 3.12 | none during install (uses fetched files) | none | no | uv, CPython: not recorded | `uninstall.sh` |
| 01-prereqs | VS Code, git, tmux, curl, python3, Node.js, optional tools, unpacked from .debs | none from the module; VS Code, git, curl, npm, browsers connect as usual | none | optional `--sudo`: `apt-get` against the fetched offline repository only (chrome, edge, zsh need it) | Ubuntu archive packages, VS Code, Node.js: not recorded | `uninstall.sh [--sudo] [item ...]` |
| 10-base-tools | rg, fd, jq, fzf, just, direnv, gitleaks, yq, delta | none | none | optional `apt.sh` (offline apt) | not recorded | `uninstall.sh` |
| 11-legacy-toolbox | ctags, scc, tree-sitter, semgrep, dependency graphs | none (`kit-semgrep` switches metrics and version check off) | none | no | Semgrep rules: Semgrep Rules License v1.0, internal analysis only; others not recorded | `uninstall.sh` |
| 12-docs-tools | d2, pandoc | none | none | optional `apt.sh` (graphviz, offline apt) | not recorded | `uninstall.sh` |
| 13-ai-governance | AI usage guideline, checklists, MCP allowlist, `ai-gov` | none (reads local config files) | none | no | none | `uninstall.sh` (keeps policy files) |
| 14-llm-usage | token and cost log of LLM calls | only the upstream the user sets (default loopback 8080) | loopback 4011, only while `llm-usage start` runs | no | none | `uninstall.sh` (keeps logs) |
| 15-local-llm | llama.cpp on the CPU with small models | none | loopback 8080 (`llama-server`, no API key), only while `kit-llm` runs it | no | models Apache-2.0; llama.cpp not recorded | `uninstall.sh [--keep-models]` |
| 16-harness-clis | Claude Code, Codex, opencode, Copilot CLI, Gemini CLI, pi, Aider (pinned) | each CLI talks to its vendor's API after sign-in; self-update off (set by 30) | none | no | Claude Code, Copilot CLI proprietary; Codex, Gemini CLI, Aider Apache-2.0; opencode, pi MIT | `uninstall.sh [name ...]` |
| 17-meeting-capture | local recording, whisper transcript, note | loopback only; a remote server needs an explicit opt-in variable | loopback, random port, whisper server during transcription | no | none (engine from 80) | `uninstall.sh [--purge-audio]` |
| 18-doc-qa | Q&A over IT-approved documents; ships disabled | none | none (MCP over stdio) | no | as 20 | `uninstall.sh` |
| 19-enablement | AI training material to `~/work/enablement` | none | none | no | none | `uninstall.sh` |
| 20-brain | work notes with local search, `brain` CLI | none; `brain sync` only to a git remote the user adds | none (MCP over stdio) | no | embedding model Apache-2.0; Python packages not recorded | `uninstall.sh` (keeps notes) |
| 30-agent-setup | one set of rules and skills for every AI tool (`kit-sync`) | none; switches update checks and telemetry of the AI tools off | none | no | none | `uninstall.sh` |
| 31-caveman | short chat style for the AI tools | none | none | no | caveman MIT | `uninstall.sh` |
| 32-harness-profiles | role prompts, guard hooks (dangerous commands, secrets), status line | none | none | no | none | `uninstall.sh` |
| 33-model-endpoints | registers company model servers for the AI tools (`kit-models`) | only endpoints the user registers | loopback 4020, translating proxy, only when a registered endpoint needs it | no | none | `uninstall.sh [--purge]` |
| 35-company-network | proxy and company root CA for user tools (`kit-net`) | none; `kit-net test <url>` only to the given URL | none | no (user CA bundle, system trust store untouched) | none | `uninstall.sh` |
| 40-data-guard | blocks secrets and company strings in git commits | none | none | no | not recorded (uses gitleaks from 10) | `uninstall.sh` |
| 50-eval | `evalkit`: test suites against models | only model endpoints set in a suite | none | no | pyyaml: not recorded | `uninstall.sh [--purge]` |
| 60-terminal | bash, tmux, direnv config, project template | none | none | no | none | `uninstall.sh` |
| 70-workbench | orchestrator and worker AI agents in tmux, VS Code extension, desktop app Agent Workbench (Electron, below `~/.local/share/work-kit`; starts without its sandbox when AppArmor restricts user namespaces, like VS Code) | none by default; optional helpers reach framer.com, api.browserbase.com, pypi.org, registry.npmjs.org, nodejs.org; launched AI CLIs reach their vendors | none by default; optional helpers on loopback (8080, 8766-8767, 8776-8777) and user-only Unix sockets (the desktop app's control socket among them) | no | extension MIT; Electron MIT (Chromium parts: its LICENSES.chromium.html); node-pty MIT; others not recorded | `uninstall.sh` |
| 71-delegate | starts AI workers in tmux panes | none; launched AI CLIs reach their vendors | none | no | none | `uninstall.sh` |
| 72-vscode-workbench | orchestrator and workers inside VS Code | only the model endpoints the user configures | none | no | not recorded | `uninstall.sh` |
| 80-quassel | local dictation (whisper.cpp) | none | loopback 8765 (whisper server, on demand, not at login); user-only Unix socket | optional `sudo bash root-steps.sh`: user to group `input`, udev rule for `/dev/uinput`, `uinput` module; `--undo` reverts. Clipboard mode works without it | Quassel: shipped `LICENSE`; whisper.cpp, models, ydotool, PySide6: not recorded | `uninstall.sh [--purge]`, then `sudo bash root-steps.sh --undo` |
| 90-design | design reference folders, `kit-design` (PPTX, HTML, PDF) | none | none | no | Chrome headless shell, python-pptx, lxml, pillow: not recorded | `uninstall.sh` |
| 95-desktop | GNOME/KDE tiling, keybindings, themes, Ghostty, fonts | none | none | optional `apt.sh` (offline apt) | see `kit/modules/95-desktop/NOTICE.md` (MIT, GPL-3.0, OFL-1.1, Apache-2.0; Space Bar extension has no licence file) | `uninstall.sh [--full-restore]` (restores the desktop settings) |

## Changes outside the kit folders

- `~/.bashrc` / `~/.profile`: marked blocks from 60, 33 and 35 (35 only after `kit-net proxy set` or `ca add`).
- git: `core.hooksPath` set globally by 30 (70 only without 30; 40 only with `--global-hooks`).
- AI tool settings (`~/.claude`, `~/.codex`, `~/.gemini`, ...) from 30, 31, 32, 33, 70. Default approval mode is
  bypass, protected by the guard hooks; `~/work/kit/install --permissions ask` switches to asking.
- VS Code extensions from 70 and 72; systemd user units from 80 (not enabled); dconf, GNOME extensions and
  autostart entries from 95 (a full `dconf dump` is saved first).
- Sandbox: VS Code (01) starts with `--no-sandbox` when AppArmor restricts user namespaces;
  headless Chrome (90) runs with `--no-sandbox`.
