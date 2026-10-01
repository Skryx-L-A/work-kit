import os

from kitbrain import config, notes
from kitbrain.index import Index, warn_once


def make(home, rel, title, body, **meta):
    p = home / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(notes.render({"title": title, **meta}, body))
    return p


def test_incremental_reindex(env):
    env.mkdir()
    a = make(env, "inbox/a.md", "Alpha", "about postgres backups")
    make(env, "inbox/b.md", "Beta", "about kafka topics")
    idx = Index(config.load())
    s = idx.reindex()
    assert (s["added"], s["updated"], s["removed"]) == (2, 0, 0)
    assert not idx.stale()
    assert idx.reindex()["unchanged"] == 2

    a.write_text(a.read_text() + "\nmore\n")
    assert idx.stale()
    assert idx.reindex()["updated"] == 1

    # Touch without content change: hash matches, nothing re-chunked.
    os.utime(a, (1, 1))
    s = idx.reindex()
    assert s["updated"] == 0 and s["unchanged"] == 2

    a.unlink()
    assert idx.reindex()["removed"] == 1
    assert idx.counts()["files"] == 1
    idx.close()


def test_bm25_search_filters_and_stopwords(env):
    env.mkdir()
    make(env, "projects/pay/x.md", "Retry policy", "the payment retry policy", type="note", project="pay")
    make(env, "decisions/0001-y.md", "Use Kafka", "kafka for orders", type="decision")
    idx = Index(config.load())
    idx.reindex()
    res, mode = idx.search("what is the retry policy", k=5)
    assert mode == "bm25"
    assert res[0].path == "projects/pay/x.md" and res[0].project == "pay"
    # Only stopwords would match everything; they are dropped from the query.
    assert [r.path for r in idx.search("kafka", ntype="decision")[0]] == ["decisions/0001-y.md"]
    assert idx.search("kafka", project="pay")[0] == []
    assert idx.search("???")[0] == []
    idx.close()


def test_hybrid_with_model_and_model_change(env, fake_model, monkeypatch):
    env.mkdir()
    make(env, "a.md", "Alpha", "## Part one\npostgres backup restore\n## Part two\nlunch menu")
    idx = Index(config.load())
    stats = idx.reindex()
    assert stats["embedded"] == 2
    res, mode = idx.search("backup restore", k=3)
    assert mode == "hybrid"
    assert res[0].heading == "Part one"
    # Unchanged content: vectors are reused, not recomputed.
    assert idx.reindex(full=False)["embedded"] == 0
    idx.close()

    monkeypatch.setenv("BRAIN_MODEL", "other-model")
    idx = Index(config.load())
    assert idx.stale()  # model changed: vectors must be rebuilt
    assert idx.reindex()["embedded"] == 2
    idx.close()


def test_missing_model_warns_once(env, capsys):
    env.mkdir()
    idx = Index(config.load())
    assert idx.embedder is None and "missing" in idx.embed_error
    warn_once(idx, idx.embed_error)
    warn_once(idx, idx.embed_error)
    assert capsys.readouterr().err.count("BM25 only") == 1
    warn_once(idx, None)  # model back: next outage warns again
    warn_once(idx, "gone")
    assert capsys.readouterr().err.count("BM25 only") == 1
    idx.close()


def test_skips_tool_dirs(env):
    env.mkdir()
    make(env, ".brain/x.md", "hidden", "x")
    make(env, ".git/y.md", "hidden", "y")
    make(env, "ok.md", "ok", "z")
    idx = Index(config.load())
    idx.reindex()
    assert idx.counts()["files"] == 1
    idx.close()


def test_model_outage_keeps_chunking_and_vectors(env, monkeypatch):
    from conftest import FakeEmbedder

    class SmallChunks(FakeEmbedder):
        class spec:
            chunk_chars = 40

    env.mkdir()
    make(env, "a.md", "A", "first paragraph about backups\n\nsecond paragraph about lunch")
    monkeypatch.setattr("kitbrain.index.try_load", lambda n, d: (SmallChunks(), None))
    idx = Index(config.load())
    assert idx.reindex()["embedded"] == 2 and idx.counts()["chunks"] == 2
    idx.close()

    monkeypatch.setattr("kitbrain.index.try_load", lambda n, d: (None, "gone"))
    idx = Index(config.load())
    assert not idx.stale() and idx.chunk_chars == 40
    idx.close()

    monkeypatch.setattr("kitbrain.index.try_load", lambda n, d: (FakeEmbedder(), None))
    idx = Index(config.load())  # default chunk size: re-chunk, but no index wipe of files on disk
    stats = idx.reindex()
    assert stats["added"] == 1 and idx.counts()["chunks"] == 1
    idx.close()


def test_switching_onnx_variant_rebuilds_vectors(env, monkeypatch):
    from conftest import FakeEmbedder

    def with_onnx(name):
        class E(FakeEmbedder):
            class spec:
                chunk_chars = 1500
                onnx = name
        return E()

    env.mkdir()
    make(env, "a.md", "A", "some text")
    monkeypatch.setattr("kitbrain.index.try_load", lambda n, d: (with_onnx("avx512.onnx"), None))
    idx = Index(config.load())
    assert idx.reindex()["embedded"] == 1
    idx.close()
    monkeypatch.setattr("kitbrain.index.try_load", lambda n, d: (with_onnx("avx2.onnx"), None))
    idx = Index(config.load())
    assert idx.stale() and idx.reindex()["embedded"] == 1
    idx.close()


def test_open_while_another_writer_holds_the_db(env, monkeypatch):
    # Regression (Linux e2e 2026-09-25): a background reindex from the git hook held the
    # database while install ran `brain reindex`; switching to WAL failed with "locked".
    import sqlite3
    import threading
    import time

    env.mkdir()
    s = config.load()
    s.state_dir.mkdir(parents=True, exist_ok=True)
    holder = sqlite3.connect(s.db_path, check_same_thread=False)
    holder.execute("CREATE TABLE IF NOT EXISTS t(x)")
    holder.execute("BEGIN EXCLUSIVE")
    threading.Timer(1.5, holder.rollback).start()
    # Shrink sqlite's own busy wait so the test does not depend on it (the real lock lasted
    # longer than that wait).
    import kitbrain.index as kindex
    real = sqlite3.connect
    monkeypatch.setattr(kindex.sqlite3, "connect", lambda p, timeout=5.0, **kw: real(p, timeout=0.05, **kw))
    t0 = time.monotonic()
    idx = Index(s)
    assert time.monotonic() - t0 < 60
    assert idx.db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    holder.close()
