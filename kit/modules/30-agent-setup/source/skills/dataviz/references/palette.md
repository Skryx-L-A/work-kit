# Palette

Replace these with company colours if a brand guide exists; keep the roles.

## Roles

| Role | Hex | Use |
|---|---|---|
| text | #1c1f24 | titles, labels |
| muted | #5b6270 | subtitles, axis labels, notes |
| grid | #e3e5e8 | light gridlines only (deliberately below 3:1; never data) |
| context | #8a919c | series that are not the finding |
| accent | #1f5fbf | the series or bar that carries the finding |
| negative | #b3261e | worse / failure (always with a label) |
| positive | #1e7a3c | better / pass (always with a label) |

## Categorical (colour-blind safe, Okabe-Ito)

Measured contrast against white with `scripts/contrast.py --palette "#ffffff" ...`:

| Colour | Hex | vs white | Note |
|---|---|---|---|
| blue | #0072B2 | 5.19:1 | first choice |
| vermillion | #D55E00 | 3.87:1 | |
| green | #009E73 | 3.42:1 | |
| purple | #CC79A7 | 3.06:1 | |
| orange | #E69F00 | 2.25:1 | below 3:1: use darker #B87700 (3.70:1) or add a dark outline |
| sky blue | #56B4E9 | 2.31:1 | below 3:1: only with outline or on dark backgrounds |
| yellow | #F0E442 | 1.32:1 | dark backgrounds only |

Use at most five at once; beyond that group into "other" or use small multiples.

## Sequential and diverging

- Sequential: matplotlib `viridis` or `cividis`, or light-to-dark of one hue.
- Diverging: `RdBu` or `PuOr`, centred on a meaningful midpoint (0, target, baseline).

## Contrast

- Text on background: at least 4.5:1 (3:1 for large text above 18 pt).
- Marks (lines, bars) against background: at least 3:1.
- Check: `python3 scripts/contrast.py "#5b6270" "#ffffff"`.
