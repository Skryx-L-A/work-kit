import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

from evalkit.cli import main

EXAMPLES = Path(__file__).resolve().parent.parent / "examples"


def test_offline_example_passes_and_saves(capsys, isolated_home):
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "--fail-under", "1"]) == 0
    out = capsys.readouterr()
    assert "Overall pass rate: 100% (16/16)" in out.out
    saved = list((isolated_home / "results").glob("offline-demo-*.json"))
    assert len(saved) == 1
    data = json.loads(saved[0].read_text())
    assert data["summary"]["passed"] == 16 and data["suite"]["sha256"]


def test_extraction_example_baseline_fails_only_german_case(capsys):
    assert main(["run", str(EXAMPLES / "extraction.yaml"), "-q", "--no-save", "--fail-under", "1"]) == 1
    out = capsys.readouterr().out
    assert "| plain | 3/3 |" in out and "| german-number-format | 0/3 |" in out


def test_docs_quality_example_against_fake_server(monkeypatch, capsys, fake_server):
    monkeypatch.setenv("EVALKIT_BASE_URL", fake_server.url)
    monkeypatch.setenv("EVALKIT_JUDGE_BASE_URL", fake_server.url)
    assert main(["run", str(EXAMPLES / "docs-quality.yaml"), "-q", "--no-save", "-n", "1", "--format", "json"]) == 0
    result = json.loads(capsys.readouterr().out)
    prov = result["summary"]["providers"]["llm"]
    # fake judge passes any answer containing "seconds": only parse-duration reaches the judge and
    # passes the cheap grader; the other two fail their cheap graders or the judge.
    assert prov["tokens_in"] is not None and prov["runs"] == 3
    by_case = {c: v["passed"] for c, v in prov["cases"].items()}
    assert by_case["parse-duration"] == 1


def test_dry_run_calls_nothing(capsys, fake_server, monkeypatch):
    monkeypatch.setenv("EVALKIT_BASE_URL", fake_server.url)
    assert main(["run", str(EXAMPLES / "docs-quality.yaml"), "--dry-run"]) == 0
    assert "runs: 9" in capsys.readouterr().out and not fake_server.requests


def test_report_and_list(capsys, isolated_home, tmp_path):
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1"]) == 0
    capsys.readouterr()
    assert main(["report"]) == 0
    assert "# Eval: offline-demo" in capsys.readouterr().out
    assert main(["report", "offline-demo", "--format", "json"]) == 0
    assert json.loads(capsys.readouterr().out)["summary"]["runs"] == 8
    assert main(["list", "--results"]) == 0
    assert "offline-demo" in capsys.readouterr().out
    assert main(["list", str(EXAMPLES)]) == 0
    listing = capsys.readouterr().out
    assert "offline-demo" in listing and "invoice-extraction" in listing and "docstring-quality" in listing
    assert main(["report", "unknown-suite"]) == 2


def test_out_and_md_files(tmp_path, capsys):
    out, md = tmp_path / "r.json", tmp_path / "r.md"
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1", "--out", str(out), "--md", str(md), "--no-save"]) == 0
    assert json.loads(out.read_text())["runs"] and md.read_text().startswith("# Eval:")


def test_errors_exit_2(capsys, write_suite):
    assert main(["run", "/nonexistent.yaml"]) == 2
    assert "cannot read" in capsys.readouterr().err
    bad = write_suite("name: x\nproviders: []\ncases: []\n")
    assert main(["run", str(bad)]) == 2
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-p", "nope"]) == 2
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-j", "0"]) == 2


def test_filters(capsys):
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "--no-save", "-p", "echo-stdin", "-c", "exact-echo", "-n", "1"]) == 0
    out = capsys.readouterr().out
    assert "| exact-echo | 1/1 |" in out and "printf-arg" not in out and "repeat-back" not in out


def _fake_brain(tmp_path, monkeypatch, exit_code=0):
    log = tmp_path / "brain.log"
    script = tmp_path / "bin" / "brain"
    script.parent.mkdir()
    script.write_text(f'#!/bin/sh\necho "$@" > {log}\ncat >> {log}\necho created reference/x.md\nexit {exit_code}\n')
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{script.parent}{os.pathsep}/usr/bin:/bin")
    return log


def test_brain_flag_calls_brain_new_reference(tmp_path, monkeypatch, capsys):
    log = _fake_brain(tmp_path, monkeypatch)
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1", "--no-save", "--brain", "--brain-project", "evals"]) == 0
    assert "saved to brain" in capsys.readouterr().err
    first, *rest = log.read_text().splitlines()
    assert first.startswith("new reference Eval offline-demo ") and first.endswith("--body - --project evals")
    assert "# Eval: offline-demo" in "\n".join(rest)


def test_brain_missing_or_failing_does_not_fail_run(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("PATH", "/usr/bin:/bin")
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1", "--no-save", "--brain"]) == 0
    assert "brain CLI not found" in capsys.readouterr().err
    _fake_brain(tmp_path, monkeypatch, exit_code=1)
    assert main(["run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1", "--no-save", "--brain"]) == 0
    assert "brain call failed" in capsys.readouterr().err


def test_module_entrypoint_runs_offline(tmp_path):
    env = {**os.environ, "EVALKIT_HOME": str(tmp_path / "h")}
    res = subprocess.run(
        [sys.executable, "-m", "evalkit.cli", "run", str(EXAMPLES / "offline.yaml"), "-q", "-n", "1"],
        capture_output=True, text=True, env=env, timeout=60,
    )
    assert res.returncode == 0 and "100%" in res.stdout
