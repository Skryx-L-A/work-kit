# 35-company-network

`kit-net`: make Claude Code, Codex, Gemini CLI, opencode, pi, aider, Copilot CLI, VS Code, python/pip/uv,
node/npm, git, curl, `kit-models` and `kit-llm` work behind a company HTTP(S) proxy and a TLS-inspecting
firewall. Needs `python3` or the kit CPython. Offline, no sudo, no other module. Install alone changes
nothing: settings are written only when you run `kit-net proxy set` or `kit-net ca add`.

```
bash install.sh                                # uninstall: bash uninstall.sh
kit-net proxy set http://proxy.example.com:8080 [--no-proxy .corp.example,10.0.0.0/8]
kit-net proxy unset
kit-net ca add corp-root.crt                   # .pem, .crt, .cer or .der; validated as a CA
kit-net ca list | ca remove NAME
kit-net test https://pypi.org/                 # python, node, curl, git, uv: what works, what is missing
kit-net status [--clients]                     # what is set, where, and how each client picks it up
kit-net refresh                                # after the system CA bundle changed
```

Open a new terminal afterwards; GUI apps and services (VS Code from the launcher) need a new login.
Files: `~/.config/work-kit/net.env`, `ca/`, `ca-bundle.pem`; `~/.config/environment.d/`; marked
blocks in `~/.bashrc`, the login file and VS Code's `settings.json`. Backups:
`~/.local/share/work-kit/backups/35-company-network`. Details and limits: `~/work/kit/docs/company-network.md`.
Tests: `bash tests/test-net.sh`.
