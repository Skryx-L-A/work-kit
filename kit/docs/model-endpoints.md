# Company model endpoints (33-model-endpoints, `kit-models`)

Work kit runs its own model servers. `kit-models add` registers one such endpoint for every
harness and kit tool that can use it. This page records which protocol each target speaks,
where kit-models writes, when the local translating proxy is used, and how it was verified.

Facts were read on **2026-09-27** from the official documentation of the versions pinned in
`kit/modules/16-harness-clis/pins.conf` and, where a harness was installed on the build Mac,
from its package or its `--help` output. Harnesses change quickly: re-check the source before
relying on a row, then change the matching class in `kit_models_targets.py` and this page.

## Endpoint kinds

| `--kind` | What the company runs | Requests kit-models sends |
|---|---|---|
| `openai` | vLLM, LiteLLM, TGI, llama.cpp `llama-server`, gateways | `POST <base>/chat/completions`, `Authorization: Bearer <key>` |
| `azure` | Azure OpenAI | `POST <base>/openai/deployments/<model>/chat/completions?api-version=<v>`, `api-key: <key>` (a base URL containing `/openai/v1` uses the v1 route with the model in the body) |
| `anthropic` | Anthropic-compatible gateways | `POST <base>/v1/messages`, `x-api-key: <key>`, `anthropic-version: 2023-06-01` |
| `ollama` | Ollama | its OpenAI-compatible `<base>/v1/chat/completions` |

`--header 'Name: value'` adds a header to every request; `${VAR}` in the value is read from the
environment at request time, so a gateway token never lands in a file. A literal value that
looks like a credential is refused. `--responses` says that an `openai` endpoint also serves the
OpenAI Responses API (Codex then talks to it directly instead of through the proxy).
`--context-window N` passes the model context size to the harnesses that take one.

## Support matrix

Route: **direct** = the harness talks to the endpoint and reads the key from the variable;
**proxy** = the harness talks to the local proxy (`http://127.0.0.1:4020/e/<name>`), which adds
the key and headers and translates the protocol.

