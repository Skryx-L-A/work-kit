# Harness CLIs (16-harness-clis)

Design notes for `kit/modules/16-harness-clis`. Status: 2026-09-27. The module README has the
commands; this file has the sources, the pinned versions and digests, how each download was
verified, and the decisions behind the layout.

## Sources and pins (checked 2026-09-25)

| Harness | Official source | Pinned | Offline artifact (`kit/offline/harness-clis/`) | Size |
|---|---|---|---|---|
| Claude Code | `https://downloads.claude.ai/claude-code-releases/2.1.283/linux-x64/claude` (the bucket behind `https://claude.ai/install.sh`; docs `https://code.claude.com/docs/en/setup`) | 2.1.283 (newest stable checked 2026-09-27) | `claude/claude-2.1.283-linux-x64` (glibc ELF, self-contained) | 240 MB |
| Codex CLI | `https://github.com/openai/codex/releases/download/rust-v0.156.1/codex-package-x86_64-unknown-linux-musl.tar.gz` (same asset the official `install.sh` unpacks) | 0.156.1 | `codex/codex-package-0.156.1-x86_64-unknown-linux-musl.tar.gz` (static binaries, `rg`, `bwrap`) | 146.0 MB |
| opencode | `https://github.com/anomalyco/opencode/releases/download/v1.18.32/opencode-linux-x64-baseline.tar.gz` (`sst/opencode` redirects here; installer `https://opencode.ai/install`) | 1.18.32 | `opencode/opencode-1.18.32-linux-x64-baseline.tar.gz` (glibc ELF, no AVX2 needed) | 60.6 MB |
| GitHub Copilot CLI | `https://github.com/github/copilot-cli/releases/download/v1.0.88/copilot-linux-x64.tar.gz` (same asset as the repository's `install.sh`) | 1.0.88 | `copilot/copilot-1.0.88-linux-x64.tar.gz` (glibc ELF, self-contained) | 100.3 MB |
| Gemini CLI | npm `@google/gemini-cli@0.61.0` (`https://registry.npmjs.org/@google/gemini-cli/-/gemini-cli-0.61.0.tgz`), tree resolved from `lock/gemini/package-lock.json` | 0.61.0 (dist-tag `latest`) | `gemini/gemini-cli-0.61.0-linux-x64.tar` (`node_modules` with the bundle and the linux-x64 pty package) | 102.8 MB |
| pi | npm `@earendil-works/pi-coding-agent@0.87.1` (`https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-0.87.1.tgz`), tree resolved from `lock/pi/package-lock.json` | 0.87.1 (dist-tag `latest` on 2026-09-25; MIT; needs Node.js >=22.19) | `pi/pi-coding-agent-0.87.1-linux-x64.tar` (`node_modules` with the CLI, 151 MB unpacked) | 137.9 MB |
| Aider | PyPI `aider-chat==0.86.2` and its dependencies | 0.86.2 (latest on PyPI, released 2026-02-12) | `aider/wheels/`, 108 wheels for CPython 3.12, manylinux x86_64 | 120 MB |

Together about 900 MB on the stick and about 1.7 GB installed (Aider's environment alone is
540 MB: numpy, scipy, tree-sitter grammars).

## Digests

The SHA-256 of every file is in `kit/modules/16-harness-clis/lock/artifacts.lock` (wheels:
`lock/aider-requirements.txt`). Each value was compared on 2026-09-25 with what the publisher
publishes; `fetch.sh --relock` repeats the comparison and refuses to write a lock line on a mismatch.

| Harness | SHA-256 | Publisher's own digest, read from |
|---|---|---|
| Claude Code | `1859583ce32920595c61ef868bee52e1b1594f7486db209935e01f1e5e804ae2` | `manifest.json` of the release, whose detached signature `manifest.json.sig` was checked with the Anthropic release key (fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`, from `https://downloads.claude.ai/keys/claude-code.asc`): "Good signature from Anthropic Claude Code Release Signing" |
| Codex CLI | `8b711520beddf385467b8da4d2c93736637c6ba1e46811cf0d8606b7c490b6f6` | GitHub's asset digest and the release file `codex-package_SHA256SUMS` (both agree) |
| opencode | `763af386ef88a8cab18df00fcf055690e5a55e31a7088beabe02307142a6adce` | GitHub's asset digest (the release has no checksum file for this asset) |
| Copilot CLI | `42f40c08ff8a8ff78522161e4b5e2b86340ad8bb0853a5f1aa64ce65b48d007b` | GitHub's asset digest and the release file `SHA256SUMS.txt` (both agree) |
| Gemini CLI | `4fea649043096b7f6e335174172ff4492e679b654951d05b2626416bb03a0ac2` (of the packed tree, not a publisher value) | npm registry: `npm ci` checks every tarball against the `integrity` (sha512) in `package-lock.json`, and `npm audit signatures` reported "7 packages have verified registry signatures". The tarball of the CLI alone also matched the registry's `shasum` (`d4880a2b42aa6786cf626184303b2fdf13bde88f`) and `integrity` when downloaded by hand |
| pi | `7dbf865a201afda9a6ce7f4b4e83c93e443e37cd1e8ccd5f732543a311dfa1bd` (of the packed tree, not a publisher value) | npm registry, as for Gemini CLI: `npm ci` checks the `integrity` (sha512) of every tarball that has one in `package-lock.json`, and `npm audit signatures` reported "119 packages have verified registry signatures". Five of pi's own packages (`@earendil-works/chord`, `pi-agent-core`, `pi-ai`, `pi-telemetry`, `pi-tui`) reach the tree through pi's `npm-shrinkwrap.json`, which lists them without `integrity`, so `npm ci` cannot check them (a wrong integrity in the lock is ignored, tested). `fetch.sh` compares those five with the registry tarballs itself: sha512 equals `dist.integrity`, and every installed file equals the tarball's ("5 packages without lock integrity match their registry tarballs") |
| Aider | one sha256 per wheel in `lock/aider-requirements.txt` | PyPI file hashes (`uv pip compile --generate-hashes`; `pip download --require-hashes`) |

Before any script existed, the same five downloads were fetched by hand and their `shasum -a 256`
compared with the values above. All matched.

## What the installer does

- Verifies the offline file against the lock, unpacks to `~/.local/share/work-kit/harness-clis/<name>/<version>/`,
  points `<name>/current` at it, removes other versions of that tool.
- Command in `~/.local/bin`: a symlink to `current/...` for claude, codex, opencode, copilot, aider;
  a small launcher for gemini (Node.js 20+) and pi (Node.js 22.19+): it takes the first Node.js on
  `PATH` or from 01-prereqs that is new enough. The pi launcher also exports
  `PI_SKIP_VERSION_CHECK=1` unless the user has set that variable.
- Starts `<command> --version` once as a smoke test. A failing tool is reported and the others go on.
- A foreign file with the same command name is moved to `~/.local/share/work-kit/backups/16-harness-clis/<name>.bak-<timestamp>` (original path in
  `<name>.bak-<timestamp>.origin`).
- Codex keeps the layout its vendor's installer creates (`bin/codex`, `codex-path/rg`,
  `codex-resources/bwrap`); the command is a symlink to `bin/codex` as in the official install.
- Aider: `uv venv` on the CPython 3.12 from 00-python, then `uv pip install --offline --no-index
  --require-hashes --find-links <wheels> -r lock/aider-requirements.txt`. No compiler needed.
- State: `~/.local/share/work-kit/state/16-harness-clis.list` (`<name> <version>`).

## Decisions

- **Standalone binaries first.** Claude Code, Codex, opencode and Copilot CLI ship self-contained
  Linux builds; they need no Node.js. Only Gemini CLI and pi need a Node runtime, taken from 01-prereqs
  (`node` item, Node.js 24, pinned there). The installer runs `01-prereqs/install.sh node` when no
  Node.js 20+ is found, so one tool can be installed without the menu.
- **Claude Code on the `stable` channel.** Anthropic's docs describe the stable channel as typically
  about a week old, skipping releases with major regressions. Change `CLAUDE_VERSION` for the newest.
- **opencode `baseline` build.** It runs on CPUs without AVX2; opencode's own installer picks it
  when `/proc/cpuinfo` lacks AVX2. The file size is the same, so the kit takes it for every host.
- **Codex `codex-package` archive** instead of the bare binary: it carries `rg` and the `bwrap`
  sandbox helper the bare binary lacks. It also contains a voice host and a Zsh build; nothing is
  removed because the archive is what the vendor's installer unpacks.
- **Copilot glibc build** (`copilot-linux-x64`, not `linuxmusl`): Ubuntu is glibc.
- **Gemini as a vendored `node_modules` tree**, not the release `gemini-cli-bundle.zip`: the npm
  package is the primary channel and pulls the prebuilt `@lydell/node-pty-linux-x64` for the shell
  tool. The tree is resolved with `npm ci --os=linux --cpu=x64 --libc=glibc --ignore-scripts
  --omit=dev`, so it can be built on the Mac, and packed as an uncompressed tar with sorted names,
  zero mtimes and owners: the same lock gives the same bytes on any host (a compressed archive
  would depend on the zlib version). `npm pack` alone would not carry the dependencies. The optional
  `node-pty` and `@github/keytar` sources are installed but not compiled (no scripts run); how the
  CLI behaves without them is untested here.
- **pi as a vendored `node_modules` tree**, same method as Gemini CLI (`lock/pi`, `npm ci`,
  reproducible tar; rebuilding in a clean directory gave the same sha256). Differences:
  the shrinkwrap of the package pulls every platform build of `esbuild` (12 MB each, 284 MB in all)
  although nothing in pi's `dist/` uses it, so `fetch.sh` keeps only `@esbuild/linux-x64`
  (424 MB down to 138 MB). `--ignore-scripts` skips the install scripts of `esbuild`, `protobufjs`
  and `@google/genai`; pi started and answered a request without them (see the pi section). pi needs
  Node.js 22.19 or newer (`engines.node`); 01-prereqs ships 24.x. The installer checks major and
  minor and runs `01-prereqs/install.sh node` when the Node.js found is older.
- **Aider on CPython 3.12.** `aider-chat` requires Python `>=3.10,<3.13`; the system Python of a
  later Ubuntu release may be newer, so the CPython 3.12 of 00-python is used. Wheels are resolved once for
  `x86_64-manylinux_2_28` with `--no-build`: all 108 distributions have binary wheels.
- **Default set.** `install.sh` without names installs all seven. To install less by default, set
  `KIT_HARNESS_CLIS="claude codex"` or edit `HC_DEFAULT` in `common.sh` before making the stick.
- **Depends on `01-prereqs` only** in `module.conf`; the 00-python step for Aider is run on demand,
  so an Aider problem does not block Claude Code.
- No credentials, profiles or permission defaults are written. Those belong to `30-agent-setup`
  (`kit-sync`) and the user's own login.

## Version check (2026-09-27)

Only Claude Code was relocked for this update. Official release/registry metadata reported the
following latest versions; the other pins remain unchanged deliberately. Codex 0.156.1 meets the
GPT-6 minimum of 0.156.

| Harness | Pinned | Latest checked | Action |
|---|---:|---:|---|
| Codex CLI | 0.156.1 | 0.157.1 | Kept pinned |
| opencode | 1.18.32 | 1.18.32 | Kept pinned |
| GitHub Copilot CLI | 1.0.88 | 1.0.88 | Kept pinned |
| Gemini CLI | 0.61.0 | 0.61.0 | Kept pinned |
| pi | 0.87.1 | 0.87.1 | Kept pinned |
| Aider | 0.86.2 | 0.86.2 | Kept pinned |

## Settings that other modules should set

Checked against the vendors' docs on 2026-09-25. The stick is offline and the versions are
pinned, so self-updates are noise or, once online, an unapproved change.

| Harness | Setting |
|---|---|
| Claude Code | `"env": {"DISABLE_AUTOUPDATER": "1"}` in `settings.json`; attribution (co-author trailer) is a `settings.json` option |
| Codex | `check_for_update_on_startup = false` in `config.toml` |
| opencode | `"autoupdate": false` in `opencode.json` |
| Gemini CLI | `general.enableAutoUpdate: false` in `~/.gemini/settings.json` |
| Aider | `--no-check-update`, `--analytics-disable`, `--no-attribute-co-authored-by` (or the same keys in `.aider.conf.yml`) |
| Copilot CLI | `~/.copilot/settings.json`: `"autoUpdate": false` (`kit-sync` writes it; not re-checked here) |
| pi | `PI_SKIP_VERSION_CHECK=1` in the environment (the launcher sets it); `"enableInstallTelemetry": false` in `~/.pi/agent/settings.json`. Details in the pi section |

## pi

Checked on 2026-09-25 against the docs that ship inside the pinned package
(`node_modules/@earendil-works/pi-coding-agent/docs/`, 0.87.1) and, where marked "run", by starting
the CLI from the packed tree on the Mac with an empty `HOME` against a stub OpenAI-compatible
server on `127.0.0.1` (no real provider, no key).

| What | Where / how |
|---|---|
| Agent directory | `~/.pi/agent/` (override: `PI_CODING_AGENT_DIR`). Holds `settings.json`, `models.json`, `auth.json`, `AGENTS.md`, `skills/`, `prompts/`, `extensions/` |
| Instruction file | `~/.pi/agent/AGENTS.md` (user level; `AGENTS.override.md` and `CLAUDE.md` are read there too) and `AGENTS.md` or `CLAUDE.md` in the working directory and each parent directory. Read without project trust. `--no-context-files` switches it off. Run: a marker in the user file and one in the project file both arrived in the system prompt |
| Skills | `~/.pi/agent/skills/<name>/SKILL.md`, `~/.agents/skills/`, and per project `.pi/skills/` (needs project trust) and `.agents/skills/` (up to the repository root). Extra paths: `skills` array in `settings.json`, or `--skill <path>`. Agent Skills format, so the kit's `SKILL.md` files load as they are. Run: one skill in `~/.pi/agent/skills` and one in `~/.agents/skills` were both listed in the system prompt |
| Update check | Only `PI_SKIP_VERSION_CHECK=1` (environment) stops the request to `https://pi.dev/api/latest-version` at start; there is no settings key. The kit launcher sets it unless the user already has a value. `PI_OFFLINE=1` (or `--offline`) stops every automatic network operation, including model catalog refreshes |
| Telemetry | `"enableInstallTelemetry": false` in `settings.json`, or `PI_TELEMETRY=0`: an anonymous install/update ping to `pi.dev` and provider attribution headers. It does not control the update check. `enableAnalytics` is off by default. Neither is set by the launcher; `kit-sync` should write the settings key |
| Updating pi itself | `pi update` exists but is not used by the kit (not tried on the vendored tree). New version: see "Updating when network is allowed" |
| Local model (15-local-llm) | `~/.pi/agent/models.json`, next block. Run: the provider appeared in `pi --list-models`, and a request went to `<baseUrl>/chat/completions` with `Authorization: Bearer <apiKey>` |
| Project trust | Interactive start asks before it loads `.pi/settings.json`, `.pi/extensions`, `.pi/skills` and similar from a folder. `-p`, `--mode json` and `--mode rpc` do not ask; without a saved decision they ignore those resources unless `defaultProjectTrust` (global settings only) is `"always"`. Context files are unaffected |
| Permissions | pi has no permission prompts and no permission mode: the tools run with the rights of the user. That is the kit's bypass default without any setting. The kit's process-kill and secrets hooks have no pi counterpart here: pi's hook point is an extension, whose `tool_call` handler can block a tool call (`docs/extensions.md` in the package), and the kit ships none. A container or VM is the boundary pi itself recommends (`docs/security.md`) |

`models.json` for a local OpenAI-compatible server (the base URL, port and model id are those of
the 15-local-llm endpoint; 11434 is Ollama's default, `llama-server` uses 8080):

```json
{
  "providers": {
    "local": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [ { "id": "qwen2.5-coder:7b" } ]
    }
  }
}
```

`apiKey` may be any string for a server without authentication; it must exist so the model shows
in `/model`. `settings.json` can then select it: `"defaultProvider": "local"`, `"defaultModel":
"<id>"`. For a llama.cpp router server pi has a built-in provider (`/login llama.cpp`, default URL
`http://127.0.0.1:8080`).

Notes for scripts: when stdin is not a terminal, pi prepends what it reads to the first prompt (`docs/cli.md`),
so it waits for end of input. Started from a shell without a terminal, `pi -p "ping"` hung in the runs
above until `</dev/null` was added; with it, three of three answered. End scripted calls with `</dev/null` or pipe the input.
Sessions are stored under `~/.pi/agent/sessions/`; `--no-session` keeps a run out of them.

## Rebuild and update

```
KIT_OFFLINE=kit/offline bash kit/modules/16-harness-clis/fetch.sh            # download, verify against lock/
bash kit/modules/16-harness-clis/fetch.sh --verify                           # no network
# new versions: edit pins.conf, then
bash kit/modules/16-harness-clis/fetch.sh --relock [--only codex,gemini]     # reads publisher digests, rewrites lock/
```

The build host needs curl and python3; `--relock` needs `gpg` (Claude), `npm` (Gemini, pi) and `uv`
(Aider); the default fetch needs `npm` for Gemini and pi and `uv` or pip 24+ for Aider. It writes only
below `kit/offline/harness-clis/`. `build/build-offline.sh --only modules` runs it and records
every file in `manifest.lock`; the script itself needs no edit.

## Updating when network is allowed

The kit switches every self-updater off (table above). The update path is the kit's own: new pin,
relock, install into the same prefix. It runs on the laptop in `~/work/kit/modules/16-harness-clis`
as soon as network access is allowed (behind a proxy after `kit-net proxy set <url>`).

| Harness | Steps (after changing the pin in `pins.conf`) | Extra tool on the laptop |
|---|---|---|
| Claude Code | `bash fetch.sh --relock --only claude && bash install.sh claude` (`CLAUDE_VERSION`) | `gpg` (checks the signed manifest) |
| Codex | `bash fetch.sh --relock --only codex && bash install.sh codex` (`CODEX_VERSION`) | none |
| opencode | `bash fetch.sh --relock --only opencode && bash install.sh opencode` (`OPENCODE_VERSION`) | none |
| Copilot CLI | `bash fetch.sh --relock --only copilot && bash install.sh copilot` (`COPILOT_VERSION`) | none |
| Gemini CLI | `bash fetch.sh --relock --only gemini && bash install.sh gemini` (`GEMINI_VERSION`) | `npm` (01-prereqs `node`) |
| pi | `bash fetch.sh --relock --only pi && bash install.sh pi` (`PI_VERSION`) | `npm` (01-prereqs `node`) |
| Aider | `bash fetch.sh --relock --only aider && bash install.sh aider` (`AIDER_VERSION`) | `uv` (00-python) |

All need `curl` and `python3`. `--relock` reads the publisher's digest, downloads, compares and
rewrites only that tool's lines in `lock/`; `install.sh` then verifies the file against the lock,
unpacks the new version next to the old one, moves `current` and removes the old version. The
vendors' own updaters (`claude update`, `pi update`, …) are not used and were not tested with this
layout. This path was not run on Linux yet. A new stick copied with
`install-kit.sh` resets `pins.conf` and `lock/` in `~/work/kit` to the stick's versions.

## Not verified here

- No Linux binary was started (pi included: its packed tree is JavaScript plus a prebuilt `linux-x64`
  clipboard addon in `pi-tui/native/`, which only a Linux run can load): this was built on macOS arm64 without a Linux VM. What was run:
  the module tests (`tests/test-install.sh`, fake artifacts), the installer against the real
  downloads on the Mac with the smoke test switched off (layout, links, state), the Gemini
  launcher with the Mac's Node.js (`gemini --version` printed 0.61.0), the pi launcher the same way
  (`pi --version` printed 0.87.1), and
  `uv pip install --require-hashes --offline --no-index --python-platform x86_64-manylinux_2_28
  --target <dir>` for the 108 Aider wheels (all install, `aider` entry point present).
- Still open for the Linux end-to-end test: `--version` of each binary on Ubuntu 24.04 and 26.04,
  the Codex sandbox (Ubuntu 24.04 restricts unprivileged user namespaces by default, which
  `bwrap` needs; Codex may need its fallback or an AppArmor exception), the Aider venv on the
  uv-managed CPython 3.12, and whether Claude Code and Copilot CLI start without a network.
- Licences: Claude Code and Copilot CLI are proprietary (GitHub's API lists no SPDX licence for
  the Copilot repository); Codex, Gemini CLI and Aider are Apache-2.0, opencode is MIT (GitHub API,
  2026-09-25); pi is MIT (npm registry `license` field of 0.87.1).
  The stick is for installing on the owner's own work machine, not for handing the binaries out.
