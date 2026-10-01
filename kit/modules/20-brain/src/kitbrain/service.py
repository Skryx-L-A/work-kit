"""Operations shared by the CLI and the MCP server."""

from __future__ import annotations

import shutil
from pathlib import Path

from . import config, gitops, notes
from .index import Index, warn_once

UserError = (notes.NoteError, gitops.GitError, TimeoutError)

_index: Index | None = None
_index_home: Path | None = None


def settings() -> config.Settings:
    return config.load()


def template_dir() -> Path:
    here = Path(__file__).resolve().parent
    for cand in (here / "template", here.parents[1] / "template"):
        if cand.is_dir():
            return cand
    raise notes.NoteError("notes template not found in the installation")


def init(home: Path | None = None) -> dict:
    """Create the notes repo from the template; never overwrites existing files."""
    home = home or settings().home
    home.mkdir(parents=True, exist_ok=True)
    created = []
    src = template_dir()
    for item in sorted(src.rglob("*")):
        dest = home / item.relative_to(src)
        if item.is_dir():
            dest.mkdir(exist_ok=True)
        elif not dest.exists():
            shutil.copy2(item, dest)
            created.append(dest.relative_to(home).as_posix())
    result = {"home": str(home), "created": created, "git": False, "hooks": []}
    if gitops.available():
        fresh = not gitops.is_repo(home)
        gitops.ensure_repo(home)
        result["git"] = True
        result["hooks"] = gitops.install_hooks(home)
        if fresh or created:
            paths = [home / c for c in created] + [home / ".gitignore"]
            result["commit"] = gitops.commit(home, [p for p in paths if p.exists()],
                                             "brain: initialize notes")
    return result


def _ensure_home() -> Path:
    home = settings().home
    if not home.is_dir() or not any(home.iterdir()):
        init(home)
    return home


def index() -> Index:
    global _index, _index_home
    home = settings().home
    if _index is None or _index_home != home:
        if _index is not None:
            _index.close()
        home.mkdir(parents=True, exist_ok=True)
        _index, _index_home = Index(settings()), home
    return _index


def fresh_index() -> Index:
    """Index with stale files reindexed (lazy reindex before reads)."""
    idx = index()
    if idx.stale():
        try:
            idx.reindex()
        except TimeoutError:
            pass  # a background reindex is busy; search what is there
    return idx


def search(query: str, k: int = 5, project=None, ntype=None, mode: str = "hybrid") -> dict:
    idx = fresh_index()
    warn_once(idx, idx.embed_error)
    results, used = idx.search(query, k=k, project=project, ntype=ntype, mode=mode)
    out = {"query": query, "mode": used, "results": [r.as_dict() for r in results]}
    if idx.embed_error:
        out["note"] = "embedding model not available; BM25 only"
    return out


def resolve(ref: str) -> Path:
    home = settings().home
    try:
        p = notes.safe_path(home, ref)
        if p.is_file():
            return p
    except notes.NoteError:
        if "/" in ref or ref.startswith("~"):  # clearly a path, not a title
            raise
    # Reading must remain fast and work without loading the embedding model. Searching note
    # metadata is cheap here and avoids refreshing the vector index just to resolve a title.
    matches = [p.relative_to(home).as_posix() for p in notes.iter_notes(home)
               if notes.load(p).title.lower() == ref.lower()]
    if len(matches) == 1:
        return home / matches[0]
    if len(matches) > 1:
        raise notes.NoteError("title is ambiguous, use a path: " + ", ".join(matches))
    stems = [p for p in notes.iter_notes(home) if p.stem.lower() == notes.slugify(ref)]
    if len(stems) == 1:
        return stems[0]
    raise notes.NoteError(f"no note found for '{ref}'")


def read(ref: str) -> tuple[str, str]:
    p = resolve(ref)
    return p.relative_to(settings().home).as_posix(), p.read_text(encoding="utf-8", errors="replace")


def _after_write(path: Path, message: str) -> dict:
    home = settings().home
    idx = index()
    try:
        idx.reindex(only=[path])
    except TimeoutError:
        pass
    commit = gitops.commit(home, [path], message)
    return {"path": path.relative_to(home).as_posix(), "commit": commit}


def new(ntype: str, title: str, project=None, body=None, tags=None) -> dict:
    home = _ensure_home()
    path = notes.create(home, ntype, title, project=project, body=body, tags=tags)
    return _after_write(path, f'brain: new {ntype} "{title.strip()}"')


def append(ref: str, body: str) -> dict:
    path = resolve(ref)
    notes.append(path, body)
    title = notes.load(path).title
    return _after_write(path, f'brain: append to "{title}"')


def recent(n: int = 10) -> list[dict]:
    home = settings().home
    if not home.is_dir():
        return []
    items = gitops.recent(home, n)
    idx = index()
    for it in items:
        row = idx.db.execute("SELECT title, type, project FROM files WHERE path=?",
                             (it["path"],)).fetchone()
        if row is None:
            meta = notes.load(home / it["path"]).meta
            row = (meta.get("title") or Path(it["path"]).stem, meta.get("type") or "",
                   meta.get("project") or "")
        it.update(title=str(row[0]), type=str(row[1]), project=str(row[2]),
                  when=gitops.fmt_time(it["time"]))
        del it["time"]
    return items


def ingest(file: str, ntype: str = "reference", title: str | None = None, project=None,
           tags=None, update: bool = False, dry_run: bool = False) -> dict:
    """Convert a document to a Markdown note with source metadata and commit it."""
    from . import ingest as ing

    if ntype not in notes.TYPES or ntype in notes.NEEDS_PROJECT and not project:
        raise notes.NoteError(f"type '{ntype}' is not usable for ingest")
    src = Path(file).expanduser().resolve()
    doc = ing.convert(src)
    sha = ing.sha256_file(src)
    meta, body = ing.build_note(src, doc, sha, ntype, title, project, tags)
    if dry_run:
        return {"path": None, "status": "dry-run", "markdown": notes.render(meta, body),
                "labels": doc.labels}
    home = _ensure_home()
    same = ing.find_by_source(home, sha=sha)
    if same is not None:
        return {"path": same.relative_to(home).as_posix(), "status": "unchanged", "commit": None,
                "labels": doc.labels}
    old = ing.find_by_source(home, path=str(src))
    if old is not None and not update:
        raise notes.NoteError(f"{src.name} was ingested before as "
                              f"{old.relative_to(home).as_posix()} and has changed; use --update")
    if old is not None:
        prev = notes.load(old).meta
        meta["created"] = prev.get("created", meta["created"])
        path = old
    else:
        path = notes.target_path(home, ntype, meta["title"], project)
        path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(notes.render(meta, body), encoding="utf-8")
    verb = "update" if old is not None else "ingest"
    res = _after_write(path, f'brain: {verb} "{meta["title"]}" from {src.name}')
    res.update(status="updated" if old is not None else "created", labels=doc.labels)
    return res
