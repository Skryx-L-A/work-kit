---
name: council
description: 'Deliberate a consequential, ambiguous decision from four perspectives (architect, skeptic, pragmatist, critic) and synthesize a recommendation that keeps the strongest dissent visible. Use when a choice has real trade-offs, is expensive to reverse, or the user asks for a council or second opinions. Do not use for routine fixes, code review, verification of facts, or decisions a quick measurement would settle.'
---

# Council

A structured way to avoid anchoring on the first idea. Four lenses, one synthesis.

| Voice | Lens |
|---|---|
| Architect | coherence, maintainability, long-term fit with existing systems |
| Skeptic | challenges the premise: is this the right question? simpler path? |
| Pragmatist | effort, time to value, what the team can actually operate |
| Critic | failure modes, edge cases, security and data protection, worst case |

## Procedure

1. **Frame the question**: what is decided, constraints, what counts as success. If it is
   vague, ask one clarifying question first.
2. **Gather only context that can change the choice**: relevant code, notes
   (`brain search "<topic>" --type decision`), numbers. Not the whole conversation.
3. **Write your own initial recommendation** before hearing the voices, so a change of mind
   is visible.
4. **Get the four positions.**
   - If the harness can start independent subagents and the decision warrants it, give each
     voice only the framed question and the context, never the full transcript, and run
     them in parallel. Use approved models only.
   - Otherwise write the four positions yourself, clearly labelled as one analysis from four
     perspectives, not as independent votes.
   Each position: stance (1 to 2 sentences), main reason, principal risk.
5. **Synthesize** with these rules:
   - do not dismiss a voice without saying why,
   - say explicitly if a voice changed your recommendation,
   - if two voices agree against your initial position, treat that as a real signal,
   - always show the strongest dissent.
6. **Present** the verdict (template below) and continue within the existing mandate. If the
   decision belongs to someone else, hand it over as a proposal.
7. **Persist** only consequential outcomes, as an ADR (`decision-record`).

## Output template

```markdown
## Council: <decision>
**Architect:** <position> — <reason>
**Skeptic:** <position> — <reason>
**Pragmatist:** <position> — <reason>
**Critic:** <position> — <reason>

**Consensus:** <where they align>
**Strongest dissent:** <most important disagreement>
**Premise check:** <did the skeptic reframe the question?>
**Recommendation:** <path>, because <reasons>. Changed from initial: <yes/no, why>
```

## Done when

All four positions are stated with reasons, the synthesis names consensus, dissent and
recommendation, and the next step is clear.

## Pitfalls

- Theatre: four voices that all agree with the first idea. Give the skeptic real force.
- Using a council where a spike or benchmark would answer the question. Measure instead.
- Feeding subagents the whole conversation (they anchor on it).
- Hiding disagreement to look decisive.
- Starting several agents for a small decision; cost must match the stakes.
