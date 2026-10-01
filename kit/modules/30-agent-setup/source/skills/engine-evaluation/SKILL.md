---
name: engine-evaluation
description: 'Compare inference engines or engine settings (llama.cpp builds, thread counts, Ollama, any OpenAI-compatible server) serving the same model file: time to first token, decode and prompt tokens per second, and a quality check that the answers did not change. Use before choosing a local runtime, after upgrading an engine, or when local inference feels slow. Do not use for choosing between different models (model-evaluation) or coding CLIs (harness-evaluation).'
---

# Engine evaluation

An engine comparison is only fair when the model file, quantization, context size, prompt and
generation settings are identical. Change one thing at a time.

## Tools

- Pack: `~/work/kit/modules/50-eval/packs/engines/` with `bench.py` (streaming benchmark,
  standard library only), `engines.conf.example` and `run.sh`.
- `kit-llm` (module 15-local-llm) starts llama.cpp; `KIT_LLM_THREADS`, `KIT_LLM_CTX` and
  `KIT_LLM_SERVER` switch settings or builds.
- `evalkit` (module 50-eval) runs the quality subset of the model pack.

## Procedure

1. **State the question**: "Is llama.cpp b11146 faster than the previous build on this laptop
   with qwen3.5-2b?" or "Which thread count gives the best decode speed?" Name the metric
   that decides (usually decode tokens/s for chat, TTFT for long prompts).
2. **Prepare the same model everywhere.** For Ollama, import the same GGUF file
   (`Modelfile` with `FROM /path/to/file.gguf`) instead of pulling a different quantization.
   Only run engines IT allows on the laptop.
3. **Write the config**: `cp engines.conf.example engines.conf`, one line per engine:
   `id | base URL | model name | start command | stop command` (`-` = already running).
4. **Quiet machine**: close heavy programs, plug in power, no other model server running
   (`kit-llm status`). Note CPU model, RAM, power mode.
5. **Run**: `bash run.sh --requests 9 --max-tokens 128` (add `--concurrency 2` to test
   parallel users). Per engine the runner starts it, waits for `/v1/models`, runs `bench.py`
   (one warm-up request, then short German, short English and a ~1,500-token German prompt),
   runs six deterministic model-pack cases, and stops it.
6. **Read `comparison.md`**: throughput table (TTFT mean/p95, decode tok/s, prompt tok/s,
   total time) and the pass rate of the quality subset. A faster engine whose pass rate
   dropped is not faster, it is different: check chat template and sampling settings.
7. **Repeat** the winning pair once more; keep a result only if it holds (±10 %).
8. **Record** engine versions, model file sha256, settings, machine and numbers in the brain
   (`brain new note "Engine evaluation: <question>"`) or the project docs.

## When a tool is missing

- No `kit-llm`: start the engine by hand and use `-` for start/stop in the config.
- No `evalkit`: run with `--quality-cases none` and compare a few answers by hand.
- `bench.py` needs only Python 3 and an OpenAI-compatible streaming endpoint.

## Done when

- Same model file and settings for every engine, differences listed explicitly.
- Throughput numbers and quality pass rate exist for every engine, from the same machine.
- The recommendation names the deciding metric and the measured margin.

## Pitfalls

- Comparing a Q4 GGUF in one engine with a Q8 or different model in another.
- Measuring the first request (model load) as latency: `bench.py` warms up; do not disable it.
- Laptop on battery or thermal throttling; background indexing (brain reindex) during runs.
- Engines that ignore `max_tokens` or report no usage: `bench.py` then counts chunks, which
  is marked `tokens_reported: false` in the JSON.
