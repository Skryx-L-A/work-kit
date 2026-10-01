---
name: presentation-design
description: 'Plan and build a slide deck for a talk, team demo, steering meeting or workshop, as PDF, PPTX/ODP or HTML slides. Use when someone must present or decide from slides. Do not use for documents meant to be read without a speaker (document-design), for a single chart (dataviz), or for web prototypes (ui-prototype-design).'
---

# Presentation design

Slides support a speaker or a decision; they are not a document projected on a wall.
Decide what the audience must know, believe or decide at the end, then build backwards.

## Design references first

Before any design decision, look into `~/work/design-refs/slides/` and
`~/work/design-refs/brand/` (`DESIGN_REFS` overrides `~/work/design-refs`). List them with
`kit-design refs` or `ls -A`; the kit's `README.md` in each folder does not count.

- **Not empty:** open every file that applies before designing (view images and PDFs, read
  guides) and follow them over the defaults in this skill: a `.pptx`/`.potx` template is the
  base (fill its layouts, do not draw a competing design), example decks set density and tone,
  the brand guide or `brand/theme.json` sets colours, fonts and logo. If a reference would
  break legibility or accessibility, use the closest compliant variant and name the conflict.
  List the references you used in the handover.
- **Empty or missing:** use this skill's defaults. Do not invent a company look, logo or brand
  colours. Say in the handover that no references were found and that files put into
  `~/work/design-refs/slides/` and `~/work/design-refs/brand/` will be used next time. For a
  deck shown outside the team, ask once whether a company template exists.

## Procedure

1. **Set the frame**: audience, their prior knowledge, time slot, setting (live, remote,
   sent around afterwards), and the one outcome ("steering approves the 4-week pilot").
2. **Write the storyline as headlines first**, one sentence per slide, before any design.
   The headlines alone should tell the story. Typical arcs:
   - decision: situation, problem, options, recommendation, cost/risk, ask;
   - demo: what problem, live demo, what it cannot do, next step;
   - results: question, method, result, what it means, next step.
   Rule of thumb: one slide per 1 to 2 minutes.
3. **One message per slide.** The title is that message as a full sentence ("The pilot cut
   review time from 40 to 15 minutes"), not a topic label ("Results").
4. **Choose the visual per message**: a chart for a comparison or trend (`dataviz`), a
   diagram for a flow or architecture, a screenshot for a real UI, a big number for one key
   figure, a short list only for genuinely parallel items (max. 4 to 5 lines).
5. **Pick the route**:

| Need | Route |
|---|---|
| Company template exists | PPTX in that template (LibreOffice Impress or PowerPoint), fill its layouts |
| From Markdown, kit tool | `kit-design new deck <dir>`, write `deck.md`, `kit-design deck deck.md` gives PPTX and a single-file HTML deck; one template in `design-refs/slides` is used automatically, else `--template <file>` |
| Editable, no template | LibreOffice Impress with master slides |
| From Markdown, versioned in git | Marp or Pandoc (`pandoc -t pptx`, or `-t revealjs` with reveal.js files stored locally) if installed |
| Handout / sent around | export to PDF; add speaker notes or a short companion document |

6. **Apply the layout rules** in `references/slide-rules.md`.
7. **Render and check every slide** (export to PDF, view as images). Check the list in
   the reference. Rehearse timing once out loud or estimate it from the headline count.
8. **Prepare the room**: a PDF backup, fonts embedded, demo data prepared and non-confidential,
   offline fallback (screenshots or a recording) for any live demo.

## AI content in slides

State plainly what was measured and on which data; show failure cases as well as successes.
Label AI-generated images or text if the company policy asks for it. Never show customer
data, internal hostnames or real credentials on a slide or in a demo.

## Missing tools

Check with `command -v kit-design soffice pandoc marp`. To view PPTX slides as images:
`soffice --headless --convert-to pdf deck.pptx` and `pdftoppm -png -r 50 deck.pdf s`; the
HTML deck prints to PDF from a browser (one slide per page). Without any of these tools, write HTML slides (one
`<section>` per slide, 16:9 fixed-size CSS) and print to PDF from a browser.

## Done when

- The headlines alone tell the story and end with the ask or next step.
- Every slide has one message and one main visual; no slide needs scrolling or tiny text.
- All slides were viewed after the last change; fonts embedded; a PDF backup exists.
- Timing fits the slot.

## Pitfalls

- Topic titles ("Agenda", "Background") instead of message titles.
- Text walls. If it needs paragraphs, it belongs in a handout.
- Charts copied from analysis without simplification: remove what does not serve the message.
- Live demos without a fallback.
- Decorative stock images and icons that add nothing.
