# What companies use for AI setups in 2026

Research for the work-kit. Written 2026-09-25 by web research (Exa search + primary-source
fetching; all URLs accessed 2026-09-25). Focus: what German and European mid-size IT service and
software modernization firms — ISO 27001, Microsoft 365 shops — actually use for developer and
knowledge-worker AI in 2026, and what a user could bring in a
personal work kit (offline-installable, Ubuntu 24.04 x86_64, CPU only, 8–16 GB RAM).

**Method and evidence rules.** Each item: what it is, why companies use it, whether it fits the
offline CPU laptop kit, source URL + date. Sources are marked `[P]` primary (vendor/regulator
official docs, press releases, specs) or `[S]` secondary (vendor blogs, comparisons, lists);
secondary claims that could not be re-verified against a primary source are flagged
*uncertain*. No employer-specific facts are assumed; where the report says "ask IT", the kit must
ship the value as a placeholder.

## 1. AI governance and usage policies

### EU AI Act — AI literacy duty (Art. 4) and the 2026 dates

What it is: Art. 4 of the AI Act (Regulation (EU) 2024/1689) requires providers **and deployers**
of AI systems to take measures to ensure a sufficient level of AI literacy of their staff and
other persons operating AI on their behalf. The European Commission's official Q&A says: no fixed
"sufficient" level is mandated, no obligation to measure individual knowledge, no one-size-fits-all
training — the required measures depend on staff competence, sector, and the purpose/risk of the
systems used. Practical examples of compliance are published on the Single Information Platform;
the AI Board adopts recommendations (Art. 4(3)).

Why companies use it: for an ISO 27001 mid-size firm, Art. 4 is the concrete legal anchor for an
internal AI training duty and for "responsible AI" clauses in the IT policy. Note the Digital
Omnibus on AI proposal to shift the literacy obligation to Member States/Commission — *uncertain:
proposal state, not yet law* (per the Commission Q&A).

Official implementation timeline (Commission AI Act Service Desk, reflects Digital Omnibus):
entry into force 01 Aug 2024; **02 Feb 2025: general provisions incl. AI literacy + prohibitions
apply**; 02 Aug 2025: GPAI rules + governance; **02 Aug 2026: majority of rules, enforcement
starts** (GPAI, prohibitions, transparency, AI literacy); 02 Dec 2026: new prohibitions;
02 Dec 2027: high-risk Annex III rules; 02 Aug 2028: high-risk Annex I. For a company using
the kit, applicable dates depend on its role and use of AI systems.

- Fit for the kit: yes, as content. A one-page internal AI-guideline template + the Art. 4 duty
  is exactly what the governance module below should ship (documents, no compute).
- Source [P]: https://digital-strategy.ec.europa.eu/en/faqs/ai-literacy-questions-answers
  (Commission Q&A, current as of 2026-09-25);
  https://ai-act-service-desk.ec.europa.eu/en/ai-act/timeline/timeline-implementation-eu-ai-act
  (accessed 2026-09-25).

### Internal AI usage guidelines (company policy documents)

