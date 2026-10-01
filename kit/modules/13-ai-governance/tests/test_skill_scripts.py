"""Tests for the governance skills' scripts (portfolio.py, inventory.py) on a fake brain."""

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

import pytest

SKILLS = Path(__file__).resolve().parents[2] / "30-agent-setup" / "source" / "skills"
PORTFOLIO = SKILLS / "ai-use-case-intake" / "scripts" / "portfolio.py"
INVENTORY = SKILLS / "ai-inventory" / "scripts" / "inventory.py"
pytestmark = pytest.mark.skipif(not PORTFOLIO.exists(), reason="30-agent-setup skills not present")

TODAY = dt.date.today()
PAST = (TODAY - dt.timedelta(days=200)).isoformat()
FUTURE = (TODAY + dt.timedelta(days=30)).isoformat()


def note(home: Path, rel: str, title: str, tags, body: str):
    p = home / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    tag_text = "[" + ", ".join(tags) + "]" if isinstance(tags, list) else tags
    p.write_text(f"---\ntitle: {title}\ntype: note\ntags: {tag_text}\ncreated: '{TODAY}'\n---\n\n{body}",
                 encoding="utf-8")


def run(script, brain, *args):
    res = subprocess.run([sys.executable, str(script), "--brain", str(brain), "--json", *args],
                         capture_output=True, text=True)
    assert res.returncode == 0, res.stderr
    return {r.get("title") or r.get("system"): r for r in json.loads(res.stdout)}


def test_portfolio(tmp_path):
    form = (SKILLS / "ai-use-case-intake" / "references" / "intake-form.md").read_text()
    note(tmp_path, "inbox/new.md", "Use case: New idea", ["ai-use-case"], form)
    note(tmp_path, "inbox/pilot.md", "Use case: Test drafting", ["ai-use-case", "x"],
         "## Record\n\n- stage: intake\n- owner: A\n\n## Gate x: G1\n\n- stage: pilot\n"
         f"- stage_since: {PAST}\n- value: 4 (saves time)\n- feasibility: 3\n- risk: 2\n- reusability: 1\n"
         f"- next_gate: {PAST}\n")
    note(tmp_path, "inbox/good.md", "Use case: Log summaries", "\n  - ai-use-case",
         "- stage: production\n- composite: 3.8\n- baseline: 20 items; 12 min\n- kill_criteria: <50% accepted\n"
         f"- next_gate: {FUTURE}\n")
    note(tmp_path, "inbox/other.md", "Unrelated", ["misc"], "- stage: pilot\n")
    (tmp_path / ".git").mkdir()
    note(tmp_path, ".git/ignored.md", "Use case: hidden", ["ai-use-case"], "- stage: pilot\n")
    rows = run(PORTFOLIO, tmp_path)
    assert set(rows) == {"New idea", "Test drafting", "Log summaries"}
    assert rows["New idea"]["stage"] == "intake" and rows["New idea"]["flags"] == []
    pilot = rows["Test drafting"]
    assert pilot["stage"] == "pilot" and pilot["composite"] == 2.5
    flags = " ".join(pilot["flags"])
    for part in ("gate overdue", "no baseline", "no kill criteria", "pilot > 12 weeks"):
        assert part in flags
    assert rows["Log summaries"]["flags"] == []
    table = subprocess.run([sys.executable, str(PORTFOLIO), "--brain", str(tmp_path)],
                           capture_output=True, text=True).stdout
    assert table.startswith("| Use case |") and "flagged: 1" in table


def test_inventory(tmp_path):
    tmpl = (SKILLS / "ai-inventory" / "references" / "ai-system-record.md").read_text()
    note(tmp_path, "reference/empty.md", "AI system: Empty", ["ai-system"], tmpl)
    note(tmp_path, "reference/ok.md", "AI system: Local coder", ["ai-system"],
         "## Record\n\n- system: Local coder\n- status: approved\n- owner: A\n- data_class: INTERNAL\n"
         f"- eu_ai_act_role: deployer\n- risk_tier: minimal\n- approved_by: IT\n- review_by: {FUTURE}\n"
         "\n## Change x\n\n- status: production\n")
    note(tmp_path, "reference/bad.md", "AI system: Screener", ["ai-system"],
         "- status: pilot\n- risk_tier: high\n- approved_by: TODO(ask IT)\n"
         f"- review_by: {PAST}\n- data_class: secret\n")
    note(tmp_path, "reference/old.md", "AI system: Old", ["ai-system"], "- status: retired\n")
    rows = run(INVENTORY, tmp_path)
    assert rows["Local coder"]["status"] == "production" and rows["Local coder"]["flags"] == []
    bad = " ".join(rows["Screener"]["flags"])
    for part in ("review overdue", "no owner", "high-risk", "without recorded approval", "data class not one of"):
        assert part in bad
    assert "no review date" in " ".join(rows["Empty"]["flags"])
    assert rows["Old"]["flags"] == []
    assert list(run(INVENTORY, tmp_path, "--status", "retired")) == ["Old"]


def test_missing_brain(tmp_path):
    res = subprocess.run([sys.executable, str(INVENTORY), "--brain", str(tmp_path / "nope")],
                         capture_output=True, text=True)
    assert res.returncode == 2 and "no brain" in res.stderr
