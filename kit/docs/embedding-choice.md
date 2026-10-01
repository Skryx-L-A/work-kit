# Embedding model choice for brain

Decision (2026-09-25): the default model is **`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`,
int8 ONNX (`onnx/model_qint8_avx512.onnx`)**, used with chunks of at most 400 characters and
plain reciprocal rank fusion (BM25 weight 1.0). It had the best hybrid retrieval on both test
conditions, is the smallest candidate on disk (127 MB), and indexes as fast as the fastest
transformer candidate. Licence: Apache-2.0. Pinned revision and checksums: `kit/modules/20-brain/model.conf`.

## Method

- Test set: `kit/modules/20-brain/bench/notes.yaml`. 154 synthetic work notes (German and English,
  software modernisation topics: mainframe, Java upgrades, databases, CI, testing, security, AI
  experiments, meetings, work contacts, how-tos, admin), all names and customers invented.
  72 queries, each with one or two relevant notes:
  - 55 paraphrase queries (25 German, 30 English), deliberately worded differently from the note,
    many cross-language (German query, English note and the reverse);
  - 17 keyword queries (identifiers such as `HikariCP maximumPoolSize`, `ora2pg`, `CycloneDX`).
- Two conditions:
  - **short**: notes as written (155 chunks, mean 43 tokens per chunk);
  - **long**: the same notes with 4 to 6 unrelated filler sentences (about 150 tokens) placed in
    front of the content in the same section. Real notes are longer than the synthetic ones; this
    checks what happens when the relevant text is not at the start of a chunk.
- Pipeline: the real `brain` index code (heading chunking, SQLite FTS5, dense cosine, note-level
  RRF). Modes: dense only, BM25 only, hybrid with BM25 weight 1.0, 0.5 and 0.3.
- Metrics at note level: recall@5 (share of relevant notes in the top 5, averaged over queries) and
  MRR (reciprocal rank of the first relevant note).
- Speed: time to embed exactly 1000 chunks (corpus chunks repeated), and the median/p95 time to
  embed one query, measured with all threads (18) and with one thread (`BRAIN_THREADS=1`).
  Peak RAM is the peak resident set size of the whole measurement process (Python, SQLite, model,
  both indexes), one process per model and thread setting.
- Runtime: onnxruntime 1.30.0, tokenizers 0.23.2, NumPy 2.5.3, CPython 3.12.13; CPU only, no PyTorch.
- Machine: Apple M5 Pro (arm64, 18 cores, 48 GB), macOS 26.5.1. Other work was running on the
  machine, so timings carry some noise. The target laptop is x86_64; absolute timings there will
  differ (see open points).
- Reproduce: `cd kit/modules/20-brain && uv run python bench/measure.py --models-root <dir>`
  (download the candidates first; the file names are in `bench/measure.py`).
  Raw numbers: `bench/results-2026-09-25.json`.

## Results

### Retrieval quality (72 queries; recall@5 / MRR)

| Model (variant) | Dense short | Hybrid short | Dense long | Hybrid long |
|---|---|---|---|---|
| BM25 only (no model) | – | 0.771 / 0.699 | – | – |
| multilingual-e5-small, int8 | 0.861 / 0.806 | 0.833 / 0.795 | 0.938 / 0.872 | 0.944 / 0.812 |
| multilingual-e5-small, fp32 | 0.847 / 0.794 | 0.833 / 0.788 | 0.924 / 0.871 | 0.944 / 0.815 |
| **paraphrase-multilingual-MiniLM-L12-v2, int8, 400-char chunks** | 0.882 / 0.832 | **0.958 / 0.861** | 0.861 / 0.762 | **0.951 / 0.846** |
| paraphrase-multilingual-MiniLM-L12-v2, int8, 1500-char chunks ¹ | 0.882 / 0.832 | 0.958 / 0.861 | 0.639 / 0.572 | 0.861 / 0.726 |
| paraphrase-multilingual-MiniLM-L12-v2, fp32, 1500-char chunks | 0.875 / 0.827 | 0.958 / 0.865 | 0.639 / 0.541 | 0.861 / 0.721 |
| Qwen3-Embedding-0.6B, int8 | 0.896 / 0.858 | 0.868 / 0.805 | 0.910 / 0.787 | 0.889 / 0.785 |
| potion-multilingual-128M (model2vec) | 0.757 / 0.631 | 0.854 / 0.754 | 0.694 / 0.548 | 0.826 / 0.736 |

