# Harness adapters (kit-sync)

File locations were read from the official documentation on **2026-09-24**, settings keys
on **2026-09-25** (pin, telemetry and pi: see the sections below). Harnesses change their layout often: before relying on a row, re-check
the source URL. If something moves, change the matching class in
`kit/modules/30-agent-setup/kit-sync` and this page.

Skill format for all of them: [agentskills.io](https://agentskills.io) (`<name>/SKILL.md`).
Canonical skill directory of the kit: `~/.agents/skills/<name>` (one link per skill,
pointing into `~/.local/share/work-kit/agent-setup/source/skills`).

## Instructions: AGENTS.md is the one source

`source/AGENTS.md` (installed to `~/.local/share/work-kit/agent-setup/source/AGENTS.md`)
is the universal instruction file. A harness that reads a file called `AGENTS.md` gets the
rules in its own `AGENTS.md`; a harness that can import or list files points at the kit
file; only harnesses that can do neither get a generated copy.

| Harness (`--harness`) | Instructions | Skills | Source (checked 2026-09-24/25) |
|---|---|---|---|
| Claude Code (`claude`) | `~/.claude/CLAUDE.md`: managed block with one import line `@~/.local/share/work-kit/agent-setup/source/AGENTS.md` (user-level imports load without an approval dialog). Also links `~/.claude/AGENTS.md` to the kit file for kit tools; Claude Code itself does not read it | reads only `~/.claude/skills/`: kit-sync links each skill there | https://code.claude.com/docs/en/memory, https://code.claude.com/docs/en/skills |
| Codex CLI (`codex`) | `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`), managed block. `AGENTS.override.md` wins if present; kit-sync warns | reads `$HOME/.agents/skills` natively | https://developers.openai.com/codex/guides/agents-md, https://developers.openai.com/codex/skills |
| Gemini CLI (`gemini`) | `~/.gemini/AGENTS.md`, managed block, plus `context.fileName = ["AGENTS.md", "GEMINI.md"]` in `~/.gemini/settings.json` (Gemini then also reads each project's `AGENTS.md`). If you set `context.fileName` yourself, the block goes to `~/.gemini/GEMINI.md`. An `@/abs/path` import is not possible: imports must stay under `~/.gemini` or the project root | reads `~/.agents/skills/` natively | https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/core/src/utils/memoryDiscovery.ts, https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/core/src/utils/memoryImportProcessor.ts, https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md |
| opencode (`opencode`) | `$XDG_CONFIG_HOME/opencode/AGENTS.md` (default `~/.config/opencode/AGENTS.md`), managed block | reads `~/.agents/skills/` natively | https://opencode.ai/docs/rules/, https://opencode.ai/docs/skills/ |
| pi (`pi`) | `$PI_CODING_AGENT_DIR/AGENTS.md` (default `~/.pi/agent/AGENTS.md`), managed block. `AGENTS.override.md` wins if present; kit-sync warns | reads `~/.agents/skills/` natively | `docs/usage.md`, `docs/skills.md`, `docs/environment-variables.md` in the installed package `@earendil-works/pi-coding-agent` 0.84.2 (read 2026-09-25) |
| GitHub Copilot (`copilot`) | `$COPILOT_HOME/copilot-instructions.md` (default `~/.copilot/`), managed block (no import mechanism) | reads `~/.agents/skills/` and `~/.copilot/skills/` natively | https://code.visualstudio.com/docs/copilot/customization/custom-instructions, https://code.visualstudio.com/docs/copilot/customization/agent-skills |
| Cursor (`cursor`) | none: User Rules live in Cursor Settings, not in a file. kit-sync writes `~/.local/share/work-kit/generated/cursor-user-rules.md` to paste there | reads `~/.agents/skills/` natively | https://cursor.com/docs/context/rules, https://cursor.com/docs/context/skills |
| Aider (`aider`) | `~/.aider.conf.yml` lists the kit `AGENTS.md` under `read:` (no copy). If the file has its own `read:` key, kit-sync tells you to add the path. Other kit modules add their file to the same `read:` list (32-harness-profiles the role file, 31-caveman the chat style rule) and tag the line `# work-kit-<module> ...`; kit-sync carries such lines when it rewrites its region and takes them over from a `read:` list they created earlier, so every install order gives one `read:` key with each line once | none (Aider has no skills) | https://aider.chat/docs/usage/conventions.html, https://aider.chat/docs/config/aider_conf.html |
| Continue (`continue`) | `~/.continue/rules/work-kit.md`, whole file, `alwaysApply: true` (copy; rules cannot import) | none (rules only) | https://docs.continue.dev/customize/deep-dives/rules ; global folder read in https://github.com/continuedev/continue/blob/main/core/promptFiles/getPromptFiles.ts |

Detection: a harness is handled when its binary is on `PATH` (or in `~/.local/bin`) or its
config directory exists. `--harness a,b` and `--all` override detection.

Copilot note: VS Code's Local agent keeps user instructions in the VS Code profile (not a
documented file path) and reads `~/.claude/CLAUDE.md` when `chat.useClaudeMdFile` is on.

