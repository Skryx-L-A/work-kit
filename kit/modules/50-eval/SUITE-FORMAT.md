# evalkit: suite format

`evalkit` runs a **suite** (a YAML file) against one or more **providers** and grades every
response with **graders**. Each provider x case pair is repeated N times; the report shows pass
rates, latency, and tokens/cost when the provider reports them.

## Commands

| Command | Purpose |
|---|---|
| `evalkit run SUITE` | Run a suite. Prints a Markdown report, saves a JSON result. |
| `evalkit report [RESULT]` | Re-render a saved result (file path, suite name = latest of that suite, none = latest overall). |
| `evalkit list [PATH]` | List suites in a folder (default `.`); `--results` lists saved results. |

`run` options: `-p/--provider ID` (repeatable), `-c/--case ID` (repeatable), `-n/--repetitions N`,
`-j/--jobs N` (parallel runs, default 1), `--format md|json` (stdout), `--out FILE`, `--md FILE`,
`--no-save`, `--brain`, `--brain-project P`, `--fail-under RATE`, `--dry-run`, `-q/--quiet`.

Exit codes: `0` ok, `1` pass rate below `--fail-under`, `2` invalid suite / usage error.

Results are saved to `$EVALKIT_HOME/results/` (default `~/.local/share/work-kit/evalkit/results/`).

## Suite schema

```yaml
name: my-suite              # default: file name
description: what this measures
repetitions: 3              # per provider x case, default 1
timeout: 60                 # seconds per provider or judge call, default 60
prompt: |                   # optional template for every case; must contain {input}
  Answer briefly.

  {input}

providers: [...]            # required, at least one
judges: [...]               # required only when a case uses an llm-judge grader
cases: [...]                # required, at least one
```

Unknown keys are errors, so typos do not silently disable a check. Provider and case ids are
plain strings; avoid the YAML words `yes`, `no`, `on`, `off`, `true`, `false`, `null` as ids (YAML
turns them into booleans).

### Providers

Common keys: `id` (unique), `type` (`shell` or `openai`), `default` (optional; `false` means the
provider only runs when selected with `-p`).

**`type: shell`**: runs a command through `sh -c` in the suite's folder.

| Key | Meaning |
|---|---|
| `command` | Command line. `{input}` is replaced by the shell-quoted prompt. `{python}` is the Python running evalkit. Other braces (awk, jq, JSON) are left alone. |
| `input_mode` | `auto` (default): `arg` if the command contains `{input}`, else `stdin`. `arg` substitutes `{input}`; `stdin` pipes the prompt to the command. |

The response is stdout. A non-zero exit code or a timeout is a provider error (the run fails and
graders are skipped). The whole process group is killed on timeout. A shell provider reports latency
only; tokens and cost are unknown for plain CLIs. Examples: `claude -p {input}`,
`codex exec {input}`, `ollama run llama3.2` (stdin).

**`type: openai`**: any OpenAI-compatible `POST {base_url}/chat/completions` (OpenAI, Ollama,
vLLM, LM Studio, company gateways).

| Key | Meaning |
|---|---|
| `base_url`, `model` | Required. May use `${VAR}` or `${VAR:-default}`; expanded when the provider is used. |
| `api_key_env` | Name of the environment variable that holds the key. Omit for endpoints without auth. |
| `system` | Optional system message. |
| `temperature`, `max_tokens` | Optional request parameters. |
| `extra_body` | Optional mapping merged into the request body. |
| `price.input_per_1m`, `price.output_per_1m` | USD per million tokens. With both set, cost is computed from the reported usage. A `usage.cost` value in the response takes precedence. |
| `retries` | Retries for HTTP 408/429/5xx and connection errors, default 2 (exponential backoff). |

**Keys never go into the suite.** A literal `api_key:` is rejected, and `api_key_env` must look
like a variable name, not a key.

### Judges

