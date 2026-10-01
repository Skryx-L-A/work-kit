# brain: design notes

Module: `kit/modules/20-brain`. Python package `kitbrain`, CLI `brain`. This page explains why the
module is built the way it is; the README only lists commands.

## Storage

- Notes are plain Markdown files with YAML frontmatter in `$BRAIN_HOME` (default `~/work/brain`).
  They stay readable and editable without the tool, and git gives history, blame and undo.
- Placement follows the type: `note` goes to `inbox/`, `decision` to `decisions/NNNN-slug.md`
  (numbered ADRs, `status: proposed`), `session` to `projects/<p>/sessions/<date>-slug.md`, `kern` to
  `projects/<p>/KERN.md` (one per project), `howto`, `reference`, `person` to their folders.
- Every write through `brain` or the MCP server is one commit (`brain: new decision "…"`,
  `brain: append to "…"`). Only the touched file is committed, so unrelated work in progress in the
  notes repo is never swept into a brain commit. If git has no user identity, the commit uses
  `brain <brain@localhost>` instead of failing.
- Backup: the notes are company data and live only in `$BRAIN_HOME` unless a remote exists, so a lost
  laptop loses them. `brain backup DIR` writes `DIR/brain-<date>.bundle` (`git bundle create --all`,
  verified, a second run on the same day replaces the file) and records the path in
  `.brain/last-backup`. `brain doctor` warns on the `remote` line while there is no remote and no
  recorded bundle newer than 7 days. Restore: `git clone <file>.bundle <folder>`. The folder must be one
  IT approves; no private machine or account.
- `brain append` edits only the `updated:` line of the frontmatter, so comments and formatting that
  the user wrote by hand survive.

## Index

- One SQLite file in `$BRAIN_HOME/.brain/index.sqlite` (gitignored, rebuildable at any time).
- Notes are split into chunks at Markdown headings (headings inside code fences are ignored).
  Sections longer than the model's `chunk_chars` (400 for the default model, which reads at most
  128 tokens; 1500 without a model setting) are split at paragraph boundaries. When the model is
  missing, the existing chunking is kept, so a temporary outage does not trigger a rebuild. Each chunk is indexed with the
  note title and its heading path, e.g. `Payment outage > Action items`.
- Incremental: a file is re-read only when its mtime or size changed, re-chunked only when its
  SHA-256 changed. Vectors are keyed by the hash of the chunk content, so editing one section of a
  note re-embeds only that section, and a pure rename re-embeds nothing.
- Changing the model (name) invalidates all vectors; the next search or `brain reindex` rebuilds them.
- `brain search` does a cheap stale check (stat of every note) and reindexes changed files first.
  Git hooks (`post-commit`, `post-merge`, `post-checkout`) start a background `brain reindex --quiet`
  so edits made in an editor and committed by hand are indexed without waiting for the next search.
  A file lock serialises concurrent reindex runs; a search that finds the lock busy searches the
  existing index instead of waiting.
- Existing hooks are kept: they are renamed to `<hook>.local` and called first by the brain hook.
  If `core.hooksPath` points elsewhere (for example a global data-guard hook directory), the brain
  hooks are inactive; `brain doctor` says so and the lazy reindex before each search still works.

## Search

- BM25 through SQLite FTS5 (`unicode61`, diacritics folded; title weighted 5, heading 2, text 1).
  The query is turned into an OR of its words after dropping German and English stopwords.
  Without the stopword filter, words like "die", "wie", "the" matched almost every note and lowered
  hybrid recall@5 on the test set from 0.782 to 0.736 (multilingual-e5-small, 55 paraphrase queries,
  measured 2026-09-24).
- Dense: cosine similarity between the query vector and all chunk vectors (NumPy matrix product;
  brute force is fast enough for tens of thousands of chunks).
- Fusion: reciprocal rank fusion at note level, `score = Σ w / (60 + rank)`, where a note's rank in
  each list is the rank of its best chunk. The reported snippet is that best chunk.
  The BM25 weight is `BM25_WEIGHT` in `index.py` (1.0, plain RRF); see `embedding-choice.md`.
- No model, broken model or missing files: search runs on BM25 alone, prints one warning (then not
  again until the model has worked once), and `--json` output carries `"mode": "bm25"`.
- `status`, `recent`, `week`, `log` and `read` do not load the embedding model. `brain doctor`
  checks model files only; `brain doctor --deep` additionally loads the model and runs inference.

## Embeddings

- `onnxruntime` on CPU and the `tokenizers` library, no PyTorch. A model directory holds
  `tokenizer.json`, the ONNX file and `brain-model.json` (ONNX path, pooling `mean` | `cls` | `last` |
  `static`, max length, query/document prefixes). Any compatible model can be used by pointing
  `BRAIN_MODEL_DIR` at such a directory and setting `BRAIN_MODEL` to a new name.
- `BRAIN_THREADS` limits the ONNX thread count (default: all cores).
- Both int8 files of the default model ship (`model_qint8_avx512.onnx`, `model_quint8_avx2.onnx`).
  `install.sh` installs one: avx512 when `/proc/cpuinfo` lists `avx512f` and `avx512bw`, else avx2
  (also without `/proc/cpuinfo`). `BRAIN_MODEL_VARIANT` overrides. The index key includes the ONNX
  file, so switching the variant rebuilds the vectors on the next search.
- The default model and the numbers behind it are in `embedding-choice.md`.

