# 70-workbench

Agent workbench: one orchestrator and any number of worker agents in visible tmux panes, for any
registered agent CLI, with result protocol, context guard, hooks, model registry, a VS Code
extension and, on Linux x86_64, the Agent Workbench desktop app (menu entry, command
`agent-workbench`). Offline, no sudo. Needs Python (`00-python`, or a system `python3`), `git`,
`tmux` (`01-prereqs`) and `jq` (`10-base-tools`). Uses `20-brain` and `30-agent-setup` when
installed.
Agent CLIs such as `claude` or `pi` come from `16-harness-clis`
(`bash ../16-harness-clis/install.sh pi`).

```sh
cd ~/work/kit/modules/70-workbench && bash install.sh   # permissions default to bypass
bash verify.sh                                          # check the installation
bash uninstall.sh
```

Open a new terminal.

```sh
mkdir -p ~/work/my-project && wb-code ~/work/my-project   # orchestrator session (tmux wb-<folder>-<hash>)
wb-state models table                   # registered models and harnesses
claude-worker w1 sonnet ~/work/my-project "task"    # from the orchestrator
pi-worker w2 qwen3.5-4b ~/work/my-project "task"    # local model via kit-llm (15-local-llm)
wb-result w1                            # result file of a worker
wb-state models discover                # import models of installed CLIs, pi and kit-llm
agent-workbench                         # desktop app: sessions, workers, approvals, settings
```

Worker models: use one listed by `wb-state models table`; other forms and settings: `~/work/kit/docs/workbench.md`.
