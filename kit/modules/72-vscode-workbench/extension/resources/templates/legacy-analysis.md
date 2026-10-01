---
name: legacy-analysis
description: Map an unfamiliar legacy code base or module before planning changes
paths: analysis/
done: analysis/OVERVIEW.md covers structure, entry points, dependencies, data flow and risks with file references
skill: legacy-code-analysis
---
Analyze {{target}} and write `analysis/OVERVIEW.md`: purpose, structure, entry points, external
dependencies, data flow, build and test commands, and the riskiest areas for change. Reference
files as `path:line`. Do not change any code. Mark every statement you could not verify.
