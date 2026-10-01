---
name: technical-writing
description: 'Write or revise human-facing prose at work: READMEs, how-tos, emails, status updates, proposals, tickets, documentation and UI text. Use when text will be read by colleagues, managers or customers. Do not use for code, commit messages that follow a fixed convention, verbatim quotes, legal texts, or layout decisions (use document-design or presentation-design).'
---

# Technical writing

Text that sounds generated gets skimmed or discarded. Clear text states concrete facts in
plain sentences, in the order the reader needs them.

## Procedure

1. **Name reader and purpose.** Who reads it, what do they know, what should they do or
   decide afterwards, how much time do they have? Write that down in one line.
2. **Collect facts.** Numbers with what they measure, names of systems, dates, commands,
   results. Text without concrete facts is filler. Mark anything unverified.
3. **Choose the structure for the genre:**

| Genre | Order |
|---|---|
| Status update | result, then changes, blockers, next step, ask |
| Email / request | the ask or decision in the first two lines, then context |
| How-to | goal, prerequisites, numbered steps with commands, check that it worked |
| README | what it is (one line), install, use, where to get help |
| Proposal / decision memo | recommendation, why, cost, risks, alternatives |
| Ticket / bug report | observed, expected, steps to reproduce, environment, evidence |

4. **Write** short paragraphs, one idea each. Active voice. Name the actor: "the import job
   drops rows", not "rows are dropped".
5. **Cut.** Remove every sentence the reader would not miss. Remove hedges ("might
   potentially"), intensifiers ("very", "highly") and meta-commentary ("it is worth noting").
6. **Check against `references/ai-tells.md`** when the text goes to other people.
7. **Read it as the reader.** Could they act on it without asking you a question?

## Style rules

- Match the recipient's language and register. German colleague writes German: answer in
  German unless the context requires English.
- One term per concept. Do not alternate "service", "component" and "module" for one thing.
- Numbers as digits with units; dates as `2026-10-01` in technical text.
- Commands, paths and identifiers in code formatting, copied exactly.
- Lists for parallel items, prose for reasoning. Not every paragraph needs bullets.
- No emojis, no exclamation marks in professional text, no superlatives about your own work.
- AI-assisted text: the author is responsible. Every fact is checked by a human before it
  leaves; say so if the company policy requires disclosure.

## Done when

- The first two lines tell the reader what they need most.
- Every claim is concrete and either verified or marked.
- No sentence can be removed without losing information.
- Identifiers, numbers and quotes are exact.

## Pitfalls

- Burying the ask or the result in paragraph three.
- Vague claims: "significantly faster". Give the measurement and its method.
- Uniform sentence length and parallel triplets: typical signs of generated text.
- Promising what was not tested. Write "not tested" instead.
- Rewriting quotes, error messages or legal wording for style. Keep them verbatim.
