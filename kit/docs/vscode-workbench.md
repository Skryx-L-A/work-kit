# 72-vscode-workbench: scope and design

Module `kit/modules/72-vscode-workbench/` ships **Kit Workbench**, a VS Code extension that
acts as the agent workbench when the terminal workbench (`70-workbench`, tmux) or the slim
`71-delegate` variant is not allowed. Everything runs inside VS Code: an orchestrator and any
number of workers, each either a CLI harness in an integrated terminal or a model called
directly from the extension (VS Code Language Model API or an OpenAI-compatible HTTP API).

## Scope

In scope:

- One offline `.vsix`, installed with `code --install-extension` (no network, no sudo).
- Model sources: every source the terminal workbench's model registry knows today
  (CLI harnesses such as Claude Code, Codex, Gemini CLI, Copilot CLI, opencode, Aider, Goose,
  Qwen Code, Crush, pi; HTTP providers such as Ollama, llama.cpp, MLX servers, OpenAI,
  Google Gemini, OpenRouter, DeepSeek, Groq, Mistral, xAI, Anthropic API) **plus** the
  VS Code Language Model API (`vscode.lm`, e.g. GitHub Copilot models) as a first-class
  provider.
- Orchestrator inside VS Code, four entry points (all share one tool set):
  1. Chat participant `@workbench` in the Chat view, using the model selected there.
  2. Language model tools (`kit_spawn_worker`, `kit_list_workers`, `kit_read_result`,
     `kit_brain_search`, `kit_read_skill`) so Copilot agent mode can orchestrate directly.
  3. Orchestrator in a terminal: any CLI harness from the registry, started with a prompt that
     points it to the `kit-wb` helper (`kit-wb spawn|list|result|wait`).
  4. Orchestrator panel (webview chat) for API models that do not appear in the Chat view
     (e.g. a local Ollama model), so no Copilot subscription is required.
- Workers: terminal workers (any CLI harness) and API workers (vscode.lm or HTTP) with a small,
  restricted tool set.
- Result protocol with task and result files, status tree view, stop/open actions.
- Brain integration (module `20-brain`, optional): `brain search/read` via the CLI for API
  agents; the `brain mcp` server is registered as an MCP server definition for Copilot agent
  mode when the `brain` command exists.
- Skills from `~/.agents/skills/*/SKILL.md` (module `30-agent-setup`, optional): the index goes
  into the system prompt of API agents, full text via the `read_skill` tool.
- Data guard awareness (module `40-data-guard`, optional): modal confirmation before the first
  request to a non-local model in a session, with a link to `data-classes.md` when present.

Out of scope: tmux, a second machine, mobile access, media models, quota lanes, the Electron
app of the terminal workbench, telemetry. Personal data or company data is never part of the
extension.

## Starting point

The extension is a rewrite of the terminal workbench's VS Code extension, not a fork. That
extension is a tmux front end (session restore, pane focusing, SSH peers) with a German UI; those
parts do not apply here. Ported and translated:

- the model registry schema (`providers`, `harnesses`, `models`) with per-entry validation,
  placeholder rules (`{model}`, `{effort}`, `{workdir}`, `{name}`, `{prompt}`), and the
  data-locality rule (`kind: local` keeps data local unless overridden);
- the display helpers (`relativeTime`, `previewText`, `escapeHtml`, `shellQuote`) and their tests;
- the file-drop command channel idea, reused for spawn requests from terminal orchestrators.

## Surfaces taken from the terminal workbench extension (phase 3)

The phase 3 scope asks for the most useful surfaces of the terminal workbench's extension,
rebuilt on the kit's run protocol (no code port: that extension reads tmux panes and state files
the kit does not have).

Taken:

| Surface | Kit Workbench | Why |
|---|---|---|
| Worker grid | `Open Worker Overview`: one card per run (status, model, runner, age, paths, done criterion, result summary, open points), filters by status, actions per card, status chips on top | The tmux grid showed all workers at once; a webview grid does that without tmux |
| Result viewer | `View Result`: run facts, result sections, DONE/FAILED outcome, task, last log entries of API workers | The old extension only showed the first result line in a tooltip; reviewing results is the human's main job |
| Model picker per worker | Quick pick with readiness (`ready`, `CLI not installed`, `no API key`, `not available`), data locality and good-for/not-for; ready models first; `Run Again with Model…` for any finished run; `Set Default Worker Model` | The old registry page showed a status dot per model (binary missing, no key); a picker that hides unusable models prevents failed spawns |
| Worker state beyond running/done | "quiet since …" badge when a running worker's files did not change for `kitWorkbench.quietMinutes` (default 15) | The old sidebar had a `stalled` state; here it is a flag, never a status change |
| Send to orchestrator | `Send Selection/File to Orchestrator` (editor and explorer context menus): to the terminal orchestrator of this window as one line `path:lines `, else into the orchestrator panel's input with the selected text | Same commands existed; nothing is submitted, the human sends |
| Status overview | `Status` view and status bar item: brain (`brain status`), skills, work rules, data guard (`data-guard status`, data classes file, cloud confirmation), models ready, `kit-wb` on PATH, worker autonomy | The old start page showed setup state; here every optional kit module shows as ok / off / warn / missing |

