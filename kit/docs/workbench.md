# 70-workbench: install options, worker models, paths, tests

## Install options

```sh
bash install.sh --permissions ask         # or accept-edits; default: bypass
bash install.sh --no-hooks                # do not register the Claude Code hooks
bash install.sh --no-vscode               # skip the VS Code extension
bash install.sh --no-app                  # skip the desktop app
```

## Desktop app (Linux x86_64)

The installer puts the Agent Workbench desktop app (Electron) below
`~/.local/share/work-kit/workbench-app/`, the launcher `~/.local/bin/agent-workbench` and the
menu entry "Agent Workbench" (search: workbench, werkbank, agents). Its interface is German or
English after the system language; it is not translated further (SPEC).

```sh
agent-workbench                   # open the window (a second start while it runs does nothing)
agent-workbench --version         # Electron version
agent-workbench --ctl state       # ask the running app (awb-ctl); --ctl --help lists the commands
```

- It shows the tmux sessions of `wb-code` and their workers, starts sessions (the plus button),
  shows pending guard questions with Approve and Reject, and has a settings window. Sessions
  it starts are started as a measured human (`wb-mensch`: the app is the caller's ancestor).
- One machine: the second-machine views, guest sources and the phone app of the source
  repository are not included (`docs/workbench-port.md`).
- Electron and node-pty come from `kit/offline/workbench-app/` (the build host fills it with
  `fetch.sh`). Without them, or on another system, the installer says so and skips the app.
- Electron needs the usual desktop libraries (GTK 3, NSS, ALSA, GBM). A desktop Ubuntu has
  them; `verify.sh` names a missing one, and `bash ../01-prereqs/install.sh vscode` installs
  the same set.
- Sandbox: like VS Code (01-prereqs), the app starts with `--no-sandbox` when AppArmor
  restricts unprivileged user namespaces (Ubuntu 23.10 and later) and `chrome-sandbox` is not
  setuid root, which it cannot be below `$HOME` without sudo.

- Slow machines: the app runs the workbench tools (`wb-mensch`, `wb-code`, `wb-state`, tmux, ps,
  git) without holding its main process, so its windows keep responding while a tool works; a
  slow tool delays only its own answer (a session start waits for `wb-mensch` up to 20 s).
- Model choice: the first-start guide and the Session page of the settings window store the
  family alias for the newest model of a family (Claude Opus 5.5 is stored as `opus`) and show
  the model it resolves to; an older version stays a deliberately pinned id.

## VS Code extension

`install.sh` installs the "Agent Workbench" extension (`payload/vsix/`). It does not open a tab
by itself: the command "Agent Workbench: Open start page" or its activity-bar icon opens the start
page. It knows this machine only; its settings page opens the desktop app.

## Worker models

- `wb-state models table` lists the registered models and harnesses; use one of those.
- `pi-worker <name> <model> <dir> <task...>`: `<model>` is a registry id (for example
  `qwen3.5-4b` via kit-llm), a `<provider>/<model>` pair from `~/.pi/agent/models.json`, or a
  Claude family alias (`haiku`, `sonnet`, `opus`, `fable`) or a Codex family alias
  (`sol`, `terra`, `luna`, `astra`). Family aliases resolve to the newest enabled member
  whenever a worker starts; use a full registry id only when a task must stay pinned.
- `pi-worker <name> default ...` uses the setting `workerModel` (delivered: `sonnet`).
- Local endpoint: kit-llm's `127.0.0.1` port; `KIT_LLM_BASE_URL=http://host:port/v1` overrides it.
- Other modules add endpoints with `wb-state models add-provider` / `remove-provider`
  (`wb-state models add-provider --help`).

## Worlds, skills, paths

- Agent worlds (`wb-welt`, `wb-agent`, `wb-ticket`): the skill and template library of the source
  repository is not included; agents get the skills you add (`wb-skill`). No mail access tools ship.
- One machine: `wb-traeger` and `wb-aufgabe` work on this machine (`wb-traeger status` names it
  "this machine"). A second machine is an explicit `agents.maschinen` entry in
  `~/.claude/workbench/settings.json`.
- A project with a file `.wb-ohne-brain` in its folder or a parent never gets brain content:
  its worker protocol forbids `brain search`, also with `--brain on`.
- `wb-hygiene` checks the size of the always-loaded instruction files, stale tmux test sockets and
  the workbench's memory (`wb-speicher`: on Linux PSS per process from `/proc` and MemAvailable);
  the checks of the build machine are named as not included.
- Claude Code hooks: guards are registered with a 60 s timeout, the other hooks with 30 s (a
  guard that times out would let the command run).
- Roles: `~/.claude/roles/`. Rules: `~/.claude/workbench/rules/`. Registry:
  `~/.claude/workbench/models.json`.
- Maintainers: the port tooling (`port/`, `docs/workbench-port.md`) lives in the kit repository
  only; the stick carries the built `payload/`.

## Tests

```sh
bash verify.sh --temp-home        # full install/spawn/uninstall test in a temp HOME
                                  # (Linux x86_64: also installs, starts and removes the app)
bash tests/linux-checks.sh        # Linux-only probes (processes, guard, status line)
```