## Settings: approval mode, attribution, MCP

`kit-sync --permissions bypass|ask` (or `install.sh --permissions …`, or `KIT_PERMISSIONS`)
writes the mode to `~/.config/work-kit/kit.conf` (`permissions=…`); later runs read it.
Default: `bypass` (owner decision 2026-09-25; the kit hooks and the data guard are the
protection). JSON files are merged key by key, never replaced. kit-sync records every key
it writes in `~/.local/share/work-kit/state/kit-sync.json`; a key you changed yourself
is kept (message `keep`) unless you pass `--permissions` explicitly. `--uninstall` removes
only keys that still hold the kit value.

| Harness | bypass | ask | No co-author | MCP servers (`brain`, `doc-qa`) | Source (checked 2026-09-25) |
|---|---|---|---|---|---|
| Claude Code | `~/.claude/settings.json`: `permissions.defaultMode = "bypassPermissions"`, `skipDangerousModePermissionPrompt = true` | `permissions.defaultMode = "default"` | `attribution = {"commit": "", "pr": ""}`; `includeCoAuthoredBy = false` for older versions (deprecated) | `~/.claude.json` `mcpServers.<name> = {type: "stdio", command, args, env}` | https://code.claude.com/docs/en/settings, https://code.claude.com/docs/en/permission-modes, https://code.claude.com/docs/en/mcp |
| Codex CLI | `config.toml`: `approval_policy = "never"`, `sandbox_mode = "danger-full-access"` | `"on-request"`, `"workspace-write"` | no setting exists; git hook | `[mcp_servers.<name>]` `command`, `args` | https://developers.openai.com/codex/config-reference (redirects to learn.chatgpt.com/docs/config-file/config-reference) |
| Gemini CLI | `~/.gemini/settings.json`: `general.defaultApprovalMode = "auto_edit"` (`yolo` is flag-only: `gemini --yolo`) | key removed (`default`) | no setting; git hook | `mcpServers.<name> = {command, args}` (no `trust`) | https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/cli/src/config/settingsSchema.ts, https://geminicli.com/docs/tools/mcp-server/ |
| opencode | `opencode.json`: `permission = "allow"` | `permission = "ask"` | no setting; git hook | `mcp.<name> = {type: "local", command: [cmd, …args], enabled: true}` | https://opencode.ai/docs/permissions/, https://opencode.ai/docs/mcp-servers/ |
| Aider | `yes-always: true` | key not written | `attribute-co-authored-by`, `attribute-author`, `attribute-committer: false` | none | https://aider.chat/docs/config/options.html |
| Copilot CLI | flag only (`--allow-all-tools`, `--yolo`); nothing written | nothing written | `~/.copilot/settings.json`: `includeCoAuthoredBy = false` (kit < 2026-09-25 wrote `include_coauthor`, the pre-1.0.15 name; the old key is removed when kit-sync had written it) | `~/.copilot/mcp-config.json` `mcpServers.<name> = {type: "local", command, args, tools: ["*"]}` | https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/change-settings, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference, https://raw.githubusercontent.com/github/copilot-cli/main/changelog.md (1.0.15 renamed the keys to camelCase) |
| Copilot in VS Code | not written: `chat.tools.global.autoApprove` is flagged by `ai-gov mcp-check` | – | user `settings.json`: `git.addAICoAuthor = "off"` (only if the VS Code config dir exists) | user `mcp.json` `servers.<name> = {type: "stdio", command, args}` | https://raw.githubusercontent.com/microsoft/vscode/main/extensions/git/package.json, https://code.visualstudio.com/docs/copilot/customization/mcp-servers |
| pi | none: pi has no approval prompts and no sandbox (`docs/security.md`); nothing written | – | no attribution feature | none: no built-in MCP (`docs/usage.md`) | `docs/settings.md`, `docs/usage.md`, `docs/security.md` of the installed package 0.84.2 (2026-09-25) |
| Cursor | not written | – | no setting found; git hook | `~/.cursor/mcp.json` `mcpServers.<name> = {command, args}` | https://cursor.com/docs/context/mcp (shape not re-fetched on 2026-09-25) |
| Continue | not written (`permissions.yaml` format undocumented) | – | no setting; git hook | block file `~/.continue/mcpServers/work-kit-<name>.yaml` | https://docs.continue.dev/reference |

