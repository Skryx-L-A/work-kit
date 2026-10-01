# AI literacy baseline session (EU AI Act Art. 4)

A 90-minute session every person takes before using AI tools at work. Slides:
`handouts/session-slides-art4.md`. Attendance: `templates/literacy-record.md`.

## Legal background, for the facilitator

- Article 4 of the EU AI Act (Regulation (EU) 2024/1689) requires providers and deployers of
  AI systems to take measures to ensure, to their best extent, a sufficient level of AI
  literacy of their staff and of other persons who operate or use AI systems on their behalf.
  A company that uses AI tools at work is a deployer.
- The duty applies since 2 February 2025. According to the Commission's implementation
  timeline, enforcement of most rules, including AI literacy, starts on 2 August 2026.
- The Commission's AI literacy Q&A says: there is no fixed "sufficient" level, no obligation
  to test individual knowledge, and no one-size-fits-all training. Measures should fit the
  staff's existing knowledge, the context and the risk of the systems used. Simply pointing
  staff at the vendor's instructions may not be enough.
- A proposal (Digital Omnibus on AI) may shift parts of this duty. Check the current state
  before each yearly review: https://digital-strategy.ec.europa.eu/en/faqs/ai-literacy-questions-answers
- Keep a record of what was taught, to whom, and when. The law does not prescribe a
  certificate, but a record is how the company shows it took measures.

This is not legal advice. `TODO(ask IT)`: have the data protection officer or legal confirm
the content and the record before the first run.

## Goals

After the session every participant can:

1. Explain in one sentence what a generative AI tool does and why it can be confidently wrong.
2. Name the approved AI tools and the data each may receive.
3. Apply the review rule: every output that reaches a customer or informs a decision is
   checked by a person, who stays responsible.
4. Recognize uses that need approval or are not allowed (decisions about people, prohibited
   practices, CUSTOMER data in unapproved tools).
5. Know whom to ask and how to report an incident.

## Company values to fill in

| Value | Filled in |
|---|---|
| Approved AI tools and what data class each may receive | `TODO(ask IT)` |
| Uses that need approval, and who approves | `TODO(ask IT)` |
| Contact for questions (name, channel) | `TODO(ask IT)` |
| How to report an AI incident or a data leak | `TODO(ask IT)` |
| Where the internal AI guideline is published | `TODO(ask IT)` |
| Official statement on AI and jobs, if any | `TODO(ask IT)` |

Until a value is filled in, teach the strict default: only PUBLIC data goes to any AI tool,
and every other case is "ask first".

## Plan (90 minutes)

| Time | Block | Content | Method |
|---|---|---|---|
| 0:00 | Welcome | Why we do this: we use AI at work, and the law and our customers expect us to use it competently. Agenda. | Talk, 5 min |
| 0:05 | What AI is | A language model predicts plausible text from patterns in training data and from what you give it. It has no reliable knowledge of facts, of your company, or of today. It can invent sources, numbers and names in a confident tone. | Talk + live demo: ask for a source on a niche topic, check it together, 10 min |
| 0:15 | What it is good and bad at | Good: drafting, rewriting, summarizing text you provide, structuring, brainstorming, explaining. Bad: facts it cannot see, calculations without tools, anything that needs to be right without checking, decisions about people. | Sort 8 example tasks on a board, 10 min |
| 0:25 | Our rules | Data classes and approved tools (`handouts/data-classes-card.md`); the review rule; no new tools or accounts without IT; no secrets in prompts; customer contracts can be stricter. | Rules slide, same in every session, 10 min |
| 0:35 | Risks in practice | Data leaking through prompts and uploads; wrong outputs reaching customers; copyright and licenses; bias in outputs about people; prompt injection in documents you paste. | Three short real-looking cases, discuss in pairs, 10 min |
| 0:45 | Hands-on | Each pair does one task with the approved tool on synthetic material: write a prompt, get an answer, check it with `handouts/review-checklist-card.md`, improve the prompt once. | Pairs, 25 min |
| 1:10 | Debrief | Two pairs show what they found wrong in the first answer. What did the second prompt change? | Group, 10 min |
| 1:20 | Where to go next | Role tracks, starter prompts, contact person, how to report an incident. Each person writes down one task to try this week. | Talk, 5 min |
| 1:25 | Check and record | Five-question check (below), sign the attendance record. | 5 min |

## Five-question check (not graded, for the record)

1. You want to summarize a customer's requirement document. Which tool may you use? (answer
   depends on the filled-in table; if unknown: "ask first")
2. The AI gives you a source with a link. What do you do before using it? (open and check it)
3. Who is responsible for an AI-drafted mail you send? (you)
4. Name one use of AI that needs approval here. (e.g. anything deciding about people)
5. You pasted confidential data into the wrong tool. What now? (report at once to the contact)

## Adapting for groups

- Developers: replace the hands-on with explaining a code snippet and checking the claims.
- Management: replace the hands-on with judging three outputs, and add the deployer duties
  (inventory of AI systems, approval of tools, transparency toward customers and staff).
- External staff who use AI on the company's behalf are in scope too.

## Yearly review

Review this session every year and when the approved tool list, the AI guideline or the law
changes. Note the review date and changes below.

| Date | Change | By |
|---|---|---|
| | | |
