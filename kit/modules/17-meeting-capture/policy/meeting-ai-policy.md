# Meeting AI policy (template)

Rules for recording, transcribing and summarizing meetings with AI tools. **This is a template,
not company policy.** Every value marked `TODO(ask IT)` is a placeholder. Until the responsible
people confirm it, the strictest reading applies: the stricter option in each rule, and "not
allowed" where the template gives no answer. The installer copies this file to
`~/.config/work-kit/meeting-ai-policy.md`. `meeting policy --todo` lists the open questions.

Version: 0.1 (template) · Owner: `TODO(ask IT)` · Approved by: `TODO(ask IT)` ·
Valid from: `TODO(ask IT)` · Next review: `TODO(ask IT)` (at least yearly)

## 1. Scope

1. Applies to every audio recording or machine transcript of a meeting, call or workshop, made
   with the kit's `meeting` tool or any other tool, including the transcription features of
   Teams and other meeting software.
2. It does not cover notes typed by a person, or dictation of one's own text (module 80-quassel).
3. It sits under the company AI usage guideline (`ai-usage-guideline.md`) and the data classes
   (`data-classes.md`). Where they differ, the stricter rule applies.

## 2. Consent

1. Recording or transcribing starts only after **every participant** has been told and has
   agreed. Say it at the start of the meeting, in words, and wait for objections.
2. External participants (customers, partners) must agree too. Ask before the meeting when
   the invitation can carry the notice. `TODO(ask IT)`: standard wording for invitations.
3. One objection ends the recording. Nobody is asked to justify it and nobody is treated
   worse for it. A person who joins later is told, and may object.
4. Consent covers the stated purpose only (meeting notes for the participants). Other uses
   (training, performance review, sharing outside the team) need a new consent.
5. No recording of: HR and personnel talks, works council talks, legal or compliance talks,
   1:1 feedback talks, medical or other special-category data (GDPR Art. 9), and talks
   between customers' people where the customer has not agreed in writing.
   `TODO(ask IT)`: confirm or extend this list.
6. The `meeting start` command shows a consent reminder every time and asks for a
   confirmation. The note records that it was given, and who took part if entered.

## 3. Works council and legal basis

1. `TODO(ask IT)`: is there a works council (Betriebsrat)? Transcription that can show who
   said what is a co-determination topic in Germany (Betriebsverfassungsgesetz section 87,
   technical equipment that can monitor behaviour or performance). Until answered: use only
   in meetings where everyone taking part is an active participant and agrees, and never
   evaluate a person from a transcript.
2. `TODO(ask IT)`: legal basis under GDPR (consent Art. 6(1)(a), or another basis) and the
   information duty (Art. 13). The data protection officer decides.
3. `TODO(ask IT)`: is a data protection impact assessment needed before regular use?

## 4. What may be transcribed

| Meeting | Recording and transcript |
|---|---|
| Own team, internal topics, class INTERNAL | allowed after consent |
| Workshops, brainstorms, training sessions run by you | allowed after consent |
| Customer meetings | only with the customer's written agreement (`TODO(ask IT)`) |
| Anything CONFIDENTIAL or CUSTOMER data (see `data-classes.md`) | not allowed until IT decides |
| HR, personnel, works council, legal, medical | never |

## 5. Where audio and transcripts may be stored

1. **Audio**: only on the laptop, in the private state folder of the tool
   (`~/.local/share/work-kit/meeting-capture/`). The tool deletes it once the transcript
   exists. Keep it only when the transcript failed, and delete it after the retry.
2. **Transcript and notes**: only on the laptop: in the brain (`~/work/brain`) or in
   `~/work/meetings/`. Files are private to the user (mode 600).
3. **Not allowed** without IT approval: cloud drives, chat channels, e-mail, public or
   personal accounts, USB sticks that are not encrypted, issue trackers, pasting the
   transcript into a chat with an AI service. `TODO(ask IT)`: approved shared location for
   meeting notes, if any.
4. The brain's remote (`brain sync`) may carry meeting notes only if the remote is a company
   server approved for INTERNAL data. `TODO(ask IT)`.
5. Speech-to-text runs only in the local whisper.cpp engine of module 80-quassel (or a
   server on this machine). No cloud speech services.

## 6. Retention

| Item | Rule |
|---|---|
| Audio | delete right after transcription (default of the tool) |
| Transcript and note | keep at most `TODO(ask IT)` days; proposal: 90 |
| Action items and decisions worth keeping | move to a decision record or project note; the transcript itself is then deleted |

`meeting purge --days N` deletes old audio and old notes in `~/work/meetings/`. Notes in the
brain are deleted by hand (`brain` has no expiry). A participant may ask for deletion of a
recording or transcript that contains their words; delete it and confirm.

## 7. Which models may summarize a transcript

1. Default: **local models only** (module 15-local-llm or another model running on this
   laptop). The transcript never leaves the machine.
2. Cloud or company-hosted models (Copilot, Claude, Codex, Gemini and others) may summarize a
   transcript only if the model appears on the approved list of the AI usage guideline for the
   data class of the meeting, and only for INTERNAL content. `TODO(ask IT)`: approved models
   and data class for meeting content.
3. Consumer or personal AI accounts: never.
4. `meeting stop --summarize` refuses a summary server that is not on this machine unless
   `MEETING_SUMMARY_ALLOW_REMOTE=1` is set for that run. Setting it is a statement that the
   model is approved.
5. Whoever summarizes checks the summary against the transcript before the note is shared.
   The note marks summaries and transcripts as machine-made.

## 8. Human review and sharing

1. A transcript is a machine product: names, numbers and decisions can be wrong. The person who
   recorded reviews it before anyone acts on it.
2. The note is shared only with participants, unless they agree to more. Do not forward a
   transcript; share the reviewed decisions and action items.
3. Nobody is evaluated, ranked or disciplined on the basis of a transcript.

## 9. Incidents

A recording made without consent, a transcript in an unapproved place, or a summary sent to
an unapproved model is an incident. Delete what you can, then report it to `TODO(ask IT)`
(contact and time limit; GDPR breach reporting can be 72 hours) with `ai-gov template
ai-incident` if module 13-ai-governance is installed.

## 10. Meeting software controls (for the record)

The company's Microsoft 365 administrator controls transcription in Teams: the tenant policy
`-AllowTranscription` in `CsTeamsMeetingPolicy`, and per meeting the organizer's Copilot setting
("only during the meeting": speech-to-text data is not stored after the meeting; "during and after
the meeting": a stored transcript starts; "off": also disables recording). Copilot data may still
be retained under Purview retention policies. Copilot is unavailable in end-to-end encrypted
meetings. `TODO(ask IT)`: the tenant's actual settings, and whether a local recording of a Teams
meeting with this tool is allowed at all (a local recording is a recording even if the organizer
switched Teams transcription off).

## Basis

Sections of this template rest on `docs/research-company-ai-setups.md`, section 12
"Meeting and transcription policies" (Microsoft Learn, Teams transcription and Copilot in meetings,
accessed 2026-09-25):
`https://learn.microsoft.com/en-us/microsoftteams/copilot-teams-transcription` and the German
edition `https://learn.microsoft.com/de-de/microsoftteams/copilot-teams-transcription`.
This template is not legal advice; the works council rule (section 3) and the GDPR items must be
confirmed by the data protection officer and legal counsel.
