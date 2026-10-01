---
title: Anatomy of a good prompt
---

# Anatomy of a good prompt

| Part | Question it answers | Example |
|---|---|---|
| Task | What should be done? | "Summarize the notes below" |
| Context | What is the input, who is it for, why? | "for the customer's project lead, who missed the meeting" |
| Material | What should it work from? | the pasted notes, not its memory |
| Format | What should the result look like? | "5 bullet points, then a table of action items" |
| Constraints | What must it not do? | "no information that is not in the notes; mark gaps" |
| Check | How will you know it is right? | "quote the sentence each bullet comes from" |

Weak: *"Summarize this."*

Strong: *"Summarize the meeting notes below in 5 bullet points for the customer's project lead,
who missed the meeting. Then list action items as a table (what, who, due). Use only the
notes; write 'not stated' where they do not say. Notes: ..."*

When the answer is wrong, do not start over: say what is wrong ("item 3 is missing, the date
is 12 May not 21 May") and ask again. Save prompts that work.
