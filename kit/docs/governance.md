# AI governance in the kit: design notes

Module `kit/modules/13-ai-governance` plus four skills in
`kit/modules/30-agent-setup/source/skills/`: `ai-policy`, `ai-inventory`, `mcp-governance`,
`ai-use-case-intake`. Written 2026-09-25. Evidence base: `docs/research-company-ai-setups.md`
sections 1 (governance), 5 (MCP) and 8 (use-case portfolio); URLs below.

## What ships and why

| Part | Form | Why it is shaped this way |
|---|---|---|
| AI usage guideline | `policy/ai-usage-guideline.md`, copied to `~/.config/work-kit/` | The document IT asks for first. Structure follows the German professional-services pattern (Steuerberaterverband model guideline, April 2026: scope incl. externals, human responsibility, coordination with DPO/IT) and the EU AI Act duties a deployer has from Aug 2026 (Art. 4 literacy, Art. 5 prohibitions, Art. 50 transparency). Same shipping pattern as `40-data-guard/data-classes.md`: company values are `TODO(ask IT)`, strictest reading until confirmed. |
| Deployer checklist | `policy/deployer-checklist.md` | ISO/IEC 42001 is certifiable but paywalled and company-scale. The checklist lists the deployer-side building blocks (inventory, risk and impact, literacy records, approvals, supplier checks, incidents, review) in management-system order, without reproducing the standard. Research §1: Idest's 42001 scope was deployer-only use of a chat product, i.e. exactly this shape. |
| MCP policy + allowlist | `policy/mcp-policy.md`, `policy/mcp-allowlist.yaml` | Research §5: default-deny allowlist, blast-radius classes (read / reversible / irreversible), human confirmation for irreversible tools, pinned packages, no secrets in config, tool descriptions as untrusted input (CSA Agentic MCP Security Best Practices v1; exploreagentic.ai hardening checklist). The allowlist ships with one entry, the kit's own `brain mcp`, at data class INTERNAL. |
| `ai-gov mcp-check` | Python stdlib CLI | A policy nobody checks decays. The checker reads every known harness config (user and `--project`), compares against the allowlist, and flags NOT-ALLOWED, MISMATCH, UNPINNED, INLINE-SECRET, AUTO-APPROVED, EXPIRED (fail) and UNCONFIRMED, UNREADABLE (warn; `--strict` fails). It never modifies configs and never prints secret values. |
| `ai-gov open-questions` | CLI | Turns every `TODO(ask IT)` in the installed policy files into one list for the first IT meeting. |
| Templates | `templates/`: system record, tool request, incident report, literacy record | Evidence records an ISMS/AIMS audit expects; the tool request is the approval path the guideline and MCP policy point to. `ai-gov template NAME` prints them for piping into `brain new`. |
| Inventory in the brain | skill `ai-inventory` + `scripts/inventory.py` | Research §1/§8: the AI system inventory doubles as the compliance register. One brain note per system (type `reference`, project `ai-inventory`, tag `ai-system`), record as `- key: value` lines. |
| Use-case portfolio | skill `ai-use-case-intake` + `scripts/portfolio.py` + references | Research §8: intake as a form (six questions, two-week answer), four-dimension scoring on 1–5 with 2.5 minimum composite (Concept-LAB), stage gates with written kill criteria and a baseline measured before building (dsstream), pilots time-boxed to 12 weeks against "pilot purgatory". One brain note per case (type `note`, project `ai-use-cases`, tag `ai-use-case`). |

## Decisions

- **No new brain note type.** `20-brain`'s type list is a contract owned by another module;
  inventory and portfolio use existing types (`reference`, `note`) plus a tag. Listing scripts
  find notes by tag, so they work wherever `brain new` places the file.
- **Append-only records.** Fields are `- key: value` lines; the last value of a key wins.
  Changes and gate decisions are appended with `brain append` (a stable contract command),
  which keeps the history in the note and in git without editing tools. Placeholder values
  written as `<...>` are ignored.
- **Scripts live in the skills**, not in module 13, so inventory and portfolio listings work
  when module 13 is not installed (SPEC: modules independent, skills degrade gracefully).
  The system-record template exists in both places; a test asserts the copies are identical.
- **Stdlib only, python3 from the system.** Ubuntu 24.04 ships Python 3.12, so the module
  does not depend on `00-python`. The allowlist uses a YAML subset parsed by a built-in
  parser; PyYAML or `yq` are used when present. Codex TOML needs Python 3.11+ (`tomllib`);
  older interpreters report the file as UNREADABLE.