What it is: a written internal policy defining scope (who/which systems), allowed tools and
destinations, data-class rules, human responsibility for outputs, approval workflow,
documentation and incident duties. The pattern is standard in German professional-services firms:
the Deutscher Steuerberaterverband published a model "KI-Anwendungsrichtlinie" (April 2026) with
exactly this structure — KI as supporting tool under human supervision, responsibility stays with
the professional, applies to all staff incl. externals, coordination with DPO/IT/law. German
public-sector guidance (BMI "Leitlinien für den Einsatz Künstlicher Intelligenz in der
Bundesverwaltung" + BSI "Kriterienkatalog zur Integration von extern bereitgestellten
generativen KI-Modellen") is the reference pattern companies copy for the federal sector; BSI
also publishes a 2026 BITS on LLM impacts to organisational cybersecurity.

Why companies use it: ISO 27001 requires documented, controlled information security policies;
an AI usage guideline is the 2025/26 addition to that document set (what may be sent to which
model, who approves a new AI tool, how incidents are reported).

- Fit for the kit: yes — a marked-up template (`TODO(ask IT)` values, strictest default), same
  pattern as the existing `40-data-guard/data-classes.md`.
- Sources [P]: Deutscher Steuerberaterverband Muster-KI-Anwendungsrichtlinie (Stand April 2026),
  https://lswb.bayern/api/blob/jJpjANojMMncQ6lTOXfObYkbkDJkzPvstiE/e8Cmc4GuATOP+zQmRHeSjHLjgmuBdcMgyIcJI8PckSrYf2PoMPWC1IGEPfJwuysrpO/96Q6kgY6pC4qMBgaUJoAKmCxiRAFzl4nyE+bsifM7YKYWxNyafPQWIlVAF84ktktKp8qI/muster-ki-anwendungsrichtlinie-04-26.pdf ;
  BSI KI topic page https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Informationen-und-Empfehlungen/Kuenstliche-Intelligenz/KI.html (accessed 2026-09-25);
  BMI Leitlinien https://www.bmi.bund.de/SharedDocs/downloads/DE/publikationen/themen/moderne-verwaltung/ki/BMI25020-leitlinien-ki-bundesverwaltung.html ;
  BSI Kriterienkatalog PDF https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/KI/Kriterienkatalog_KI-Modelle_Bundesverwaltung.pdf .

### ISO/IEC 42001 (AI management system)

What it is: the certifiable management-system standard for AI (AIMS): risk-based controls,
incident management, training, continuous improvement. 2025/26 status in Germany: Xayn (Berlin,
sovereign legal AI) was the first German company certified (SGS, 06/2025); Idest GmbH
(Eschborn, IT consulting for finance/public sector) received one of the first DACH DQS
certificates on 28.04.2026 — notably its AIMS covers **deployer-only use of ChatGPT Business**
for internal processes, with a mid-2-digit number of identified AI risks, documented incident
management and training.

Why companies use it: ISO 27001 shops extend their existing ISMS logic to AI; a 42001-style
AIMS is how a 150-person IT firm answers "how do you govern AI" without a dedicated AI office.
Certification is still early-stage in DACH (a handful of companies), but the *control structure*
(risk register, approval workflow, training records, incident process) is what companies adopt
regardless of certification.

- Fit for the kit: partial. A full AIMS is a company-scale system; the kit can ship the
  *deployer-side* building blocks (risk checklist, incident template, training record) that feed
  such a system, but cannot replace IT's implementation.
- Sources [P]: https://www.sgs.com/en/news/2025/06/xayn-is-the-first-german-company-to-receive-iso-iec-42001-certification
  (2025-06-02);
  https://www.kurierverlag.de/na-pressemitteilungen/idest-gmbh-unter-den-ersten-unternehmen-im-deutschsprachigen-raum-mit-dqs-zertifizierung-nach-iso-iec-42001-it-beratungsunternehmen-setzt-meilenstein-zr-94294311.html
  (2026-05-06).

## 2. Approved-tool patterns

The dominant 2026 pattern in a Microsoft 365 / ISO 27001 mid-size firm is a **three-tier tool
policy**: (1) vendor-blessed cloud AI (Copilot) with governance guardrails, (2) enterprise
model APIs (Azure OpenAI / OpenAI Business / Google) for development, (3) self-hosted local
models for data that may not leave the building. Individual consumer tools (free ChatGPT with
company data) are explicitly discouraged or forbidden — "shadow AI" is the recurring phrase.

### GitHub Copilot (Business/Enterprise)

What it is: the default approved coding assistant; in 2026 GitHub ships **enterprise managed
permissions for agent operations** (changelog 2026-09-09): admins centrally block, require human
approval for, or auto-allow shell commands, file reads/edits, and network domains; restrictions
cannot be weakened by user/workspace settings, and different teams get different policies. GA in
Copilot app, CLI, and VS Code Agent Host sessions.

Why companies use it: permissive developer tooling without opening the security model;
allowlist-style agent control is exactly what ISO 27001 + data-class policies need. Adoption in
Europe is broad: TheirStack's detected-technology list counts ~3,050 companies using GitHub
Copilot in Europe, 401 in Germany, including IT services firms (SAP, Nagarro, Luxoft, PALO IT,
NTT DATA, Sopra Steria) [S] — the list is scraper-based, so treat numbers as order-of-magnitude,
not census.

- Fit for the kit: no — it is a licensed cloud IDE/CLI service provided by the company, not
  installable offline. The kit's job is to work *alongside* it (kit-sync already targets
  Copilot; agent-permission awareness belongs in the AGENTS.md/governance docs).
- Sources [P]: https://github.blog/changelog/2026-09-09-enterprise-managed-permissions-for-github-copilot-agent-operations/
  (2026-09-09); [S]: https://theirstack.com/en/technology/gitHub-copilot/europe (accessed 2026-09-25).

### Microsoft 365 Copilot (knowledge workers)

What it is: the Copilot add-on for Teams/Word/Outlook/Excel grounded in the user's M365 data.
Microsoft's 2026 guidance for a "secure, governed data foundation" is explicit: M365 E3/E5 +
Microsoft Purview + SharePoint Advanced Management; remediate overshared sites (DSPM risk
assessments, SAM content assessment), exclude sensitive content from Copilot grounding via
Purview DLP, enforce sensitivity labels and restricted access by default, monitor usage with
Insider Risk Management.

Why companies use it: it is the knowledge-worker AI layer the M365 shop already owns; the
governance pattern (label → exclude from grounding → monitor) is the template for any
RAG/knowledge tool.

- Fit for the kit: no as a module (licensed cloud service); yes as knowledge: the
  label/DLP/monitor pattern transfers to any local RAG the kit builds (see item 12 of the
  addition list).
- Source [P]: https://learn.microsoft.com/en-us/microsoft-365/copilot/configure-secure-governed-data-foundation-microsoft-365-copilot
  (accessed 2026-09-25).

### Azure OpenAI / enterprise model APIs

What it is: enterprise LLM APIs (Azure OpenAI, OpenAI Business, Google Vertex/Gemini, Anthropic
API) with contractual data handling (no training on your data), content filtering, and network
control. The kiba solutions article (Berlin AI consulting, 2026-04-15) states the German
decision rule plainly: for clients demanding "no US provider, no EU cloud" (law firms, tax
advisors, healthcare, government) the answer is self-hosted local models; for most other cases
**Azure OpenAI or another enterprise cloud is the pragmatic choice** [S].

Why companies use it: developer access to frontier capability with procurement-grade contracts,
while a data-class policy decides per data class which destination is allowed.

- Fit for the kit: no as a module; the kit's eval/gateway components must *speak* the
  OpenAI-compatible API so they work against whichever approved endpoint IT configures.
- Source [S]: https://kiba.berlin/articles/ollama-lokale-ki-unternehmen (2026-04-15).

### Self-hosted gateways and local runtimes (LiteLLM, Open WebUI, Ollama, Dify)

What it is:
- **LiteLLM** — OpenAI-compatible gateway: virtual keys, budgets/spend tracking, fallbacks,
  guardrails (incl. Presidio PII masking), request/response logging; the Enterprise edition adds
  SSO/SCIM, RBAC, audit logs, per-team log routing to Langfuse/LangSmith/Arize, team-level
  GDPR opt-out, self-hosted deployment ("no data leaves your environment").
