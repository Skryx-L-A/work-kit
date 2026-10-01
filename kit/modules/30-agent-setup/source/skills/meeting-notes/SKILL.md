---
name: meeting-notes
description: 'Prepare a meeting (agenda, questions, goal) or turn raw notes or a transcript into concise minutes with decisions, action items and open questions. Use for team meetings, stakeholder interviews, use-case workshops and one-on-ones about work. Do not use for verbatim transcription, for recording or transcribing people without their consent, or for private conversations.'
---

# Meeting notes

Minutes exist so that decisions and tasks survive the meeting. Most readers read only the
top block; put decisions and actions there.

## Before the meeting (optional)

1. Search context: `brain search "<topic or team>" -k 5`, open action items from the last
   meeting on this topic.
2. Write a short prep note: goal of the meeting (a decision, information, ideas), agenda
   with time boxes, questions to ask, material to show. For interviews about possible AI
   use cases, ask about the task, frequency, time spent, what "correct" means, which data is
   involved and who checks results today (see `ai-use-case-assessment`).

## After the meeting

1. **Collect input**: your raw notes, chat, whiteboard photos, or a transcript. A transcript
   or recording needs the participants' consent and must be handled as at least INTERNAL
   data; do not paste it into an AI tool that is not approved for that data class.
   If the `meeting` CLI (module 17-meeting-capture) is installed, it records and transcribes
   locally after a consent check; follow `~/.config/work-kit/meeting-ai-policy.md`.
2. **Extract**, in this order:
   - decisions (what, who decided, any condition),
   - action items (task, owner, due date); an item without owner is marked "owner: open",
   - open questions (and who can answer),
   - key information (facts, numbers, dates) only if someone will need them later.
3. **Write the minutes** with the template. Neutral wording; attribute statements to roles
   or names only when it matters for follow-up. No opinions about people.
4. **Mark uncertainty**: anything you did not clearly hear or understand gets "(to confirm)".
   Do not fill gaps with plausible content.
5. **Share** with participants within one working day if minutes are expected; ask for
   corrections. Only send to people who were invited or should know.
6. **Save**: `brain new note "<yyyy-mm-dd> <meeting title>" --project <slug> --body -`.
   Decisions with alternatives also go into an ADR (`decision-record`); new work contacts
   into `people/` with role and topics only.

## Template

```markdown
# <Meeting title> — <yyyy-mm-dd>
Participants: <names or roles> · Notes: <who>

## Decisions
- <decision> (decided by <who>)

## Action items
| Task | Owner | Due |
|---|---|---|

## Open questions
- <question> — who can answer: <who>

## Notes
- <topic>: <key facts>
```

## When `brain` is missing

Save the file as `~/work/brain/projects/<slug>/<yyyy-mm-dd>-<title>.md` or wherever the team
keeps minutes (e.g. the project's shared channel), following their template.

## Done when

- Decisions, action items (each with owner and due date or "open") and open questions are
  listed at the top.
- Uncertain points are marked, not guessed.
- The notes are saved and, if expected, shared with the participants.

## Pitfalls

- Minutes that retell the conversation chronologically. Readers want outcomes.
- Action items like "look into X" without owner and date.
- AI summaries of a transcript that invent a decision nobody made. Check each decision and
  action against the source before sending.
- Personal remarks, health, performance or HR topics in shared minutes.
- Storing customer names or internal details in a data class the destination does not allow.
