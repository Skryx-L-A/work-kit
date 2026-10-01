---
name: model-evaluation
description: 'Compare language models (local GGUF models or approved cloud endpoints) on the same fixed task set and recommend one for a named use, with pass rates, latency, tokens and cost. Use when choosing or replacing a model, when someone asks "is model X good enough for Y", or before switching a prototype to a local model. Do not use for comparing inference engines with the same model (engine-evaluation), coding CLIs (harness-evaluation), or for designing a new suite from scratch (eval-design).'
---

# Model evaluation

Pick a model by measured results on the work it will do, not by leaderboards or datasheets.
Same cases, same settings, same repetitions for every candidate.

## Tools

- `evalkit` (module 50-eval) runs the suites. The model pack lives in
  `~/work/kit/modules/50-eval/packs/models/` (`suite.yaml`, `run.sh`, `checks.py`).
- `kit-llm` (module 15-local-llm) starts one local model at a time on `127.0.0.1`.
- `llm-usage` (module 14-llm-usage, optional) records tokens and latency of every call.

## Procedure

1. **Fix the decision first.** Write down the use ("summarize German support e-mails"), the
   threshold ("≥ 90 % of cases pass, answer within 20 s on the laptop") and the data class of
   the real inputs. Decide which destinations are allowed for that data class (`data-guard`
   skill); cloud candidates only if the class allows them.
2. **Choose candidates**: 2 to 4 models. Local: `kit-llm models` shows installed models and
   whether they fit in the free RAM. Cloud: only endpoints IT approved, key in an environment
   variable (never in the suite).
3. **Choose cases.** Start with the shipped pack (13 German and English cases: extraction to
   JSON, classification, summary, translation, arithmetic, code, SQL, grounded answers).
   Add 5 to 20 cases from the real use, with synthetic or public data only, in a copy of
   `suite.yaml`. Freeze the cases before looking at any output.
4. **Dry run**: `evalkit run suite.yaml -p fake` must pass all cases and `-p fake-bad` must
   fail nearly all; this proves the graders work before model time is spent.
5. **Run**:
   - local models: `bash run.sh --models qwen3.5-4b,ministral-3-3b -n 3`
   - cloud or other endpoints: add providers to the copied suite, then
     `bash run.sh --suite my-suite.yaml --providers gateway-model -n 3`
   `run.sh` starts and stops each local model, writes one evalkit JSON per candidate and
   `comparison.md` (pass rate, per-case matrix, latency, output tokens/s, cost).
6. **Read the failures** in the JSON (`runs[].output`, `runs[].graders[].reason`). Classify:
   model error, prompt ambiguity, grader bug, wrong expectation. Fix graders only with a
   written reason and rerun every candidate.
7. **Decide and record**: recommendation against the threshold from step 1, with the
   per-case table, model versions (catalog id, file sha256 or API model name), date, machine,
   repetitions. Save with `evalkit report --brain` or `brain new note "Model evaluation: <use>"`.

## Reading the numbers

- Temperature 0 makes local runs nearly deterministic; use `-n 3` anyway for cloud models.
- A difference of one or two cases out of 13 is noise. Add cases before claiming a winner.
- Latency on the laptop CPU depends on RAM bandwidth and threads; measure on the machine
  that will run it. Tokens per second in the table come from reported usage.
- Small local models (1–4 B) are fine for extraction, classification and short summaries;
  expect failures on multi-step reasoning and long code. Say so in the recommendation.

## When a tool is missing

- No `kit-llm`: point `KIT_LLM_BASE_URL` at any OpenAI-compatible endpoint and run
  `evalkit run suite.yaml -p local` per model with `EVAL_MODEL=<name>`.
- No `evalkit`: send the same prompts by script, save outputs to files and grade them with
  `checks.py` (it reads the answer on stdin). Report that the run was manual.

## Done when

- Decision, threshold, candidates and cases were fixed before the first run.
- Every candidate ran the same cases with the same settings; `comparison.md` exists.
- Failures were read and classified; the recommendation names its limits.
- The result is saved in the brain (or a file in the project) with versions and date.

## Pitfalls

- Testing with real customer or confidential data on a cloud candidate.
- Changing the prompt or cases after seeing results for one candidate only.
- Comparing a quantized local model with a full cloud model and calling it "the same model".
- Forgetting that `--force` skips the RAM guard: a swapping laptop gives useless latencies.
