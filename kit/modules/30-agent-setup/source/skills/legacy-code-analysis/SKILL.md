---
name: legacy-code-analysis
description: Build an evidence-based map of an unfamiliar or undocumented legacy codebase (entry points, modules, data stores, dependencies, hotspots, risks) before changing, estimating or modernizing it. Use when starting on a customer system you do not know, when documentation is missing or untrusted, or before a refactoring plan or modernization assessment. Do not use for a small fix in code you already understand, for reviewing a finished diff (use code-review), or for hunting one specific bug (use debugging-protocol).
---

# Legacy Code Analysis

Goal: a written map of the system that another engineer can check against the code. Every
statement in the map points to a file, a command output or a person. Guesses are labeled.

## Before you start

- Confirm scope with the requester: which repository, which modules, what decision the map
  must support (fix, estimate, refactoring, modernization, handover).
- Check the data class of the code and any sample data before sending anything to an AI
  model (see the `data-guard` skill). Customer code is usually not PUBLIC.
- Search earlier notes: `brain search "<system name>" --project <slug>`. If `brain` is not
  installed, ask the team for existing documentation and continue.
- Work read-only. Do not build, run migrations or start services against shared or customer
  environments to "see what happens".

## Procedure

1. **Inventory.** List languages, build systems, file counts and sizes per top-level folder.
   Useful commands: `git ls-files | sed 's/.*\.//' | sort | uniq -c | sort -rn`,
   `rg --files | wc -l`, `du -sh */`. Note generated or vendored code and exclude it later.
2. **History.** If the repository has history: age, active authors, and change hotspots.
   `git log --since=2.years --name-only --format= | sort | uniq -c | sort -rn | head -30`.
   Files that change often and are large or complex are the risk hotspots
   (see references/sources.md, "code as a crime scene").
3. **Entry points.** Find how the system starts and is invoked: `main` functions, web routes,
   scheduled jobs, message consumers, stored procedures called from outside, CLI scripts,
   batch files, cron tables, installer scripts. List each with its file and line.
4. **Data.** Identify every data store and how it is accessed: connection strings (do not copy
   credentials), ORM mappings, raw SQL, stored procedures, triggers, file-based exchange
   (CSV, fixed-width, XML), queues. Business logic hidden in the database counts as code.
5. **Dependencies.** External libraries with versions (manifest files, vendored jars/dlls),
   runtime and OS versions, integrations with other systems (URLs, host names, shares).
   Flag end-of-life runtimes and libraries without a maintained upstream.
6. **Structure.** Sketch module boundaries and the call/dependency direction between them.
   Prefer tool output (import graphs, `rg "import|using|#include"`) over reading intuition.
   Note cycles and "god" modules that everything depends on.
7. **Behavior samples.** Trace two or three important business flows end to end, from entry
   point to data store, with file:line references. These become candidates for
   characterization tests (see `characterization-tests`).
8. **Tests and build.** What tests exist, do they run, how long, what do they cover? Can the
   system be built locally from a clean checkout? Record exact commands and results.
9. **Risks and unknowns.** List what you could not determine, dead-looking code you did not
   prove dead, and questions for people who know the system.
10. **Write the map** using the template below and save it: `brain new reference
    "<system>: code map" --project <slug> --body -`. Without `brain`, save it as
    `docs/code-map.md` in the working repository or hand it to the requester.

## Tools

Optional kit CLIs (modules `11-legacy-toolbox`, `12-docs-tools`). Check each with
`command -v <tool>`; if it is missing, use the fallback and say so in the map.

| Step | Tool | Fallback |
|---|---|---|
| 1 Inventory | `scc .` (files, lines, complexity per language) | `git ls-files` counts, `du -sh */` |
| 3 Entry points | `ctags -R --output-format=json .`, `tree-sitter parse <file>` | `rg -n -e "main\(" -e RequestMapping -e cron` |
| 6 Structure | `kit-depgraph . --format d2 > deps.d2`, then `d2 deps.d2 deps.svg` | `rg -e "^import" -e "^using" -e "#include"` and a hand-made list |
| 5, 9 Risks | `kit-semgrep <dir>` (local rules, no network) | read the risky spots, `rg` for dangerous calls |

Tool output is evidence to check, not a result. `kit-depgraph` reads explicit imports only
(no reflection, no same-package references); `kit-semgrep` findings are leads.

## Map template

```
# <System> code map (<date>, commit <sha>)
Scope and purpose of this map:
Inventory: languages, size, build, generated/vendored parts
Entry points: <kind> <file:line> <what it does>
Data stores and access paths:
External dependencies and integrations (versions, EOL flags):
Module structure and dependency direction (diagram or list):
Traced flows: <flow> -> <file:line> -> ... -> <table/file>
Tests and build status (commands, results):
Hotspots (change frequency x size/complexity):
Risks, unknowns, open questions (with who could answer):
Evidence labels: [verified] seen in code or output, [inferred], [told by <role>]
```

## Done when

- Every entry point, data store and integration found is listed with a file reference.
- At least two business flows are traced end to end.
- Build and test status is stated with the commands that were actually run.
- Unknowns and inferred statements are labeled, and the map names the commit it describes.
- The map is saved where the team can find it.

## Pitfalls

- Trusting old documentation or comments over the code. Record contradictions, do not resolve
  them silently.
- Declaring code dead because nothing in the repository calls it. Reflection, configuration,
  database jobs, reports and other systems may call it. Mark it "no caller found", not "dead".
- Reading the whole codebase linearly. Start from entry points and hotspots.
- Pasting large amounts of customer code or data into an AI tool without checking its data class.
- Running the system against production-like data or shared databases during analysis.
- Letting the map drift: always record the commit hash and date.

## Related skills

`characterization-tests` (pin down traced behavior), `refactoring-plan`,
`modernization-assessment`, `test-strategy`, `data-guard`.
Modernization chain (`modernization-workflow`): next step is `modernization-assessment`.
