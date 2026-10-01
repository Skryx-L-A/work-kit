# 31-caveman

Chat with the human in caveman style (level full) in every harness: Claude Code, Codex CLI,
Gemini CLI, opencode, Copilot in VS Code, Cursor, Aider, Continue. Offline copy of
[caveman](https://github.com/JuliusBrussee/caveman) (MIT, pinned in `upstream/UPSTREAM.md`).
Needs `python3` or the kit CPython (`01-prereqs`, `00-python`); `node` is optional. No sudo.

```sh
cd ~/work/kit/modules/31-caveman && bash install.sh    # detected harnesses
bash uninstall.sh
```

Open a new terminal, then restart the harness.

Cursor user rules cannot be written from outside: paste
`~/.local/share/work-kit/generated/caveman-cursor-user-rule.md` into Cursor Settings > Rules.

Level in Claude Code: `/caveman lite`, `/caveman full`, `/caveman ultra`; off: "stop caveman".

Options and tests: `~/work/kit/docs/caveman.md`.