- **Open WebUI** — self-hosted chat platform connecting any model (Ollama/OpenAI/Anthropic),
  RAG, SSO/RBAC/audit logs, on-prem/air-gapped deployment; exposes OpenAI- **and**
  Anthropic-compatible REST APIs (its `/api/v1/messages` endpoint works with Claude Code).
- **Ollama** — local model runtime ("Mini-OpenAI" on your own server); in German enterprise use
  it is the standard answer to "where does my data go?" — "it stays in the server rack, no
  internet egress" [S]; typically paired with vLLM for production throughput on GPU/K8s [S].
- **Dify** — agentic workflows + RAG platform; Community (Apache-2.0-derivative, Docker) and
  Enterprise (SSO/RBAC/audit, SOC 2 + ISO 27001, Helm) tiers, MCP marketplace.

Why companies use it: one internal endpoint that all tools talk to (OpenAI-compatible), with
budgets, masking, and audit at the gateway; for confidential data, local models close the loop
so nothing leaves the building.

- Fit for the kit: **yes, with size discipline.** All four are pip-installable and can run on a
  CPU laptop, but on 8–16 GB RAM only small models (≈1–4B quantized) are usable, and a full
  Open WebUI/Dify stack with PostgreSQL is heavy for a laptop. The kit-appropriate cut is a
  minimal local runtime (Ollama or llama.cpp) + LiteLLM as the OpenAI-compatible front door;
  see ranked addition 6.
- Sources [P]: https://docs.litellm.ai/docs/enterprise (accessed 2026-09-25);
  https://openwebui.com/ and https://docs.openwebui.com/reference/ ;
  [S]: https://kiba.berlin/articles/ollama-lokale-ki-unternehmen ;
  [S]: https://ayedo.de/en/posts/souverane-ki-warum-llms-vllm-ollama-self-hosted-sein-mussen/ ;
  [P]: https://dify.ai/ .

## 3. Prompt and skill libraries

### Central prompt registries

What it is: a versioned repository of prompt templates with access control and lifecycle
management. Reference implementation: **MLflow Prompt Registry** (Databricks docs, updated
2026-06-23) — Git-like versions with immutable snapshots, mutable aliases (`production`,
`staging`), non-engineers editing via UI, Unity Catalog access control and audit, lineage linking
prompts to experiments and evaluation results, framework-agnostic loading (LangChain,
LlamaIndex). Vendor platforms (e.g. InsightPrompts) sell the same idea as SaaS [S].

Why companies use it: prompts are production artifacts; versioning + alias promotion + eval
lineage is how teams ship prompt changes without breaking agents. The lighter sibling of the
same pattern — **agent skills as a library** — is now the de-facto open standard (agentskills.io:
a folder with `SKILL.md` metadata + instructions + scripts/references, loaded on demand,
cross-product reuse); the kit already implements this via `30-agent-setup` + `~/.agents/skills`.

- Fit for the kit: **yes.** A curated, git-versioned prompt/skill library with role-based
  templates and data-class labels fits the kit's existing source-of-truth design (ranked
  addition 7). It cannot replace a company registry if IT runs MLflow/W&B; it must degrade to
  plain files.
- Source [P]: https://docs.databricks.com/aws/en/mlflow3/genai/prompt-version-mgmt/prompt-registry/
  (updated 2026-06-23); [P]: https://agentskills.io/home (accessed 2026-09-25).

## 4. Agent instruction standards (AGENTS.md, skills, MCP)

### AGENTS.md

