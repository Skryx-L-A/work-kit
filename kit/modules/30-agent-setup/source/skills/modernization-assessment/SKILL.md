---
name: modernization-assessment
description: Assess a legacy system or module and recommend a modernization path per component (retain, retire, rehost, replatform, refactor, rearchitect, rebuild, replace) with evidence, risks, rough effort and an incremental roadmap. Use when a customer or team asks whether and how to modernize, when preparing an offer or estimate for modernization work, or when a technology is reaching end of life. Do not use for planning the steps of an already chosen refactoring (use refactoring-plan), for a single dependency version bump (use dependency-upgrade), or without access to the code or someone who knows it.
---

# Modernization Assessment

Output: a short decision document that a customer or project lead can act on. Every
recommendation traces back to evidence about the system and to the business driver.

## Inputs you need

- **Business drivers,** asked explicitly, not assumed: cost of operation, end-of-life risk,
  security or compliance findings, missing skills for the old stack, change speed,
  performance, integration or cloud requirements. Rank them with the requester.
- **Constraints:** budget frame, deadlines, regulatory rules, data residency, which parts
  must keep running, customer IT policies, team skills.
- **The system:** a code map (`legacy-code-analysis`), operating data if available (load,
  incidents, change frequency), and access to people who know it.
- Earlier assessments or decisions: `brain search "<system> modernization"`; if `brain` is
  missing, ask the team.

## Procedure

1. **Decompose.** Split the system into components that could take different paths: UI,
   business logic modules, batch jobs, interfaces, database, reporting, infrastructure.
2. **Rate each component** on a 1-5 scale with a one-line reason and evidence reference:
   - Business value and expected change rate.
   - Technical health: test coverage, complexity, hotspots, defect history.
   - Technology risk: end-of-life runtime, framework or database; unsupported vendor;
     security exposure; scarce skills.
   - Coupling: how hard it is to separate from the rest (shared tables, shared state).
   - Knowledge: documented, known by current staff, or only in the code.
   See references/assessment-matrix.md for scales and the option table.
3. **Choose an option per component** from the matrix (retain, retire, rehost, replatform,
   refactor, rearchitect, rebuild, replace with a product). State why the cheaper options
   are not enough. Retire and retain are valid and often the right answer.
4. **Check feasibility.** Data migration effort and quality, interfaces to other systems,
   parallel operation, licensing, hosting, test effort (a missing safety net is effort).
5. **Sequence incrementally.** Prefer a roadmap where each stage delivers value and leaves
   a working system (strangler fig over big-bang rewrite). Name the first stage concretely
   enough to start, later stages coarser.
6. **Estimate honestly.** Ranges with stated assumptions, not single numbers. Mark the
   largest uncertainties and propose cheap spikes to reduce them (a proof of concept,
   a data quality sample, a characterization test run).
7. **List risks and mitigations,** including organizational ones (knowledge holders leaving,
   customer acceptance, freeze periods).
8. **Write the document** (template below), have a human expert review it before it goes to
   a customer, and store it: `brain new decision "<system>: modernization path"
   --project <slug> --body -`, or in the project documentation if `brain` is missing.

## Tools

Optional kit CLIs (modules `11-legacy-toolbox`, `12-docs-tools`). Check each with
`command -v <tool>`; if it is missing, use the fallback and say so in the document.

| Use | Tool | Fallback |
|---|---|---|
| Size and complexity per component (effort ranges) | `scc <component dir>` | count `git ls-files <dir>` |
| Coupling between components (rating in step 2) | `kit-depgraph . --level dir --depth 2 --format d2` | `rg -e "^import" -e "^using" -e "#include"` across component borders |
| Security exposure indicator | `kit-semgrep <dir>` | `security-review` skill by hand |
| Diagrams and a Word copy for review | `d2 in.d2 out.svg`, `pandoc doc.md -o doc.docx` | keep Markdown, draw by hand |

Metrics and findings from tools are inputs to the ratings, not the ratings themselves.

## Document template

```
# <System> modernization assessment (<date>)
Drivers (ranked) and constraints:
Summary recommendation (3-5 sentences):
Component table: component | ratings | option | reason | evidence
Roadmap: stage | scope | value delivered | prerequisites | estimate range
Data migration and interfaces:
Risks and mitigations:
Assumptions and open questions (with owner):
Spikes proposed to reduce uncertainty:
```

## Done when

- Every component has an option, a reason and evidence; unknowns are labeled.
- The recommendation follows from the ranked drivers, and alternatives are addressed.
- The roadmap starts with a concrete, independently valuable first stage.
- Estimates are ranges with assumptions; biggest uncertainties have a proposed spike.
- A human expert has reviewed it before it is shared outside the team.

## Pitfalls

- Recommending a full rewrite by default. Rewrites lose undocumented behavior and take longer
  than planned; require a clear reason.
- Technology-first thinking ("move to microservices") without a driver that needs it.
- Ignoring the database: stored procedures, triggers and reports often hold core logic.
- Underestimating data migration and data quality work.
- Presenting AI-generated estimates or code metrics as facts without checking them.
- Sending customer code or documents to an AI tool that its data class does not allow
  (see `data-guard`).

## Related skills

`legacy-code-analysis`, `refactoring-plan`, `dependency-upgrade`, `security-review`,
`characterization-tests`. Sources: references/sources.md.
Modernization chain (`modernization-workflow`): next steps are `characterization-tests`, `modernization-spec`, `migration-plan`.
