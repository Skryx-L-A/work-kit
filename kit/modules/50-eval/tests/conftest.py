import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from fake_server import FakeServer  # noqa: E402


@pytest.fixture(autouse=True)
def isolated_home(tmp_path, monkeypatch):
    monkeypatch.setenv("EVALKIT_HOME", str(tmp_path / "home"))
    return tmp_path / "home"


@pytest.fixture
def fake_server():
    with FakeServer() as srv:
        yield srv


@pytest.fixture
def write_suite(tmp_path):
    def write(text: str, name: str = "suite.yaml") -> Path:
        path = tmp_path / name
        path.write_text(text, encoding="utf-8")
        return path

    return write