New in the kit (no counterpart in the old extension):

- Task templates: Markdown with frontmatter (`name`, `description`, `model`, `paths`, `done`,
  `brain`, `skill`) and `{{variables}}` asked for at spawn time. Built-ins in
  `extension/resources/templates/` (code review, characterization tests, bug fix, legacy
  analysis, docs update, research summary), each naming a kit skill; the user's folder
  `kitWorkbench.templatesDir` (default `~/.config/work-kit/workbench/templates/`) replaces a
  built-in of the same name.
- `Archive Finished Runs` / `Archive Run`: moves runs to `<stateDir>/archive/`; nothing is deleted.
- The cloud confirmation opens the user's data classes (`~/.config/work-kit/data-classes.md`,
  installed by 40-data-guard) before the kit's template copy.

Left out, with reason:

- Start page with resumable sessions and Claude transcript previews: bound to tmux sessions and
  one harness's transcript format; kit runs are listed in the overview instead.
- Worker tab, layout sync, re-grid, overflow tabs: tmux window management; VS Code terminals
  need none of it.
- Closing the tmux session when the window closes (orphan watcher): no tmux here; runs of a
  closed window are marked failed on the next activation.
- Remote machine state over SSH and remote results: out of scope (second machine).
- Settings page and the models-and-harnesses editor that write through the terminal
  workbench's own CLI: VS Code settings plus `Open Model Registry` cover it without a second
  writer for the same file.
- Provider key status from a login check path: keys are checked from the environment variable
  and SecretStorage only; subscription logins cannot be verified without running the CLI.
- URI handler and command-file watcher: the kit's `requests/` channel (`kit-wb spawn`) is the
  one way in from outside.
- Bundled icon font: VS Code's built-in codicons suffice.

## Registry

File: `~/.config/work-kit/workbench/models.json` (setting `kitWorkbench.registryPath`).
Same shape as the terminal workbench registry, so a registry can be copied between the two;
unknown fields are ignored. Built-in providers and harnesses are merged under file entries
(a file entry with the same id wins). Models come from three places:

1. `models` in the registry file (manual entries; CLI harness or HTTP provider models);
2. `vscode.lm.selectChatModels()` at run time (provider `vscode-lm`, id `vscode-lm:<vendor>/<id>`);
3. discovery on demand (`Kit Workbench: Discover Local Models`): Ollama `/api/tags` and
   OpenAI-compatible `/models` of **local** providers only. Cloud catalogs are never fetched
   automatically.

A model's `harness` decides how it runs:

| harness | runs as | provider requirements |
|---|---|---|
| any CLI harness (`claude`, `codex`, ...) | terminal worker | the CLI is installed and logged in |
| `api` | in-process agent loop, OpenAI-compatible `/chat/completions` | `baseUrl`, key from `apiKeyEnv` or SecretStorage (not needed for local) |
| `vscode-lm` | in-process agent loop via `vscode.lm` | a chat model provider (e.g. Copilot) is installed |

## Runs and the result protocol

State lives in `~/.local/share/work-kit/workbench/` (setting `kitWorkbench.stateDir`):

```
runs/<run-id>/meta.json     name, model, role, cwd, paths, done criterion, status, times
runs/<run-id>/task.md       full task: goal, exclusive paths, done criterion, protocol
runs/<run-id>/result.md     written by the worker; last line "DONE" marks success
runs/<run-id>/log.jsonl     API workers: every model turn and tool call (no secrets)
requests/<id>/              spawn requests from terminal orchestrators (kit-wb spawn)
archive/<run-id>/           finished runs moved out of the lists (Archive Finished Runs)
```

Each run records the process id of the extension host that drives it; on activation only runs
whose host is gone are marked failed, so several VS Code windows can share one state dir.

Status: `running`, `done` (result file ends with `DONE`), `failed` (result without `DONE`,
terminal closed without result, or an API error), `stopped` (user or orchestrator stopped it).
A file watcher on `runs/` and terminal close events keep the tree view current.

`kit-wb` (bash, no dependencies) lets any terminal orchestrator use the protocol:

```
kit-wb spawn --name N --model ID [--paths a,b] [--done TEXT] [--cwd DIR] (--task-file F | -)
kit-wb list            kit-wb result RUN-ID            kit-wb wait RUN-ID [--timeout S]
```

`spawn` writes `requests/<id>/{request,task.md}`; the extension (it must be running) turns the
request into a run and writes `requests/<id>/run-id`, which `spawn` prints.

## API agent loop

