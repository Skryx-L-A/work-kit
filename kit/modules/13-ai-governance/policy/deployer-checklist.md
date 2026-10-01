# AI deployer checklist (ISO/IEC 42001 style)

A checklist for a company that *uses* AI systems (deployer), structured like an AI
management system. It is not the ISO/IEC 42001 standard and does not replace it; it lists
the building blocks such a system needs, so gaps become visible. Mark each line
`done`, `partial`, `missing` or `n/a`, with evidence (file, ticket, date).
`TODO(ask IT)`: whether the company runs or plans an AI management system, and who owns it.

## Context and scope

- [ ] Role under the EU AI Act stated per system (deployer / provider / neither).
- [ ] Scope of AI governance written down: which units, persons and systems.
- [ ] Interested parties and their requirements listed: customers (contract clauses on
      AI), staff and works council, regulators, certification body (ISO 27001).

## Leadership and policy

- [ ] AI usage guideline approved and published (`ai-usage-guideline.md`).
- [ ] Roles named: guideline owner, approver of AI systems, data protection, system owners.
- [ ] AI governance linked to the existing ISMS (policies, risk process, audits).

## Planning: risk and impact

- [ ] AI system inventory exists and is current (`ai-system-record.md` per system).
- [ ] Each system has a risk tier (EU AI Act: prohibited / high / limited / minimal) and
      a data-class ceiling.
- [ ] Risks per system assessed (wrong output, data leakage, prompt injection, vendor
      lock-in, license, bias) with owner and treatment.
- [ ] Impact on persons assessed where AI touches people (staff, customers); data
      protection impact assessment where required.

## Support: competence, awareness, documentation

- [ ] AI literacy measures per role (Art. 4), with records.
- [ ] Guideline and approved list are easy to find for every user.
- [ ] Templates exist for tool requests, inventory entries, incidents.

## Operation

- [ ] Approval process for new AI systems, providers, models and MCP servers.
- [ ] Data classes and allowed destinations enforced (data guard, contracts, settings).
- [ ] Human review defined per use case (who, what, how long).
- [ ] Agent tool access default deny, blast-radius tags, confirmation for irreversible
      actions (`mcp-policy.md`).
- [ ] Supplier checks: data processing agreement, data location, retention, training on
      customer data opted out, subprocessors.
- [ ] Use cases pass stage gates with written kill criteria (skill `ai-use-case-intake`).

## Performance evaluation

- [ ] Each use case in production has a baseline and a measured result.
- [ ] Inventory and allowlist reviewed on schedule; review dates recorded.
- [ ] Internal audit covers AI governance (can be part of the ISMS audit).

## Improvement

- [ ] AI incidents reported, reviewed without blame, and fed back into guideline,
      inventory and allowlist.
- [ ] Systems that no longer meet their purpose or rules are decommissioned and marked
      `retired` in the inventory.