`judges` is a list of providers (same format) that grade responses; they are not evaluated as
candidates. An `llm-judge` grader uses the first judge unless it names another one with
`judge: <id>`. Use a judge from a different model family than the candidate when possible.

### Cases

```yaml
cases:
  - id: unique-name
    input: "text sent to the provider"      # or: input_file: path/relative/to/suite
    graders: [...]                           # all must pass
```

### Graders

A run passes when the provider answered without error and **all** graders pass. Graders run in the
listed order except `llm-judge`, which always runs last and only if all other graders passed (saves
judge calls). Any grader accepts `negate: true` to invert its result.

| Type | Keys | Passes when |
|---|---|---|
| `exact` | `value`, `strip` (default true), `ignore_case` | response equals `value` |
| `contains` | `value` (string or list), `mode` (`all` default, or `any`), `ignore_case` | substring(s) present |
| `regex` | `pattern`, `flags` (letters `i m s x`) | `re.search` finds a match |
| `json-schema` | `schema` (inline) or `schema_file` (relative to suite) | JSON found in the response validates |
| `numeric` | `expected`, `tolerance` (absolute), `rel_tolerance`, `pick` | number within tolerance |
| `script` | `command` | command exits 0 |
| `llm-judge` | `rubric`, `judge` | judge answers `pass` |

Details:

- **json-schema** extracts JSON from plain output, from a fenced code block, or from prose (first
  parseable object/array). Supported keywords: `type`, `enum`, `const`, `properties`, `required`,
  `additionalProperties`, `items`, `minItems`, `maxItems`, `uniqueItems`, `minLength`, `maxLength`,
  `pattern`, `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`, `anyOf`,
  `oneOf`, `allOf`, `not`. Any other keyword (for example `$ref`) is a load-time error, never
  ignored.
- **numeric** `pick`: `whole` (default; the entire response must be a number), `first` or `last`
  (first or last number found in the text). Thousands separators like `1,234.5` are understood.
  The effective tolerance is `max(tolerance, |expected| * rel_tolerance)`.
- **script** receives the response on stdin and the files `$EVALKIT_INPUT_FILE` (the case input)
  and `$EVALKIT_OUTPUT_FILE` (the response). It runs in the suite's folder; `{python}` is
  available. The last line of stdout (or stderr) becomes the reason shown in the report.
- **llm-judge** sends the rubric, the case input and the response to the judge and expects
  `{"verdict": "pass"|"fail", "reason": "..."}`. An unparseable answer or a provider error fails
  the run. The judge is told to treat response text as data. Judge tokens, latency and cost are
  reported separately and are not part of the candidate columns.

## Result JSON

`evalkit run` writes (and `--format json` prints):

```
{ evalkit, suite{name,description,path,sha256}, started, finished, repetitions,
  providers[], cases[],
  runs[]{provider, case, rep, passed, error, latency_s, tokens_in, tokens_out, cost,
         output (max 8000 chars), graders[]{type,passed,reason}, judge{latency_s,tokens_in,tokens_out,cost}},
  summary{runs, passed, pass_rate, providers{id: {runs, passed, pass_rate, errors,
          latency_mean_s, latency_p95_s, tokens_in, tokens_out, cost, judge_cost, cases{id:{runs,passed}}}}} }
```

`null` means "not reported by the provider", never zero.

## Brain

`--brain` pipes the Markdown report to `brain new reference "Eval <suite> <date>" --body -`
(plus `--project` when `--brain-project` is given). If the `brain` CLI is not installed, or the
call fails, evalkit prints a note on stderr and still exits normally.

## Reading results honestly

- With few repetitions, a pass rate is a rough signal: 3 runs cannot separate 80% from 100%.
  Raise `-n` before comparing models, and keep `temperature` low for repeatability.
- An LLM judge is itself a model: spot-check its verdicts (`evalkit report --format json`,
  `runs[].graders[].reason`) and prefer cheap deterministic graders where they suffice.
- Do not put confidential or customer data in suites that use an external provider. Follow the
  data classes of the data-guard module when it is installed.
