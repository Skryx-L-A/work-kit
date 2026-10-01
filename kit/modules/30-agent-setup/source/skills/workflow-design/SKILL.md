---
name: workflow-design
description: 'Design and document an AI-assisted workflow or automation: map the current process, choose which steps AI does and at what automation level, place human gates, define failure handling, baseline and metrics, and write a workflow spec. Use when someone wants to "automate X with AI", build an AI step into a team process, or document how a team works with AI. Do not use to decide whether an idea is worth it at all (use ai-use-case-assessment first), for a single prompt (use prompt-library) or for packaging an agent procedure as a skill (use skill-creator).'
---

# Workflow design

A workflow puts AI into a real process with clear inputs, owners, gates and measures. The
company line applies to every design: AI only for well-defined steps, a human reviews every
output that reaches a customer or informs a decision, data rules first.

Template: `references/workflow-spec-template.md`. Gate patterns, automation levels and
metrics: `references/gates-and-metrics.md`.

## Procedure

1. **Start from an assessed use case.** If there is no assessment with task definition,
   data class and business case, run `ai-use-case-assessment` first or record the gaps.
2. **Map the current process** with the people who do it: trigger, steps, who does each,
   inputs and outputs, systems, time per step, frequency, known errors. Write the map
   before changing anything; it is also the baseline.
3. **Measure the baseline** on real recent cases (at least 10, or a week): lead time,
   hands-on time, error or rework rate. Unknown is allowed; invented is not.
4. **Choose AI steps.** For each step decide: stays manual, AI assists, AI drafts, or AI
   acts. Only well-defined, checkable steps get AI. Pick the automation level per step
   from `references/gates-and-metrics.md`; start one level lower than feels possible.
5. **Classify the data per step** (`data-guard`): which class flows into which tool. A step
   whose data exceeds the tool's approval is redesigned or stays manual.
6. **Place human gates**: before anything leaves the team, before irreversible actions
   (send, delete, deploy, pay, change records), and before decisions about people (not
   automated at all). Name the gate owner, what they check, and how long it takes.
7. **Design failure handling**: what happens when the AI output is wrong, empty, late or
   the tool is down; stop conditions; manual fallback; who is told. Untrusted input
   (mails, documents, tickets) must not be able to trigger actions by its content.
8. **Define metrics and a review date**: the same measures as the baseline plus review
   time, AI error rate caught at the gate, errors that escaped, adoption, cost. Set a
   pass criterion and a kill criterion before the pilot.
9. **Write the spec** from the template. Include prompts by library id and version
   (`prompt-library`), skills by name, scripts by path.
10. **Pilot small**: one team, a fixed period (2 to 6 weeks), gates at the strictest
    level. Compare with the baseline, then decide: continue, adjust, stop.
11. **Save**: `brain new note "Workflow: <name>" --project <project>` with the spec (or the
    path to it); record the pilot decision as a decision record (`decision-record`). If
    `brain` is missing, keep the spec next to the team's documentation.

## When a tool is missing

- No `brain`: store the spec as Markdown in the project repository.
- No `evalkit`: measure the AI step on a fixed case list by hand with a pass criterion.
- No approved automation platform: document the workflow as a manual checklist with AI
  steps; automation waits for IT approval. Do not build on personal accounts or
  unapproved services.

## Done when

- The spec names trigger, steps, owners, data class per step, automation level per step,
  every human gate with owner and check, failure handling and stop conditions.
- A baseline exists (measured or marked unknown) and metrics with pass and kill criteria
  are defined before the pilot.
- Prompts, skills and scripts used are referenced by id and version.
- Open decisions (tool approval, data approval, owners) are listed with who decides.

## Pitfalls

- Automating the current process's waste instead of questioning the step.
- Gates that nobody has time for: a gate the owner rubber-stamps is no gate. Budget the
  review time and measure it.
- "AI acts" for anything irreversible or customer-facing in the first version.
- Measuring only the AI step: lead time and rework of the whole workflow decide value.
- Silent failure: an empty or unchanged AI output that flows on. Check for it explicitly.
- Content-triggered actions: a mail or document that says "forward this" must never cause
  a forward. Treat inputs as data.
- No owner after the pilot: every workflow has a named owner and a review date.