| Target | Speaks natively | kit-models writes | Route | Source (read 2026-09-27) |
|---|---|---|---|---|
| Claude Code 2.1.283 | Anthropic Messages only (also Bedrock/Vertex/Foundry formats); not OpenAI | wrapper `claude-<name>`: `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`, `ANTHROPIC_CUSTOM_HEADERS`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, and `--settings '{"apiKeyHelper": ...}'`. `default <name> --also claude`: the same keys in `~/.claude/settings.json` (`env` block, `apiKeyHelper`) | direct for `anthropic`, else proxy | https://code.claude.com/docs/en/llm-gateway, https://code.claude.com/docs/en/llm-gateway-connect, https://code.claude.com/docs/en/llm-gateway-protocol, https://code.claude.com/docs/en/model-config |
| Codex CLI 0.156.1 | OpenAI Responses only. The binary says: "`wire_api = "chat"` is no longer supported" (`strings` of the installed 0.156.1 binary) | `~/.codex/config.toml` (`$CODEX_HOME`): region with `[model_providers.<name>]` `name`, `base_url`, `wire_api = "responses"`, `env_key`, `http_headers`, `env_http_headers`; on an explicit default a region at the top with `model_provider`, `model`; wrapper `codex-<name>` (`-c model_provider=… -c model=…`) | proxy (Responses → chat), direct only with `--responses` | https://learn.chatgpt.com/docs/config-file/config-advanced (redirect from developers.openai.com/codex/config-advanced), https://github.com/openai/codex/discussions/7782 |
| opencode 1.18.32 | OpenAI chat (`@ai-sdk/openai-compatible`), Responses, Anthropic (`@ai-sdk/anthropic`), Azure | `~/.config/opencode/opencode.json` `provider.<name>` = `{npm, name, options: {baseURL, apiKey: "{env:VAR}", headers}, models}`; explicit default: `model = "<name>/<model>"`. An `opencode.jsonc`-only setup is left alone (`kit-models show`) | direct; Azure via proxy (the Azure package options are untested) | https://opencode.ai/docs/providers/, https://opencode.ai/docs/config/ (`{env:VAR}`) |
| Gemini CLI 0.61.0 | Gemini API only (`GOOGLE_GEMINI_BASE_URL`) | wrapper `gemini-<name>` (`GOOGLE_GEMINI_BASE_URL`, `GEMINI_API_KEY` = the local proxy token, `GEMINI_MODEL`); `~/.gemini/settings.json` `security.auth.selectedType = "gemini-api-key"` when unset (0.61 treats the base URL alone as auth type `gateway` and refuses to start headless: read in the 0.61.0 bundle, `validateAuthMethod`); `default --also gemini`: `~/.gemini/.env` region | always proxy | npm 0.61.0 `bundle/docs/reference/configuration.md`; https://docs.litellm.ai/docs/tutorials/litellm_gemini_cli |
| GitHub Copilot CLI 1.0.88 | OpenAI chat or Responses, Azure, Anthropic (BYOK) | wrapper `copilot-<name>`: `COPILOT_PROVIDER_TYPE`, `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY_COMMAND` (the kit key helper, no key in the environment block), `COPILOT_PROVIDER_HEADERS`, `COPILOT_PROVIDER_AZURE_API_VERSION`, `COPILOT_PROVIDER_WIRE_MODEL`, `COPILOT_MODEL`. No config-file keys exist (`copilot help config`). `default --also copilot`: exported by the shell snippet | direct | `copilot help providers`, `copilot help environment` (1.0.88); https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models |
| VS Code Copilot Chat (BYOK) | OpenAI chat or Responses, Anthropic Messages, Azure | `<VS Code user dir>/chatLanguageModels.json`: provider `kit: <name>`, vendor `customendpoint`, models with `url`, `apiType`, `toolCalling`, token limits, `requestHeaders`; `apiKey: "${input:kit-<name>-key}"`: VS Code asks once and keeps the key in its secret storage (the file cannot reference an environment variable) | direct; proxy when a header needs a variable | https://code.visualstudio.com/docs/agent-customization/language-models ; Business/Enterprise policy "Bring Your Own Language Model Key in VS Code": https://github.blog/changelog/2026-04-22-bring-your-own-language-model-key-in-vs-code-now-available/ |
| Aider 0.86.2 | OpenAI chat, Azure, Anthropic (litellm) | wrapper `aider-<name>` (`AIDER_OPENAI_API_BASE`, `AIDER_OPENAI_API_KEY`, `AIDER_MODEL`; the `AIDER_*` variables win over `~/.aider.conf.yml`, plain `OPENAI_API_BASE` does not: observed); explicit default: `~/.aider.conf.yml` region `model`, `openai-api-base`, `openai-api-key:` the local proxy token | wrapper direct for OpenAI-compatible without headers, else proxy; the YAML default always via proxy (the file cannot reference a variable) | https://aider.chat/docs/llms/openai-compat.html, https://aider.chat/docs/config/aider_conf.html |
| pi 0.87.1 | OpenAI chat and Responses, Anthropic, Azure Responses, Gemini | `~/.pi/agent/models.json` `providers.<name>` = `{baseUrl, api, apiKey: "$VAR", headers: {"…": "${VAR}"}, models}`; explicit default: `settings.json` `defaultProvider`, `defaultModel`. With 70-workbench installed, `wb-state` writes the provider entry instead | direct; Azure via proxy (pi's Azure path is Responses-only) | `docs/models.md`, `docs/providers.md`, `docs/settings.md` in the 0.84.2 package and the 0.87.1 npm tarball |
| Continue | OpenAI, Azure, Anthropic, Ollama | `~/.continue/config.yaml`: region inside `models:` (`provider: openai`, `apiBase`, `apiKey:` the local proxy token) | proxy: the IDE extensions do not read shell variables, `${{ secrets.X }}` would need the key in `~/.continue/.env` | https://docs.continue.dev/reference, https://docs.continue.dev/faqs |
| Cursor | OpenAI key + "Override OpenAI Base URL", settings screen only | nothing: no documented file. `kit-models show <name> --target cursor` prints the values | manual; requests may come from Cursor's servers (unverified), so the endpoint would have to be reachable from the internet | https://cursor.com/docs/settings/api-keys |
| 70-workbench | pi workers | `wb-state models add-provider --id <name> --kind openai\|anthropic\|local --base-url … [--key-env VAR] --owner 33-model-endpoints --model …`; `remove-provider` on removal. Registry `~/.claude/workbench/models.json`, pi entry written by wb-state | direct; Azure and endpoints with headers via proxy (the registry has no header field) | interface from branch `wb/kit-wb-models` commit `0ffd7b3` (2026-09-25) |
| 72-vscode-workbench | OpenAI chat with Bearer key (harness `api`) | `~/.config/work-kit/workbench/models.json`: provider `{id, kind, baseUrl, api: openai, apiKeyEnv}`, one model per id (`harness: api`), marked `managedBy: kit-models` | direct for OpenAI-compatible without headers; else proxy with `apiKeyEnv: KIT_MODELS_PROXY_KEY` | `docs/vscode-workbench.md`, `extension/src/registry.ts` |
| evalkit (50-eval) | OpenAI chat (`type: openai`, `api_key_env`) | `~/.config/work-kit/evalkit/kit-models-providers.yaml`: provider entries to copy into a suite (suites have no include) | as 72 | `kit/modules/50-eval/SUITE-FORMAT.md` |
| llm-usage (14) | OpenAI pass-through proxy | the shell snippet exports `LLM_USAGE_UPSTREAM` = proxy URL of the default endpoint | proxy | `kit/modules/14-llm-usage/llm_usage.py` |
| meeting summaries (17) | OpenAI chat, Bearer key (token found by meeting), loopback only by policy | opt-in `default <name> --also meeting`: `meeting.conf` region `summary_url` (proxy), `summary_model`. Refused when the endpoint is allowed PUBLIC data only; meeting sends the local proxy token itself | proxy | `kit/modules/17-meeting-capture/meeting` |
| doc-qa prompts (18) | prints a prompt | nothing: `doc-qa ask "…" --prompt \| kit-models ask --name <name> -` | direct | `kit/modules/18-doc-qa/README.md` |

Detection: a target is handled when its binary is on `PATH` (or in `~/.local/bin`) or its
config directory exists; `--targets a,b` and `--all-targets` override this per endpoint.

## Model defaults

The kit does not pin a vendor version as a normal default. 70-workbench keeps family aliases
in its registry: Claude `opus`, `sonnet`, `fable`; Codex `sol`, `terra`, `luna`, `astra`.
They select the newest enabled version whenever the workbench starts a task. `gpt-5.6-terra`
and `gpt-5-6-terra` compare as the same Terra generation; Codex CLI receives the current
`modelRef` (`gpt-5.6-terra` for the pinned 0.156.1 package).

| Writer | Default-model behavior |
|---|---|
| 30-agent-setup (`kit-sync`) | Writes `model: opus` (family alias: always the newest Opus) to Claude settings unless a model was set by hand (owner decision 2026-09-27); writes no model to Codex `config.toml`. |
| 32-harness-profiles | Writes roles, hooks and profiles only; it does not set a model. |
| 33-model-endpoints (`kit-models`) | Writes an explicit endpoint model only after `kit-models default <endpoint>`; that value is the endpoint's selected model, not a public Claude/Codex default. |
| 70-workbench | Claude orchestrator default is `opus`; Codex orchestrator default is `sol`. Worker defaults use `sonnet` or `opus` according to the existing role logic; the delivered `workerModel` setting is `sonnet`. The desktop app's first-start guide and settings window store the family alias when the chosen model is the newest of its family. |
| 71-delegate | Leaves the model unset unless the caller supplies `agent-spawn --model`; the example uses the Claude family alias `sonnet`. |

## Keys

- Asked once with hidden input. Stored by `secret-tool` (Secret Service) when a desktop session
  answers, else in `~/.config/work-kit/secrets.env` (mode 0600, `export VAR='…'`).
- Harness configs hold only the variable name (`{env:VAR}`, `$VAR`, `env_key`) or the key
  helper `~/.local/share/work-kit/model-endpoints/key-helper VAR` (Claude Code
  `apiKeyHelper`, Copilot CLI `COPILOT_PROVIDER_API_KEY_COMMAND`). VS Code keeps its copy in its
  own secret storage. The proxy reads keys into its process memory only.
- `~/.config/work-kit/model-endpoints.sh` (no secrets) exports the variables; `~/.bashrc`,
  `~/.profile` (and an existing `~/.zshrc`) source it from a delimited region. It also starts
  the proxy once per login when a registered target needs it (`KIT_MODELS_NO_AUTOSTART=1`
  turns that off).
- `kit-models remove` deletes the key unless `--keep-key`; `uninstall.sh --purge` removes all.

## Files and ownership

Same rules as kit-sync (`kit_models_files.py` holds copies of its helpers; 30-agent-setup is not
needed): a file is never replaced without a copy in
`~/.local/share/work-kit/backups/33-model-endpoints/` (never beside the file); JSON keys are set
only when missing or still holding the value kit-models wrote (recorded in
`~/.local/share/work-kit/state/kit-models.json`); TOML, YAML and shell files get a delimited
`# work-kit:begin … managed by kit-models` region; wrappers carry a marker line. Codex keeps
kit-sync's regions untouched: kit-models uses its own markers, top-level keys at the start and
tables at the end.

## The proxy

`kit-models proxy start|stop|status` (127.0.0.1 only, default port 4020, `--port` or
`KIT_MODELS_PROXY_PORT`). Client side: OpenAI chat, OpenAI Responses, Anthropic Messages (with
`count_tokens`), Gemini `generateContent`, `streamGenerateContent`, `countTokens`. Upstream:
the four kinds above. Same protocol on both sides is passed through, streams included.

### Local token (security review 2026-09-26)

The proxy holds the endpoint keys, so it does not serve every local process. Every request, on
every path and method, must carry a per-install random token (32 random bytes, URL-safe) as
`Authorization: Bearer <token>`, `x-api-key: <token>` or `x-goog-api-key: <token>`, whichever
the client sends. Anything else gets `401` before routing; nothing is forwarded upstream and no
endpoint name is revealed (`/health` included). The comparison is constant-time. The bind stays
`127.0.0.1`. A browser page cannot use the proxy either: it cannot set these headers cross-origin
without a preflight, and the proxy answers no preflight.

- The token is created on first use in `~/.local/share/work-kit/model-endpoints/proxy.token`
  (mode 0600 in a 0700 directory) and never changes until you delete the file (then
  `kit-models sync` writes the new token into every target, and the proxy picks it up at once,
  no restart). It opens only this proxy; it is not an endpoint key. `uninstall.sh --purge`
  deletes it.
- Harness targets get the token instead of the former placeholder `kit-proxy`. Where the file
  format needs the literal value (opencode `apiKey`, pi `apiKey`, Continue `apiKey`, Aider
  `openai-api-key`, `~/.gemini/.env`) it is written there and kit-models sets that file to mode
  0600. World-readable scripts do not contain it: wrappers use `${KIT_MODELS_PROXY_KEY}`, the
  shell snippet sets that variable from the token file, and the key helper (`--proxy`, used by
  Claude Code `apiKeyHelper`) prints the file. The state file that records what
  kit-models wrote is 0600 for the same reason.
- Codex (`env_key`), the 70-workbench provider (`--key-env`) and the evalkit provider list
  (`api_key_env`) name the variable `KIT_MODELS_PROXY_KEY` when the route is the proxy.
- 72-vscode-workbench uses `apiKeyEnv: KIT_MODELS_PROXY_KEY`; start VS Code from a shell that
  sourced the snippet.
- llm-usage (14) forwards the client's `Authorization` header to the upstream unchanged (it drops
  only hop-by-hop headers and never logs it; test `test_non_stream_call_is_recorded_with_genai_attributes`).
  With the proxy as upstream the client must therefore send the token as its key:
  `export OPENAI_BASE_URL=http://127.0.0.1:4011/v1` and
  `export OPENAI_API_KEY="$KIT_MODELS_PROXY_KEY"` (both printed by `kit-models show <name> --target
  llm-usage`; the shell snippet defines `KIT_MODELS_PROXY_KEY`).
