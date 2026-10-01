# evalkit comparison packs

Ready-made suites and runners. Each runner writes one evalkit JSON per candidate and a
`comparison.md` into `--out` (default `~/.local/share/work-kit/evalkit/packs/<pack>-<time>/`).

| Pack | Compares | Run |
|---|---|---|
| `models/` | models on 13 German/English work tasks | `bash models/run.sh --models qwen3.5-4b,ministral-3-3b -n 3` |
| `engines/` | engines/settings with the same model: TTFT, tokens/s, quality | `cp engines/engines.conf.example engines/engines.conf; bash engines/run.sh` |
| `harnesses/` | coding CLIs on 5 tasks in temp git repos | `cp harnesses/harnesses.conf.example harnesses/harnesses.conf; bash harnesses/run.sh --harnesses claude,codex` |

Offline checks without any model: `evalkit run models/suite.yaml -p fake` (all pass),
`-p fake-bad` (all fail), `bash harnesses/run.sh --harnesses fake-good,fake-noop`.
Other tools: `lib/compare.py DIR` (side-by-side table), `engines/bench.py` (one endpoint).
Local models come from `kit-llm` (module 15-local-llm). Skills: `model-evaluation`,
`engine-evaluation`, `harness-evaluation`. Test: `bash tests/test-packs.sh`.
