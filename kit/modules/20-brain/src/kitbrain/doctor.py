"""`brain doctor`: check home, git, hooks, model and index."""

from __future__ import annotations

import shutil
import sqlite3

from . import gitops
from .config import Settings
from .embed import files_error
from .index import Index


def run(s: Settings, deep: bool = False) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
    add = lambda level, name, msg: out.append((level, name, msg))  # noqa: E731

    if not s.home.is_dir():
        add("FAIL", "home", f"{s.home} does not exist; run 'brain init'")
        return out
    add("OK", "home", str(s.home))

    try:
        con = sqlite3.connect(":memory:")
        con.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
        con.close()
        add("OK", "sqlite", f"FTS5 available (SQLite {sqlite3.sqlite_version})")
    except sqlite3.OperationalError:
        add("FAIL", "sqlite", "SQLite without FTS5")

    if not gitops.available():
        add("WARN", "git", "git not found; notes are not versioned")
    elif not gitops.is_repo(s.home):
        add("WARN", "git", "brain home is not a git repository; run 'brain init'")
    else:
        dirty = gitops.run(s.home, "status", "--porcelain", check=False).stdout.strip()
        add("WARN" if dirty else "OK", "git",
            "uncommitted changes present" if dirty else "repository clean")
        if gitops.has_remote(s.home):
            add("OK", "remote", "remote configured")
        else:
            age = gitops.backup_age_days(s.home)
            if age is not None and age <= gitops.BACKUP_MAX_AGE_DAYS:
                add("OK", "remote", f"no remote (local only); last backup {age:.0f} day(s) ago")
            else:
                last = "no backup yet" if age is None else f"last backup {age:.0f} days ago"
                add("WARN", "remote", f"no remote and {last}: a lost laptop loses the notes; "
                    "add a remote or run 'brain backup <IT-approved folder>'")
        hooks = gitops.hooks_status(s.home)
        override = gitops.hooks_path_override(s.home)
        if override and gitops.hooks_path_is_dispatcher(override, s.home):
            add("OK", "hooks", f"core.hooksPath={override} is the kit-sync dispatcher, "
                "which runs .git/hooks")
            if not all(hooks.values()):
                missing = [n for n, v in hooks.items() if not v]
                add("WARN", "hooks", f"missing {', '.join(missing)} in .git/hooks; run 'brain init'")
        elif override:
            add("WARN", "hooks", f"core.hooksPath={override} bypasses .git/hooks; "
                "reindex still runs lazily before each search")
        elif all(hooks.values()):
            add("OK", "hooks", ", ".join(hooks))
        else:
            missing = [n for n, v in hooks.items() if not v]
            add("WARN", "hooks", f"missing {', '.join(missing)}; run 'brain init'")
        if not shutil.which("brain"):
            add("WARN", "path", "'brain' not on PATH; git hooks cannot trigger a reindex")

    model_error = files_error(s.model, s.model_dir)
    if model_error:
        add("WARN", "model", f"{s.model}: {model_error}; search falls back to BM25")
    elif not deep:
        add("OK", "model", f"{s.model} files found in {s.model_dir} (use --deep to load and test)")

    idx = Index(s)
    try:
        if deep and idx.embedder is None:
            add("WARN", "model", f"{s.model}: {idx.embed_error}; search falls back to BM25")
        elif deep:
            vec = idx.embedder.embed_queries(["doctor check"])
            add("OK", "model", f"{s.model} ({vec.shape[1]} dims) from {s.model_dir}")
        c = idx.counts()
        stale = idx.stale(include_model=deep)
        level = "WARN" if stale or (deep and idx.embedder and c["missing_vectors"]) else "OK"
        add(level, "index", f"{c['files']} files, {c['chunks']} chunks, {c['vectors']} vectors"
            + ("; stale, run 'brain reindex'" if stale else ""))
    finally:
        idx.close()
    return out
