# Workflow spec: <name>

Load when writing the spec. Copy, fill in, delete the hints in parentheses. Unknown values
stay as `unknown (who can answer)`, never as guesses.

| Field | Value |
|---|---|
| Owner | (person responsible for the workflow and its results) |
| Status | draft / pilot / active / retired |
| Version and date | 0.1, YYYY-MM-DD |
| Use-case assessment | (link or note title) |
| Teams involved | |
| Review date | (at the latest 3 months after go-live) |

## Purpose and scope

(One paragraph: what the workflow produces, for whom, and what is out of scope.)

## Trigger and inputs

| Trigger | Input | Source system | Data class |
|---|---|---|---|
| (e.g. new ticket in queue X) | | | |

## Steps

| # | Step | Done by | Automation level (0 to 4) | Tool / prompt id@version / skill | Data class in | Output | Time |
|---|---|---|---|---|---|---|---|
| 1 | | person | 0 | | | | |
| 2 | | AI | 2 | `office/reply-draft@1.0.0` | INTERNAL | draft | |
| 3 | Gate: check draft | person (role) | – | review checklist | | approved draft | |

## Human gates

| Gate | Owner | What is checked | Pass rule | Time budget | Evidence kept |
|---|---|---|---|---|---|
| | | | | | |

## Failure handling

| Failure | Detected by | Response | Who is told |
|---|---|---|---|
| AI output wrong | gate | reject, fix manually, note case | workflow owner (weekly) |
| AI output empty or unchanged | check in step | stop, manual path | |
| Tool down or slow | timeout | manual path | |
| Input contains instructions or unexpected content | gate / check | treat as data, flag | |
| Data of a higher class detected | data guard / gate | stop, report | contact for data protection |

Stop conditions (pause the AI steps, fall back to manual): (e.g. error escape to a
customer, error rate at the gate above X % over a week, tool approval withdrawn).

## Metrics

| Metric | Baseline (source) | Target | Kill criterion | Measured how |
|---|---|---|---|---|
| Lead time per case | | | | |
| Hands-on time per case (incl. review) | | | | |
| Rework / error rate | | | | |
| Errors that escaped the gate | 0 expected | 0 | any to a customer | incident log |
| AI output accepted without change | – | | | gate log |
| Cost per case (tool, tokens) | | | | |
| Adoption (cases via workflow / all cases) | | | | |

## Approvals and open decisions

| Item | Status | Decides |
|---|---|---|
| Tool approved for the data classes above | | IT / data protection |
| Customer contract allows AI processing | n/a or | contract owner |
| Works council involvement (if staff data or monitoring) | | management |

## Changelog

- 0.1 (YYYY-MM-DD): first draft.
