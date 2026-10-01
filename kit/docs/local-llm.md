# Local LLM, usage capture and comparison packs: design notes

Modules `15-local-llm` (CLI `kit-llm`), `14-llm-usage` (CLI `llm-usage`) and the comparison
packs in `50-eval/packs/`. Research background: `docs/research-company-ai-setups.md` sections 2
(three-tier tool policy, local runtimes for data that must not leave the building), 6 (eval
tooling) and 7 (observability, OpenTelemetry GenAI conventions). All facts below were checked
on 2026-09-25.

## Engine: llama.cpp prebuilt release, not Ollama

| | llama.cpp `b11146` ubuntu-x64 | Ollama `v0.34.4` linux-amd64 |
|---|---|---|
| Download | 17.0 MB `.tar.gz` | 1,427.7 MB `.tar.zst` (bundles GPU libraries) |
| Install | unpack into `$HOME`, run `llama-server` | unpack into `$HOME`, run `ollama serve`, import GGUF via Modelfile into its own store |
| API | OpenAI-compatible `/v1/chat/completions`, `/v1/models`, web chat | OpenAI-compatible `/v1`, own API |
| Model files | GGUF used in place | copied into `~/.ollama/models` (second copy on disk) |
| CPU dispatch | 13 CPU backends (`sse42` ... `haswell` = AVX2 ... `sapphirerapids`), best one loaded at runtime | bundles llama.cpp-derived runner |

Decision: llama.cpp. It is 80 times smaller on the stick, needs no model import step, and the
runtime CPU dispatch covers the AVX2 baseline and newer CPUs with one archive. Ollama stays an
option the engine pack can compare against when IT allows it (`engines.conf.example`), but it is
not shipped.

Version: release `v0.5.0` of 2026-09-23, whose `nightly-tag.txt` asset names build `b11146`; the
per-build releases (`bNNNNN`) are marked prerelease on GitHub, `v0.5.0` is the versioned release.
sha256 values come from the GitHub release API `digest` field and were re-checked after download.

Linux runtime dependencies of `llama-server` and its libraries (from `objdump -p`): `libstdc++.so.6`,
`libgcc_s.so.1`, `libc.so.6` (max symbol version GLIBC_2.34), `libm.so.6`, `libgomp.so.1`,
`libssl.so.3`, `libcrypto.so.3`, all with `RUNPATH $ORIGIN` for the bundled libraries. The
Ubuntu 24.04.5 desktop manifest lists `libc6 2.39`, `libgomp1`, `libssl3t64`, `libstdc++6` and
`libgcc-s1`, so nothing extra is shipped; `install.sh` and `kit-llm doctor` run `ldd` and name
missing libraries (IT fix: `apt install libgomp1 libssl3t64`).

The macOS arm64 archive of the same build is fetched only with `fetch.sh --dev-mac` for testing
the kit on a Mac; it is not needed on the laptop.

## Models

Candidates: GGUF, 1–4 B parameters, Apache-2.0, not gated, German in the training languages,
Q4 quantization (fits 8 GB RAM with a desktop running). Licenses and gating read from the
Hugging Face model API (`cardData.license`, `gated`) of the base model and the GGUF repo on
2026-09-25. Every file is pinned by repository commit and sha256 in `models.conf`; `fetch.sh`
downloads `https://huggingface.co/<repo>/resolve/<commit>/<file>` and checks the sha256.

| id | GGUF repo (publisher) | file | MB | ship |
|---|---|---|---|---|
| qwen3.5-4b | unsloth/Qwen3.5-4B-GGUF (quantized by Unsloth; Qwen publishes no GGUF) | Q4_K_M | 2,614 | default |
| granite-4.0-micro | ibm-granite/granite-4.0-micro-GGUF (IBM) | Q4_K_M | 2,002 | default |
| qwen3.5-2b | unsloth/Qwen3.5-2B-GGUF | Q4_K_M | 1,222 | default |
| ministral-3-3b | mistralai/Ministral-3-3B-Instruct-2512-GGUF (Mistral) | Q4_K_M | 2,048 | optional |
| gemma-4-e2b | ggml-org/gemma-4-E2B-it-GGUF (ggml-org) | Q4_0 | 2,710 | optional |

Not considered further: SmolLM3-3B (German not in its language list), Llama 3.2 (community
license with use restrictions), Phi-4-mini (3.8 B, older generation), EuroLLM-1.7B and
Teuken-7B (no official instruct GGUF in range / too large).

Qwen3.5 thinks by default; the catalog passes `--reasoning-budget 0` so answers come without a
reasoning block (checked: German smoke answer "Berlin" in 4 output tokens).

### Measurement (model pack, CPU only)

Method: `50-eval/packs/models/run.sh --models ... -n 2`, 13 cases, temperature 0, 512 max
tokens, context 4,096, `-ngl 0` (CPU only), llama.cpp b11146 macOS arm64 build on a MacBook Pro
(Apple M5 Pro, 48 GB), 2026-09-25. Quality numbers transfer to the Linux laptop (same GGUF, same
engine version, greedy decoding); speed does not (ARM CPU with high memory bandwidth), so the
speed column only ranks the models against each other. gemma-4-e2b was re-run after adding
`--reasoning-budget 0` (without it every answer was spent on reasoning text, 9,120 output tokens).

