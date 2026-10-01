---
title: Starter prompts for day one
---

# Starter prompts for day one

Copy a prompt, replace the parts in `[brackets]`, check the result with the review card.
The data label says the most sensitive data the prompt is meant for; check that your tool is
approved for it (data classes card). The same prompts, versioned, are in the prompt library
(`30-agent-setup/source/prompts/`) under the id in brackets, if the agent setup is installed.

## For everyone

**Improve my text** (INTERNAL) `[general/improve-text]`
> Improve the following text for [audience]. Keep the meaning and all facts. Make it clearer
> and shorter, in a [neutral / friendly / formal] tone. List the changes you made below the
> text. Text: [paste]

**Summarize for me** (INTERNAL) `[general/summarize]`
> Summarize the text below in at most [5] bullet points for [who]. Then list open questions
> and any dates or numbers exactly as they appear in the text. Do not add anything that is
> not in the text. Text: [paste]

**Explain it simply** (PUBLIC) `[general/explain]`
> Explain [topic] to someone who [background]. Use one everyday example. Say which parts are
> simplified and where I should check an authoritative source.

**Challenge my plan** (INTERNAL) `[general/challenge]`
> Here is my plan: [plan]. Ask me up to five questions that expose weak points, one at a
> time. Do not propose a new plan until I have answered.

## Office staff

**Reply to a request** (INTERNAL) `[office/reply-draft]`
> Draft a reply to the message below. Goal: [goal]. Must include: [points]. Must not promise:
> [limits]. Tone: [tone]. Length: at most [n] sentences. Message: [paste]

**Extract action items** (INTERNAL) `[office/action-items]`
> From the notes below, list every action item as a table: what, who, due date. Write "not
> stated" where the notes do not say. Then list decisions separately. Notes: [paste]

**Turn notes into a checklist** (INTERNAL) `[office/checklist]`
> Turn this process description into a numbered checklist someone new can follow. Mark every
> step where a decision or approval is needed. Description: [paste]

## Project managers

**Status report** (INTERNAL) `[pm/status-report]`
> Write a status report from these notes for [audience]. Sections: summary (3 sentences),
> progress, risks and issues, decisions needed, next steps. Use only information from the
> notes; mark gaps as "to confirm". Notes: [paste]

**Meeting agenda** (INTERNAL) `[pm/agenda]`
> Draft an agenda for a [duration] meeting with [participants]. Goal: [decision or outcome].
> Give each item a time box, an owner and the question it must answer.

**Pre-mortem** (INTERNAL) `[pm/pre-mortem]`
> Imagine this work package failed six months from now: [description]. List the ten most
> likely reasons, each with an early warning sign and one preventive action.

## Developers

**Explain this code** (CUSTOMER only in an approved tool) `[dev/explain-code]`
> Explain what this [language] code does, for a developer new to the codebase: purpose, inputs,
> outputs, side effects, and anything surprising. For each claim, point to the line. Say what
> you cannot tell without other files. Code: [paste]

**Characterization tests** (CUSTOMER only in an approved tool) `[dev/characterization-tests]`
> Write characterization tests for this function that pin its current behavior, including
> edge cases and errors. Do not fix bugs; note them in comments. Framework: [framework].
> Code: [paste]

**Review this change** (CUSTOMER only in an approved tool) `[dev/review-diff]`
> Review this diff for correctness, security, error handling and readability. List findings
> by severity with the line and a concrete fix. Say "no findings" for a category if none.
> Diff: [paste]

## Management

**Decision brief** (INTERNAL) `[mgmt/decision-brief]`
> Write a one-page decision brief on [question]: options, costs and benefits of each, risks,
> what we would need to believe for each option to be right, and a recommendation. Use only
> the facts below and mark assumptions. Facts: [paste]

**Question the proposal** (INTERNAL) `[mgmt/question-proposal]`
> Here is a proposal I must decide on: [paste]. List the questions I should ask its authors
> before deciding, grouped by value, cost, risk and people.

## Habits that make every prompt better

- Give the source text; do not ask the tool to remember facts.
- Say who the reader is and what format you need.
- Ask it to mark what it is unsure about or what it could not find in the text.
- When the answer is wrong, say what is wrong and ask again; do not start from zero.
- Save prompts that worked and share them with your team.
