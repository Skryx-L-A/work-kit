"""Real embedding model. Deselected by default; run with: pytest -m model

Needs the model directory from fetch-model.sh (kit/offline/models/<name>) or BRAIN_TEST_MODEL_DIR.
"""
import json
import os
import re
from pathlib import Path

import pytest

from kitbrain import cli, config

pytestmark = pytest.mark.model
MODULE = Path(__file__).resolve().parents[1]


def model_conf():
    text = (MODULE / "model.conf").read_text()
    return dict(re.findall(r'^(BRAIN_MODEL_\w+)="?([^"\n]*)"?', text, re.M))


def test_default_model_matches_model_conf():
    assert config.DEFAULT_MODEL == model_conf()["BRAIN_MODEL_NAME"]


def test_hybrid_search_with_real_model(env, capsys, monkeypatch):
    name = model_conf()["BRAIN_MODEL_NAME"]
    mdir = Path(os.environ.get("BRAIN_TEST_MODEL_DIR") or MODULE.parents[1] / "offline" / "models" / name)
    assert (mdir / "brain-model.json").is_file(), f"run fetch-model.sh first ({mdir})"
    monkeypatch.setenv("BRAIN_MODEL_DIR", str(mdir))
    cli.main(["new", "howto", "Restore the database backup", "--body",
              "## Steps\nStop the service, run pg_restore into a scratch instance, compare row counts."])
    cli.main(["new", "note", "Lunch options", "--body", "The cafeteria opens at 11:30."])
    capsys.readouterr()
    cli.main(["search", "Wie spiele ich eine Datensicherung zurück?", "--json"])
    res = json.loads(capsys.readouterr().out)
    assert res["mode"] == "hybrid"
    assert res["results"][0]["title"] == "Restore the database backup"
