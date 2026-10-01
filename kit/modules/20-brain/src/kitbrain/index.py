"""SQLite index: FTS5 (BM25) plus dense vectors, incremental by content hash."""

from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import re
import sqlite3
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import chunking, notes
from .config import Settings
from .embed import Embedder, try_load
from .stopwords import STOPWORDS

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY, hash TEXT, mtime REAL, size INTEGER,
    title TEXT, type TEXT, project TEXT, tags TEXT, updated TEXT);
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY, path TEXT, ord INTEGER, heading TEXT, text TEXT, chash TEXT);
CREATE INDEX IF NOT EXISTS chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS chunks_chash ON chunks(chash);
CREATE TABLE IF NOT EXISTS emb (chash TEXT PRIMARY KEY, vec BLOB);
CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(
    title, heading, text, tokenize='unicode61 remove_diacritics 2');
"""
SCHEMA_VERSION = "1"
RRF_K = 60
# Weight of the BM25 list in the fusion. Plain RRF (1.0) was kept: lower weights helped one
# test condition and hurt the other (docs/embedding-choice.md).
BM25_WEIGHT = 1.0
CANDIDATES = 50


@dataclass
class Result:
    path: str
    title: str
    type: str
    project: str
    heading: str
    snippet: str
    score: float
    text: str = ""  # full text of the best chunk

    def as_dict(self, full: bool = False) -> dict:
        d = self.__dict__.copy()
        if not full:
            d.pop("text")
        return d


class Index:
    def __init__(self, settings: Settings):
        self.s = settings
        self.s.state_dir.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.s.db_path, timeout=30)
        self._enable_wal()
        self.db.execute("PRAGMA busy_timeout=30000")
        self.db.executescript(SCHEMA)
        if self.get_meta("schema") != SCHEMA_VERSION:
            self.set_meta("schema", SCHEMA_VERSION)
        self._embedder: Embedder | None = None
        self._embed_error: str | None = None
        self._embed_tried = False
        self._matrix: tuple[np.ndarray, list[int]] | None = None

    def _enable_wal(self, wait_s: float = 120.0) -> None:
        """Switch to WAL. The switch needs a moment without writers; a background reindex
        (git hook) may hold the database for a while on a slow CPU, so retry, and carry on
        in the current journal mode if it never frees up (WAL is set once and then sticks)."""
        deadline = time.monotonic() + wait_s
        delay = 0.2
        while True:
            try:
                self.db.execute("PRAGMA journal_mode=WAL")
                return
            except sqlite3.OperationalError as e:
                if "locked" not in str(e) and "busy" not in str(e):
                    raise
                if time.monotonic() >= deadline:
                    return
                time.sleep(delay)
                delay = min(delay * 2, 5.0)

    # -- small helpers -------------------------------------------------
    def close(self) -> None:
        self.db.close()

    def get_meta(self, key: str) -> str | None:
        row = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return row[0] if row else None

    def set_meta(self, key: str, value: str | None) -> None:
        if value is None:
            self.db.execute("DELETE FROM meta WHERE key=?", (key,))
        else:
            self.db.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", (key, value))
        self.db.commit()

    @property
    def embedder(self) -> Embedder | None:
        if not self._embed_tried:
            self._embed_tried = True
            self._embedder, self._embed_error = try_load(self.s.model, self.s.model_dir)
        return self._embedder

    @property
    def model_key(self) -> str:
        """Model name plus ONNX file: switching the CPU variant also rebuilds the vectors."""
        spec = getattr(self.embedder, "spec", None)
        onnx = getattr(spec, "onnx", None)
        return f"{self.s.model}:{onnx}" if onnx else self.s.model

    @property
    def chunk_chars(self) -> int:
        if self.embedder is None:  # model missing for now: keep the existing chunking
            stored = self.get_meta("chunk_chars")
            return int(stored) if stored else chunking.MAX_CHARS
        spec = getattr(self.embedder, "spec", None)
        return getattr(spec, "chunk_chars", chunking.MAX_CHARS)

    @property
    def embed_error(self) -> str | None:
        _ = self.embedder
        return self._embed_error

    @contextlib.contextmanager
    def lock(self, timeout: float = 120.0):
        fh = open(self.s.state_dir / "lock", "w")
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    fh.close()
                    raise TimeoutError("another brain reindex holds the lock") from None
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)
            fh.close()

    # -- indexing ------------------------------------------------------
    def stale(self, include_model: bool = True) -> bool:
        """Cheap check: any file added, removed or touched since last index."""
        known = {p: (m, s) for p, m, s in self.db.execute("SELECT path, mtime, size FROM files")}
        seen = 0
        for p in notes.iter_notes(self.s.home):
            rel = p.relative_to(self.s.home).as_posix()
            st = p.stat()
            if known.get(rel) != (st.st_mtime, st.st_size):
                return True
            seen += 1
        if seen != len(known):
            return True
        if not include_model:
            return False
        if self.embedder is not None and self.get_meta("model") != self.model_key:
            return True
        if self.get_meta("chunk_chars") != str(self.chunk_chars):
            return True
        return self._missing_vectors() > 0 and self.embedder is not None

    def _missing_vectors(self) -> int:
        return self.db.execute(
            "SELECT COUNT(DISTINCT c.chash) FROM chunks c LEFT JOIN emb e ON e.chash=c.chash "
            "WHERE e.chash IS NULL").fetchone()[0]

    def reindex(self, full: bool = False, only: list[Path] | None = None) -> dict:
        with self.lock():
            return self._reindex(full, only)

    def _reindex(self, full: bool, only: list[Path] | None) -> dict:
        stats = {"added": 0, "updated": 0, "removed": 0, "unchanged": 0, "embedded": 0}
        if self.embedder is not None and self.get_meta("model") != self.model_key:
            # Different model: old vectors are meaningless.
            self.db.execute("DELETE FROM emb")
            self.set_meta("model", self.model_key)
        rechunk = self.get_meta("chunk_chars") != str(self.chunk_chars)
        if rechunk:
            self.set_meta("chunk_chars", str(self.chunk_chars))
        if full:
            self.db.execute("DELETE FROM emb")
        if full or rechunk:  # vectors are keyed by chunk hash and survive a re-chunk
            self.db.execute("DELETE FROM files")
            self.db.execute("DELETE FROM chunks")
            self.db.execute("DELETE FROM fts")
        known = {p: (h, m, s) for p, h, m, s in
                 self.db.execute("SELECT path, hash, mtime, size FROM files")}
        paths = only if only is not None else list(notes.iter_notes(self.s.home))
        seen = set()
        for p in paths:
            rel = p.relative_to(self.s.home).as_posix()
            seen.add(rel)
            if not p.is_file():
                continue
            st = p.stat()
            old = known.get(rel)
            if old and (old[1], old[2]) == (st.st_mtime, st.st_size):
                stats["unchanged"] += 1
                continue
            raw = p.read_bytes()
            digest = hashlib.sha256(raw).hexdigest()
            if old and old[0] == digest:
                self.db.execute("UPDATE files SET mtime=?, size=? WHERE path=?",
                                (st.st_mtime, st.st_size, rel))
                stats["unchanged"] += 1
                continue
            self._index_file(rel, raw.decode("utf-8", errors="replace"), digest, st)
            stats["updated" if old else "added"] += 1
        if only is None:
            for rel in set(known) - seen:
                self._drop(rel)
                stats["removed"] += 1
        else:
            for p in only:
                rel = p.relative_to(self.s.home).as_posix()
                if not p.exists() and rel in known:
                    self._drop(rel)
                    stats["removed"] += 1
        self.db.commit()
        stats["embedded"] = self._embed_missing()
        self.db.execute("DELETE FROM emb WHERE chash NOT IN (SELECT chash FROM chunks)")
        self.db.commit()
        self.set_meta("indexed_at", str(time.time()))
        self._matrix = None
        return stats

    def _drop(self, rel: str) -> None:
        ids = [r[0] for r in self.db.execute("SELECT id FROM chunks WHERE path=?", (rel,))]
        self.db.executemany("DELETE FROM fts WHERE rowid=?", [(i,) for i in ids])
        self.db.execute("DELETE FROM chunks WHERE path=?", (rel,))
        self.db.execute("DELETE FROM files WHERE path=?", (rel,))

    def _index_file(self, rel: str, text: str, digest: str, st) -> None:
        self._drop(rel)
        meta, body = notes.split_frontmatter(text)
        title = str(meta.get("title") or Path(rel).stem)
        tags = meta.get("tags") or []
        if not isinstance(tags, list):
            tags = [tags]
        self.db.execute(
            "INSERT INTO files VALUES (?,?,?,?,?,?,?,?,?)",
            (rel, digest, st.st_mtime, st.st_size, title, str(meta.get("type") or ""),
             str(meta.get("project") or _project_from_path(rel)), json.dumps([str(t) for t in tags]),
             str(meta.get("updated") or "")))
        for i, ch in enumerate(chunking.chunk(body, self.chunk_chars)):
            content = f"{title}\n{ch.heading}\n{ch.text}"
            chash = hashlib.sha256(content.encode()).hexdigest()
            cur = self.db.execute(
                "INSERT INTO chunks (path, ord, heading, text, chash) VALUES (?,?,?,?,?)",
                (rel, i, ch.heading, ch.text, chash))
            self.db.execute("INSERT INTO fts (rowid, title, heading, text) VALUES (?,?,?,?)",
                            (cur.lastrowid, title, ch.heading, ch.text))

    def _embed_missing(self) -> int:
        rows = self.db.execute(
            "SELECT DISTINCT c.chash, f.title, c.heading, c.text FROM chunks c "
            "JOIN files f ON f.path=c.path LEFT JOIN emb e ON e.chash=c.chash "
            "WHERE e.chash IS NULL").fetchall()
        if not rows or self.embedder is None:
            return 0
        done = 0
        for s in range(0, len(rows), 64):
            batch = rows[s:s + 64]
            vecs = self.embedder.embed_docs([f"{t}\n{h}\n{x}".strip() for _, t, h, x in batch])
            self.db.executemany("INSERT OR REPLACE INTO emb VALUES (?,?)",
                                [(r[0], v.astype(np.float32).tobytes()) for r, v in zip(batch, vecs)])
            self.db.commit()
            done += len(batch)
        return done

    # -- search --------------------------------------------------------
    def _filter_sql(self, project: str | None, ntype: str | None) -> tuple[str, list]:
        where, args = [], []
        if project:
            where.append("f.project=?")
            args.append(notes.slugify(project))
        if ntype:
            where.append("f.type=?")
            args.append(ntype)
        return (" AND " + " AND ".join(where)) if where else "", args

    def bm25(self, query: str, project=None, ntype=None, limit=CANDIDATES) -> list[int]:
        terms = re.findall(r"\w+", query, re.UNICODE)
        terms = [t for t in terms if t.lower() not in STOPWORDS] or terms
        if not terms:
            return []
        match = " OR ".join('"' + t.replace('"', "") + '"' for t in terms)
        extra, args = self._filter_sql(project, ntype)
        sql = ("SELECT c.id FROM fts JOIN chunks c ON c.id=fts.rowid JOIN files f ON f.path=c.path "
               f"WHERE fts MATCH ?{extra} ORDER BY bm25(fts, 5.0, 2.0, 1.0) LIMIT ?")
        return [r[0] for r in self.db.execute(sql, [match, *args, limit])]

    def dense(self, query: str, project=None, ntype=None, limit=CANDIDATES) -> list[int]:
        if self.embedder is None:
            return []
        if self._matrix is None:
            rows = self.db.execute(
                "SELECT c.id, e.vec FROM chunks c JOIN emb e ON e.chash=c.chash").fetchall()
            if not rows:
                return []
            self._matrix = (np.stack([np.frombuffer(v, dtype=np.float32) for _, v in rows]),
                            [r[0] for r in rows])
        mat, ids = self._matrix
        q = self.embedder.embed_queries([query])[0]
        if q.shape[0] != mat.shape[1]:
            return []
        sims = mat @ q
        allowed = None
        if project or ntype:
            extra, args = self._filter_sql(project, ntype)
            allowed = {r[0] for r in self.db.execute(
                f"SELECT c.id FROM chunks c JOIN files f ON f.path=c.path WHERE 1=1{extra}", args)}
        out = []
        for i in np.argsort(-sims):
            cid = ids[i]
            if allowed is None or cid in allowed:
                out.append(cid)
                if len(out) >= limit:
                    break
        return out

    def search(self, query: str, k: int = 5, project=None, ntype=None,
               mode: str = "hybrid") -> tuple[list[Result], str]:
        lists: list[tuple[float, list[int]]] = []
        used = "bm25"
        if mode in ("hybrid", "bm25"):
            lists.append((BM25_WEIGHT if mode == "hybrid" else 1.0, self.bm25(query, project, ntype)))
        if mode in ("hybrid", "dense") and self.embedder is not None:
            lists.append((1.0, self.dense(query, project, ntype)))
            used = "hybrid" if mode == "hybrid" else "dense"
        chunk_path = {}
        scores: dict[str, float] = {}
        best_chunk: dict[str, tuple[float, int]] = {}
        for weight, ranked in lists:
            # File-level fusion: a file's rank is the rank of its best chunk in each list.
            files_seen: list[str] = []
            for cid in ranked:
                path = chunk_path.get(cid) or self.db.execute(
                    "SELECT path FROM chunks WHERE id=?", (cid,)).fetchone()[0]
                chunk_path[cid] = path
                if path not in files_seen:
                    files_seen.append(path)
                    contrib = weight / (RRF_K + len(files_seen))
                    scores[path] = scores.get(path, 0.0) + contrib
                    if path not in best_chunk or best_chunk[path][0] < contrib:
                        best_chunk[path] = (contrib, cid)
        top = sorted(scores, key=lambda p: -scores[p])[:k]
        results = []
        for path in top:
            cid = best_chunk[path][1]
            title, ntype_, proj = self.db.execute(
                "SELECT title, type, project FROM files WHERE path=?", (path,)).fetchone()
            heading, text = self.db.execute(
                "SELECT heading, text FROM chunks WHERE id=?", (cid,)).fetchone()
            results.append(Result(path, title, ntype_, proj, heading,
                                  _snippet(text), round(scores[path], 5), text))
        return results, used

    # -- listings ------------------------------------------------------
    def find_title(self, title: str) -> list[str]:
        rows = self.db.execute("SELECT path FROM files WHERE lower(title)=lower(?)", (title,)).fetchall()
        return [r[0] for r in rows]

    def counts(self) -> dict:
        q = lambda sql: self.db.execute(sql).fetchone()[0]  # noqa: E731
        return {"files": q("SELECT COUNT(*) FROM files"), "chunks": q("SELECT COUNT(*) FROM chunks"),
                "vectors": q("SELECT COUNT(*) FROM emb"), "missing_vectors": self._missing_vectors()}


def _project_from_path(rel: str) -> str:
    parts = rel.split("/")
    return parts[1] if len(parts) > 2 and parts[0] == "projects" else ""


def _snippet(text: str, n: int = 240) -> str:
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def warn_once(idx: Index, reason: str | None) -> None:
    """Tell the user once (per index) that search runs BM25-only."""
    if reason is None:
        if idx.get_meta("warned_no_model"):
            idx.set_meta("warned_no_model", None)
        return
    if not idx.get_meta("warned_no_model"):
        print(f"brain: embedding model not available ({reason}); "
              "search uses BM25 only. Run 'brain doctor' for details.", file=sys.stderr)
        idx.set_meta("warned_no_model", "1")
