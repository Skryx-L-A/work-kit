---
name: ui-prototype-design
description: 'Design and build a clickable UI prototype or small internal tool front end (HTML/CSS/JS or the project''s existing web stack) to test an idea with users or stakeholders. Use for new screens, internal tools, demo front ends for AI prototypes, and redesigns of a legacy screen. Do not use for production UI in an established design system (follow that system), fixed-page documents or slides, or backend-only work.'
---

# UI prototype design

A prototype answers a question ("can clerks find the order status in under 10 seconds?").
Design only as much as the question needs, but make what is shown real enough to judge.

## Design references first

Before any design decision, look into `~/work/design-refs/web/` and
`~/work/design-refs/brand/` (`DESIGN_REFS` overrides `~/work/design-refs`). List them with
`kit-design refs` or `ls -A`; the kit's `README.md` in each folder does not count.

- **Not empty:** open every file that applies before designing (view images and PDFs, read
  guides) and follow them over the defaults in this skill: screenshots and style guides set
  layout density, components and tone; the brand guide or `brand/theme.json` sets the tokens
  (colours, fonts, logo). Take the feel, never copy assets or code you may not use. If a
  reference would break legibility or accessibility, use the closest compliant variant and
  name the conflict. List the references you used in the handover.
- **Empty or missing:** use this skill's defaults. Do not invent a company look, logo or brand
  colours. Say in the handover that no references were found and that files put into
  `~/work/design-refs/web/` and `~/work/design-refs/brand/` will be used next time.

## Procedure

1. **Write a four-part brief** before any code:
   - *Intent*: who uses it, for which task, what action ends the task.
   - *Question*: what the prototype must prove or disprove; how it will be tested.
   - *Reference*: the existing screen being replaced, or 1 to 3 examples to take the feel
     from (never copy their assets or code).
   - *Guardrails*: always/never lists, e.g. "always keyboard-usable", "never real customer
     data", "must run offline from a static folder".
2. **Map the flow**: list screens and states for the task (start, input, loading, result,
   error, empty). Sketch in text or boxes before styling.
3. **Choose the stack**: the project's existing framework if there is one; otherwise one
   static `index.html` with plain CSS and minimal JavaScript. No build step, no CDN, so it
   runs from a file or `python3 -m http.server`. Fake data lives in a local data file.
   `kit-design new web <dir>` (module 90-design) gives such a start: tokens, list/detail
   screen, loading/empty/error states; replace its sample screen with your flow.
4. **Set tokens first**: colours, font stack, type scale, spacing unit, radius, as CSS custom
   properties. Starting values in `references/ui-floor.md`. Use system fonts or fonts
   shipped with the prototype.
5. **Build the main path**, then the states. Real-looking labels and data (synthetic),
   not lorem ipsum. Legacy replacement: keep field names and order users know unless
   changing them is part of the question.
6. **Check** in a browser at desktop and narrow widths: keyboard navigation and visible
   focus, contrast, all states reachable, no console errors. Use the checklist in the
   reference. One fix batch, then one confirming look; stop polishing.
7. **Hand over**: how to open it, what it demonstrates, what is faked, the test question,
   and what feedback to collect. Save findings from user tests in the brain.

## Legacy modernization notes

- Power users of old desktop screens rely on keyboard shortcuts, dense layouts and tab
  order. Measure task time on the old screen before claiming the new one is better.
- Show the new screen side by side with the old one in reviews.
- Keep domain terms from the old UI; rename only with the users.

## Done when

- The brief and the flow exist; every state in the flow is reachable in the prototype.
- It runs locally without network access.
- The checklist in `references/ui-floor.md` passes at desktop and narrow width.
- Fake parts and the test question are stated in the handover.

## Pitfalls

- Polishing visuals before the flow is right.
- Only the happy path: missing error, empty and loading states are what users hit first.
- Generic template look: gradient hero, identical icon cards, one default font everywhere.
- Real customer data or screenshots in a prototype that will be shown around.
- Prototype code silently becoming production code. Say it is a prototype.
