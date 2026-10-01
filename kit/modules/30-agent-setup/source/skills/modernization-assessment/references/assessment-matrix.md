# Assessment matrix

## Rating scales (1 = low, 5 = high)

| Dimension | 1 | 3 | 5 |
|---|---|---|---|
| Business value | rarely used, replaceable | used daily by one department | core revenue or legal duty |
| Change rate | untouched for years | a few changes per year | changes every sprint |
| Technical health (inverse risk) | no tests, huge complex files, frequent defects | partial tests, some hotspots | good tests, clear structure |
| Technology risk | current, supported stack | support ends within 2-3 years | end of life, unpatched, no skills available |
| Coupling | clear interface, own data | some shared tables | shared state everywhere |
| Knowledge | documented and known | known by one or two people | only in the code |

Record the evidence for each rating (file, metric, incident, interview).

## Options

The option names follow the widely used "R" migration strategies (Gartner's 5 Rs, extended by
AWS to 7 Rs); "rearchitect" and "rebuild" are split here because they differ in effort.

| Option | What it means | Typical fit |
|---|---|---|
| Retain | keep as is, maybe monitor | low change rate, low risk, good enough |
| Retire | switch off, archive data | low value, few users, functionality exists elsewhere |
| Rehost | move unchanged to new infrastructure | infrastructure is the problem, code is fine |
| Replatform | small changes to run on a new runtime, database or managed service | EOL runtime or database, logic still sound |
| Refactor | improve structure in place, same functionality | high change rate, poor health, logic valuable |
| Rearchitect | change architecture incrementally (split modules, new interfaces) | coupling blocks change or scaling |
| Rebuild | rewrite the component on a new stack, same scope | code unmaintainable and behavior well understood |
| Replace | buy or adopt a standard product | commodity functionality, customization low |

Rules of thumb:
- High value + high change rate + poor health: refactor or rearchitect incrementally.
- High technology risk + good logic: replatform before anything else.
- Low value: retire or retain; do not modernize for its own sake.
- Rebuild only when behavior is captured (characterization tests or a trusted specification)
  and the component can be cut over on its own.
