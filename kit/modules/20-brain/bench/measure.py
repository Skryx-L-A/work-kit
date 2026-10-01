"""Embedding model measurement for `brain` (see docs/embedding-choice.md).

Usage (from kit/modules/20-brain):
    uv run python bench/measure.py --models-root .cache/models > bench/results.json
Each model/thread setting runs in its own subprocess so peak RAM is per model.
"""

from __future__ import annotations

import argparse
import json
import os
import resource
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent

# name -> (download dir under models root, spec overrides written to brain-model.json)
VARIANTS = {
    "multilingual-e5-small (int8)": ("Xenova_multilingual-e5-small", {
        "name": "multilingual-e5-small", "onnx": "onnx/model_quantized.onnx", "pooling": "mean",
        "max_length": 512, "query_prefix": "query: ", "doc_prefix": "passage: "}),
    "multilingual-e5-small (fp32)": ("Xenova_multilingual-e5-small", {
        "name": "multilingual-e5-small-fp32", "onnx": "onnx/model.onnx", "pooling": "mean",
        "max_length": 512, "query_prefix": "query: ", "doc_prefix": "passage: "}),
    "paraphrase-multilingual-MiniLM-L12-v2 (int8, 1500-char chunks)": (
        "sentence-transformers_paraphrase-multilingual-MiniLM-L12-v2", {
            "name": "paraphrase-multilingual-MiniLM-L12-v2", "onnx": "onnx/model_qint8_avx512.onnx",
            "pooling": "mean", "max_length": 128, "chunk_chars": 1500}),
    "paraphrase-multilingual-MiniLM-L12-v2 (fp32)": (
        "sentence-transformers_paraphrase-multilingual-MiniLM-L12-v2", {
            "name": "paraphrase-multilingual-MiniLM-L12-v2-fp32", "onnx": "onnx/model.onnx",
            "pooling": "mean", "max_length": 128, "chunk_chars": 1500}),
    "paraphrase-multilingual-MiniLM-L12-v2 (int8, 400-char chunks)": (
        "sentence-transformers_paraphrase-multilingual-MiniLM-L12-v2", {
            "name": "paraphrase-multilingual-MiniLM-L12-v2", "onnx": "onnx/model_qint8_avx512.onnx",
            "pooling": "mean", "max_length": 128, "chunk_chars": 400}),
    "paraphrase-multilingual-MiniLM-L12-v2 (uint8 avx2, 400-char chunks)": (
        "sentence-transformers_paraphrase-multilingual-MiniLM-L12-v2", {
            "name": "paraphrase-multilingual-MiniLM-L12-v2", "onnx": "onnx/model_quint8_avx2.onnx",
            "pooling": "mean", "max_length": 128, "chunk_chars": 400}),
    "Qwen3-Embedding-0.6B (int8)": ("onnx-community_Qwen3-Embedding-0.6B-ONNX", {
        "name": "qwen3-embedding-0.6b", "onnx": "onnx/model_quantized.onnx", "pooling": "last",
        "max_length": 512,
        "query_prefix": "Instruct: Given a search query, retrieve relevant work notes\nQuery: "}),
    "potion-multilingual-128M (model2vec)": ("minishlab_potion-multilingual-128M", {
        "name": "potion-multilingual-128M", "onnx": "onnx/model.onnx", "pooling": "static",
        "max_length": 512}),
}


FILLER = [
    "The meeting started ten minutes late because the previous group still used the room.",
    "Wir haben zuerst die offenen Punkte aus der letzten Woche kurz durchgesprochen.",
    "Everyone agreed to keep the notes short and to send the slides afterwards.",
    "Ein Teilnehmer war nur telefonisch zugeschaltet, die Verbindung war zeitweise schlecht.",
    "We spent some time on general questions about the timeline and the next steps.",
    "Danach ging es um organisatorische Fragen, die nicht direkt zum Thema gehörten.",
    "Some of the background was already known from earlier conversations with the team.",
    "Die Unterlagen lagen vorab im gemeinsamen Ordner, wurden aber nicht von allen gelesen.",
    "Coffee was provided, and the discussion was friendly and constructive throughout.",
    "Am Ende blieb wenig Zeit, deshalb wurden einige Punkte auf den nächsten Termin verschoben.",
    "Several people mentioned that they would need to check details with colleagues first.",
    "Zur Einordnung wurde noch einmal die Ausgangslage aus Sicht des Projekts erklärt.",
]


