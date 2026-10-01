"""Dense embeddings on CPU with onnxruntime and a HuggingFace tokenizer.json.

A model directory holds `tokenizer.json`, an ONNX file and `brain-model.json`
describing how to run it. Without `brain-model.json` the built-in spec for the
configured model name is used. No PyTorch is involved.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

# pooling: mean | cls | last (last token, needs left context) | static (model2vec EmbeddingBag)
KNOWN: dict[str, dict] = {
    "multilingual-e5-small": {
        "onnx": "onnx/model_quantized.onnx", "pooling": "mean", "max_length": 512,
        "query_prefix": "query: ", "doc_prefix": "passage: ",
        "source": "Xenova/multilingual-e5-small",
    },
    "paraphrase-multilingual-MiniLM-L12-v2": {
        "onnx": "onnx/model_qint8_avx512.onnx", "pooling": "mean", "max_length": 128,
        "chunk_chars": 400,
        "source": "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
    },
    "qwen3-embedding-0.6b": {
        "onnx": "onnx/model_quantized.onnx", "pooling": "last", "max_length": 512,
        "query_prefix": "Instruct: Given a search query, retrieve relevant work notes\nQuery: ",
        "source": "onnx-community/Qwen3-Embedding-0.6B-ONNX",
    },
    "potion-multilingual-128M": {
        "onnx": "onnx/model.onnx", "pooling": "static", "max_length": 512,
        "source": "minishlab/potion-multilingual-128M",
    },
}


class ModelMissing(Exception):
    pass


@dataclass
class ModelSpec:
    name: str
    onnx: str
    pooling: str = "mean"
    max_length: int = 512
    query_prefix: str = ""
    doc_prefix: str = ""
    # Longest chunk the model should see; sections above it are split at paragraphs.
    # Keep it within max_length tokens, or text past the limit is silently ignored.
    chunk_chars: int = 1500
    extra: dict = field(default_factory=dict)

    @classmethod
    def load(cls, name: str, model_dir: Path) -> "ModelSpec":
        data = dict(KNOWN.get(name, {}))
        meta = model_dir / "brain-model.json"
        if meta.is_file():
            data.update(json.loads(meta.read_text()))
        data.setdefault("name", name)
        if "onnx" not in data:
            raise ModelMissing(f"unknown model '{name}' and no brain-model.json in {model_dir}")
        known = {k: data.pop(k) for k in list(data) if k in cls.__dataclass_fields__ and k != "extra"}
        return cls(**known, extra=data)


class Embedder:
    def __init__(self, name: str, model_dir: Path, threads: int | None = None):
        import onnxruntime as ort
        from tokenizers import Tokenizer

        self.spec = ModelSpec.load(name, model_dir)
        onnx_path = model_dir / self.spec.onnx
        tok_path = model_dir / "tokenizer.json"
        if not onnx_path.is_file() or not tok_path.is_file():
            raise ModelMissing(f"model files missing in {model_dir}")
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        threads = threads if threads is not None else int(os.environ.get("BRAIN_THREADS", "0"))
        if threads:
            opts.intra_op_num_threads = threads
            opts.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(onnx_path), opts, providers=["CPUExecutionProvider"])
        self.inputs = {i.name for i in self.session.get_inputs()}
        self.tok = Tokenizer.from_file(str(tok_path))
        self.tok.no_padding()
        self.tok.enable_truncation(self.spec.max_length)
        self.name = self.spec.name
        self.dim: int | None = None

    def embed_queries(self, texts: list[str]) -> np.ndarray:
        return self._embed([self.spec.query_prefix + t for t in texts])

    def embed_docs(self, texts: list[str], batch_size: int = 16) -> np.ndarray:
        texts = [self.spec.doc_prefix + t for t in texts]
        # Sort by length so batches pad little; restore order afterwards.
        order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
        out: list[np.ndarray | None] = [None] * len(texts)
        for s in range(0, len(order), batch_size):
            idx = order[s:s + batch_size]
            vecs = self._embed([texts[i] for i in idx])
            for i, v in zip(idx, vecs):
                out[i] = v
        if not out:
            return np.zeros((0, self.dim or 0), dtype=np.float32)
        return np.stack(out)

    def _embed(self, texts: list[str]) -> np.ndarray:
        if self.spec.pooling == "static":
            vecs = self._static(texts)
        else:
            vecs = self._transformer(texts)
        vecs = vecs.astype(np.float32)
        norms = np.linalg.norm(vecs, axis=1, keepdims=True)
        vecs = vecs / np.maximum(norms, 1e-12)
        self.dim = vecs.shape[1]
        return vecs

    def _static(self, texts: list[str]) -> np.ndarray:
        encs = self.tok.encode_batch(texts, add_special_tokens=False)
        ids, offsets, pos = [], [], 0
        for e in encs:
            offsets.append(pos)
            ids.extend(e.ids or [0])
            pos += len(e.ids or [0])
        feeds = {"input_ids": np.array(ids, dtype=np.int64), "offsets": np.array(offsets, dtype=np.int64)}
        return self.session.run(None, feeds)[0]

    def _transformer(self, texts: list[str]) -> np.ndarray:
        encs = self.tok.encode_batch(texts)
        n = max(len(e.ids) for e in encs)
        ids = np.zeros((len(encs), n), dtype=np.int64)
        mask = np.zeros((len(encs), n), dtype=np.int64)
        pad_id = self.spec.extra.get("pad_id", 0)
        ids[:] = pad_id
        left = self.spec.pooling == "last"  # left padding keeps the last token at the end
        for i, e in enumerate(encs):
            L = len(e.ids)
            sl = slice(n - L, n) if left else slice(0, L)
            ids[i, sl] = e.ids
            mask[i, sl] = 1
        feeds = {"input_ids": ids, "attention_mask": mask}
        if "token_type_ids" in self.inputs:
            feeds["token_type_ids"] = np.zeros_like(ids)
        if "position_ids" in self.inputs:
            pos = np.cumsum(mask, axis=1) - 1
            feeds["position_ids"] = np.clip(pos, 0, None)
        feeds = {k: v for k, v in feeds.items() if k in self.inputs}
        for inp in self.session.get_inputs():
            if inp.name.startswith("past_key_values"):  # decoder export: empty KV cache
                shape = [len(encs) if d == "batch_size" else 0 if isinstance(d, str) else d
                         for d in inp.shape]
                dtype = np.float16 if "float16" in inp.type else np.float32
                feeds[inp.name] = np.zeros(shape, dtype=dtype)
        hidden = self.session.run(None, feeds)[0]
        if self.spec.pooling == "cls":
            return hidden[:, 0]
        if self.spec.pooling == "last":
            return hidden[:, -1]
        m = mask[..., None].astype(hidden.dtype)
        return (hidden * m).sum(1) / np.maximum(m.sum(1), 1e-9)


def try_load(name: str, model_dir: Path) -> tuple[Embedder | None, str | None]:
    """Return (embedder, None) or (None, reason)."""
    try:
        return Embedder(name, model_dir), None
    except ModelMissing as exc:
        return None, str(exc)
    except Exception as exc:  # broken ONNX file, wrong runtime...
        return None, f"model failed to load: {exc}"


def files_error(name: str, model_dir: Path) -> str | None:
    """Check the configured model files without importing ONNX Runtime or loading the model."""
    try:
        spec = ModelSpec.load(name, model_dir)
    except Exception as exc:
        return f"model metadata is invalid: {exc}"
    missing = [str(model_dir / path) for path in (spec.onnx, "tokenizer.json")
               if not (model_dir / path).is_file()]
    if missing:
        return f"model files missing in {model_dir}"
    return None