| model | pass rate (26 runs) | latency mean | output tok/s | failed cases |
|---|---|---|---|---|
| qwen3.5-4b | 92 % | 1.75 s | 15.1 | en-code-explain |
| granite-4.0-micro | 92 % | 0.90 s | 24.2 | de-math |
| ministral-3-3b | 77 % | 1.41 s | 20.6 | de-math, en-code-explain, en-code-python |
| gemma-4-e2b | 77 % | 6.11 s | 35.1 | de-sentiment, en-bullets, en-ticket-classify (reasoning text leaks into the answer, format ignored) |
| qwen3.5-2b | 69 % | 0.92 s | 28.3 | de-email-summary, de-math, en-code-explain, en-de-translate |

All five passed German extraction to JSON (after the gemma fix), both grounding cases (answer
"NICHT IM TEXT" when the fact is missing) and German/English translation direction DE→EN.

Decision: ship qwen3.5-4b (best overall, default), granite-4.0-micro (equal pass rate, fastest,
second model family for cross-checks and LLM-judge use), qwen3.5-2b (1.2 GB, for 8 GB
machines and quick classification; weaker German generation). Ministral 3 3B and Gemma 4 E2B
stay in the catalog as `optional` (`fetch.sh --all`). Default download: 5.8 GB of models plus
17 MB engine. Thirteen cases separate "usable" from "not usable", not 92 % from 85 %; re-run
the pack with cases from the real use before relying on a model.

Engine settings, same model (qwen3.5-2b), `engines/run.sh --requests 9 --max-tokens 128`,
unique prompt prefix per request (prompt cache defeated), same machine:

| engine | decode tok/s | prompt tok/s | TTFT 2,176-token prompt | quality subset |
|---|---|---|---|---|
| b11146, default threads | 44.6 | 130 | 12.2–13.1 s | 4/6 |
| b11146, 4 threads | 41.7 | 111 | 14.8–15.2 s | 4/6 |
| Homebrew build 10470 | 28.8 | 86 | 24.8–27.4 s | 2/6 |

The old build ignores `--reasoning-budget 0` for Qwen3.5 (2,903 output tokens for six short
answers) and loses JSON and SQL cases: the engine pack catches exactly this kind of regression.
On a CPU, prompt processing (~100–130 tokens/s here) dominates for long inputs: a 2,000-token
document takes 15–20 s before the first answer token; plan use cases accordingly.

## RAM guard

`kit-llm start` refuses when `model file + KV cache estimate + 300 MB` plus a reserve
(`KIT_LLM_RESERVE_MB`, default 1,024 MB for the desktop) exceeds available memory
(`MemAvailable` from `/proc/meminfo`; on macOS free + inactive + speculative pages). The KV
estimate is 0.12 MB per context token: an upper bound for the catalog models (a 26-layer model
with 8 KV heads of 128 dimensions in f16 needs 2 × 26 × 8 × 128 × 2 bytes = 0.1 MB per token;
the Qwen3.5 hybrid-attention models need less). With the default 16,384-token context (`KIT_LLM_CTX`) the need
is file size + about 2,270 MB (300 MB + 16,384 × 0.12 MB), plus the reserve. `kit-llm models` prints the need
of every catalog model at the current context, `kit-llm doctor` repeats it with the fit verdict; on an 8 GB
laptop pick a smaller model or lower the context (`--ctx 4096` saves about 1.5 GB). `--force` overrides with a warning. `-ngl 0` keeps inference on
the CPU even where a GPU backend exists, so numbers are comparable to the laptop.

## Endpoint and safety

- `llama-server` binds to `127.0.0.1` only (`--host` is not configurable in `kit-llm`); other
  machines cannot reach it. Other local users could; the laptop is single-user.
- No API key is configured by default; OpenAI clients get `OPENAI_API_KEY=local-no-key` from
  `kit-llm env`.
- The config file is parsed (known keys, plain values), never sourced; a test proves a
  `$(...)` value is not executed.
- The web chat of llama-server (`http://127.0.0.1:8080/`) stays enabled: it is the quickest
  way for non-developers to try a local model on confidential text without any cloud.

## 14-llm-usage: OpenTelemetry GenAI fields

Source: `open-telemetry/semantic-conventions-genai`, `docs/gen-ai/gen-ai-spans.md` at commit
`8ffdf568e1b4` (2026-09-22). The GenAI conventions moved out of the main semantic-conventions
repository (v1.44.0); status is "Development", so names may still change.

One JSONL line per call, one span per line: `trace_id`, `span_id`, `name`
(`{gen_ai.operation.name} {gen_ai.request.model}`), `kind` CLIENT, `start_time`, `end_time`,
`duration_s`, `status`, `attributes`:

