---
name: dataviz
description: 'Choose and build a chart, table or small dashboard that shows data honestly and readably, with Python (matplotlib/plotly), HTML/SVG or LibreOffice Calc. Use for charts in reports, slides, eval results, benchmarks and status dashboards. Do not use for architecture or flow diagrams, for decorative illustrations, or when a single number or a short table says it better (then use that).'
---

# Data visualization

A chart is an argument: it should make one finding obvious and let the reader check it.

## Design references first

Before any design decision, look into `~/work/design-refs/brand/` and
`~/work/design-refs/diagrams/` (`DESIGN_REFS` overrides `~/work/design-refs`). List them with
`kit-design refs` or `ls -A`; the kit's `README.md` in each folder does not count.

- **Not empty:** open every file that applies before designing (view images and PDFs, read
  guides) and follow them over the defaults in this skill: brand colours replace the
  placeholder palette in `references/palette.md` (still run the contrast check), chart
  examples in `diagrams/` set the house look for axes, labels and fonts. If a reference would
  break legibility or accessibility, use the closest compliant variant and name the conflict.
  List the references you used in the handover.
- **Empty or missing:** use this skill's defaults. Do not invent a company look, logo or brand
  colours. Say in the handover that no references were found and that files put into
  `~/work/design-refs/brand/` and `~/work/design-refs/diagrams/` will be used next time.

## Procedure

1. **State the finding** the chart must show, as a sentence: "Model B passes 12 points more
   cases than A at half the latency." If there is no finding yet, you are exploring; make
   quick default plots and do not polish them.
2. **Check the data**: units, time range, sample size, missing values, outliers, how it was
   measured. Put the source and date in a note under the chart.
3. **Pick the form** by the question:

| Question | Form |
|---|---|
| compare a few categories | horizontal bar chart, sorted |
| change over time | line chart (bars for few, discrete periods) |
| part of a whole | stacked bar or 100 % bar; pie only for 2 to 3 parts |
| distribution | histogram, box or strip plot |
| relation of two measures | scatter plot, labelled points |
| exact values matter | table (right-aligned numbers, units in header) |
| one key figure | the number, large, with comparison ("15 min, was 40") |

4. **Colour by rule** (`references/palette.md`): neutral grey for context, one accent for
   the finding; categorical palette only when categories must be told apart; sequential for
   ordered values, diverging only around a meaningful midpoint. Never encode meaning by
   colour alone: add labels or patterns.
5. **Draw it** with the template in `references/matplotlib-template.py` or the equivalent in
   another tool. Rules:
   - title states the finding; subtitle states measure, unit, n and date,
   - bars start at zero; line charts may zoom but say so,
   - label lines and bars directly instead of a legend where possible,
   - remove chart junk: heavy gridlines, borders, 3D, shadows, background fills,
   - show uncertainty (repetitions, ranges) when it exists.
6. **Check** the rendered image at the size it will be used: readable labels (≥ 9 pt in
   print, ≥ 14 pt on slides), no overlaps, contrast of text and marks. Validate colours with
   `python3 scripts/contrast.py <fg> <bg>` (or `--palette` for a whole set).
7. **Export**: SVG or PDF for documents, PNG at 2x for slides and chat; keep the script and
   data file next to the image so it can be regenerated.

## Dashboards

Start from the questions users check daily; one row of key numbers with comparisons, then
at most 4 to 6 charts. Same colours mean the same thing on every chart. State data
freshness ("as of 2026-10-01 08:00"). A static HTML page or a notebook is often enough for a
prototype; do not introduce a BI server without approval.

## Missing tools

`kit-design theme` prints the brand colours and fonts in use, if module 90-design is installed.
Check `python3 -c "import matplotlib"`. Without matplotlib: LibreOffice Calc charts, a
hand-written SVG, or an HTML table with inline bars (CSS width percentages).

## Done when

- The title states a finding the data supports; source, n and date are shown.
- Form fits the question; axes and units are labelled; bars start at zero.
- Colours pass contrast and do not carry meaning alone.
- The image was viewed at its final size; the script and data are saved.

## Pitfalls

- Truncated axes that exaggerate differences.
- Rainbow palettes and a legend with 10 entries.
- Dual y-axes: they imply correlations that the scale choice creates.
- Averages without spread for noisy results (e.g. LLM evals with few repetitions).
- Charts of confidential data leaving the approved data class in a slide or a screenshot.