- **Strictest defaults.** Unknown blast radius is `irreversible`; servers not on the list are
  NOT-ALLOWED; allowlist entries past `review_by` fail; the brain entry is capped at INTERNAL
  until IT confirms local tools for CONFIDENTIAL. Unconfirmed approvals are warnings rather
  than failures so a fresh install does not fail on its own shipped entry; `--strict`
  changes that.
- **Auto-approval checks** cover what is file-based and documented: Claude Code
  `permissions.allow` rules (`mcp__server`, `mcp__server__*`, `mcp__server__tool`) and
  `enableAllProjectMcpServers`, Gemini CLI `trust: true`, VS Code
  `chat.tools.global.autoApprove`. Not checked: Codex approval modes (value semantics not
  confirmed), Cursor run mode and VS Code per-server UI trust (not in files), Copilot CLI
  `--allow-tool` (command-line flags).

## Harness MCP config locations

Verified from official docs on 2026-09-25; table and caveats in
`kit/modules/30-agent-setup/source/skills/mcp-governance/references/config-locations.md`.
The checker's list is `config_sources()` in `kit/modules/13-ai-governance/ai-gov`; update
both together. Not confirmed from an official page: VS Code user `mcp.json` path on Linux
(derived from the documented user settings folder), Continue's global `config.yaml` path,
Claude Code's managed MCP file on Linux (not scanned).

## EU AI Act dates relevant to a deployer

From the Commission's AI Act Service Desk timeline (reflects the Digital Omnibus proposal):
02 Feb 2025 AI literacy and prohibitions apply; 02 Aug 2026 most rules apply and enforcement
starts; 02 Dec 2026 new prohibitions; 02 Dec 2027 high-risk Annex III; 02 Aug 2028 high-risk
Annex I. The Omnibus proposal to shift the literacy duty is not law (research §1, marked
uncertain). Re-check before relying on any date.

## Open points

- All `TODO(ask IT)` values (run `ai-gov open-questions`); starter list in
  `skills/ai-policy/references/questions-for-it.md`.
- The integration step may register `ai-gov` in `kit/install` and `kit/README.md`
  (not in this module's paths).
- Score anchor texts in the scoring sheet are the kit's own; calibrate with the company.

## Sources (accessed 2026-09-25)

1. European Commission, AI literacy Q&A: https://digital-strategy.ec.europa.eu/en/faqs/ai-literacy-questions-answers [P]
2. European Commission, AI Act implementation timeline: https://ai-act-service-desk.ec.europa.eu/en/ai-act/timeline/timeline-implementation-eu-ai-act [P]
3. Regulation (EU) 2024/1689: https://eur-lex.europa.eu/eli/reg/2024/1689/oj [P]
4. Deutscher Steuerberaterverband, Muster-KI-Anwendungsrichtlinie (04/2026); URL in
   `docs/research-company-ai-setups.md` source 3 [P]
5. BSI, KI topic page: https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Informationen-und-Empfehlungen/Kuenstliche-Intelligenz/KI.html [P]
6. ISO/IEC 42001:2023 overview: https://www.iso.org/standard/81230.html [P]; certifications
   in DACH: research doc sources 6 and 7 [P]
7. Cloud Security Alliance, Agentic MCP Security Best Practices v1: https://labs.cloudsecurityalliance.org/agentic/agentic-mcp-security-best-practices-v1/ [P]
8. exploreagentic.ai, MCP server security hardening (2026-06-09): https://www.exploreagentic.ai/insights/mcp-server-security-hardening/ [S]
9. Concept-LAB, AI use case portfolio scoring: https://www.concept-lab.be/blog/ai-use-case-portfolio-scoring [S]
10. dsstream, AI use case pipeline (2026-09-01): https://www.dsstream.com/post/ai-use-case-pipeline [S]
11. Harness MCP docs: see `config-locations.md` (Claude Code, Codex, Gemini CLI, opencode,
    Cursor, VS Code, Copilot CLI, Continue, Aider) [P]

## Module tests

`python3 -m pytest tests/` (build host only: pytest is not shipped on the stick) and
`bash tests/test-install.sh` in the module folder. The four
governance skills live in `30-agent-setup/source/skills/`: `ai-policy`, `ai-inventory`,
`mcp-governance`, `ai-use-case-intake`.