| Attribute | Filled from |
|---|---|
| `gen_ai.operation.name` | `chat` (chat/completions, responses), `text_completion`, `embeddings`, `invoke_agent` (wrap) |
| `gen_ai.provider.name` | `--provider` (well-known values like `openai`, `azure.ai.openai`; default `llama.cpp`) |
| `gen_ai.request.model`, `.temperature`, `.top_p`, `.seed`, `.max_tokens`, `.stream` | request body |
| `gen_ai.response.id`, `.model`, `.finish_reasons` | response body or stream chunks |
| `gen_ai.response.time_to_first_chunk` | streaming only, seconds |
| `gen_ai.usage.input_tokens`, `.output_tokens`, `.cache_read.input_tokens`, `.reasoning.output_tokens` | `usage` object (chat and responses API names) |
| `gen_ai.input.messages`, `gen_ai.output.messages` | only with `--capture-content` (opt-in, as the conventions require) |
| `server.address`, `server.port`, `error.type`, `http.response.status_code` | upstream and result |
| `kit.cost_usd`, `kit.tag`, `kit.command`, `kit.exit_code` | kit extensions |

Cost: `usage.cost` from the provider if present, else `llm-prices.toml`, else unknown (never
silently 0); `--free` records 0 for local engines. Streaming requests are passed through chunk
by chunk; usage is taken from the last chunk, which OpenAI-compatible servers send only when the
client asks for `stream_options.include_usage` (the proxy does not modify requests, so such
calls may have unknown tokens). `llm-usage export` writes OTLP/JSON (`resourceSpans`) that an
OpenTelemetry collector or an OTLP-capable backend (Langfuse, Phoenix) can ingest later; no
backend runs on the laptop.

## Comparison packs (50-eval)

- `models/`: 13 cases, German and English, deterministic graders only (exact/regex, JSON
  schema + field values, numeric, script checks that run generated Python and SQL against
  fixtures). `fake` / `fake-bad` providers prove the graders accept correct and reject wrong
  answers without a model. Runner starts each catalog model with `kit-llm`, one at a time.
- `engines/`: `bench.py` (streaming, warm-up excluded, TTFT, decode and prompt tokens/s) plus
  six deterministic model-pack cases per engine, so a speed gain that changes answers shows up.
- `harnesses/`: five synthetic tasks (bug fix, tests that must catch two planted bugs, rename
  refactoring, README usage docs, COBOL explanation), each in a fresh temp git repo with hooks
  disabled, harness stdin closed, script check. `fake-good` / `fake-noop` validate the checks.

evalkit core is unchanged; packs use only the documented suite format.

## Verification log

All on the Mac above, 2026-09-25, scratch directories only (no user configuration touched).
The pytest runs need pytest, which is not shipped on the stick (build host only).

| What | Command | Observed |
|---|---|---|
| Pins | `fetch.sh --all --dev-mac` then `--verify` | 7/7 files `ok` against the pinned sha256 |
| kit-llm logic (fake engine) | `bash 15-local-llm/tests/test-kit-llm.sh` | 40/40 ok: install/idempotence/backup, RAM guard refuse and `--force`, busy port, crash at start, stop leaves no process, config parsed not executed, uninstall |
| Real engine | `bash 15-local-llm/tests/smoke-real.sh qwen3.5-4b` | ready, DE "Berlin" (4 tokens), EN "42", stop ok |
| llm-usage | `pytest 14-llm-usage/tests` + `bash tests/test-install.sh` | 9 passed; 10/10 ok |
| llm-usage on the real engine | proxy on 14011 in front of kit-llm, `bench.py` (streaming) + evalkit (non-streaming) through it | 6 calls recorded, 2,488 in / 201 out tokens, proxy tok/s 45.5 = bench 45.4, prompts not stored |
| Packs offline | `bash 50-eval/packs/tests/test-packs.sh` | 20/20 ok: fake 100 %, fake-bad 0 %, engine runner with fake streaming server, harness fake-good 5/5 and fake-noop 0/5, no temp repos left |
| Real harness | aider 0.86.2 + local qwen3.5-4b via harness pack | fix-bug pass, doc-readme and rename fail with a correct reason, temp repos removed |
| Lint | `shellcheck -x` (0.11.0) on all new shell files, `py_compile` on all new Python | clean |

Not tested here: the Linux x86_64 binary (needs the Lima VM end-to-end test), cloud harnesses
(Claude Code, Codex, opencode, Copilot, Gemini CLI: flags checked with `--help` only, Gemini CLI
from its docs because it is not installed), Ollama as a second engine.

## 14-llm-usage: commands, logs, prices

```sh
llm-usage wrap --provider claude-code --tag review -- claude -p "Summarize this diff"
llm-usage export --since 30d --out spans.json      # OTLP/JSON for a collector
```

Logs: `~/.local/share/work-kit/llm-usage/usage-YYYY-MM.jsonl` (one line per call, as above).
Prices: `~/.config/work-kit/llm-prices.toml`. `llm-usage summary --by` accepts
`model`, `provider`, `day`, `operation`, `tag`.

## 15-local-llm: build host

`bash fetch.sh` in the module folder fills `kit/offline/local-llm` (pins and sha256 inside;
`--all` adds the optional models). `install.sh` options: `--models ID[,ID]`, `--all`,
`--no-models`; `bash uninstall.sh --keep-models` keeps the model files.
