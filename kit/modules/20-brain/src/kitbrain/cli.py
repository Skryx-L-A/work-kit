"""`brain` command line."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from . import __version__, gitops, notes, service
from .embed import files_error


def _body(arg: str | None) -> str | None:
    if arg == "-":
        return sys.stdin.read()
    return arg


def cmd_search(a) -> int:
    res = service.search(a.query, k=a.k, project=a.project, ntype=a.type, mode=a.mode)
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
        return 0
    if not res["results"]:
        print("no results")
        return 0
    for i, r in enumerate(res["results"], 1):
        tag = "/".join(x for x in (r["type"], r["project"]) if x)
        where = f" > {r['heading']}" if r["heading"] else ""
        print(f"{i}. {r['title']}  [{tag}]  {r['path']}{where}")
        if r["snippet"]:
            print(f"   {r['snippet']}")
    return 0


def cmd_read(a) -> int:
    path, text = service.read(a.note)
    if a.json:
        print(json.dumps({"path": path, "text": text}, ensure_ascii=False))
    else:
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
    return 0


def cmd_new(a) -> int:
    tags = [t.strip() for t in (a.tags or "").split(",") if t.strip()]
    res = service.new(a.type, a.title, project=a.project, body=_body(a.body), tags=tags)
    print(json.dumps(res) if a.json else f"created {res['path']}"
          + (f" (commit {res['commit']})" if res["commit"] else ""))
    return 0


def cmd_append(a) -> int:
    body = _body(a.body)
    if body is None:
        body = sys.stdin.read()
    res = service.append(a.path, body)
    print(json.dumps(res) if a.json else f"appended to {res['path']}"
          + (f" (commit {res['commit']})" if res["commit"] else ""))
    return 0


def cmd_recent(a) -> int:
    items = service.recent(a.n)
    if a.json:
        print(json.dumps(items, ensure_ascii=False, indent=1))
        return 0
    for it in items:
        print(f"{it['when']}  {it['path']}  {it['title']}")
    return 0


def cmd_status(a) -> int:
    s = service.settings()
    info = {"home": str(s.home), "exists": s.home.is_dir(), "model": s.model,
            "model_dir": str(s.model_dir)}
    if s.home.is_dir():
        idx = service.index()
        info.update(idx.counts())
        info["stale"] = idx.stale(include_model=False)
        model_error = files_error(s.model, s.model_dir)
        info["search_mode"] = "bm25" if model_error else "hybrid"
        info["git"] = gitops.is_repo(s.home)
        if info["git"]:
            info["uncommitted"] = len([ln for ln in gitops.run(
                s.home, "status", "--porcelain", check=False).stdout.splitlines() if ln])
            info["remote"] = gitops.has_remote(s.home)
    if a.json:
        print(json.dumps(info, indent=1))
    else:
        for k, v in info.items():
            print(f"{k:16} {v}")
    return 0


def cmd_reindex(a) -> int:
    if not service.settings().home.is_dir():
        print("brain home does not exist; run 'brain init'", file=sys.stderr)
        return 1
    # One reindex at a time. The git hook runs `reindex --quiet` in the background: if another
    # reindex already runs it exits at once (the next search reindexes lazily anyway); a
    # foreground reindex waits for the running one.
    import fcntl

    state = service.settings().state_dir
    state.mkdir(parents=True, exist_ok=True)
    lock = open(state / "reindex.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if a.quiet else 0))
    except BlockingIOError:
        return 0
    idx = service.index()
    stats = idx.reindex(full=a.full)
    if not a.quiet:
        mode = "hybrid" if idx.embedder else f"bm25 only ({idx.embed_error})"
        print(" ".join(f"{k}={v}" for k, v in stats.items()) + f"  search={mode}")
    return 0


def cmd_sync(a) -> int:
    print(gitops.sync(service.settings().home))
    return 0


def cmd_backup(a) -> int:
    path = gitops.backup(service.settings().home, Path(a.dir))
    print(f"backup written: {path}")
    print(f"restore: git clone {path} <folder>")
    return 0


def cmd_init(a) -> int:
    res = service.init()
    print(f"brain home: {res['home']}")
    if res["created"]:
        print(f"created {len(res['created'])} template files")
    if not res["git"]:
        print("warning: git not found; notes are not versioned", file=sys.stderr)
    elif res["hooks"]:
        print("installed git hooks: " + ", ".join(res["hooks"]))
    return 0


def cmd_doctor(a) -> int:
    from .doctor import run
    checks = run(service.settings(), deep=a.deep)
    bad = 0
    for level, name, msg in checks:
        bad += level == "FAIL"
        print(f"[{level:4}] {name}: {msg}")
    return 1 if bad else 0


def cmd_ingest(a) -> int:
    tags = [t.strip() for t in (a.tags or "").split(",") if t.strip()]
    res = service.ingest(a.file, ntype=a.type, title=a.title, project=a.project, tags=tags,
                         update=a.update, dry_run=a.stdout)
    if a.stdout:
        sys.stdout.write(res["markdown"])
        return 0
    if a.json:
        print(json.dumps(res, ensure_ascii=False))
        return 0
    msg = {"created": "ingested as", "updated": "updated", "unchanged": "already ingested as"}
    print(f"{msg[res['status']]} {res['path']}" + (f" (commit {res['commit']})" if res.get("commit") else ""))
    if res.get("labels"):
        print(f"labels found in the document: {', '.join(res['labels'])}")
    return 0


def cmd_log(a) -> int:
    import datetime as dt
    from . import worklog
    home = service._ensure_home()
    day = dt.date.fromisoformat(a.date) if a.date else None
    path, entry, _ = worklog.add_entry(home, a.text, hours=a.hours, project=a.project, day=day)
    hours = f"{entry.hours:g} h" if entry.hours else "no hours"
    res = service._after_write(path, f"brain: log {hours}" + (f" {entry.project}" if entry.project else ""))
    print(f"logged ({hours}) in {res['path']}" + (f" (commit {res['commit']})" if res["commit"] else ""))
    y, w, _ = entry.date.isocalendar()
    rep = worklog.week_report(home, f"{y}-W{w:02d}")
    print(f"week {rep['week']}: {rep['hours']:g} of {rep['limit']:g} h")
    if rep["status"] != "ok":
        print(f"warning: week {rep['week']} is {'over' if rep['status'] == 'over' else 'close to'} "
              f"the {rep['limit']:g} h limit", file=sys.stderr)
    return 0


def cmd_week(a) -> int:
    from . import worklog
    home = service.settings().home
    rep = worklog.week_report(home, a.iso_week)
    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=1))
    else:
        sys.stdout.write(worklog.render_report(rep))
    if a.save:
        path = home / "worklog" / f"{rep['week']}-report.md"
        meta = {"title": f"Week report {rep['week']}", "type": "note", "tags": ["worklog", "report"],
                "created": notes.today(), "updated": notes.today()}
        body = worklog.render_report(rep).split("\n", 1)[1]
        service._ensure_home()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(notes.render(meta, body), encoding="utf-8")
        res = service._after_write(path, f"brain: week report {rep['week']}")
        print(f"saved {res['path']}", file=sys.stderr)
    return 0


def cmd_mcp(a) -> int:
    from .mcp import serve
    return serve()


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="brain", description="Local work notes with hybrid search.")
    p.add_argument("--version", action="version", version=f"brain {__version__}")
    sub = p.add_subparsers(dest="cmd", required=True, metavar="command")

    s = sub.add_parser("search", help="hybrid search (BM25 + embeddings)")
    s.add_argument("query")
    s.add_argument("-k", type=int, default=5)
    s.add_argument("--project")
    s.add_argument("--type", choices=notes.TYPES)
    s.add_argument("--mode", choices=("hybrid", "bm25", "dense"), default="hybrid",
                   help=argparse.SUPPRESS)
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_search)

    s = sub.add_parser("read", help="print a note by path or title")
    s.add_argument("note")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_read)

    s = sub.add_parser("new", help="create a note and commit it")
    s.add_argument("type", choices=notes.TYPES)
    s.add_argument("title")
    s.add_argument("--project")
    s.add_argument("--body", help="text, or - to read stdin")
    s.add_argument("--tags", help="comma separated")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_new)

    s = sub.add_parser("append", help="append text to a note and commit it")
    s.add_argument("path")
    s.add_argument("--body", help="text, or - to read stdin (default: stdin)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_append)

    s = sub.add_parser("recent", help="recently changed notes")
    s.add_argument("-n", type=int, default=10)
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_recent)

    s = sub.add_parser("status", help="index and repo status")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_status)

    s = sub.add_parser("reindex", help="update the search index")
    s.add_argument("--full", action="store_true", help="rebuild from scratch")
    s.add_argument("--quiet", action="store_true")
    s.set_defaults(fn=cmd_reindex)

    s = sub.add_parser("ingest", help="convert PDF/DOCX/PPTX/XLSX/HTML/MD to a note, commit it")
    s.add_argument("file")
    s.add_argument("--type", choices=notes.TYPES, default="reference")
    s.add_argument("--title")
    s.add_argument("--project")
    s.add_argument("--tags", help="comma separated")
    s.add_argument("--update", action="store_true", help="replace the note of a changed source")
    s.add_argument("--stdout", action="store_true", help="print the Markdown, write nothing")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_ingest)

    s = sub.add_parser("log", help="add a worklog entry, commit it")
    s.add_argument("text")
    s.add_argument("--hours", help="e.g. 2, 1.5, 90m, 1:30")
    s.add_argument("--project")
    s.add_argument("--date", help="YYYY-MM-DD (default today)")
    s.set_defaults(fn=cmd_log)

    s = sub.add_parser("week", help="weekly hours vs. limit, worklog and git activity")
    s.add_argument("--iso-week", help="e.g. 2026-W39 (default: this week)")
    s.add_argument("--json", action="store_true")
    s.add_argument("--save", action="store_true", help="also save the report as a note")
    s.set_defaults(fn=cmd_week)

    sub.add_parser("sync", help="git pull --rebase and push, if a remote exists").set_defaults(fn=cmd_sync)
    s = sub.add_parser("backup", help="write a git bundle of the notes to DIR (restore: git clone FILE)")
    s.add_argument("dir")
    s.set_defaults(fn=cmd_backup)
    sub.add_parser("init", help="create the notes repo from the template").set_defaults(fn=cmd_init)
    s = sub.add_parser("doctor", help="check index, model, git and hooks")
    s.add_argument("--deep", action="store_true", help="load the embedding model and run an inference check")
    s.set_defaults(fn=cmd_doctor)
    sub.add_parser("mcp", help="run the MCP server on stdio").set_defaults(fn=cmd_mcp)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except service.UserError as exc:
        print(f"brain: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0


if __name__ == "__main__":
    sys.exit(main())