One loop for workers and the orchestrator panel, independent of the backend
(`ChatBackend.send(messages, tools) -> { text, toolCalls }`); backends: `vscode.lm` and
OpenAI-compatible HTTP. Worker tools: `read_file`, `list_dir`, `write_file` (only inside the
run's exclusive paths, relative to its cwd), `brain_search`, `read_skill`, `finish`
(writes `result.md`). There is no shell tool: API workers cannot execute commands; tasks that
need commands go to a terminal worker. Step limit: `kitWorkbench.maxSteps` (default 40).
Cancellation stops the loop at the next step.

System prompt: the project's `AGENTS.md` if the workspace has one, else the kit rules
(`~/work/kit/modules/30-agent-setup/source/AGENTS.md`, setting `kitWorkbench.rulesFile`), plus
the skill index, the role text, and for workers the task file.

## Terminal workers

Command line: `harness.command` + `harness.args` (placeholders filled), plus `promptArgs`
(`{prompt}` = one line pointing at `task.md`) when the harness takes an initial prompt;
otherwise the prompt is sent with `terminal.sendText` after `kitWorkbench.promptDelayMs`.
Autonomy flags (`harness.autonomy.args`) are added only when `kitWorkbench.workerAutonomy` is
on (default off: a human approves tool use in the terminal). Every terminal gets
`BROWSER=true` so first-run prompts cannot open a browser.

## Switches and visibility

- `kitWorkbench.brainSearch` (default on, resource scope, so it can be switched off per project
  in workspace settings) controls the knowledge search step of the worker protocol and the
  `brain_search` tool. Per task: `kit-wb spawn --no-brain` or tool input `brain: false`.
- `kitWorkbench.revealWorkers` (default on): a new worker's terminal is shown without taking
  focus; API workers reveal the "Kit Workbench" output channel. Every run is in the Workers view.

## Safety

- API keys: environment variable named by `apiKeyEnv`, else VS Code SecretStorage
  (`Kit Workbench: Set Provider API Key`). Keys are never logged or written to run files.
- Cloud confirmation: before the first request to a model whose data does not stay local,
  a modal dialog asks once per provider and session (`kitWorkbench.confirmCloudModels`).
- Terminal workers are not gated by that dialog: the CLI agent talks to its provider itself.
  The model lists mark every model as "local" or "leaves this machine".
- `write_file` rejects absolute paths, `..`, and anything outside the exclusive paths.
- The extension runs no network request except the configured model endpoints and local
  discovery.

## Tests

- Unit tests (`node --test`, TypeScript run natively): registry parsing and merging, placeholder
  expansion, command lines per harness, run protocol, request parsing, agent loop with a fake
  backend, the `vscode.lm` backend against a fake `lm` object, the HTTP backend against a local
  test server, skills and brain helpers, templates, result parsing, model readiness, status
  rules, overview and result HTML (escaping, nonce-only script), archiving.
- Extension host test: VS Code is started with the extension in development mode, a temporary
  user-data and extensions directory, and a test workspace (`@vscode/test-electron`; on macOS
  the same entry is launched with `open -g` so the test window never takes focus). It checks
  activation, commands and LM tools, registry and discovery, an API worker against a fake
  OpenAI-compatible server on an ephemeral 127.0.0.1 port, a `vscode.lm` worker against a
  test-only chat model provider (`test/host/fake-lm`, loaded as a second development extension),
  a terminal worker, a `kit-wb spawn` request, an orchestrator turn that delegates, stop,
  model readiness, the status view, a template spawn, the overview and result views, run again
  with another model, the default-model command, send selection, and archiving. On macOS the
  runner hands focus back to the previously active app if the test window takes it.
- A path test checks that every kit path, skill and resource the extension references exists
  (including the skills the templates name and the data classes path of 40-data-guard), that
  every command a menu or view calls is contributed, and that the module contains no
  private-setup references.

## kit-wb from the terminal

```sh
kit-wb spawn --name w1 --paths src,tests --done DONE - < task.md   # prints the run id
printf 'Fix the failing login test\n' | kit-wb spawn --name w2 --done DONE -
kit-wb list                                   # runs, newest first
kit-wb result RUNID                           # status and result
kit-wb wait RUNID --timeout 3600              # wait until the run ends
```

`--model ID` selects a registered model, `--cwd DIR` the workspace, `--no-brain` skips the
knowledge-search step for this run. Runs: `~/.local/share/work-kit/workbench/runs/`
(archived: `.../archive/`). Task templates:
`~/.config/work-kit/workbench/templates/*.md` (`Kit Workbench: Open Task Templates Folder`).

More commands (Command Palette): `Start Orchestrator in Terminal`, `Spawn Worker`,
`Spawn Worker from Template`, `Open Worker Overview`, `View Result`, `Run Again with Model…`,
`Set Default Worker Model`, `Archive Finished Runs`, `List Models`, `Discover Local Models`,
`Set Provider API Key`, `Open Model Registry`, `Open Task Templates Folder`; side bar views
`Workers` and `Status`; status bar with running/failed workers; editor/Explorer context menu
`Send Selection/File to Orchestrator`. Settings `kitWorkbench.*`: `brainSearch`, `workerAutonomy`,
`confirmCloudModels`, `defaultWorkerModel`, `templatesDir`, `quietMinutes`.

## Development

```sh
cd extension && npm ci && npm run check && npm run test:host
```

`install.sh` needs `kit-workbench.vsix` in the module folder (build machine: `./build.sh`);
it falls back to `kit/offline/vscode/kit-workbench.vsix`.
