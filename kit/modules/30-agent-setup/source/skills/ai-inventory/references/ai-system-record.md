<!-- AI system inventory entry. Create with:
  brain new reference "AI system: <name>" --project ai-inventory --tags ai-system --body - < this-file
Fill every field; unknown values stay "unknown", never guessed. Later changes are appended
as a "## Change <date>" section with the changed "- key: value" lines (the last value of a
key counts), so the history stays in the note. -->
## Record

- system: <product or tool name>
- provider: <vendor, or "self-hosted" / "local">
- model: <model name and version, or "vendor default">
- kind: <chat | coding assistant | agent | API | feature in other software | local model | MCP server>
- destination: <where data goes: vendor cloud region, company tenant, laptop only>
- data_class: <highest allowed: PUBLIC | INTERNAL | CONFIDENTIAL | CUSTOMER>
- purpose: <the defined tasks it is used for>
- users: <teams or roles>
- owner: <one named person>
- eu_ai_act_role: <deployer | provider | none>
- risk_tier: <prohibited | high | limited | minimal | unknown>
- contract: <licence / data processing agreement reference, or "none">
- human_review: <who reviews outputs and how>
- status: <requested | approved | pilot | production | suspended | retired>
- approved_by: <name, or TODO(ask IT)>
- approved_on: <YYYY-MM-DD, or TODO(ask IT)>
- review_by: <YYYY-MM-DD>

## Notes

<Risks, restrictions, settings (for example "training on inputs disabled"), links to the
tool request, eval results and incidents.>
