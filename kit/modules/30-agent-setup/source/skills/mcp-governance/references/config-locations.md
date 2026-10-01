# Where harnesses keep MCP configuration (Linux)

Checked against official documentation on 2026-09-25. Harnesses change these locations;
if a file is not where this table says, check the harness documentation and update this
file and `ai-gov` (module 13-ai-governance).

| Harness | User level | Project level | Key | Auto-approve settings to watch |
|---|---|---|---|---|
| Claude Code | `~/.claude.json` (user scope; local scope under `projects.<path>.mcpServers`) | `.mcp.json` | `mcpServers` | `permissions.allow` entries `mcp__<server>`, `mcp__<server>__*`, `mcp__<server>__<tool>` in `~/.claude/settings.json` and `.claude/settings*.json`; `enableAllProjectMcpServers` |
| Codex CLI | `~/.codex/config.toml` | `.codex/config.toml` (trusted projects only) | `[mcp_servers.<name>]` | per-server/per-tool approval mode settings (values: see Codex docs) |
| Gemini CLI | `~/.gemini/settings.json` | `.gemini/settings.json` | `mcpServers` | `trust: true` per server skips all confirmations |
| opencode | `~/.config/opencode/opencode.json` | `opencode.json` | `mcp` (`command` is an array) | tool enable/disable globs under `tools` |
| Cursor | `~/.cursor/mcp.json` | `.cursor/mcp.json` | `mcpServers` | run mode / auto-run in the app settings |
| VS Code (Copilot) | `~/.config/Code/User/mcp.json` (profile folder) | `.vscode/mcp.json` | `servers` | `chat.tools.global.autoApprove`, `chat.tools.eligibleForAutoApproval` in user `settings.json`; per-server trust in the UI |
| Copilot CLI | `~/.copilot/mcp-config.json` (`$COPILOT_HOME`) | `.mcp.json`, `.github/mcp.json` | `mcpServers` | `--allow-tool`, `--allow-all-tools` flags |
| Continue | `~/.continue/config.yaml`, `~/.continue/mcpServers/*` | `.continue/mcpServers/*` | `mcpServers` (list) | – |
| Aider | no native MCP support | – | – | – |

Not verified from an official source: the exact VS Code user `mcp.json` path (derived from
the documented user settings folder), the global Continue `config.yaml` path, and approval
keys for opencode and Continue. `ai-gov mcp-check` does not evaluate Codex approval modes,
Cursor run modes or VS Code UI trust; check those by hand.

## Sources (accessed 2026-09-25)

- Claude Code: https://code.claude.com/docs/en/mcp , https://code.claude.com/docs/en/permissions
- Codex CLI: https://developers.openai.com/codex/mcp
- Gemini CLI: https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md
- opencode: https://opencode.ai/docs/mcp-servers , https://opencode.ai/docs/config
- Cursor: https://cursor.com/docs/context/mcp
- VS Code: https://code.visualstudio.com/docs/copilot/customization/mcp-servers
- Copilot CLI: GitHub Docs, "Adding MCP servers for GitHub Copilot CLI" (docs.github.com, Copilot CLI section)
- Continue: https://docs.continue.dev/customize/deep-dives/mcp
- Aider: open feature requests https://github.com/Aider-AI/aider/issues/4506
