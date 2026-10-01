# 33-model-endpoints

`kit-models` registers a company model server once for every harness and kit tool. Offline, no sudo.

```
cd ~/work/kit/modules/33-model-endpoints && bash install.sh
```

Open a new terminal. Ask IT for the URL, the key and which data classes the server may receive, then:

```
kit-models add                     # asks for name, kind, URL, models, key, data classes
kit-models list
kit-models test corp
kit-models default corp
kit-models targets                 # what was set up for each harness
kit-models remove corp
```

Without questions (example):

```
kit-models add --name corp --kind openai --base-url https://llm.example.com/v1 --model gpt-oss-120b --default
```

Per endpoint there are wrappers: `claude-corp`, `codex-corp`, `gemini-corp`, `copilot-corp`, `aider-corp`.
Company proxy or internal CA: `kit-net proxy set …` / `kit-net ca add …` (module 35-company-network).
Remove: `bash uninstall.sh` (`--purge` also removes your endpoints). Details: `~/work/kit/docs/model-endpoints.md`.
