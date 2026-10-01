# 15-local-llm

Local language models on the CPU: llama.cpp `llama-server` (prebuilt Linux x86_64 release)
and small GGUF models, served as an OpenAI-compatible endpoint on `127.0.0.1`. CLI `kit-llm`.
Offline, no sudo, no other module needed.
Needs `kit/offline/local-llm` (engine + models, about 6 GB).

```sh
cd ~/work/kit/modules/15-local-llm && bash install.sh       # engine + default models
bash uninstall.sh
```

Open a new terminal.

```sh
kit-llm models                      # catalog, installed, fits in free RAM?
kit-llm start qwen3.5-4b            # refuses when the model does not fit; first start can take minutes
kit-llm status
kit-llm ask "Name three Python testing tools."
eval "$(kit-llm env)"               # OPENAI_BASE_URL etc. for other tools
kit-llm stop
kit-llm doctor                      # AVX2, libraries, engine, models, port
```

Web chat while running: http://127.0.0.1:8080/.

Model variants, settings, build host and why this engine: `~/work/kit/docs/local-llm.md`.
