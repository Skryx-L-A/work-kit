# Automation levels, gate patterns, metrics

Load when choosing automation levels, placing gates or defining metrics.

## Automation levels per step

| Level | Name | AI does | Human does | Allowed for |
|---|---|---|---|---|
| 0 | Manual | nothing | everything | any step |
| 1 | Assist | answers questions, suggests on request | does the step, decides | any step with an approved tool |
| 2 | Draft | produces a complete draft | reviews every draft, edits, releases | outputs to customers or decisions: this is the highest level by default |
| 3 | Act with approval | prepares the action (mail, ticket change, commit) | approves each action before it runs | reversible internal actions; irreversible ones only with explicit sign-off of the owner |
| 4 | Act with sampling | acts; humans review a sample and all flagged cases | samples, handles exceptions, audits | internal, reversible, low-impact steps with a measured error rate; never for customer-facing output, decisions about people or irreversible actions |

Start one level lower than feels possible and raise a level only after the metrics show it
(for example 4 weeks with zero escaped errors and a stable gate rejection rate).

## Gate patterns

| Pattern | Use when | Watch out for |
|---|---|---|
| Release gate: human approves every output | anything leaving the team, customer-facing text, decisions | rubber-stamping: budget the time, measure rejection rate (0 % for weeks is a warning sign) |
| Four-eyes: second person for high impact | contract text, prices, security-relevant changes, deletions | both reviewers assume the other checked; give each a distinct check |
| Checklist gate | repeatable checks (facts vs. source, completeness, data) | the list grows stale; review it with the workflow |
| Diff gate | AI changes existing content (code, documents, records) | review the change, not only the result; keep diffs small |
| Sampling gate | level 4 only | sample size and selection defined in advance; flagged cases always reviewed |
| Automatic pre-checks before the human | format, schema, forbidden content, data guard, empty output | automatic checks support the human gate, they do not replace it |
| Stop gate | error thresholds, tool or approval change | somebody must actually watch the numbers; name them |

Never gate-free: sending to customers, deleting or changing records of record, payments,
deployments to production, anything about individual people (hiring, performance,
monitoring). Decisions about people are not automated at all.

## Metrics

Measure the whole workflow, not only the AI step. Take the baseline before the change.

| Metric | Definition | Note |
|---|---|---|
| Lead time | trigger to finished output, per case | median and 90th percentile |
| Hands-on time | person-minutes per case, including review at gates | the honest measure of time saved |
| Time saved per week | (baseline hands-on − new hands-on) × cases per week | review time included by definition |
| Gate rejection rate | outputs rejected or heavily edited at a gate / all outputs | too high: AI step not ready; near zero for long: check for rubber-stamping |
| Escaped errors | errors found after the gate (by customer, colleague, audit) | the key safety metric; each one is reviewed |
| Rework rate | cases that needed another pass after completion | compare with baseline |
| Adoption | cases handled via the workflow / all eligible cases | low adoption is a finding, not a failure to hide |
| Cost per case | tool licences, tokens, compute, per case | from the tool's usage report or local capture if available |
| Satisfaction | short survey of the people doing the work and, if possible, the recipients | 1 to 5 scale, same questions each time |

Pass and kill criteria are written before the pilot starts, for example: "continue if hands-on
time drops by 20 % with no escaped error to a customer; stop if any customer-facing error
escapes or rejection rate stays above 40 % after three weeks".
