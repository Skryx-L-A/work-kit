import datetime as dt
import json
import subprocess

import pytest

from conftest import git
from kitbrain import cli, notes, worklog


@pytest.mark.parametrize("raw,hours", [("2", 2), ("1,5", 1.5), ("90m", 1.5), ("1:30", 1.5),
                                       ("0.25h", 0.25), (None, None), ("-", None)])
def test_parse_hours(raw, hours):
    assert worklog.parse_hours(raw) == hours


@pytest.mark.parametrize("raw", ["abc", "0", "25"])
def test_parse_hours_rejects(raw):
    with pytest.raises(notes.NoteError):
        worklog.parse_hours(raw)


def test_parse_week():
    today = dt.date(2026, 9, 25)
    assert worklog.parse_week(None, today) == (2026, 39)
    assert worklog.parse_week("2026-W39", today) == (2026, 39)
    assert worklog.parse_week("W1", today) == (2026, 1)
    assert worklog.parse_week("40", today) == (2026, 40)
    with pytest.raises(notes.NoteError):
        worklog.parse_week("2026-W54", today)


def test_log_and_week(env, tmp_path, capsys, monkeypatch):
    work = tmp_path / "work"
    repo = work / "proto"
    repo.mkdir(parents=True)
    git(repo, "init", "-q")
    (repo / "a.txt").write_text("x")
    git(repo, "add", "a.txt")
    subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "Add prototype"], check=True,
                   env={**__import__("os").environ, "GIT_AUTHOR_DATE": "2026-09-23T10:00:00",
                        "GIT_COMMITTER_DATE": "2026-09-23T10:00:00"})
    monkeypatch.setenv("BRAIN_WORK_DIR", str(work))

    assert cli.main(["log", "Characterization tests", "--hours", "6", "--project", "Billing",
                     "--date", "2026-09-21"]) == 0
    out = capsys.readouterr().out
    assert "logged (6 h) in worklog/2026-W39.md" in out and "6 of 20 h" in out
    assert git(env, "log", "-1", "--pretty=%s").strip() == "brain: log 6 h billing"
    cli.main(["log", "Workshop prep", "--hours", "12,5", "--date", "2026-09-22"])
    cap = capsys.readouterr()
    assert "close to the 20 h limit" in cap.err
    cli.main(["log", "Reading only", "--date", "2026-09-22"])
    capsys.readouterr()
    text = (env / "worklog" / "2026-W39.md").read_text()
    assert "- 2026-09-21 | 6 h | billing | Characterization tests" in text

    assert cli.main(["week", "--iso-week", "2026-W39", "--json"]) == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["hours"] == 18.5 and rep["status"] == "near" and rep["remaining"] == 1.5
    assert rep["per_project"] == {"billing": 6, "(none)": 12.5}
    assert rep["git"][0]["repo"] == "proto" and rep["git"][0]["commits"] == 1
    assert rep["git_days_without_hours"] == ["2026-09-23"]

    cli.main(["log", "More", "--hours", "3", "--date", "2026-09-24"])
    capsys.readouterr()
    cli.main(["week", "--iso-week", "39", "--save"])
    cap = capsys.readouterr()
    assert "Hours: 21.5 of 20 h (OVER THE LIMIT" in cap.out
    assert "Add prototype" in cap.out and "saved worklog/2026-W39-report.md" in cap.err
    assert git(env, "status", "--porcelain") == ""

    monkeypatch.setenv("BRAIN_WEEK_LIMIT", "40")
    cli.main(["week", "--iso-week", "2026-W39", "--json"])
    assert json.loads(capsys.readouterr().out)["status"] == "ok"


def test_week_without_entries(env, capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("BRAIN_WORK_DIR", str(tmp_path / "nothing"))
    assert cli.main(["week", "--iso-week", "2026-W01"]) == 0
    assert "Hours: 0 of 20 h" in capsys.readouterr().out
