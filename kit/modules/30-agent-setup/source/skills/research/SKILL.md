---
name: research
description: 'Answer a question about external facts (tools, libraries, standards, vendors, regulations, prices, versions) with retrieved sources and cited evidence. Use for lookups, tool or vendor comparisons and source gathering. Do not use for questions the codebase or the brain can answer, for opinions that need no evidence, or when no web access is available and the user needs current facts (say so instead).'
---

# Research

Two rules carry everything:

1. **What you did not retrieve, you do not have.** Every factual claim comes from a page or
   file you actually opened in this task. Model memory is labelled as such.
2. **Raw text goes into a file, not the chat.** Long pages fill the context and degrade the
   rest of the work. Save them under the project's `research/` folder or a temp folder.

## Scale the process to the question

| Question | Process |
|---|---|
| Single fact ("latest LTS of Node?") | one search, open the primary source, cite it |
| Comparison of 2 to 5 options | criteria first, one primary source per option and criterion, table |
| Broad survey | source plan, saved raw material, open-questions list, report |

## Procedure

1. **Frame.** Write the question, what counts as an answer, and constraints (date range,
   region, language, "only official docs"). A `site:` or domain constraint in the request
   is a hard filter, not a hint.
2. **Check what is known.** `brain search "<question>" -k 5`. Reuse notes, but re-check
   anything time-sensitive (versions, prices, licenses, laws) against a current source.
3. **Search** with the available web search or browser tool. Prefer primary sources:
   official documentation, standards, release notes, source repositories, legal texts.
   Use secondary sources (blogs, forums) for experience reports, and mark them as such.
4. **Open and record** each source you rely on: URL, date shown on the page, and a short
   verbatim quote that carries the claim. Keep quotes in the original language.
5. **Check coverage.** If well-known options or sources are missing from your results,
   your search was too narrow. Search again before concluding.
6. **Write the answer** (template below). Separate facts, your inference, and gaps.
7. **Save** a durable result to the brain as `reference` (`brain new reference "<title>"`),
   with sources.

## Answer template

```markdown
**Answer:** <one to three sentences>

| Claim | Source | Date | Quote |
|---|---|---|---|
| ... | <url> | <yyyy-mm-dd> | "<verbatim>" |

**Inference:** <what follows from the facts, marked as your reasoning>
**Not found / unverified:** <gaps; model knowledge not confirmed by a source>
```

## Company context

- Searching sends your query to an external service. Do not put customer names, internal
  project names, hostnames or code into search queries. Rephrase generically.
- For vendor or tool evaluations, record license, data residency (where data is processed),
  and whether a data processing agreement exists. These decide adoption more than features.
- Security or compliance claims ("ISO 27001 certified", "GDPR compliant") need the vendor's
  own document or certificate listing as source, not a marketing page.

## When tools are missing

Without web access: answer from the brain and local documentation only, label the result
"not verified against current sources", and list what should be checked online.

## Done when

- The question is answered or explicitly marked unanswerable with the reason.
- Every factual claim has a source you opened, or sits under "unverified".
- At least one quote directly supports the main answer, not just a side fact.

## Pitfalls

- Fabricated URLs or quotes. A real page with an invented quote is the most common error.
  Only quote text you saw.
- Paraphrasing a quote or translating it. Quote verbatim; explain around it.
- HTTP 403 is not proof of fabrication (publishers block bots); 404 or a non-existent
  domain is a red flag.
- Results that arrive faster than the reading could take were probably not read.
- Version numbers, stars, prices from memory. Look them up.