What it is: the open markdown convention giving coding agents project-specific guidance
(behavioral expectations, rules, constraints). Released by OpenAI (Aug 2025), donated to the
**Agentic AI Foundation (AAIF)** under the Linux Foundation on 2025-12-09 alongside MCP and
goose. The LF press release: AGENTS.md is adopted by 60,000+ open-source projects and agent
frameworks including Amp, Codex, Cursor, Devin, Factory, Gemini CLI, GitHub Copilot, Jules,
VS Code. The spec defines hierarchical scope (files in ancestor directories apply, accumulate,
local overrides ancestor, user instructions override AGENTS.md); a v1.1 proposal (issue #135)
adds optional YAML frontmatter and progressive disclosure (index → inject → load on demand).

Why companies use it: one readable file per repo works across every major harness; it is the
standard the kit's `kit-sync` already targets.

- Fit for the kit: already core (`30-agent-setup`); no gap, but the kit should keep tracking the
  AAIF spec (frontmatter/progressive disclosure) when it lands.
- Sources [P]: https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation
  (2025-12-09); https://github.com/agentsmd/agents.md ; https://github.com/agentsmd/agents.md/issues/135 .

### Agent skills (agentskills.io)

What it is: a lightweight open format for packaging procedural knowledge as folders
(`SKILL.md` with `name`+`description` frontmatter, plus optional scripts/references/templates),
loaded via progressive disclosure (metadata → instructions → resources). Cross-product: the same
folder works in Claude, and per the skills registry in other compatible agents.

Why companies use it: skills encode "how we do X here" (review checklists, data-class rules,
incident steps) as version-controlled, on-demand context — the 2025/26 successor to ad-hoc
prompt snippets, and the unit of reuse for enablement.

- Fit for the kit: already core (`source/skills/`, `~/.agents/skills`).
- Source [P]: https://agentskills.io/home (accessed 2026-09-25); AAIF press release above.

## 5. MCP servers in the enterprise

What it is: the Model Context Protocol (Anthropic, open-sourced Nov 2024; donated to the Linux
Foundation AAIF 2025-12-09) is the standard for connecting models to tools, data, and
applications. Scale per the LF launch: **10,000+ published MCP servers**, adopted by Claude,
Cursor, Microsoft Copilot, Gemini, VS Code, ChatGPT; deployed on AWS, Google Cloud, Azure.
The 2026 enterprise discussion is dominated by security:

- **CSA "Agentic MCP Security Best Practices" v1** (Cloud Security Alliance): 30+ CVEs filed
  Jan–Feb 2026 against MCP servers/clients/infra; worst: CVE-2025-6514 (CVSS 9.6) in the
  widely used `mcp-remote` proxy (~437,000 affected environments); 2025 incidents include
  cross-tenant exposure (Asana), prompt injection against the GitHub MCP server, unauthenticated
  RCE in MCP Inspector; by early 2026 ~7,000 internet-exposed MCP servers, roughly half without
  authentication. Prescribed controls: OAuth 2.1 + PKCE per the Nov 2025 MCP spec, tool-level
  (not just server-level) scopes, **verification of tool descriptions** (hash at registration,
  alert on change; scanning via Invariant Labs' open-source `mcp-scan` as pre-commit/CI step),
  a centralized versioned tool registry, and a governance process with security + business
  sign-off (target: one-week review cycle). Maturity is staged L1–L3.
- **12-point hardening checklist** (exploreagentic.ai, 2026-06-09): inventory every
  server/tool/credential; **default-deny allowlist** of servers and tools per agent/task;
  classify tools by blast radius (read-only / reversible / irreversible); human confirmation on
  irreversible actions; least-privilege, audience-bound (RFC 8707), short-lived tokens; sandbox
  server execution with egress allowlists; sanitize and bound tool outputs; pin and verify
  packages; put an **MCP gateway** in front (central auth, discovery, policy, logging).

Why companies use it: MCP is now the default integration path, so IT policy has to name which
servers are allowed, who approves new ones, and how high-impact tools require human approval.
The pattern to note for a 150-person ISO 27001 firm: allowlist + blast-radius classification +
human gate + gateway — the same shape as GitHub's managed agent permissions (§2).

- Fit for the kit: **yes** (ranked addition 3): a user-level MCP client-configuration module
  with default-deny allowlist, blast-radius tags, and approval rules for the harnesses
  actually installed; the kit's own `brain mcp` server is the example of a safe local server.
  Nothing here needs GPU or cloud; all controls are local files + CLIs.
- Sources [P]: https://labs.cloudsecurityalliance.org/agentic/agentic-mcp-security-best-practices-v1/
  (accessed 2026-09-25); [S]: https://www.exploreagentic.ai/insights/mcp-server-security-hardening/
  (2026-06-09); [P]: LF AAIF press release (2025-12-09, §4).

## 6. Evaluation and benchmark tooling

Three distinct layers are in common enterprise use in 2026:

- **promptfoo** — CLI/CI LLM evaluation + red-teaming. Enterprise tiers: hosted SaaS or
  **Enterprise On-Prem with a dedicated runner behind the firewall** (network isolation, RBAC,
  teams, remediation suggestions, export to existing tools); works against any live LLM
  application, agent, or foundation model. The on-prem runner is the answer to "evals must not
  send our prompts/cases to a third party" [P].
- **Inspect** — open-source (MIT) evaluation framework from the UK AI Security Institute and
  Meridian Labs; prompt engineering, tool use, multi-turn dialog, model-graded scoring;
  200+ pre-built evaluations runnable on any model; the reference framework for agentic/safety
  evaluations in the public sector [P].
- **lm-evaluation-harness (EleutherAI)** — the academic standard: 60+ standard benchmarks with
  hundreds of subtasks; Dec 2025 release refactored the CLI (`run`/`ls`/`validate`, YAML
  config) and split model backends into extras (`lm_eval[hf]`, `[vllm]`); backend of the
  Hugging Face Open LLM Leaderboard; used internally by NVIDIA, Cohere, BigScience, Nous,
  Mosaic ML — i.e. it is what model teams use to compare models, not applications [P].

Why companies use it: the 2026 norm for "which model, which prompt" decisions is an eval gate:
application-level (promptfoo/Inspect-style, on the real task), model-level (lm-eval-style
benchmarks), both feeding the use-case decision. For an internal tooling shop, the practical
pattern is a lightweight in-house eval runner on top of these open formats, pointed at
whichever endpoints IT approved.

- Fit for the kit: **yes, partially already** — `50-eval` (evalkit) covers the in-house runner
  (YAML suites, graders, N repetitions, cost/latency). The gap the research exposes is a
  *standard-suite layer*: prebuilt promptfoo/Inspect-compatible case packs and a
  benchmark pack for model comparison via the OpenAI-compatible local endpoint (ranked
  addition 9). All three tools are Python/Node CLIs, fine offline on CPU.
- Sources [P]: https://www.promptfoo.dev/docs/enterprise/ (2026-09-03);
  https://github.com/UKGovernmentBEIS/inspect_ai + https://inspect.aisi.org.uk/ ;
  https://github.com/EleutherAI/lm-evaluation-harness (release notes accessed 2026-09-25).

## 7. LLM observability

What it is: tracing/monitoring for LLM applications — calls, tokens, cost, latency, prompt/response
content, quality scores. The 2026 market, per a buyer's guide (May 2026, secondary):
**Langfuse** (MIT, self-host full parity) was acquired by **ClickHouse in Jan 2026** during its
$400M Series D; v3 ships ClickHouse-backed analytics, prompt experiments, Datasets v2 — license
and self-host story stayed. **Arize Phoenix** (Elastic License 2.0, free self-host) is the
OpenTelemetry-native, framework-neutral option (OpenInference auto-instrumentors). **LangSmith**
(proprietary, LangChain/LangGraph-first, from $39/seat/mo) is the default inside LangChain
shops; self-host only on Enterprise. **Helicone** (Apache-2.0 HTTP proxy, zero-code) was
acquired by Mintlify Mar 2026 and is in maintenance mode *uncertain: single secondary source*.
Underneath all of it: **OpenTelemetry GenAI semantic conventions** — Langfuse's OTLP endpoint
(`/api/public/otel`) and OpenLLMetry/OpenLIT extend OTel tracing to Java/Go and frameworks like
Semantic Kernel and AutoGen [P for the Langfuse part].

Why companies use it: cost control, quality regression detection, and the audit trail a
compliance environment needs ("what did the model see and output"). The self-hostable,
OTel-native options (Langfuse, Phoenix) are the credible picks where data may not leave the
premises; the OTel convention matters because it means instrumentation is vendor-neutral.

- Fit for the kit: **partially.** A full Langfuse/ClickHouse or Phoenix backend is too heavy for
  an 8 GB laptop. What fits: emitting **OTel GenAI spans** from the kit's tooling (eval runs,
  agent sessions) to a local file/collector, so the same instrumentation works against whatever
  backend the company runs later (ranked addition 5). CPU-only, no GPU, small Python package.
- Sources [S]: https://ctaio.dev/en/labs/agentic-orchestration/compare/langsmith-vs-helicone-vs-phoenix-vs-langfuse/
  (2026-05-22; acquisition facts single-source, flagged uncertain);
  [P]: https://langfuse.com/integrations/native/opentelemetry (accessed 2026-09-25).

## 8. AI use-case intake and portfolio

What it is: a standing process that turns "AI ideas" into a governed portfolio. Two 2026
reference descriptions agree on the shape [S for both — consulting blogs, not one company's
internal doc]:

- **Concept-LAB "AI Use Case Portfolio"**: six disciplines — structured intake,
  multi-dimensional scoring (Value, Feasibility, Risk, Reusability on a 5-point scale, min
  composite 2.5 to advance), prioritised investment selection, stage-gate governance,
  **inventory of all AI systems in the estate**, platform coordination for reuse. Five-stage
  funnel: Ideation (intake template + EU AI Act prohibited-practices triage) → Assessment
  (scoring workshop, ~90 min, EU AI Act risk classification) → Pilot (time-boxed 6–12 weeks
  against defined success criteria on real data) → Production Build (documentation + human
  oversight are hard gates) → Operations (quarterly review, value tracking, decommissioning
  trigger). Anti-pattern named: "pilot purgatory". Context stats it cites: McKinsey 2024 State
  of AI (~72% of orgs use AI in ≥1 function, <30% captured significant value); Deloitte 2024
  (67% planned increased AI investment). The EA function owns it, not project management.
- **dsstream "AI Use Case Pipeline"** (2026-09-01): intake is **a form, not a meeting** — open
  to anyone, answered within two weeks, ~6 fields; funding released stage by stage with **written
  kill criteria**; return measured against a baseline captured *before* the build; cites MIT
  NANDA: >50% of genAI budgets go to visible functions (sales/marketing) while stronger returns
  sat in back-office automation.

Why companies use it: portfolio discipline is the identified root cause of the value gap; for
an ISO 27001 firm the AI system inventory doubles as the compliance register (which systems
exist, risk tier, data classes, owners) that the EU AI Act enforcement from Aug 2026 forces.

- Fit for the kit: **yes** (ranked addition 4): the intake form, 4-dimension scoring sheet,
  stage gates, and inventory register as brain-backed templates — zero compute, pure Markdown +
  the existing `brain` CLI, which is the kit's knowledge layer. This is the management half of
  the student's actual job ("find AI use cases").
- Sources [S]: https://www.concept-lab.be/blog/ai-use-case-portfolio-scoring (accessed 2026-09-25);
  https://www.dsstream.com/post/ai-use-case-pipeline (2026-09-01);
  [P] for the regulatory driver: EU AI Act timeline (§1).

## 9. Enablement and training for non-technical staff

What it is: the 2026 formats that recur across sources:

- **Role-based, workflow-anchored workshops** — separate curricula per function (finance,
  client-facing, plant, executives), exercises built on the team's *actual* tools, documents,
  and data policy rather than generic demos; weekly cadence with assignments; completion
  assessment + certificate; a **train-the-trainer "champions" track** that leaves delivery
  notes, Q&A scripts, and a facilitator guide with the company; adoption tracked via
  confidence/usage/saved-hours metrics (ReadyIQ, vendor example [S]).
- **Free vendor academies** — Microsoft's Power Up program ran exactly this pattern (free,
  self-paced, cohort-based, no technical experience required, tracks from 1-hour intro to
  multi-week paths, incl. building first agents in Copilot Studio). **Status: no longer
  accepting registrations; site and assets retired 31 Aug 2026**, with a transition guide to
  the Copilot/Copilot Studio curriculum [P]. Microsoft maintains a standing "AI Skills"
  resources page for skilling links [P].