- 17-meeting-capture sends `Authorization: Bearer <key>` with its summary request: the key is
  `MEETING_SUMMARY_KEY` if set; when `summary_url` is the local kit-models proxy (loopback,
  `/e/<endpoint>/...`, as `default <name> --also meeting` writes it), else `KIT_MODELS_PROXY_KEY`,
  else the token file. Nothing to configure, `meeting.conf` holds no token. A key set for a URL
  that is not the proxy is sent to that URL only when `MEETING_SUMMARY_KEY` says so; the proxy
  token is never sent elsewhere.
- An older proxy without token check that is still running is stopped and restarted by
  `kit-models proxy start`.
- What this does not do: it is no protection against another process of the same user that can
  read the 0600 files or the environment; a same-user attacker can read the endpoint keys from
  their storage anyway. It closes the open door for every other local caller (other users on a
  shared machine, browser pages, sandboxed tools without file access).

Decision: a small standard-library proxy (`kit_models_proxy.py`), not LiteLLM. LiteLLM is MIT
licensed except its `enterprise/` folder, but `litellm[proxy]` for CPython 3.12 on Linux
x86_64 resolves to 108 packages and about 158 MB of compressed wheels (largest: polars-runtime
50 MB, litellm 27 MB, numpy 17 MB, botocore 16 MB; resolved with `uv pip compile` on
2026-09-25, not installed). The kit needs four translations, no routing, budgets or database.