## Ingest

- `brain ingest <file>` turns PDF, DOCX, PPTX, XLSX, HTML, Markdown and text into a note (default
  type `reference`) and commits it. Office files are read straight from their ZIP/XML parts with
  the standard library; PDF uses `pypdf` (pure Python). No converter binary, office suite or
  network is needed, and the wheel set stays small. `pandoc` from 12-docs-tools is not required.
- Structure is kept where it helps search: DOCX headings become Markdown headings, lists and
  tables are kept; PPTX gives one `## Slide N: <title>` section per slide plus speaker notes;
  XLSX one `## Sheet: <name>` table per visible sheet (first 1000 rows); PDF one `## Page N`
  section per page, so search hits cite the page or slide.
- Frontmatter `source` records path, file name, format, SHA-256, ingest time, pages and any
  classification labels found in document properties (sensitivity labels such as
  `MSIP_Label_*_Name`, keywords, PDF metadata).
- The same content twice is a no-op; a changed source needs `--update` (then the note is replaced
  and keeps its `created` date). `--stdout` converts without writing.
- Limits: scanned PDFs have no text layer and are refused (no OCR); archives that expand beyond
  300 MB are refused; charts, images and formulas are not converted.

## Worklog and week report

- `brain log "<text>" [--hours H] [--project P] [--date D]` appends one line to
  `worklog/<ISO year>-W<week>.md` (`- 2026-09-25 14:05 | 2.5 h | billing | text`) and commits it.
  Hours accept `2`, `1.5`, `1,5`, `90m`, `1:30`. The files stay editable by hand; `brain week`
  parses every line of that format.
- `brain week` sums the hours of an ISO week against the working-student limit (20 h, change
  with `week_limit_hours` or `BRAIN_WEEK_LIMIT`), marks the week "close" from 90 % and "over"
  above the limit, and adds git activity: own commits (by each repo's `user.email`) in every git
  repo up to three levels below `~/work` (`work_dir`, `BRAIN_WORK_DIR`). Days with commits but no
  logged hours are listed so missing entries are easy to spot. `--save` stores the report as
  `worklog/<week>-report.md`. `brain log` prints the running total and warns near the limit.

## doc-qa (module 18-doc-qa)

- Questions over approved company documents. The code ships in the `kitbrain` wheel as the
  second command `doc-qa`, because the offline build resolves each module's dependencies from
  PyPI and cannot depend on another kit module's package. Module 18-doc-qa installs the config,
  the approval checklist and the tests; without it `doc-qa` only reports that it is disabled.
- Separate scope: its own notes repo and index (default `~/work/doc-qa`), never the personal brain.
  Only ingested documents answer; the scope has no template notes.
- Disabled until `~/.config/work-kit/doc-qa.toml` has `enabled = true`, a scope name, approver,
  approval date, source folders and either allowed labels or `unlabeled = "allow"`. Every command
  except `init` and `status` refuses otherwise and says which field is missing.
- Gate per file, exclusions first: path patterns (`exclude`), then excluded labels (confidential,
  customer, personal, … in English and German, matched as words), then allowed labels. Labels come
  from document properties and from label markers in the first 3000 and last 1500 characters
  (`Classification: Internal`, a line reading only `VERTRAULICH`, …). Unlabeled documents are
  skipped unless configured otherwise.
- `doc-qa sync` ingests new and changed documents and removes notes whose source vanished or no
  longer passes the gate (relabelled, excluded), each as a git commit.
- No answer generation: `doc-qa ask` returns numbered passages with source file and page/slide/
  heading plus answering rules; `--prompt` prints them as a prompt for whatever model IT approved.
  The MCP tool `ask_documents` returns the same, so the agent writes the cited answer and a human
  reviews it. This keeps doc-qa free of any model or network choice.

## MCP server

`brain mcp` speaks MCP over stdio (newline-delimited JSON-RPC 2.0) and offers the tools `search`,
`read`, `new_note`, `append`, `recent`. It is implemented by hand (about 150 lines) instead of using
the MCP Python SDK, because the SDK pulls in about 20 more wheels (pydantic, starlette, uvicorn,
httpx, …) that the offline kit would have to ship and keep patched, for four JSON-RPC methods.
Paths are confined to `$BRAIN_HOME`; `.git/` and `.brain/` are not readable through it.

## Known limits

- Brute-force dense search holds all vectors in memory: about 1.5 KB per chunk at 384 dimensions.
- The stopword lists are short and fixed; German compounds are not split, so BM25 does not match
  `Datenbankverbindung` for `Datenbank`. The dense side covers most of these cases.

## Settings, model variant, build host, tests

- Settings: `BRAIN_HOME`, `BRAIN_MODEL`, `BRAIN_MODEL_DIR`, `BRAIN_WEEK_LIMIT`, `BRAIN_WORK_DIR`,
  or `~/.config/work-kit/brain.toml` (`home`, `model`, `model_dir`, `week_limit_hours`,
  `work_dir`). The config file wins over the built-in default, the environment over the file.
- Model CPU variant is detected from `/proc/cpuinfo`; force one with
  `BRAIN_MODEL_VARIANT=avx2` or `BRAIN_MODEL_VARIANT=avx512` before running `install.sh`.
- Build host: `bash fetch-model.sh` fills `kit/offline/models/`.
- Tests: `uv run pytest` in the module folder (`-m model` also runs the tests with the model).