- **Regulatory floor** — EU AI Act Art. 4 (see §1): the duty exists since 02 Feb 2025 and
  enforcement support starts with the Aug 2026 milestone; the Commission Q&A is explicit that
  training must be adapted to target group, sector, and system risk — "no one size fits all",
  and merely pointing staff at the vendor's instructions may not suffice.

Why companies use it: adoption is the failure mode, not model quality; internal champions and
role-based practice are the documented adoption levers, and Art. 4 makes *some* documented
literacy measure a legal duty for deployers.

- Fit for the kit: **yes** (ranked addition 8): a workshop pack — facilitator guide, role-based
  curriculum outline, Art.-4-compliant session plan, completion-assessment and prompt-starter
  templates — all plain Markdown/slides, buildable offline with the existing `90-design`
  tooling; it is content, not compute.
- Sources [P]: https://powerup.microsoft.com/ (retirement notice, accessed 2026-09-25);
  https://www.microsoft.com/en-us/corporate-responsibility/ai-skills-resources ;
  [S]: https://www.readyiq.ai/services/team-training (vendor, accessed 2026-09-25);
  [P]: Commission AI-literacy Q&A (§1).

## 10. AI tools for legacy code

What it is: two distinct tool classes in 2026 enterprise modernization:

- **Managed modernization agents (single-stack)** — Microsoft's GitHub Copilot "upgrade" agent
  (Microsoft Learn): managed end-to-end scenarios — .NET Framework → .NET 8/9/10, SDK-style
  conversion, Newtonsoft.Json → System.Text.Json, SqlClient → Microsoft.Data.SqlClient, Azure
  Functions in-process → isolated, **WebForms → Blazor**, plus a separate Azure-migration agent
  (database, storage, identity, messaging) — each scenario runs assessment → recommendations →
  fixes → build/test validation, across VS, VS Code, Copilot CLI, and GitHub.com; C# and Visual
  Basic project types covered [P].
