# 16-harness-clis

Claude Code, Codex, opencode, GitHub Copilot CLI, Gemini CLI, pi and Aider from fetched files, pinned,
Linux x86_64. Offline, no sudo.
Needs `kit/offline/harness-clis`. Gemini needs Node.js 20+, pi needs Node.js 22.19+ and Aider needs
CPython 3.12: the installer runs `01-prereqs/install.sh node` and `00-python/install.sh` itself when
they are missing.

```sh
cd ~/work/kit/modules/16-harness-clis && bash install.sh    # all seven (default set)
bash install.sh claude codex                                # only these
bash install.sh --list                                      # pinned versions, offline files, installed versions
bash uninstall.sh claude codex        # removes the tools, keeps your ~/.claude, ~/.codex, ... config
```

Open a new terminal, then sign in to every tool you use. No login or key ships with the kit.
Each tool: `~/.local/share/work-kit/harness-clis/<name>/<version>/`, command in `~/.local/bin`.

## Updating when network is allowed

The tools do not update themselves. Per tool: set the new version in `pins.conf`, then

```sh
cd ~/work/kit/modules/16-harness-clis
bash fetch.sh --relock --only claude && bash install.sh claude       # CLAUDE_VERSION, needs gpg
bash fetch.sh --relock --only codex && bash install.sh codex         # CODEX_VERSION
bash fetch.sh --relock --only opencode && bash install.sh opencode   # OPENCODE_VERSION
bash fetch.sh --relock --only copilot && bash install.sh copilot     # COPILOT_VERSION
bash fetch.sh --relock --only gemini && bash install.sh gemini       # GEMINI_VERSION, needs npm (01-prereqs node)
bash fetch.sh --relock --only pi && bash install.sh pi               # PI_VERSION, needs npm (01-prereqs node)
bash fetch.sh --relock --only aider && bash install.sh aider         # AIDER_VERSION, needs uv (00-python)
```

`fetch.sh` needs curl and python3, checks each download against the publisher's digest and writes
only to `lock/` and `~/work/kit/offline/harness-clis/`. Behind a proxy: `kit-net proxy set <url>` first.
Running `~/work-kit/setup/install-kit.sh` from an updated repository resets `pins.conf` and `lock/` to that repository's versions.

Sources, digests and rebuild: `~/work/kit/docs/harness-clis.md`.
