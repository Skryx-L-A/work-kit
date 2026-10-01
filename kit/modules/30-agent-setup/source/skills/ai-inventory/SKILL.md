---
name: ai-inventory
description: 'Keep the register of AI systems in use (tools, model APIs, assistants, local models, MCP servers) current in the brain: one note per system with provider, model, data destination, data class, purpose, owner, EU AI Act role and risk tier, status and review date; list it and flag gaps. Use when a new AI tool or model is requested, approved, piloted, changed or retired, when preparing an audit or IT review, or when asked "which AI systems do we use". Do not use to decide whether a tool is approved (IT decides; use ai-policy for the request) or to assess a use case (ai-use-case-intake).'
---

# AI system inventory

The inventory answers: which AI systems are in use, for what, with which data, who owns
them, what risk tier they have and when they are reviewed next. Under the EU AI Act a
deployer must know this; it is also the register an ISMS audit asks for. Each system is one
brain note tagged `ai-system` in project `ai-inventory`. Changes are appended, never
overwritten, so the note is its own audit trail.

Template: `references/ai-system-record.md` (same as `ai-gov template ai-system-record`
from module 13-ai-governance). Listing: `scripts/inventory.py`.

## Procedure

1. **Find the existing entry.** `brain search "<system or vendor>" --project ai-inventory`.
   One entry per system and deployment; a new model version of the same system is a change,
   a different provider or tenant is a new entry.
2. **Create a missing entry** from the template:
   `brain new reference "AI system: <name>" --project ai-inventory --tags ai-system --body - < references/ai-system-record.md`,
   then fill in every field. Values come from the tool request, contract, vendor documentation
   or IT. Unknown stays `unknown`; approval fields stay `TODO(ask IT)` until someone approved.
3. **Classify the EU AI Act risk tier** per system and purpose (the same tool can be minimal
   for code explanation and high for screening applicants):
   - `prohibited`: Art. 5 practices (for example emotion recognition at work): stop, report.
   - `high`: Annex III purposes such as employment decisions, access to essential services,
     critical infrastructure: escalate to the guideline owner before any use.
   - `limited`: transparency duties (chatbots talking to people, generated content published).
   - `minimal`: everything else, for example coding assistants for internal work.
   When unsure, write `unknown` and ask; the listing flags it.
4. **Record changes** by appending: `brain append <note path> --body -` with
   `## Change <YYYY-MM-DD>` and the changed `- key: value` lines (status, model, data_class,
   review_by, owner) plus one sentence why. Status flow:
   `requested → approved → pilot → production → suspended / retired`.
5. **Review.** `python3 scripts/inventory.py` (options `--status production`, `--json`,
   `--brain DIR`) prints the register as a Markdown table with flags: review overdue or
   missing, no owner, unknown / high / prohibited tier, in use without recorded approval,
   missing data class or EU AI Act role. Resolve each flag or give it an owner and a date.
6. **Keep the links.** MCP servers in the inventory must match the MCP allowlist
   (`mcp-governance`); pilots link their use-case note (`ai-use-case-intake`); incidents
   link the affected entry (`ai-policy`).

## When a tool is missing

- No `brain`: same notes as Markdown files with frontmatter `tags: [ai-system]` in any
  folder; list with `--brain DIR`.
- No Python: read the notes; the flags above are the checklist.
- No module 13-ai-governance: the template in `references/` is complete on its own.

## Done when

- Every AI system used for company work, including local models and MCP servers, has an entry.
- Every entry has owner, data class, destination, risk tier, status and a future review date,
  or a flag with an owner and a date.
- `inventory.py` shows no unowned flags; changes since the last review are appended with reasons.

## Pitfalls

- Forgetting AI features inside existing software (office suite, IDE, ticket system) and
  personal browser extensions: they are AI systems too.
- Recording the tool but not the model or where data goes; the data route is what matters.
- Marking a system `approved` because it is widely used. Only a named approver counts.
- Writing contract details, prices or credentials into the note. Reference the contract,
  do not copy it.
- Treating the tier as fixed: a new purpose can change it.

## Related skills

`ai-policy`, `mcp-governance`, `ai-use-case-intake`, `data-guard`, `brain`.