- **Deterministic reverse engineering + agent forward engineering (stack-agnostic)** — AWS
  Transform for mainframe (product + 2026-05-08 workflow blog with Claude Code): two patterns —
  *Refactor* (automated deterministic COBOL→Java, architecture preserved) and *Reimagine*
  (extract structured business rules, data lineage, data dictionary from millions of lines of
  COBOL/PL/I/JCL, then forward-engineer new microservices with an agentic coding tool, any
  target stack). The documented workflow is deliberately human-gated: extracted specs must be
  **validated by application experts before code generation**, then code review, automated +
  integration + UAT before production; steering is carried in CLAUDE.md/skills files; the
  service integrates via MCP with existing IDEs/pipelines, with traceability from every
  generated line back to original source [P].

Why companies use it: software modernization firms may offer exactly this
in 2026: AI compresses assessment + extraction, while the sellable trust is determinism,
traceability, and human validation gates — "not a task you can solve by pointing a
general-purpose agent at a repository".

- Fit for the kit: the *static-analysis* layer already exists (`11-legacy-toolbox`: ctags,
  tree-sitter, scc, semgrep, dependency graphs). The research-backed gap is the **AI-assisted
  workflow layer on top of it** (ranked addition 10): skills implementing
  assess → characterize → spec (with HITL gates) → migration plan, reusable across harnesses,
  working on local code. No cloud dependency for the analysis side.
- Sources [P]: https://learn.microsoft.com/en-us/dotnet/core/porting/github-copilot-app-modernization/overview
  (accessed 2026-09-25);
  https://aws.amazon.com/blogs/migration-and-modernization/reimagining-mainframe-applications-with-aws-transform-and-claude-code/
  (2026-05-08); https://aws.amazon.com/transform/mainframe/ .

## 11. Document and knowledge tools

What it is: the enterprise RAG/knowledge layer. Market comparison (April 2026, vendor-published,
10 tools [S]): Glean (permission-aware search across 100+ apps, the default enterprise AI
search), Guru (human-verified knowledge cards for revenue/CS), Confluence/Atlassian
Intelligence, Notion AI (fastest time-to-value, weakest governance), Document360, Bloomfire,
plus open frameworks (LlamaIndex, Haystack, LangChain) and vector DBs (Pinecone managed,
Weaviate open-source hybrid search). Its cross-cutting finding: **no reviewed tool certifies
its source data** — source quality/governance is the universal gap, and RAG market growth is
cited at 44.7% CAGR through 2030. Self-hosted platforms (Open WebUI, Dify — §2) close the
sovereignty loop; the Microsoft-365 default is the Purview/SAM-governed Copilot grounding over
SharePoint/OneDrive/Exchange (§2).

Why companies use it: knowledge workers live in documents; grounded answers with citations and
*permission-aware* retrieval are the expected feature, and ISO 27001 shops add the label/
exclusion/monitor layer from §2.

- Fit for the kit: **yes, in two tiers.** Personal tier: the kit already has it — `20-brain`
  (hybrid search over Markdown, MCP server, git-backed). Company tier (only if IT allows): a
  local document Q&A over ingested, *approved* documents with the same label/exclusion logic,
  exported as an MCP server (ranked addition 12). Embeddings on CPU (the kit's chosen
  ONNX models) make both tiers offline-capable.
- Sources [S]: https://atlan.com/know/llm-knowledge-base-tools/ (2026-04-07, vendor-published
  comparison — directionally useful, numbers unverified); [P]: M365 governed-data-foundation
  doc (§2); [P]: Open WebUI/Dify (§2).

## 12. Meeting and transcription policies

What it is: the M365/Teams policy surface (Microsoft Learn, German edition — the relevant
language for a German firm): transcription is controlled by the admin's `CsTeamsMeetingPolicy`
`-AllowTranscription`; per meeting, the organizer sets Copilot to **"only during the meeting"**
(realtime speech-to-text data, **not stored after the meeting**), **"during and after"**
(starts a stored transcript), or **"Off"** (also disables recording). Default policy values
range from "Enabled, transcript required" (organizer cannot change it) to "Off"; Copilot
prompts/answers in meetings may still be retained under **Microsoft Purview retention
policies** even with recording off; Copilot is unavailable in end-to-end-encrypted meetings.

Why companies use it: in Germany the combination of GDPR (special rules for recording
conversations), the works council (Betriebsrat co-determination over employee monitoring), and
ISO 27001 makes transcription a *policy* topic before it is a feature: who may transcribe,
what is retained, who is told, what is stored. The M365 controls above are the mechanism such
policies are implemented with.

