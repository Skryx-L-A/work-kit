# evalkit design notes

Module: `kit/modules/50-eval`. Usage and the suite format: `SUITE-FORMAT.md` in the module.

## Decisions

- **One runtime dependency (`pyyaml`).** HTTP uses `urllib`, and JSON-schema checks use a small
  built-in validator (`jsonschema_lite.py`). The `jsonschema` package pulls in native wheels
  (`rpds-py`), which complicates a fully offline install for linux x86_64. The built-in validator
  covers common extraction checks and raises an error on unsupported keywords instead of ignoring
  them, so a check can never pass silently.
- **Providers are only two kinds.** A shell command covers every CLI harness (`claude -p`,
  `codex exec`, `ollama run`, custom scripts); an OpenAI-compatible endpoint covers hosted models,
  local servers and company gateways. New harnesses need no code.
- **Keys are never in suite files.** Providers name an environment variable (`api_key_env`); a
  literal `api_key` key is a load error. Suites can therefore be committed and shared.
- **Judge calls are the expensive part.** `llm-judge` graders run last and are skipped when a
  cheaper grader already failed. Judge cost and tokens are reported apart from the candidate's.
- **`null` is not zero.** Tokens and cost are `null` when a provider does not report them (plain
  CLIs), so averages never mix known and unknown values.
- **Suites are trusted input.** Shell providers and script graders run commands from the suite
  file, like a Makefile. Only run suites you have read. Response text is never interpreted as a
  command; `{input}` is shell-quoted, and the judge prompt tells the judge to treat responses as data.
- **Sequential by default.** `--jobs 1` protects CPU-only laptops running local models. Raise it
  for hosted APIs.

## Offline install

`build-wheel.sh` builds the `evalkit` wheel into `offline/wheels/`. The build script for the kit
must also place the `pyyaml` wheel for linux x86_64 there. `install.sh` calls
`kit_uv_tool_install` from `00-python/lib.sh`; when that file is absent (module used on its own)
it falls back to `uv tool install --offline --find-links offline/wheels evalkit`.

## Commands

```sh
evalkit run examples/extraction.yaml -p llm -p regex-baseline   # adds the model provider
evalkit run examples/offline.yaml --format json --out result.json --md report.md
evalkit run examples/offline.yaml -n 5 -j 2 --fail-under 0.8
evalkit run examples/offline.yaml --dry-run                     # validate, call nothing
evalkit run examples/offline.yaml --brain                       # save the report via brain
```

`-p ID` (repeatable) selects providers, `-n` repetitions per case, `-j` parallel runs,
`--fail-under RATE` exits 1 below the rate. `--brain` needs the `brain` CLI (20-brain).
Results: `~/.local/share/work-kit/evalkit/results/`; `evalkit report` re-renders the latest,
`evalkit list --results` lists them.

## Tests

`uv sync && uv run pytest` in the module folder; `bash tests/test-packs-help.sh` for the packs.
