# Suite structure (sketch)

This shows the parts an evalkit suite has. Field names are illustrative: take the exact
names from the shipped examples or `evalkit --help`, which are authoritative.

```yaml
description: Explain legacy COBOL paragraphs for developers
providers:
  - id: model-a
    command: "<cli> -p {prompt}"          # shell provider, prompt substituted
  - id: local
    endpoint: http://localhost:11434/v1   # OpenAI-compatible HTTP provider
    model: <model-name>
prompt: |
  Explain what this COBOL paragraph does in 3 sentences. Name every file it reads.
  {input}
repeat: 3
cases:
  - id: read-customer-file
    input: "<synthetic COBOL snippet>"
    graders:
      - type: contains
        value: CUSTFILE
      - type: judge
        rubric:
          - Names the file that is read
          - Describes the loop condition correctly
          - Invents no variables that are not in the code
  - id: numeric-total
    input: "<snippet computing a total>"
    graders:
      - type: numeric
        expected: 1250.50
        tolerance: 0.01
```

Checklist per case: an `id` that says what it tests, input of an allowed data class, at
least one deterministic grader where possible, and a rubric of pass/fail criteria for
judged text.
