# 20-brain

Personal work notes in `~/work/brain` with hybrid search. CLI: `brain`. Depends on `00-python`.

```sh
cd ~/work/kit/modules/20-brain && bash install.sh   # CLI, embedding model, notes repo, git hooks, first index
bash uninstall.sh                                   # notes stay in ~/work/brain
```

Open a new terminal.

```sh
brain doctor
brain search "how did we fix the connection pool" -k 5
brain new decision "Use PostgreSQL for the audit log" --project billing --body -
brain append decisions/0001-use-postgresql-for-the-audit-log.md --body "Accepted."
brain read "Use PostgreSQL for the audit log"
brain recent -n 10
brain status
brain reindex --full
brain sync
brain ingest report.pdf                 # also docx pptx xlsx html
brain log "Characterization tests" --hours 1.5
brain week
brain mcp                               # MCP server on stdio (tools: search, read, new_note, append, recent)
```

Backup (the notes exist only on this laptop; the company decides where copies may live):

```sh
git -C ~/work/brain remote add origin <company git URL> && brain sync   # remote, if IT provides one
brain backup <IT-approved folder>                                       # else: git bundle, repeat weekly
```

`brain doctor` warns while there is no remote and no bundle from the last 7 days. Restore: `git clone <file>.bundle ~/work/brain`.

Settings, model variant, build host and tests: `~/work/kit/docs/brain.md`.
