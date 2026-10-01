# 50-eval

`evalkit`: run test suites against models and CLI agents, get pass rates as Markdown and JSON.
Depends on: `00-python`.

```sh
cd ~/work/kit/modules/50-eval && bash install.sh
bash uninstall.sh
```

Open a new terminal.

```sh
evalkit run examples/offline.yaml          # offline demo, no model needed
evalkit run examples/extraction.yaml -n 5  # offline providers of the demo suite
evalkit report                             # re-render the latest result
evalkit list examples/                     # suites in a folder
```

Options and suite format: `~/work/kit/docs/eval.md`, `SUITE-FORMAT.md` in this folder.
