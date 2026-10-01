# 14-llm-usage

`llm-usage`: a logging proxy for any OpenAI-compatible endpoint, a wrapper for CLI tools,
summaries and OTLP export. Records token count, cost and latency as OpenTelemetry GenAI spans
in local JSONL files. Offline, no sudo. Standard-library Python (system `python3` >= 3.11 or
`00-python`).

```sh
cd ~/work/kit/modules/14-llm-usage && bash install.sh
bash uninstall.sh             # keeps the logs
```

Open a new terminal.

```sh
kit-llm start qwen3.5-2b                                     # upstream from 15-local-llm (or any OpenAI-compatible server)
llm-usage start --upstream http://127.0.0.1:8080/v1 --free   # logging proxy for it, port 4011
export OPENAI_BASE_URL=http://127.0.0.1:4011/v1              # point tools at the proxy
llm-usage summary --since 7d --by model
llm-usage tail -n 20
llm-usage stop
```

Prompts and answers are not stored (`--capture-content` records them). The proxy listens on
`127.0.0.1` only and passes API keys through without storing them.

More commands, log and price files: `~/work/kit/docs/local-llm.md`.