def lengthen(notes: list[dict]) -> list[dict]:
    """Same notes, but each section starts with 4-6 unrelated filler sentences (~150 tokens)."""
    out = []
    for i, n in enumerate(notes):
        k = 4 + i % 3
        filler = " ".join(FILLER[(i + j) % len(FILLER)] for j in range(k))
        lines = n["body"].splitlines()
        head = [ln for ln in lines if ln.startswith("#")][:1]
        rest = [ln for ln in lines if not ln.startswith("#")] if head else lines
        body = "\n".join(head + [filler, ""] + rest)
        out.append({**n, "body": body})
    return out


def load_data():
    data = yaml.safe_load((HERE / "notes.yaml").read_text())
    return data["notes"], data["queries"]


def write_corpus(home: Path, notes: list[dict]) -> None:
    from kitbrain.notes import render
    home.mkdir(parents=True, exist_ok=True)
    for n in notes:
        (home / f"{n['id']}.md").write_text(render({"title": n["title"], "type": "note"}, n["body"]))


def score(ranked: list[list[str]], queries: list[dict]) -> dict:
    recall, rr = [], []
    for ids, q in zip(ranked, queries):
        rel = set(q["rel"])
        recall.append(len(rel & set(ids[:5])) / len(rel))
        rank = next((i + 1 for i, x in enumerate(ids) if x in rel), None)
        rr.append(1.0 / rank if rank else 0.0)
    return {"recall@5": round(statistics.mean(recall), 3), "mrr": round(statistics.mean(rr), 3)}


def model_size(model_dir: Path, spec: dict) -> int:
    files = [model_dir / spec["onnx"], model_dir / "tokenizer.json"]
    data = model_dir / (spec["onnx"] + "_data")
    if data.exists():
        files.append(data)
    return sum(f.stat().st_size for f in files if f.exists())


