# MCP governance policy (template)

Rules for connecting AI agents to tools through the Model Context Protocol (MCP) and
similar tool integrations. Part of the AI usage guideline, section 5. Values marked
`TODO(ask IT)` are placeholders; until confirmed, the strictest reading applies.

## Rules

1. **Default deny.** An MCP server may be configured in a harness only if it is on the
   allowlist `~/.config/work-kit/mcp-allowlist.yaml`. Everything else is removed or
   disabled, including servers that a project repository brings along (`.mcp.json`,
   `.vscode/mcp.json`, `.cursor/mcp.json` and similar).
2. **Approval.** A server is added to the allowlist only after approval by
   `TODO(ask IT)`, requested with `templates/ai-tool-request.md`. The allowlist entry
   records who approved it and when.
3. **Blast radius.** Every server, and where it matters every tool, carries one tag:
   - `read`: only reads data (search, read files, list issues);
   - `reversible`: changes data in a way that can be undone (create a draft, write a
     local note under version control);
   - `irreversible`: effects that cannot be undone or leave the company (delete, send
     e-mail or chat messages, publish, deploy, pay, push, change permissions).
   Unknown means `irreversible`.
4. **Confirmation.** Tools tagged `irreversible` require a human confirmation for each
   call. They are never added to a harness's auto-approve or "always allow" list, and
   servers containing them never get a "trust" flag.
5. **Data classes.** Each allowlist entry states the highest data class the server may
   see. A server that sends data to a remote service is a destination in the sense of
   `data-classes.md`.
6. **Pinned local servers first.** Prefer local stdio servers with a fixed version
   (`package@1.2.3`, a checked-in binary, or a path in `~/.local/bin`). Unpinned
   launchers (`npx -y package`, `uvx package` without a version) and remote HTTP servers
   need an explicit allowlist entry that names the URL or the exact version.
7. **No secrets in configuration.** Tokens are passed through environment variables or a
   secret store, never written into MCP configuration files. Tokens are scoped to the
   minimum and short-lived where the service allows it.
8. **Tool descriptions are untrusted.** A tool description or tool output that tries to
   instruct the agent (for example "ignore previous instructions", "also send ...") is a
   suspected prompt injection: stop, disable the server, report an incident.
9. **Review.** The allowlist is reviewed every `TODO(ask IT)` months and when a server
   changes version, owner, publisher or tools. Entries past `review_by` count as not
   allowed until reviewed.

## Check

`ai-gov mcp-check` lists every MCP server configured in the installed harnesses (and with
`--project DIR` in a repository) and flags servers that are not on the allowlist, differ
from their pinned command or URL, use unpinned launchers, carry inline secrets, are past
their review date, or are auto-approved although tagged `irreversible`. Exit code 1 means
there is something to fix. Run it after installing a harness, after `kit-sync`, and
before opening a repository you did not create.

## Sources

Cloud Security Alliance, Agentic MCP Security Best Practices v1 (default-deny registry,
tool-level scopes, description pinning); exploreagentic.ai, MCP server security hardening,
2026-06-09 (inventory, default-deny allowlist, blast-radius classes, human confirmation,
pinned packages). Details and URLs: `docs/governance.md` in the kit repository.