## Settings: no self-update, no telemetry, no auto-commits (pin protection)

The stick is offline and `16-harness-clis` installs pinned versions, so a background
self-update is noise offline and an unapproved change online; telemetry goes to the vendor
without anyone deciding it (data protection is an open concern at the company). Aider's
auto-commits are off because commits happen only when asked. `kit-sync` writes these keys with
the same rules as the settings above (key by key, ownership recorded, a value you set is kept,
`--uninstall` removes only keys that still hold the kit value). They do not depend on
`--permissions`.

| Harness | File and key | Effect | Source (read 2026-09-25) |
|---|---|---|---|
| Claude Code | `~/.claude/settings.json`: `env.DISABLE_AUTOUPDATER = "1"` | stops the background update check; `claude update` still works. `DISABLE_UPDATES` would block that too (not set: it would also block the manual update) | https://code.claude.com/docs/en/setup ("Disable auto-updates"), https://code.claude.com/docs/en/env-vars |
| Claude Code | `~/.claude/settings.json`: `env.DISABLE_TELEMETRY = "1"` | no usage metrics to Anthropic. `claude update` is not affected (only `DISABLE_UPDATES` blocks it). Side effect, stated in the docs: feature-flag fetching stops, so Remote Control, `claude import`, `/skill-doctor`, syncing claude.ai skills and plugins, the advisor tool, and starting in auto mode by default are unavailable. Delete the key in `settings.json` to get them back (kit-sync keeps your change) | https://code.claude.com/docs/en/env-vars (`DISABLE_TELEMETRY`, section "Features that need feature-flag fetching"), https://code.claude.com/docs/en/data-usage (read 2026-09-25) |
| Claude Code | `~/.claude/settings.json`: `env.DISABLE_ERROR_REPORTING = "1"` | no error reports (stack traces of Claude Code itself) to a third-party service; does not touch feature flags | https://code.claude.com/docs/en/env-vars, https://code.claude.com/docs/en/data-usage (read 2026-09-25) |
| Codex CLI | `config.toml`: `check_for_update_on_startup = false` (top level) | no update check on startup | https://developers.openai.com/codex/config-reference (redirects to learn.chatgpt.com/docs/config-file/config-reference) |
| Codex CLI | `config.toml`: `analytics = { enabled = false }` (top level, inline table) | no metrics collection on this machine for the CLI, IDE extension and desktop app; the default metrics exporter is `statsig`, and this switch is the documented way to turn it off. Not written when the file already has an `[analytics]` table, an `analytics.…` key or `analytics = …` (kit-sync says so) | https://developers.openai.com/codex/config-reference (`analytics.enabled`), https://developers.openai.com/codex/config-advanced ("set the analytics flag"), https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/config.schema.json (read 2026-09-25) |
| opencode | `opencode.json`: `autoupdate = false` | no automatic download (`"notify"` would only announce) | https://opencode.ai/docs/config/ (section Autoupdate) |
| Gemini CLI | `~/.gemini/settings.json`: `general.enableAutoUpdate = false` | no automatic update; default is `true` | https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/cli/src/config/settingsSchema.ts |
| Gemini CLI | `~/.gemini/settings.json`: `privacy.usageStatisticsEnabled = false` | no anonymized usage statistics (tool names, model, durations); default is `true` | https://raw.githubusercontent.com/google-gemini/gemini-cli/main/docs/reference/configuration.md ("Usage statistics", how to opt out), `settingsSchema.ts` as above (read 2026-09-25) |
| Aider | `~/.aider.conf.yml`: `check-update: false`, `analytics-disable: true` | no version check on launch; analytics permanently off | https://aider.chat/docs/config/options.html, https://aider.chat/docs/config/aider_conf.html |
| Aider | `~/.aider.conf.yml`: `auto-commits: false`, `dirty-commits: false` | Aider does not commit its own edits (default `true`) and does not commit your uncommitted files before an edit (default `true`, independent of `auto-commits`); you commit or use `/commit`. Written in both approval modes | https://aider.chat/docs/config/options.html (`--auto-commits`, `--dirty-commits`), https://aider.chat/docs/git.html ("Disabling git integration") (read 2026-09-25) |
| Copilot CLI | `~/.copilot/settings.json`: `autoUpdate = false` | no automatic download of CLI updates or first-party plugin updates | https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference, https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/change-settings |
| pi | `~/.pi/agent/settings.json`: `enableInstallTelemetry = false` | no anonymous install/update ping to pi.dev. The update check has no setting: `PI_SKIP_VERSION_CHECK=1` (or `PI_OFFLINE=1` for every startup network operation) must be set in the environment | `docs/settings.md` ("Telemetry and update checks"), `docs/environment-variables.md` of the installed package 0.84.2 (read 2026-09-25) |

