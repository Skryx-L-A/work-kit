# 13-ai-governance

AI usage guideline template, deployer checklist, MCP policy + allowlist, and the `ai-gov`
CLI. Offline, no sudo. Needs `python3` or the kit CPython (3.11+ to read Codex TOML). Independent module.

```sh
cd ~/work/kit/modules/13-ai-governance && bash install.sh
bash uninstall.sh
```

Open a new terminal.

```sh
ai-gov open-questions                 # every TODO(ask IT): the list for IT
ai-gov mcp-check                      # MCP servers in all harnesses vs. allowlist
ai-gov mcp-check --project ~/work/x   # also the repository's own MCP configs
ai-gov template ai-system-record      # also: ai-tool-request, ai-incident, literacy-record
```

Then edit in `~/.config/work-kit/`: `ai-usage-guideline.md`, `deployer-checklist.md`,
`mcp-policy.md`, `mcp-allowlist.yaml`.

Skills and tests: `~/work/kit/docs/governance.md`.
