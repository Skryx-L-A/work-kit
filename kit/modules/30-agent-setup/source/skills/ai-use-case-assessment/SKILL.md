---
name: ai-use-case-assessment
description: 'Assess whether a proposed AI use case is worth pursuing, safe to pursue and how to test it: task definition, data class, human review, business case, risks, and a minimal experiment. Use when someone suggests "we could use AI for X", when collecting or ranking use cases, or before building an AI prototype. Do not use for choosing between already-approved tools on technical grounds only (use decision-record) or for measuring a built prototype (use eval-design).'
---

# AI use case assessment

Company line for AI: only for well-defined tasks, every output reviewed by a human, a
business case is required, and data protection must be settled before real data is used.
This skill turns an idea into a one-page assessment that applies that line honestly.

## Procedure

1. **Define the task precisely.** Input, output, who does it today, how often, how long it
   takes, and how a correct result is recognized. If correctness cannot be stated, the task
   is not well-defined yet: stop and clarify (`grill-me`).
2. **Classify the data** that the AI would see (`data-guard` skill: PUBLIC, INTERNAL,
   CONFIDENTIAL, CUSTOMER). Name the allowed AI destinations for that class. If the class or
   the allowed destinations are unknown, the answer is "ask IT / data protection first".
3. **Design the human review.** Who checks each output, what they check, how long it takes.
   If review takes as long as doing the task, the case has no time benefit.
4. **Estimate the business case** with the formula in `references/assessment-template.md`:
   time saved minus review time, times frequency, minus tool cost and setup effort. Use
   ranges and say where each number comes from. Unknown is allowed; invented is not.
5. **List risks**: wrong output reaching a customer, data leaving the company, dependence on
   one vendor, legal/licensing (e.g. generated code licenses), acceptance by the team, EU AI
   Act category if the use case touches people decisions (HR, credit, safety).
6. **Choose the smallest experiment** that could kill the idea: 10 to 30 real-looking but
   non-confidential examples, a baseline (how a human or the current process does), and a
   pass criterion. Hand over to `eval-design` for the test suite.
7. **Score and recommend** using the template: pursue / experiment first / park / reject,
   with the one or two deciding reasons.
8. **Save** the assessment: `brain new note "Use case: <name>" --project ai-use-cases`, and
   add it to the project's use-case list in `KERN.md` if one exists.

## Good first use cases in legacy modernization

Typically well-defined and reviewable: explaining legacy code sections for a developer,
drafting characterization tests, summarizing change logs, translating documentation,
generating boilerplate for a known target pattern, searching internal documentation.
Poorly suited at first: autonomous code migration without tests, customer-facing answers
without review, anything decided about people.

## Done when

- Task, data class, reviewer, business-case estimate, risks and experiment are filled in.
- Every number has a source or is marked as an estimate with its basis.
- The recommendation is one of the four outcomes with explicit reasons.
- Open blockers (e.g. data protection approval) name who can resolve them.

## Pitfalls

- Starting from a tool ("what can we do with Copilot?") instead of a task.
- Counting time saved without counting review time.
- Testing with confidential data before the destination is approved. Use synthetic or
  public examples.
- A demo on three hand-picked examples. Use a fixed set chosen before seeing results.
- Overselling. State limits and failure rates plainly; that builds more trust.
