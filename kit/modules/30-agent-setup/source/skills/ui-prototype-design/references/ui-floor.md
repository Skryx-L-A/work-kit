# UI floor: tokens and checklist

## Starting tokens

```css
:root {
  --font: system-ui, "Segoe UI", Roboto, "Noto Sans", sans-serif;
  --mono: ui-monospace, "DejaVu Sans Mono", monospace;
  --text: #1c1f24; --muted: #5b6270; --bg: #ffffff; --surface: #f4f5f7;
  --border: #d6d9de; --input-border: #8a919c; --accent: #1f5fbf; --danger: #b3261e; --ok: #1e7a3c;
  --s1: 4px; --s2: 8px; --s3: 12px; --s4: 16px; --s5: 24px; --s6: 32px; --s7: 48px;
  --fs-sm: 0.875rem; --fs: 1rem; --fs-lg: 1.25rem; --fs-xl: 1.75rem;
  --radius: 6px;
}
body { font: var(--fs)/1.5 var(--font); color: var(--text); background: var(--bg); }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
```

Measured on white: `--muted` 6.1:1, `--accent` 6.1:1, `--input-border` 3.2:1. `--border`
(1.4:1) is for decorative dividers only; input and control outlines use `--input-border`.

Business tools may be denser than marketing pages: 14 px body and 32 px row height are
fine for data tables if contrast and focus are good.

## Checklist

- Contrast: body and placeholder text at least 4.5:1, large text and UI borders 3:1.
- Keyboard: every action reachable with Tab/Enter/Escape; logical tab order; focus visible.
- Labels: every input has a visible label; buttons name their action ("Save order", not
  "OK"); error messages name the problem and the fix.
- States: hover, focus, disabled, loading, empty, error, success.
- Layout: text lines at most about 75 characters; no horizontal scroll at 360 px width
  (except data tables, which scroll inside their container).
- Spacing: tight within groups, larger between groups; more space above headings.
- Motion: none needed; if used, short and respecting `prefers-reduced-motion`.
- Avoid: nested cards, gradient text, coloured side borders on every card, an icon tile
  before every heading, the same entrance animation on every section.
- Console: no errors; works offline.