- Fit for the kit: **yes** (ranked addition 11): a short meeting-AI policy template (consent,
  retention, what may be transcribed, works-council note as `TODO(ask IT)`) plus the
  local-capture path — the kit's `80-quassel` (whisper.cpp, CPU) already does offline
  speech-to-text; extending it from dictation to "record meeting locally → transcript →
  meeting notes in brain" keeps the audio on the laptop. No cloud, no camera, CPU-only.
- Sources [P]: https://learn.microsoft.com/de-de/microsoftteams/copilot-teams-transcription and
  https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription (both verified
  200, accessed 2026-09-25).

## Ranked additions to the kit (not in SPEC.md)

Ranked by expected value to a working student "AI & Innovation" at a 150-person ISO 27001 /
M365 software-modernization firm, first weeks in, 20 h/week, on the offline CPU laptop. "Fits"
refers to the hard constraints: English, offline install, CPU-only, user-level, no secrets.

1. **`13-ai-gov`: internal AI usage guideline module.** Marked-up policy template (scope,
   allowed destinations per data class, human-review rule, approval workflow, incident duty,
   Art. 4 literacy duty, ISO 42001-style deployer checklist) with `TODO(ask IT)` values,
   strictest defaults — same shipping pattern as `40-data-guard/data-classes.md`. Research:
   §1. Why first: it is the document IT will ask for day one and the one that protects the
   student; zero compute.
2. **Use-case intake + portfolio in the brain (`ai-use-case-intake` skill + templates).**
   Intake form (~6 fields, 2-week SLA), 4-dimension scoring sheet (value/feasibility/risk/
   reusability), stage gates with written kill criteria, pre-build baseline, portfolio list
   command over brain notes. Research: §8. The management half of his job.
3. **`13-mcp-gov` (or extension of `30-agent-setup`): MCP client governance.** User-level MCP
   client configuration per installed harness: default-deny allowlist, blast-radius tags
   (read / reversible / irreversible), human-confirmation rule for irreversible tools,
   version-pinned local servers (brain as the shipped example). Research: §5 (CSA L1–L3).
4. **AI system inventory register (brain-backed).** One Markdown register: system, provider,
   model, destination, risk tier, data classes, purpose, owner, status — plus an `ai-inventory`
   skill that keeps it current and flags EU AI Act tier changes. Research: §1/§8. Compliance
   duty from Aug 2026, trivial offline.
5. **`14-llm-otel`: lightweight LLM usage capture.** OTel GenAI-semantic-convention spans from
   evalkit runs and agent sessions, token/cost/latency capture, export to local file (or a
   company-approved collector/backend); no ClickHouse/Phoenix backend on the laptop. Research:
   §7. Makes "measured, not estimated" claims possible for every experiment he runs.
6. **`15-local-llm`: optional local inference.** Ollama or llama.cpp (CPU) + one or two
   quantized 1–4B models from `offline/models/`, exposed as an OpenAI-compatible endpoint
   (LiteLLM front door) for confidential-data experiments; clearly optional, RAM-guarded
   (8 GB works: small models only). Research: §2 (kiba/ayedo patterns). The kit's differentiator
   for "data that must not leave the building".
7. **Prompt library (in `30-agent-setup` source, versioned).** Role-based prompt/skill templates
   (non-technical staff, developers, management) with variables, data-class labels, and
   retirement markers — the MLflow-registry pattern reduced to git + brain. Research: §3.
   Feeds #8 directly.
8. **Enablement workshop pack (skill `ai-enablement` + templates).** Facilitator guide,
   role-based curriculum outline, Art.-4-compliant session plan, train-the-trainer track,
   completion-assessment template, starter prompt pack; offline-buildable with `90-design`.
   Research: §9 (Power Up pattern, pre-retirement). Phase 2 already names an enablement skill;
   this is the *delivery content* around it.
9. **Model/harness comparison suite (extension of `50-eval`).** Standardized evalkit YAML packs
   (promptfoo/Inspect-compatible cases; lm-eval-style benchmark subset) runnable against any
   OpenAI-compatible endpoint — local `15-local-llm` or IT-approved cloud — producing the
   side-by-side model comparison reports the phase-2 eval skill will consume. Research: §6.
10. **Modernization workflow pack (skills over `11-legacy-toolbox`).** assess → characterize →
    spec-with-HITL-gate → migration-plan skills, encoding the AWS Transform / Copilot-upgrade
    pattern (deterministic analysis first, human spec validation, traceability) in
    harness-agnostic form. Research: §10. Directly his industry.
11. **Meeting-AI policy + local capture (policy doc + `16-meeting-capture`).** Consent/retention
    template with works-council `TODO(ask IT)`; local record → whisper.cpp transcript → notes
    in brain (extends `80-quassel` runtime, no new cloud). Research: §12.
12. **Document Q&A over approved company documents (`17-doc-qa`, optional, IT-gated).** Local
    ingestion (reuse `20-brain ingest`), label/exclusion gate mirroring the Purview pattern,
    CPU hybrid search, exposed as MCP server + chat CLI; ships disabled until IT approves a
    document scope. Research: §11. Highest privacy exposure → ranked last despite high
    usefulness.

**Not added (considered, rejected):** full Langfuse/Phoenix backend (too heavy for 8 GB,
§7); Docker-based Open WebUI/Dify stacks (no-sudo constraint, §2); Glean/Notion-class SaaS
(not installable, not portable); consumer tool allowlists beyond MCP (IT decides, not the kit).

## Sources (all accessed 2026-09-25)

