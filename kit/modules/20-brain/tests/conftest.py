import hashlib
import re
import subprocess

import numpy as np
import pytest

from kitbrain import service


class FakeEmbedder:
    """Deterministic bag-of-words vectors: enough to test the dense plumbing."""

    name = "fake"
    dim = 64

    def _vec(self, text):
        v = np.zeros(self.dim, dtype=np.float32)
        for w in re.findall(r"\w+", text.lower()):
            v[int(hashlib.md5(w.encode()).hexdigest(), 16) % self.dim] += 1
        n = np.linalg.norm(v)
        return v / n if n else v

    def embed_queries(self, texts):
        return np.stack([self._vec(t) for t in texts])

    def embed_docs(self, texts, batch_size=16):
        return np.stack([self._vec(t) for t in texts]) if texts else np.zeros((0, self.dim))


@pytest.fixture
def env(tmp_path, monkeypatch):
    """Isolated brain: own home, config and data dirs, no model, hooks inert."""
    home = tmp_path / "brain"
    monkeypatch.setenv("BRAIN_HOME", str(home))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("BRAIN_MODEL_DIR", str(tmp_path / "no-model"))
    monkeypatch.setenv("BRAIN_NO_HOOKS", "1")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(tmp_path / "gitconfig"))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.delenv("BRAIN_MODEL", raising=False)
    (tmp_path / "gitconfig").write_text("[user]\n\tname = Test\n\temail = test@example.invalid\n"
                                        "[init]\n\tdefaultBranch = main\n")
    service._index = None
    service._index_home = None
    yield home
    if service._index is not None:
        service._index.close()
    service._index = None


@pytest.fixture
def fake_model(monkeypatch):
    monkeypatch.setattr("kitbrain.index.try_load", lambda name, d: (FakeEmbedder(), None))


def git(home, *args):
    return subprocess.run(["git", "-C", str(home), *args], capture_output=True, text=True,
                          check=True).stdout

