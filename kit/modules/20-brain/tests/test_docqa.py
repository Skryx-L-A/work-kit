import json
import os
import subprocess
import sys

import pytest

import docfixtures as fx
from conftest import git
from kitbrain import docqa


@pytest.fixture
def scope(env, tmp_path, monkeypatch):
    cfg = tmp_path / "config" / "work-kit" / "doc-qa.toml"
    docs = tmp_path / "approved"
    (docs / "customers").mkdir(parents=True)
    fx.docx(docs / "handbook.docx", title="Engineering handbook", label="Internal",
            paras=[("Heading1", "Branching"), ("", "Feature branches live at most two days.")])
    fx.docx(docs / "salaries.docx", title="Salary bands", label="Strictly Confidential",
            paras=[("", "Band B pays well.")])
    fx.docx(docs / "customers" / "acme.docx", title="Customer contract", label="Internal",
            paras=[("", "Contract details.")])
    fx.pdf(docs / "unlabeled.pdf", [["Lunch menu of the week"]])
    (docs / "wiki.html").write_text("<p>Classification: Public</p><h1>VPN</h1><p>Use the client "
                                    "and the second factor.</p>")
    (docs / "memo.md").write_text("VERTRAULICH\n\nDo not share the reorg plan.\n")
    cfg.parent.mkdir(parents=True, exist_ok=True)

    def write(**over):
        values = {"enabled": "true", "scope": '"handbooks"', "approved_by": '"IT ticket 4711"',
                  "approved_on": '"2026-10-02"', "home": f'"{tmp_path / "docqa"}"',
                  "sources": f'["{docs}"]', "allowed_labels": '["Internal", "Public"]',
                  "unlabeled": '"skip"'}
        values.update(over)
        body = "\n".join(f"{k} = {v}" for k, v in values.items())
        tpl = docqa.TEMPLATE
        excluded = tpl[tpl.index("excluded_labels"):]
        cfg.write_text(body + "\n" + excluded)

    write()
    return {"cfg": cfg, "docs": docs, "home": tmp_path / "docqa", "write": write}


def test_template_is_disabled(env, tmp_path, capsys):
    assert docqa.main(["init"]) == 0
    assert docqa.main(["init"]) == 0
    assert "left unchanged" in capsys.readouterr().out
    cfg = docqa.load_config()
    assert not cfg.enabled and "enabled = false" in cfg.problems()
    assert docqa.main(["ask", "anything"]) == 1
    assert "disabled until an approved scope" in capsys.readouterr().err
    assert docqa.main(["sync"]) == 1


def test_missing_approval_keeps_it_disabled(scope, capsys):
    scope["write"](approved_by='""')
    assert docqa.main(["sync"]) == 1
    assert "approved_by is empty" in capsys.readouterr().err
    assert not scope["home"].exists()


def test_gate_decisions():
    cfg = docqa.Config(path=None, allowed_labels=["Internal", "Public"], unlabeled="skip",
                       excluded_labels=["confidential", "customer"], exclude=["**/hr/**"])
    from pathlib import Path
    p = Path("/docs/a.docx")
    assert docqa.gate(cfg, p, ["Internal"])[0]
    assert not docqa.gate(cfg, p, ["Internal", "Strictly Confidential"])[0]  # exclusion wins
    assert not docqa.gate(cfg, p, ["Restricted"])[0]
    assert not docqa.gate(cfg, p, [])[0]
    assert not docqa.gate(cfg, Path("/docs/hr/x.docx"), ["Public"])[0]
    cfg.unlabeled = "allow"
    assert docqa.gate(cfg, p, [])[0]


def test_text_labels():
    assert "Public" in docqa.text_labels("Classification: Public\n\ntext")
    assert "VERTRAULICH" in docqa.text_labels("VERTRAULICH\n\ntext")
    assert docqa.text_labels("We keep confidential data out of prompts, as a rule of thumb.") == []


def test_sync_ask_and_revocation(scope, capsys, monkeypatch):
    assert docqa.main(["sync", "--dry-run", "--json"]) == 0
    dry = json.loads(capsys.readouterr().out)
    assert not scope["home"].exists()
    assert sorted(os.path.basename(x["file"]) for x in dry["added"]) == ["handbook.docx", "wiki.html"]

    assert docqa.main(["sync", "--json"]) == 0
    rep = json.loads(capsys.readouterr().out)
    added = sorted(os.path.basename(x["file"]) for x in rep["added"])
    skipped = {os.path.basename(x["file"]): x["reason"] for x in rep["skipped"]}
    assert added == ["handbook.docx", "wiki.html"]
    assert "excluded" in skipped["salaries.docx"] and "exclude pattern" in skipped["acme.docx"]
    assert "no label" in skipped["unlabeled.pdf"] and "excluded" in skipped["memo.md"]
    home = scope["home"]
    assert not (home / "README.md").exists()  # no personal-notes template in the scope
    log = git(home, "log", "--pretty=%s")
    assert "doc-qa: initialize scope handbooks" in log and 'brain: ingest "Engineering handbook"' in log

    # The personal brain is untouched.
    assert os.environ["BRAIN_HOME"] == str(home.resolve())

    assert docqa.main(["ask", "how long may a feature branch live", "--json"]) == 0
    res = json.loads(capsys.readouterr().out)
    assert res["passages"][0]["source"] == "handbook.docx"
    assert "two days" in res["passages"][0]["text"] and res["passages"][0]["location"] == "Branching"
    assert docqa.main(["ask", "feature branch", "--prompt"]) == 0
    assert "Answer only from the passages" in capsys.readouterr().out

    # Relabel the handbook as confidential: next sync removes it.
    fx.docx(scope["docs"] / "handbook.docx", title="Engineering handbook", label="Confidential",
            paras=[("", "Feature branches live at most two days.")])
    docqa.main(["sync", "--json"])
    rep = json.loads(capsys.readouterr().out)
    assert [os.path.basename(x["file"]) for x in rep["removed"]] == ["handbook.docx"]
    docqa.main(["ask", "feature branch", "--json"])
    assert all(p["source"] != "handbook.docx" for p in json.loads(capsys.readouterr().out)["passages"])
    assert git(home, "status", "--porcelain") == ""


def test_mcp(scope):
    docqa.main(["sync"])
    env = {**os.environ}
    proc = subprocess.run(
        [sys.executable, "-m", "kitbrain.docqa", "mcp"], env=env, capture_output=True, text=True,
        timeout=60, input="\n".join(json.dumps(m) for m in [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": {"name": "ask_documents", "arguments": {"question": "VPN second factor"}}},
        ]) + "\n")
    replies = [json.loads(line) for line in proc.stdout.splitlines()]
    assert replies[0]["result"]["serverInfo"]["name"] == "doc-qa"
    assert {t["name"] for t in replies[1]["result"]["tools"]} == {"ask_documents", "documents_status"}
    res = json.loads(replies[2]["result"]["content"][0]["text"])
    assert res["passages"][0]["source"] == "wiki.html"