1. Commission, AI Literacy Q&A — https://digital-strategy.ec.europa.eu/en/faqs/ai-literacy-questions-answers [P]
2. Commission, EU AI Act implementation timeline — https://ai-act-service-desk.ec.europa.eu/en/ai-act/timeline/timeline-implementation-eu-ai-act [P]
3. Deutscher Steuerberaterverband, Muster-KI-Anwendungsrichtlinie (04/2026) — https://lswb.bayern/api/blob/jJpjANojMMncQ6lTOXfObYkbkDJkzPvstiE/e8Cmc4GuATOP+zQmRHeSjHLjgmuBdcMgyIcJI8PckSrYf2PoMPWC1IGEPfJwuysrpO/96Q6kgY6pC4qMBgaUJoAKmCxiRAFzl4nyE+bsifM7YKYWxNyafPQWIlVAF84ktktKp8qI/muster-ki-anwendungsrichtlinie-04-26.pdf [P]
4. BSI, KI topic page — https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Informationen-und-Empfehlungen/Kuenstliche-Intelligenz/KI.html [P]
5. BMI, Leitlinien für den Einsatz KI in der Bundesverwaltung — https://www.bmi.bund.de/SharedDocs/downloads/DE/publikationen/themen/moderne-verwaltung/ki/BMI25020-leitlinien-ki-bundesverwaltung.html [P]
6. SGS, Xayn ISO/IEC 42001 (2025-06-02) — https://www.sgs.com/en/news/2025/06/xayn-is-the-first-german-company-to-receive-iso-iec-42001-certification [P]
7. DQS/Idest, ISO/IEC 42001 DACH (2026-05-06) — https://www.kurierverlag.de/na-pressemitteilungen/idest-gmbh-unter-den-ersten-unternehmen-im-deutschsprachigen-raum-mit-dqs-zertifizierung-nach-iso-iec-42001-it-beratungsunternehmen-setzt-meilenstein-zr-94294311.html [P]
8. GitHub Changelog, enterprise managed permissions for Copilot agents (2026-09-09) — https://github.blog/changelog/2026-09-09-enterprise-managed-permissions-for-github-copilot-agent-operations/ [P]
9. Microsoft Learn, M365 Copilot governed data foundation — https://learn.microsoft.com/en-us/microsoft-365/copilot/configure-secure-governed-data-foundation-microsoft-365-copilot [P]
10. LiteLLM Enterprise docs — https://docs.litellm.ai/docs/enterprise [P]
11. Open WebUI — https://openwebui.com/ ; https://docs.openwebui.com/reference/ [P]
12. TheirStack, GitHub Copilot in Europe — https://theirstack.com/en/technology/gitHub-copilot/europe [S]
13. kiba solutions, Ollama im Unternehmen (2026-04-15) — https://kiba.berlin/articles/ollama-lokale-ki-unternehmen [S]
14. ayedo, Sovereign AI vLLM/Ollama — https://ayedo.de/en/posts/souverane-ki-warum-llms-vllm-ollama-self-hosted-sein-mussen/ [S]
15. Dify — https://dify.ai/ [P]
16. Databricks/MLflow Prompt Registry docs (2026-06-23) — https://docs.databricks.com/aws/en/mlflow3/genai/prompt-version-mgmt/prompt-registry/ [P]
17. Linux Foundation, Agentic AI Foundation press release (2025-12-09) — https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation [P]
18. AGENTS.md — https://github.com/agentsmd/agents.md ; v1.1 proposal https://github.com/agentsmd/agents.md/issues/135 [P]
19. Agent Skills — https://agentskills.io/home [P]
20. CSA, Agentic MCP Security Best Practices v1 — https://labs.cloudsecurityalliance.org/agentic/agentic-mcp-security-best-practices-v1/ [P]
21. exploreagentic.ai, MCP server security hardening (2026-06-09) — https://www.exploreagentic.ai/insights/mcp-server-security-hardening/ [S]
22. Promptfoo Enterprise — https://www.promptfoo.dev/docs/enterprise/ (2026-09-03) [P]
23. Inspect (UK AISI) — https://github.com/UKGovernmentBEIS/inspect_ai ; https://inspect.aisi.org.uk/ [P]
24. lm-evaluation-harness (EleutherAI) — https://github.com/EleutherAI/lm-evaluation-harness [P]
25. ctaio.dev, 2026 LLM observability buyer's guide (2026-05-22) — https://ctaio.dev/en/labs/agentic-orchestration/compare/langsmith-vs-helicone-vs-phoenix-vs-langfuse/ [S]
26. Langfuse, OpenTelemetry integration — https://langfuse.com/integrations/native/opentelemetry [P]
27. Concept-LAB, AI Use Case Portfolio scoring — https://www.concept-lab.be/blog/ai-use-case-portfolio-scoring [S]
28. dsstream, AI use case pipeline (2026-09-01) — https://www.dsstream.com/post/ai-use-case-pipeline [S]
29. Microsoft Power Up (retirement notice) — https://powerup.microsoft.com/ [P]
30. Microsoft AI Skills resources — https://www.microsoft.com/en-us/corporate-responsibility/ai-skills-resources [P]
31. ReadyIQ, team training (vendor) — https://www.readyiq.ai/services/team-training [S]
32. Microsoft Learn, GitHub Copilot modernization overview — https://learn.microsoft.com/en-us/dotnet/core/porting/github-copilot-app-modernization/overview [P]
33. AWS, Transform for mainframe + Claude Code (2026-05-08) — https://aws.amazon.com/blogs/migration-and-modernization/reimagining-mainframe-applications-with-aws-transform-and-claude-code/ ; product https://aws.amazon.com/transform/mainframe/ [P]
34. Atlan, LLM knowledge base tools comparison (2026-04-07) — https://atlan.com/know/llm-knowledge-base-tools/ [S]
35. Microsoft Learn (de/en), M365 Copilot in Teams meetings — https://learn.microsoft.com/de-de/microsoftteams/copilot-teams-transcription ; https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription [P]
