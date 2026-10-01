# 18-doc-qa

Questions over approved company documents, with cited passages. CLI and MCP server: `doc-qa`.
Needs `20-brain` (the `doc-qa` command ships with it). Stays disabled until an approved
document scope is filled in.

```sh
cd ~/work/kit/modules/18-doc-qa && bash install.sh    # writes ~/.config/work-kit/doc-qa.toml (disabled)
bash uninstall.sh                                     # removes the index; config and ~/work/doc-qa stay
```

Open a new terminal.

```sh
doc-qa status
```

Enable:

1. Go through `~/work/kit/modules/18-doc-qa/approval-checklist.md` with IT.
2. Fill in `~/.config/work-kit/doc-qa.toml`: `scope`, `approved_by`, `approved_on`, `sources`,
   `allowed_labels`; then `enabled = true`.
3. `doc-qa sync --dry-run`, then `doc-qa sync`.

Use:

```sh
doc-qa ask "How long may a feature branch live?"
```

Commands and design: `~/work/kit/docs/brain.md` (section doc-qa).
