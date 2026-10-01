---
name: eval-design
description: 'Design and run a test suite that measures whether an AI prompt, model, agent or tool does a defined task well enough, using the evalkit CLI. Use before adopting a model or prompt, when comparing models/harnesses, after changing a prompt, or to back a use-case decision with numbers. Do not use for ordinary unit tests of deterministic code (use test-strategy) or for judging a single answer by eye.'
---

# Eval design

An eval replaces "it looked good in the demo" with a pass rate on cases chosen before the
results were seen. Small and honest beats large and vague.

## Procedure

1. **Fix the question.** "Does model X explain our COBOL paragraphs correctly enough that a
   developer accepts ≥ 80 % without edits?" Name the decision the result will inform and
   the threshold, before running anything.
2. **Collect cases** (start with 15 to 40):
   - representative everyday inputs, plus known hard cases and edge cases,
   - only data the destination may see (`data-guard`); use synthetic or public examples
     when unsure,
   - freeze the set before looking at outputs; keep a held-out part if you will tune
     prompts on the rest.
3. **Choose graders per case**, cheapest reliable first:

| Output | Grader |
|---|---|
| exact label, ID, yes/no | exact |
| must mention / must not mention | contains, regex |
| structured data | JSON schema, then field checks |
| number | numeric tolerance |
| runnable code | script (compile, run tests) |
| free text quality | LLM judge with a written rubric, spot-checked by a human |

4. **Write the rubric** for judged cases as observable criteria ("names the file that is
   read", "no invented variable names"), each pass/fail, not a 1-10 vibe score.
5. **Define providers**: the command or endpoint for each candidate (shell command such as
   a CLI harness in print mode, a local model runner, or an OpenAI-compatible endpoint).
   Keep temperature and system prompt fixed and recorded.
6. **Write the suite** as YAML for evalkit. Copy the exact field names from the examples
   shipped with the eval module (`~/work/kit/modules/50-eval/examples/`) or
   `evalkit --help`; see `references/suite-sketch.md` for the structure.
7. **Run** with repetitions (at least 3 for non-deterministic outputs):
   `evalkit run <suite.yaml>` (options per `evalkit run --help`). Record model versions,
   date and cost/latency if reported.
8. **Read failures**, not just the rate. Classify each failure: model error, prompt
   ambiguity, wrong expected value, grader bug. Fix graders and expectations only with a
   written reason; never tune them to make a candidate pass.
9. **Report**: pass rate per candidate with repetitions, cost and latency, failure classes,
   and a recommendation against the threshold from step 1. Save with `--brain` or
   `brain new note "Eval: <topic>"`.

## When evalkit is missing

Write the cases as a YAML or CSV file anyway, run each provider with a small shell or Python
loop, save raw outputs to files, and grade with the same graders by script or by hand. The
report format stays the same. Say that it was run without evalkit.

## Done when

- Question, threshold and case set were fixed before results were seen.
- Every candidate ran the same cases with the same repetitions and settings.
- The report shows pass rate, variance across repetitions, failure classes and cost/latency.
- The raw outputs are saved and the run can be repeated with one command.

## Pitfalls

- Test set leakage: tuning the prompt on the same cases you report.
- LLM judge grading its own model family's outputs without human spot checks (check at
  least 10 judged cases by hand and report agreement).
- Too few cases to separate candidates: 18/20 vs 17/20 is not a difference.
- Confidential inputs sent to an unapproved provider during testing.
- Reporting only the average. Show the worst failures; they decide adoption.
