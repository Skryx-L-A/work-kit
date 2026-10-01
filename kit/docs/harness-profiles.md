# Harness profiles: support matrix and mechanisms

Module `kit/modules/32-harness-profiles` gives every AI harness what a well-set-up Claude Code
has beyond `AGENTS.md`: a role prompt (lead or worker), guards before shell commands, session
context from the kit brain, the caveman chat style and a status line. A `.wb-ohne-brain` marker
in the effective project directory or a parent disables both KERN injection and automatic brain
recall. This page records which
mechanism each harness offers, what the module writes, and where the mechanism is documented.
Doc pages were read on 2026-09-25 unless a cell says otherwise.

Levels: **full** = the harness enforces or injects it by itself; **partial** = works with a
limitation named in the cell; **none** = no mechanism, the rule in `AGENTS.md` is all there is.

## Matrix

| Harness | Role prompt | Session context | Pre-tool guard | Post-tool | Caveman | Status line | Skills |
|---|---|---|---|---|---|---|---|
| Claude Code | full: output style `kit-lead`/`kit-worker` (`keep-coding-instructions: true`), `outputStyle` in `settings.json` | full: `SessionStart` (KERN) + `UserPromptSubmit` (brain recall), `additionalContext` | full: `PreToolUse` `Bash` and `Write|Edit|MultiEdit`, deny / ask | full: `PostToolUse` `Bash` warns on secrets in output | full (31-caveman hooks) | full: `statusLine` command `kit-statusline` | full (30-agent-setup) |
| pi | full: extension appends `roles/<role>.md` to the system prompt (`before_agent_start`) | full: extension adds KERN + recall as a hidden message per prompt | full: extension `tool_call` blocks `bash`; ask via `ctx.ui.confirm` | full: `tool_result` redacts provider tokens before the model sees them | full: extension appends the 31-caveman rule | partial: footer status (`ctx.ui.setStatus`), not a full line | full (`~/.agents/skills`) |
| Codex CLI | full: `developer_instructions` in `config.toml` (adds to Codex's own prompt); profiles `kit-lead`/`kit-worker` | full: hooks `SessionStart` + `UserPromptSubmit` in `~/.codex/hooks.json` | partial: `PreToolUse` `Bash` denies; no ask, so "ask" becomes deny with instructions | full: `PostToolUse` | full (31-caveman rule block) | none: `[tui] status_line` takes built-in items only | full |
| Gemini CLI | partial: role injected by the `SessionStart` hook; `GEMINI_SYSTEM_MD` would replace the whole prompt, so it is not used | full: `SessionStart` + `BeforeAgent` `additionalContext` | partial: `BeforeTool` `run_shell_command` denies; no ask | full: `AfterTool` | full (31-caveman rule block) | none: footer items are built-in | full |
| Copilot CLI | partial: role injected by `sessionStart`; custom agents `kit-lead`/`kit-worker` for `--agent` | partial: `sessionStart` only (output of `userPromptSubmitted` command hooks is dropped) | full: `preToolUse` allow / deny / ask | full: `postToolUse` | full (31-caveman) | not wired: `statusLine` command exists, left to the user | full |
| Copilot in VS Code | partial: same `~/.copilot` hooks + custom agents | partial: `SessionStart` via `~/.copilot/hooks` (hooks are a preview feature) | full: `PreToolUse` `hookSpecificOutput`, allow / deny / ask | full: `PostToolUse` | full (31-caveman) | none | full |
| Cursor | partial: role injected by `sessionStart`; User Rules have no file, paste file generated | partial: `sessionStart` `additional_context`; no per-prompt recall | full: `beforeShellExecution`, allow / deny / ask (docs do not say whether the CLI runs hooks) | not wired | partial (31-caveman paste file) | none | full |
| opencode | partial: role file in `instructions` of `opencode.json` (fixed per install, no env switch) | none: plugins can only observe `session.created` | partial: plugin `tool.execute.before` throws; no ask | not wired | full (31-caveman) | none | full |
| Aider | partial: role file in `read:` of `~/.aider.conf.yml` | none | none: no hook interface | none | full (31-caveman) | none | none |
| Continue | partial: rule `~/.continue/rules/kit-role.md` (`alwaysApply`) | partial: the `cn` CLI runs Claude-format hooks from `~/.claude/settings.json` (source only, undocumented) | partial: same, through the Claude hooks | partial: same | full (31-caveman) | none | partial (`cn` only) |

Co-author trailers: the guard refuses commits whose message names an agent co-author, and
`30-agent-setup` switches attribution off where a setting exists and installs the git hook that
strips `Co-authored-by:` lines.

## What the guard checks

`kit-guard` (one Python program, `guard/lib/checks.py`) decides for every shell command, the
first refusal wins:

| Check | Refuses | Ported from |
|---|---|---|
| `kill` | `pkill`/`killall`/`kill $(pgrep …)`/`tmux kill-server` without an own test socket or a concrete PID; pipes into a bare interpreter; unparseable forms with a kill | 70-workbench `kill_pattern_classify.py` (logic unchanged) |
| `secrets` | a provider token or high-entropy credential in the command line; `git add`/`commit -a` that would stage `.env`, key files or a file whose content holds a secret | 70-workbench `bash-guard-secrets.sh` |
| `trailer` | a commit message with an agent `Co-authored-by:` or "generated with" line | 70-workbench `bash-guard-commit-trailer.sh`, extended to all agents |
| `noverify` | `git commit --no-verify` / `-n` (skips data guard and trailer hook) | new |
| `dataguard` | outbound commands (`curl -d/-F/-T`, `scp`, `rsync host:`, `gh gist`, …) whose text or payload file fails `data-guard check` | new, calls 40-data-guard |
| `commit` | asks before `git commit` in the lead role (policy `commit=ask`); workers may commit | new (the rule "commit only when asked") |
| `publish` | asks before something is published or cannot be taken back: `gh release create/upload/edit`, `gh repo create` (any visibility when typed; `--public` inside a script), `gh pr merge`, `git push --force`/`-f`/`--force-with-lease`/`--delete`/`-d`, a `:ref` or `+ref` refspec, `npm`/`pnpm`/`yarn`/`cargo`/`uv publish`, `twine upload` (also `python -m twine`), `docker push`, `hf`/`huggingface-cli upload`; a normal `git push` is not asked. Always "ask" (both roles, never deny); after the human agreed, `KIT_PUBLISH_OK=1` in front of that command (in front of the command that starts the script, for a script). Found inside started scripts too | new (the workbench's question stage covers a shorter list) |
| `script` | kill patterns, commit trailers, publishing questions and guard-policy writes also run over a local script the command starts: `bash x.sh`, `sh x.sh`, `zsh x.sh`, `./x.sh`, `source x.sh`, `. x.sh`, `bash < x.sh`, also behind `sudo`/`env`/`time` and inside `bash -c '…'` (SPEC known defect 9); the answer names script and line | new |

Settings: `~/.config/work-kit/guard.conf` (`commit=`, `commit.lead=`, `commit.worker=`,
`disable=`), exceptions for the content scan in `guard-exceptions.conf`. The human alone edits
these files and `profiles.conf`: kit-guard denies shell writes, redirects, moves and removals,
including those inside started scripts, and Claude Code Write/Edit/MultiEdit calls. Reading is allowed.
This protection is independent of `disable=` and script exemptions. After the human agreed
to a commit in a harness without a native "ask", the agent runs `KIT_COMMIT_OK=1 git commit …`;
the prefix stays visible in the transcript. This is a soft gate by design: the guard must never
hold a pane waiting for an approval (known live defect 4).

Scripts (`script`): the file is resolved against the hook's cwd (literal paths, `~` and `$HOME` only;
a `$VAR` or glob path is not followed), must be a regular text file up to 256 KiB, and is read one
level deep. A file started directly (`./x.sh`) counts only with a shell shebang or none. The
script pass checks publication, commit trailers, kill patterns and guard-policy writes; with
70-workbench it also checks the worker push gate. Other guards, including secrets, staging,
commit policy, data guard, snapshots, role and local question patterns such as `chmod -R`,
apply to typed Bash commands only. A refusal names the script and line. `KIT_PUBLISH_OK=1`
can approve a script's publication after the human agreed. `disable=script` and
`guard-exceptions.conf` affect the optional script scan, while guard-policy writes stay protected.

A combined-hook selfprobe on 257 kit shell test suites in an isolated HOME found 4 remaining
refusals. One writes an isolated policy fixture, and three contain actual kill patterns. They are listed in the task result; no test-path bypass
was added because it would also exempt an agent-run script placed under `tests/`.

Publishing and the workbench: with 70-workbench installed, its `bash-guard.py` runs kit-guard in its own process,
after its own guards but before its question stage. Where the workbench's question stage (its `askPatterns`,
approval queue `wb-freigabe`) already holds a command, kit-guard leaves it to that stage, so the human is asked
once and through the queue that does not lock the pane; what that stage does not cover (`docker push`, `gh pr merge`,
`uv publish`, `hf upload`, `gh repo create`, `gh release upload/edit`, a tag deletion) is asked by kit-guard as a native
Claude Code "ask". In the queue path `KIT_PUBLISH_OK=1` has no effect (the approval is the human's `wb-freigabe`).
If the workbench question stage is switched off in its settings, kit-guard still defers while its pattern list is
non-empty; switch it off there and here (`disable=publish`) together. Without 70 (71/72 only, or another harness) kit-guard asks
itself; harnesses without a native ask (codex, gemini, copilot) get a deny that tells the agent to ask the human in chat.
Cost: 26.3 -> 26.7 ms per call (macOS, temp HOME, median of 25).

Not ported from the workbench: the approval queue, pane/worker locks, snapshot enforcement,
test-protection and push gate. They depend on the workbench's task and pane model.

One Bash guard for Claude Code (2026-09-25): with 70-workbench installed, its `bash-guard.py` runs
the checks above in its own process, after the workbench guards and with the same `guard.conf`,
`guard-exceptions.conf` and role. The 70 installer takes kit-guard's Claude `PreToolUse` entry out
(its uninstall puts it back); 32 does not add it while a workbench guard is registered. The
`PostToolUse` output scan stays registered either way. Claude hook and status-line commands start
the script with the interpreter found at install time (`[ -x PY ] && exec PY SCRIPT ...; exec
LAUNCHER ...`), with the `~/.local/bin` launcher as fallback. The launchers themselves
(`kit/lib/kit-python`, `kit_write_py_launcher`) record the interpreter found at install and run
the lookup (one more Python start for the version check) only when that interpreter is gone:
a launcher call took 32-42 ms, now 21 ms (direct Python 16-18 ms). Measured natively on macOS (temp HOME, 32 and 70, median of 9, per Bash call): the
four PreToolUse hooks took 206-235 ms, now three hooks take 59-66 ms; kit-guard post 54 -> 32 ms,
kit-context 54-63 -> 33-40 ms, status line 63 -> 39 ms.

Worker panes of 70-workbench start with `KIT_AGENT_ROLE=worker` (role prompt, commit policy
`allow`); the `wb-code` orchestrator keeps the configured role (`lead`).

Backups of changed files go to `~/.local/share/work-kit/backups/32-harness-profiles/` (same
path as below `$HOME`), never next to the file.

## Role prompts

`roles/lead.md` and `roles/worker.md` carry variant blocks for the installed orchestration
module: `workbench` (70: `claude-worker`, `pi-worker`, `wb-result`), `delegate` (71:
`agent-spawn`) or `none` (harness subagents). The installer detects the module
(`--orchestration auto`) and renders the matching text. `KIT_AGENT_ROLE=worker` switches a
session to the worker role where the harness allows it at run time (pi, Claude Code through the
session hook, Gemini, Copilot, Cursor); Codex uses `codex --profile kit-worker`, opencode and
Aider keep the installed role.

## Sources

| Harness | Pages (read 2026-09-25) |
|---|---|
| Claude Code | https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/output-styles, https://code.claude.com/docs/en/settings-reference, https://code.claude.com/docs/en/statusline, https://code.claude.com/docs/en/skills |
| pi 0.84.2 | package docs `docs/extensions.md`, `docs/usage.md`, `docs/skills.md`, `docs/sdk.md`; online https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent/docs |
| Codex CLI | https://learn.chatgpt.com/docs/hooks, https://learn.chatgpt.com/docs/config-file/config-reference, https://learn.chatgpt.com/docs/build-skills (developers.openai.com/codex redirects there) |
| Gemini CLI | https://geminicli.com/docs/hooks/reference/, https://geminicli.com/docs/cli/system-prompt/, https://geminicli.com/docs/reference/configuration/, https://geminicli.com/docs/cli/skills/ |
| Copilot CLI | https://docs.github.com/en/copilot/reference/hooks-configuration, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference |
| Copilot in VS Code | https://code.visualstudio.com/docs/agents/reference/hooks-reference, https://code.visualstudio.com/docs/copilot/customization/custom-agents, https://code.visualstudio.com/docs/copilot/customization/agent-skills |
| Cursor | https://cursor.com/docs/hooks, https://cursor.com/docs/rules, https://cursor.com/docs/skills, https://cursor.com/docs/cli/reference/configuration |
| opencode | https://opencode.ai/docs/agents, https://opencode.ai/docs/config, https://opencode.ai/docs/plugins/, https://opencode.ai/docs/skills |
| Aider | https://aider.chat/docs/config/options.html, https://aider.chat/docs/usage/conventions.html |
| Continue | https://docs.continue.dev/customize/deep-dives/rules; hooks only in source: https://github.com/continuedev/continue (`extensions/cli/src/hooks/`), docs issue https://github.com/continuedev/continue/issues/11678 |

## Verification

`bash kit/modules/32-harness-profiles/tests/run-tests.sh` (temp HOMEs only): unit tests of every
check and of each harness's hook input and output shape, installer round trip with existing user
settings (kept, idempotent, removed cleanly), the opencode plugin loaded by node, and pi end to
end: the real `pi` CLI with a scripted faux model (pi-ai's test provider) and the kit extension,
so no network or account is needed. Codex 0.156.1 and opencode loaded the generated
`config.toml`, `hooks.json` and `opencode.json` without error. The hooks of Claude Code, Codex,
Gemini, Copilot and Cursor were checked against the documented JSON shapes, not in a running
session of those harnesses.

## Command-line and exit codes

`kit-guard check [--cwd DIR] [--harness H] [--json] -- COMMAND` exits 0 allow, 2 deny (reason
on stderr), 3 ask; `--json` prints the decision on stdout and exits 0. `kit-guard hook`,
`kit-guard post`, `kit-guard redact` and `kit-guard policy` serve the harness hooks and the
status line. `kit-profiles role [lead|worker]` prints the rendered role prompt.

`install.sh` options: `--all | --harness LIST`, `--role lead|worker|none`,
`--orchestration auto|workbench|delegate|none`, and for troubleshooting
`--no-guard --no-context --no-statusline --dry-run` (they leave the protective hooks out; not
for daily use). `KIT_COMMIT_OK=1 git commit ...` commits after the human agreed, in a harness
without an ask dialog; the prefix stays visible in the transcript (see "What the guard checks").

`kit-statusline` shows the role, model and effort, project path and branch, plus absolute context
use and percentage (for example `ctx 85k/1.0M (8%)`). It does not calculate or expose quotas.

Prompt recall has a three-second internal budget. It uses the brain's BM25/FTS mode, caches a
successful result for one minute and returns no context on timeout. Claude and Codex allow 60
seconds for every registered kit hook, Gemini 60,000 ms and Copilot 60 seconds; Copilot registers
session context only, not a prompt recall hook. Guard-internal Git checks stop after two seconds
and deny on timeout, so a slow helper does not turn into an unguarded command.