¹ Measured in an earlier run of the same script, before the chunk size became a model setting.
In the short condition every chunk is below 400 characters, so short numbers are identical.
In `results-2026-09-25.json` the row labelled plain "int8" also ran with 400-character chunks
(the built-in model setting overrode the benchmark's); `bench/measure.py` now pins 1500 for it.

Split by query kind (short condition, recall@5): MiniLM dense finds 0.918 of the paraphrase
targets but only 0.765 of the keyword targets; hybrid lifts keywords to 1.0 and paraphrases to
0.945. e5-small dense already finds all keyword targets (1.0) but only 0.818 of the paraphrases,
and adding BM25 lowers its paraphrase recall to 0.782.

BM25 weight (hybrid recall@5, short / long): MiniLM 1.0: 0.958 / 0.951, 0.5: 0.958 / 0.938,
0.3: 0.993 / 0.931. e5-small 1.0: 0.833 / 0.944, 0.3: 0.819 / 0.972. No weight wins on both
conditions for the chosen model, so the default stays at plain RRF (1.0) rather than a value tuned
to this small test set.

### Speed and size (all threads = 18 / one thread)

| Model (variant) | Disk (ONNX + tokenizer) | Index time per 1000 chunks | Query embed median (p95) | Peak RSS |
|---|---|---|---|---|
| multilingual-e5-small, int8 | 135 MB | 2.4 s / 5.9 s | 1.6 ms (2.0) / 1.8 ms (2.4) | 757 MB |
| multilingual-e5-small, fp32 | 487 MB | 2.0 s / 4.8 s | 1.9 ms (2.1) / 2.0 ms (2.3) | 1400 MB |
| **paraphrase-multilingual-MiniLM-L12-v2, int8** | **127 MB** | **2.5 s / 5.9 s** | **1.6 ms (2.0) / 1.6 ms (2.1)** | **679 MB** |
| paraphrase-multilingual-MiniLM-L12-v2, fp32 | 479 MB | 2.0 s / 4.7 s | 2.1 ms (2.5) / 1.8 ms (2.0) | 1393 MB |
| Qwen3-Embedding-0.6B, int8 | 625 MB | 30.2 s / 125.9 s | 21.3 ms (29.5) / 61.0 ms (77.5) | 2665 MB |
| potion-multilingual-128M (model2vec) | 531 MB | 0.08 s / 0.03 s | 0.02 ms / 0.02 ms | 2070 MB |

Model load time was 0.3 to 0.6 s for all candidates. A full `brain search` including query
embedding took about 2 ms with every model except Qwen3 (22 ms all threads, 61 ms one thread).

## Why this model

- Quality: best hybrid recall@5 and MRR in both conditions (0.958 short, 0.951 long). Its weak
  spot, exact identifiers, is exactly what BM25 covers, so the fusion gains more than for e5-small,
  whose errors overlap more with BM25's.
- Long sections: the model reads at most 128 tokens. With 1500-character chunks, text behind the
  first ~128 tokens was invisible to it (long-condition dense recall 0.639). Limiting chunks to
  400 characters (`chunk_chars` in `brain-model.json`) restored it to 0.861 dense and 0.951 hybrid.
- Cost: smallest download, lowest RAM of the transformer candidates (under 700 MB peak for the
  whole process, fine for an 8 GB laptop), about 6 s per 1000 chunks on one thread.
- Qwen3-Embedding-0.6B has the best dense-only quality on short notes, but it is 12 to 21 times
  slower to index, needs about 2.7 GB of RAM and did not beat MiniLM in hybrid mode.
- potion-multilingual-128M is by far the fastest but has the weakest dense quality and, as ONNX,
  a surprisingly high RSS (2 GB). It is not worth the 531 MB.
- int8 lost nothing against fp32 for either small model and needs a quarter of the disk and half
  the RAM. On arm64 the int8 files were slightly slower than fp32; x86 CPUs with VNNI usually show
  the opposite.

## CPU variants (2026-09-25)

The model repository has int8 builds tuned for different x86 instruction sets. Both ship, and
`install.sh` picks one from `/proc/cpuinfo` (see `docs/brain.md`). Retrieval quality on the same
test set (72 queries, 400-character chunks, recall@5 / MRR; raw numbers
`bench/results-2026-09-25-avx2.json`):

| Variant | Dense short | Hybrid short | Dense long | Hybrid long |
|---|---|---|---|---|
| `model_qint8_avx512.onnx` | 0.882 / 0.832 | 0.958 / 0.861 | 0.861 / 0.762 | 0.951 / 0.846 |
| `model_quint8_avx2.onnx` | 0.889 / 0.847 | 0.972 / 0.867 | 0.847 / 0.758 | 0.938 / 0.843 |

The two are equivalent within the noise of 72 queries. The timings of that run (13 to 21 s per
1000 chunks) were taken while the machine was busy with other work and are not comparable with
the table above; speed per variant has to be measured on the x86 laptop.

## Open points

- All timings come from an Apple M5 Pro. The Lima Ubuntu x86_64 end-to-end test should record
  `brain reindex --full` time for a few hundred notes with each CPU variant.
- The test set was written by one person together with the queries; real notes and real queries
  will be longer and messier. Re-run `bench/measure.py` with a sample of real (non-confidential)
  notes after a few weeks of use before changing the default.
- Changing the model later is supported: install another model directory with a
  `brain-model.json`, set `BRAIN_MODEL`/`BRAIN_MODEL_DIR`, and the next search rebuilds the vectors.
