# Role-based curriculum

Everyone first takes the baseline session (`art4-literacy-session.md`). Then each person joins
the track for their role. Each track has four sessions of about 60 minutes, one per week, and
a task between sessions that people do in their real work. Sessions follow the structure in
`facilitator-guide.md`: why, rules, show, do, share, next step.

Pick the tool per session from the approved list (`TODO(ask IT)`: approved tools per role).
Exercises use synthetic material from `exercises/`.

## Learning goals for every track

After the track a participant can:

1. Name the data classes and say, for a given input, which approved tool may receive it.
2. Write a prompt with task, context, format and constraints, and improve it after a bad
   answer.
3. Check an AI output with the review checklist and find typical errors: invented facts,
   missing parts, wrong numbers, wrong tone.
4. Decide whether a task suits AI: well-defined, checkable, worth the review time.
5. Report a problem (wrong output that went out, data sent to the wrong place) and know to whom.

## Track A: office staff (administration, HR support, finance support, assistants)

| # | Session | Content | Exercise | Task until next week |
|---|---|---|---|---|
| A1 | Writing with AI | Drafting and rewriting emails and letters; tone; length; the "you send it, you own it" rule | Rewrite `exercises/office-email.md` for two audiences | Draft three real mails with AI, note the time with and without |
| A2 | Summarizing and extracting | Summaries of long texts you provide; extracting dates, action items and tables; checking against the source | Summarize `exercises/office-meeting-notes.md`, then find what the summary missed | Summarize one long internal document you are allowed to use |
| A3 | Templates and checklists | Turning a repeated task into a reusable prompt; variables in brackets | Build a prompt for a recurring request (e.g. travel request answer) | Use your prompt five times, improve it once |
| A4 | Limits and safe habits | Personal data, HR data, confidential numbers; what never goes into a tool; when AI is the wrong choice | Sort 12 cards: send / anonymize first / never | Share your best prompt with the team |

## Track B: project managers and team leads

| # | Session | Content | Exercise | Task until next week |
|---|---|---|---|---|
| B1 | Status and reporting | Status reports from notes you provide; consistent format; no invented progress | Status report from `exercises/pm-status-notes.md` | Write one real status report with AI support |
| B2 | Meetings | Agenda from goals; minutes and action items from notes; consent and retention rules for recordings (`TODO(ask IT)`: meeting policy) | Minutes plus action list from notes; compare with a colleague | Use AI for one agenda and one set of minutes |
| B3 | Planning and risks | Breaking down a work package; risk lists; questions to ask a customer; AI as a sparring partner, not a planner | Risk list for `exercises/pm-project-brief.md`, then challenge it | Run a pre-mortem with AI on a current work package |
| B4 | Leading AI use in the team | Finding good use cases in the team; review duty; measuring time saved; handling fear and overuse | Fill `templates/adoption-metrics.md` for your team as a plan | Collect three use-case ideas from the team (intake form if available) |

## Track C: developers

Developers get the same rules plus the engineering skills in the agent setup (`30-agent-setup`),
if installed.

| # | Session | Content | Exercise | Task until next week |
|---|---|---|---|---|
| C1 | Understanding legacy code | Explaining unknown code; asking for call paths and data flow; verifying explanations by running code; customer code is CUSTOMER data | Explain `exercises/dev-legacy-snippet.md`, then verify two claims | Use AI to explain one unfamiliar internal module |
| C2 | Tests first | Characterization tests before changes; AI drafts, you check assertions against real behavior | Write characterization tests for the snippet | Add tests to one real change |
| C3 | Reviewing AI code | Security, licenses, invented APIs, over-large changes; small diffs; the human reviewer rule | Review a flawed AI patch in `exercises/dev-legacy-snippet.md` | Review one AI-assisted change with the checklist |
| C4 | Agents and automation | Agent instructions (AGENTS.md), skills, what an agent may run; secrets and permissions; when not to automate | Write an instruction file for a small repo | Propose one task to automate, with a human gate |

## Track D: management

Two sessions of 60 minutes instead of four; the task between them is a decision, not practice.

| # | Session | Content | Exercise | Task |
|---|---|---|---|---|
| D1 | What AI does well and badly here | Live demo on the company's own kind of work; typical errors; cost of review; data protection and customer contracts; EU AI Act duties for deployers (literacy, transparency, prohibited practices, high-risk areas such as HR) | Judge three real-looking outputs: send, fix, or reject | Name one area where AI must not be used without your approval |
| D2 | Steering AI use | Use-case portfolio with stage gates and kill criteria; baseline before building; AI system inventory; who approves tools; measuring value | Score two use-case ideas with value, feasibility, risk, reusability | Approve or change the program plan (`templates/program-plan.md`) |

## Completion

A participant completes a track when they attended at least three of four sessions (both for
management), did the tasks between sessions, and passed `assessment/completion-assessment.md`.
Record completion in `templates/literacy-record.md`.

## Keeping it current

- Review the curriculum every quarter and whenever the approved tool list changes.
- Replace exercises with cleared real examples from the teams as they come in.
- Remove content about features the approved tool no longer has.
