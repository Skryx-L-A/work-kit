---
name: grill-me
description: 'Clarify a vague request, a new prototype or a plan by asking focused questions one at a time until goal, constraints and a checkable done criterion are clear. Use when the user asks to be grilled or questioned, or when a new piece of work has open decisions that change what gets built. Do not use when the answer can be found in the code or notes, for routine fixes, or when the user has said to proceed.'
---

# Grill me

Turn an idea into a plan someone can build and check. Ask only what changes the plan.

## Procedure

1. **Read first.** The request, existing notes (`brain search "<topic>" -k 5`), the
   repository, tickets and documents the user named. Answer everything you can from them
   yourself and state those answers as assumptions.
2. **List the open decisions** privately, ordered by impact: which answer would change the
   most work? Typical ones:
   - Goal and user: who uses the result, for which task, how often?
   - Done criterion: what observable result means "finished"? A number, a demo, a test?
   - Scope: what is explicitly out?
   - Data: which data class is involved (`data-guard`)? May it go to an AI model?
   - Constraints: approved tools, deadline, budget, systems it must fit into.
   - Risk: what happens if the result is wrong? Who reviews it?
3. **Ask one question at a time**, the highest-impact one first. Each question:
   - states why it matters in one clause,
   - offers 2 to 4 concrete options when possible,
   - gives your recommendation and the reason.
   Use the harness's question tool if it has one; otherwise a short text question.
4. **Update the plan** after each answer. Drop questions that the answer made irrelevant.
   Never ask the same question twice.
5. **Stop** when goal, scope, done criterion, data class and the next reversible step are
   clear. Hypothetical future questions do not block the start.
6. **Write the result** as a short brief (template below) and confirm it in one message.
   Save it to the brain if the work spans more than one session.

## Brief template

```markdown
# <work title>
Goal: <one sentence: who gets what, for which task>
Done when: <observable, checkable criterion>
Out of scope: <list>
Data class: <PUBLIC|INTERNAL|CONFIDENTIAL|CUSTOMER> — AI use allowed: <yes/no/which>
Constraints: <tools, systems, deadline>
Risks and review: <what can go wrong, who checks the output>
Assumptions: <answers taken from code/notes, not asked>
First step: <smallest reversible step>
```

## Stress-testing an existing plan

When the user already has a plan and wants it attacked:
- ask about the weakest assumption first ("what if the legacy interface is undocumented?"),
- ask what evidence supports each estimate,
- ask how the plan fails and how that would be noticed,
- then summarize: holds / needs change / unknown, with the proposed change.

## Done when

The brief is written, every field is filled or marked "open: <who decides>", and the user
has confirmed it or corrected it.

## Pitfalls

- A questionnaire of ten questions at once. One at a time, highest impact first.
- Asking what the code already says. Look it up.
- Questions without a recommendation. The user wants a partner, not a form.
- Endless interviews. If the next step is reversible, start and learn from it.
- Skipping the data class. For AI work it decides which tools are allowed at all.
