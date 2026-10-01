<!-- AI use-case intake. Create with:
  brain new note "Use case: <short name>" --project ai-use-cases --tags ai-use-case --body - < intake-form.md
Anyone may submit; the six intake questions are enough. Answer within two weeks.
Record fields are "- key: value" lines; later gates append a "## Gate <date>" section with
changed lines (the last value counts). Replace every <...>; leave unknown fields out. -->
## Intake

1. Task: <what should get easier; input and output in one or two sentences>
2. Who does it today, how often, how long: <role; n per week; minutes each>
3. What a correct result looks like: <checkable criterion>
4. Data involved: <what data; class if known: PUBLIC | INTERNAL | CONFIDENTIAL | CUSTOMER>
5. Benefit if it works: <time, quality, speed, new capability; who benefits>
6. Contact: <name, team>

## Record

- stage: intake
- stage_since: <YYYY-MM-DD>
- submitted_by: <name, team>
- owner: <person who drives it; not the AI team by default>
- sponsor: <manager who funds the next stage>
- data_class: <PUBLIC | INTERNAL | CONFIDENTIAL | CUSTOMER | unknown>
- eu_ai_act: <no people decisions | limited (transparency) | possible high risk: escalate | prohibited: stop>
- next_gate: <YYYY-MM-DD, at most two weeks after submission>

## Triage (at intake)

- Prohibited practice (Art. 5 EU AI Act) or decisions about people? <no | yes: stop / escalate>
- Already solved by an approved tool or an existing use case? <no | yes: link>
- Well-defined (correct result checkable)? <yes | no: clarify first>