def run_one(variant: str, models_root: Path, threads: int) -> dict:
    """Runs inside a subprocess."""
    from kitbrain.config import Settings
    from kitbrain.embed import Embedder
    from kitbrain.index import Index

    folder, spec = VARIANTS[variant]
    notes, queries = load_data()
    tmp = Path(tempfile.mkdtemp(prefix="brain-bench-"))
    mdir = tmp / "model"
    mdir.mkdir()
    src = models_root / folder
    for item in src.iterdir():
        (mdir / item.name).symlink_to(item.resolve())
    (mdir / "brain-model.json").write_text(json.dumps(spec))
    os.environ["BRAIN_THREADS"] = str(threads)
    out = {"variant": variant, "threads": threads or os.cpu_count(), "size_mb": round(model_size(src, spec) / 1e6)}

    t0 = time.perf_counter()
    emb = Embedder(spec["name"], mdir)
    out["load_s"] = round(time.perf_counter() - t0, 2)

    home = tmp / "brain"
    write_corpus(home, notes)
    idx = Index(Settings(home=home, model=spec["name"], model_dir=mdir))
    idx._embedder, idx._embed_tried = emb, True
    t0 = time.perf_counter()
    idx.reindex(full=True)
    out["corpus_index_s"] = round(time.perf_counter() - t0, 2)
    out["chunks"] = idx.counts()["chunks"]

    # Throughput on exactly 1000 chunk texts (corpus chunks repeated with a counter).
    texts = [f"{t}\n{h}\n{x}" for t, h, x in idx.db.execute(
        "SELECT f.title, c.heading, c.text FROM chunks c JOIN files f ON f.path=c.path")]
    batch = [f"{texts[i % len(texts)]} ({i})" for i in range(1000)]
    t0 = time.perf_counter()
    emb.embed_docs(batch)
    out["index_s_per_1000_chunks"] = round(time.perf_counter() - t0, 2)
    toks = [len(e.ids) for e in emb.tok.encode_batch(batch)]
    out["avg_tokens_per_chunk"] = round(statistics.mean(toks))

    import kitbrain.index as index_mod
    para = [i for i, q in enumerate(queries) if q.get("kind") != "keyword"]
    kw = [i for i, q in enumerate(queries) if q.get("kind") == "keyword"]
    for mode, weight in (("dense", 1.0), ("bm25", 1.0), ("hybrid", 1.0), ("hybrid", 0.5), ("hybrid", 0.3)):
        index_mod.BM25_WEIGHT = weight
        ranked = []
        for q in queries:
            res, _ = idx.search(q["q"], k=10, mode=mode)
            ranked.append([Path(r.path).stem for r in res])
        key = mode if mode != "hybrid" else f"hybrid_w{weight}"
        out[key] = {"all": score(ranked, queries),
                    "paraphrase": score([ranked[i] for i in para], [queries[i] for i in para]),
                    "keyword": score([ranked[i] for i in kw], [queries[i] for i in kw])}
    index_mod.BM25_WEIGHT = 1.0

    # Robustness: relevant text pushed behind ~150 tokens of filler in the same section.
    home2 = tmp / "brain-long"
    write_corpus(home2, lengthen(notes))
    idx2 = Index(Settings(home=home2, model=spec["name"], model_dir=mdir))
    idx2._embedder, idx2._embed_tried = emb, True
    idx2.reindex(full=True)
    for mode, weight in (("dense", 1.0), ("hybrid", 1.0), ("hybrid", 0.5), ("hybrid", 0.3)):
        index_mod.BM25_WEIGHT = weight
        ranked = [[Path(r.path).stem for r in idx2.search(q["q"], k=10, mode=mode)[0]] for q in queries]
        key = "long_" + (mode if mode != "hybrid" else f"hybrid_w{weight}")
        out[key] = score(ranked, queries)
    index_mod.BM25_WEIGHT = 1.0
    idx2.close()

    lat = []
    for q in queries:
        t0 = time.perf_counter()
        emb.embed_queries([q["q"]])
        lat.append((time.perf_counter() - t0) * 1000)
    out["query_embed_ms_median"] = round(statistics.median(lat), 2)
    out["query_embed_ms_p95"] = round(sorted(lat)[int(0.95 * (len(lat) - 1))], 2)
    lat = []
    for q in queries:
        t0 = time.perf_counter()
        idx.search(q["q"], k=5)
        lat.append((time.perf_counter() - t0) * 1000)
    out["search_ms_median"] = round(statistics.median(lat), 1)
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    out["peak_rss_mb"] = round(rss / (1e6 if sys.platform == "darwin" else 1e3))
    idx.close()
    shutil.rmtree(tmp, ignore_errors=True)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models-root", type=Path, default=HERE.parent / ".cache" / "models")
    ap.add_argument("--one")
    ap.add_argument("--threads", type=int, default=0)
    ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    if a.one:
        print(json.dumps(run_one(a.one, a.models_root.resolve(), a.threads)))
        return
    notes, queries = load_data()
    results = {"notes": len(notes), "queries": len(queries), "runs": []}
    for variant in a.only or VARIANTS:
        for threads in (0, 1):
            proc = subprocess.run([sys.executable, __file__, "--one", variant, "--threads", str(threads),
                                   "--models-root", str(a.models_root)], capture_output=True, text=True)
            if proc.returncode != 0:
                print(proc.stderr, file=sys.stderr)
                continue
            row = json.loads(proc.stdout.strip().splitlines()[-1])
            print(json.dumps(row), file=sys.stderr)
            results["runs"].append(row)
    print(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