Limits of the translation:
- Translated requests go upstream without streaming; a streaming client gets the whole answer
  as one well-formed event stream, with keep-alive pings while it waits.
- System or developer messages in the middle of a conversation (Claude Code, Codex do this) are
  merged into one leading system message: chat templates such as Qwen's reject them otherwise
  (observed with `llama-server`: "System message must be at the beginning").
- Model names the endpoint does not serve (`claude-…`, `gemini-…`) map to its first model.
- Hosted tools (web search) cannot run on a company endpoint and are dropped; Codex `custom`
  and `local_shell` tools become function tools and are mapped back.
- Thinking blocks are not carried across protocols.

## Verification (2026-09-25, build Mac, macOS, Python 3.9 and 3.12)

- `python3 -m unittest discover -s tests`: 16 tests (registry and secrets, every target in a
  temp HOME, idempotent sync, user values win, remove and purge restore the files, 70-workbench
  calls with a stub `wb-state`, 72 registry, meeting data-class gate, proxy protocol matrix, meeting summary through the token check,
  local token (401 without or with a wrong token on every path, all three header forms, token
  file and target file modes, no literal token in scripts, no placeholder left)
  against fake OpenAI, Azure and Anthropic servers including tools, streams and headers).
- `bash tests/test-install.sh`: install, idempotent re-install, proxy start with 401/200 checks by curl, `uninstall --purge`.
- Real harnesses in a temp HOME against `llama-server` (`qwen3.5-4b`, 127.0.0.1:18180) and
  against fake OpenAI/Anthropic servers that require a key and a variable header:
  Claude Code 2.1.282, Codex 0.156.1 (including a tool call that wrote a file), opencode
  1.18.32, pi 0.84.2, Aider 0.86.2, Copilot CLI 1.0.88, Gemini CLI 0.61.0 (npm tarball run with
  node) all answered; the fake servers saw the key and the header value from the variable.
  `default --also claude,gemini` and `--no-also` switched the plain `claude` and `gemini`
  commands and restored `settings.json`. The 70-workbench path ran against `wb-state` from
  commit `0ffd7b3`, and pi answered through the provider entry it wrote.
- Not verified here: Linux (end-to-end VM test is a separate task), `secret-tool`, VS Code
  BYOK and Continue inside a running IDE, Cursor, the 72 extension with a kit-models entry,
  an Azure or real company endpoint.
