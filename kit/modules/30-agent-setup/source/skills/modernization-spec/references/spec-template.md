# Spec item template

One file `spec.md` per scope. Item headings must start with `### <ID> ` (for example
`### BR-001 Late fee is capped`); `scripts/trace-check.sh` reads them.

```
# <System / capability> behavioral spec
Version: 1        Status: draft | in-review | validated | rejected
Code map: <link>  Commit: <sha>  Scope:  Out of scope:
Validator (role and name):

### BR-001 <short title>
Statement: given <inputs / state>, the system <does what>; result <output / side effect>.
Rules and formulas:            Error and edge cases:
Evidence: <file:line>, <test name>, [told by <role>]
Class: intended | accidental | defect | unknown
Target: keep | change | drop | defer      Rationale (required for change/drop/defer):
Open question (role): 
```

ID prefixes: `BR` business rule, `DM` data rule (schema, constraints, retention), `IF` interface
or file format, `BT` batch or scheduled behavior, `NF` non-functional behavior that is
observable (timeouts, limits, ordering). Never renumber released IDs; mark them dropped.