Not set on purpose (listed so nobody searches again; all checked 2026-09-25):

- Claude Code `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (also switches off release notes, `/feedback`,
  PR status checks and feature flags; the docs list "auto-updates" among what it stops and do not say
  whether that includes `claude update`) and `DO_NOT_TRACK` (same effect as `DISABLE_TELEMETRY`).
  `DISABLE_UPDATES` blocks `claude update`. `DISABLE_TELEMETRY` and `DISABLE_ERROR_REPORTING` above
  cover what the docs call telemetry.
- Codex `feedback.enabled` (`/feedback` is user-initiated) and the `otel` exporters (`exporter` and
  `trace_exporter` default to `none`; `metrics_exporter` defaults to `statsig` and is covered by
  `analytics.enabled`).
- Gemini `telemetry.enabled` (default `false`, an OpenTelemetry export the user configures).
- opencode: no telemetry or analytics key in the config docs or in https://opencode.ai/config.json.
  The only related key, `experimental.openTelemetry`, is off by default. Nothing is written.
- Copilot CLI: no telemetry or analytics off switch is documented in the pages above (only OpenTelemetry
  export, off by default: `COPILOT_OTEL_ENABLED`, `OTEL_EXPORTER_OTLP_ENDPOINT`). `remoteExport`
  (session export, default `true`) is not written: it is not telemetry. Nothing is written for Copilot.
- Copilot in VS Code and Cursor update with the editor and follow the editor's telemetry setting;
  Continue has no CLI pin.

Docs pages were fetched on 2026-09-25 (Claude Code, Codex, Gemini CLI, opencode, Aider and Copilot CLI
pages as raw text; the Claude Code lines are verbatim from `env-vars` and `data-usage`, the Codex keys from
the config reference table and the published JSON schema). Re-check before a new pin.

MCP: a server is registered only when its binary exists (`~/.local/bin` first, then `PATH`),
with the absolute path as command and `args: [mcp]`, matching the `13-ai-governance`
allowlist entry format. When `~/.config/work-kit/mcp-allowlist.yaml` exists, a server
missing from it is not registered (default deny). A server that is no longer installed is
removed from every harness config again.

Files that are not plain JSON (comments, JSONC) are left untouched with a message; set the
values by hand. opencode's `opencode.jsonc` is not edited either.

## Global git hooks (no agent co-authors)

kit-sync copies `git-hooks/dispatch` under every client hook name into
`~/.config/work-kit/git-hooks/` and sets `git config --global core.hooksPath` there,
unless it already points somewhere else (then nothing changes and kit-sync says so).
With `core.hooksPath` set, git ignores `.git/hooks`, so the dispatcher:

1. `commit-msg`: removes every `Co-authored-by:` line (case-insensitive). A repository that
   wants human co-authors: `git config work-kit.keepCoAuthors true`.
2. `pre-commit`: runs `data-guard staged` when data-guard's global opt-in was on (kit-sync
   found its stubs in the directory and left the flag `.data-guard-global`) or the repository
   is listed in `~/.config/work-kit/hooked-repos.list`, unless the repository's own
   pre-commit is the data-guard stub.
3. Every hook: runs the repository's own hook (`$(git rev-parse --git-common-dir)/hooks/<name>`),
   e.g. the reindex hooks `post-commit`, `post-merge`, `post-checkout` of 20-brain, with the
   same arguments and stdin, and returns its exit code.

The dispatcher is pure bash (no grep/sed/awk). `--uninstall` removes the dispatchers, puts
data-guard's stubs back if it had taken them over, and unsets `core.hooksPath` otherwise.
`git commit --no-verify` skips the hooks; the harness settings above are the first line.

## Python

`kit-sync` is a shell/Python polyglot. The shell part picks `$KIT_PYTHON`, `python3` on
`PATH`, `~/.local/bin/python3.12`, `uv python find 3.12`, or
`~/.local/share/uv/python/cpython-3.12*/bin/python3` (module 00-python), in that order.

## Project level (`kit-sync --project DIR`)

Existing files are never overwritten. Files carrying the kit marker are refreshed.

| File | Content | Default | Why |
|---|---|---|---|
| `AGENTS.md` | project template (created only if missing); the human-edited source for the rest | yes | read natively by Codex, opencode, Cursor, Copilot, Gemini (via setting), Claude Code >= 2.1.277 when no `CLAUDE.md` exists |
| `CLAUDE.md` | `@AGENTS.md` import line | yes (`claude`) | Claude Code prefers `CLAUDE.md`; the import keeps one source. https://code.claude.com/docs/en/memory#agents-md |
| `.github/copilot-instructions.md` | copy of `AGENTS.md` (kit marker) | yes (`copilot`) | Copilot format; https://code.visualstudio.com/docs/copilot/customization/custom-instructions |
| `.cursor/rules/work-kit.mdc` | always-apply rule that references `@AGENTS.md` | yes (`cursor`) | https://cursor.com/docs/context/rules |
| `GEMINI.md` | `@AGENTS.md` import line | `--harness gemini` | Gemini CLI imports with `@file`; not needed when the user-level `context.fileName` is set |
| `.aider.conf.yml` | `read: [AGENTS.md]` | `--harness aider` | https://aider.chat/docs/config/aider_conf.html |
| `.continue/rules/work-kit.md` | copy of `AGENTS.md` (kit marker) | `--harness continue` | https://docs.continue.dev/customize/deep-dives/rules |

`--all` selects every project harness. After editing `AGENTS.md`, run `kit-sync --project DIR`
again to refresh the copies.

## Known gaps

- Cursor user rules cannot be written from outside the app (paste step). Cursor and Continue
  approval settings are not written.
- Gemini CLI and Copilot CLI allow a full bypass only with a command-line flag.
- Codex, Gemini CLI, opencode, Cursor and Continue have no co-author setting; the git hook is
  the only guard there.
- Copilot CLI settings live in `~/.copilot/settings.json` (JSONC allowed; kit-sync leaves a file
  with comments untouched and says so). The docs list `includeCoAuthoredBy` and `autoUpdate`.
- pi update checks cannot be switched off from a file; `60-terminal` or the user's shell profile
  has to export `PI_SKIP_VERSION_CHECK=1`.
- The pin and telemetry keys were checked against the docs, not against the pinned binaries: no Linux
  binary was started here (end-to-end test pending). That includes the claim that
  `DISABLE_TELEMETRY` leaves `claude update` working, which is the docs' statement, not an observation.
- Telemetry that has no file setting or off switch stays on: opencode and Copilot CLI (see above).
- Not verified on a real Linux desktop: detection of VS Code and Cursor uses `~/.config/Code`
  and `~/.config/Cursor` as config directories; the binary check (`code`, `cursor`) is the
  primary signal.
- Claude Code reads a project `AGENTS.md` itself from v2.1.277; older versions need the
  `CLAUDE.md` import.

## Tests

`python3 -m unittest discover -s tests` in the module folder. Edit rules in
`source/AGENTS.md`, skills in `source/skills/<name>/SKILL.md`, then run `bash install.sh`
again to re-sync; keep co-authors in one repo with `git config work-kit.keepCoAuthors true`.
