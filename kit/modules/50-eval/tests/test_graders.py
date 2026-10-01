from pathlib import Path

import pytest

from evalkit import graders
from evalkit.graders import Context, GraderConfigError
from evalkit.providers import ShellProvider


def run(spec, output, inp="", judges=None):
    spec = graders.normalise(spec, "t", Path("."), list((judges or {}).keys()))
    return graders.grade(spec, Context(output, inp, Path.cwd(), 10, judges or {}))


def test_exact():
    assert run({"type": "exact", "value": "42"}, " 42\n").passed
    assert not run({"type": "exact", "value": "42", "strip": False}, "42\n").passed
    assert run({"type": "exact", "value": "Yes", "ignore_case": True}, "yes").passed
    assert "expected" in run({"type": "exact", "value": "a"}, "b").reason


def test_contains_all_any_and_case():
    spec = {"type": "contains", "value": ["foo", "bar"]}
    assert run(spec, "foo bar").passed
    assert not run(spec, "foo").passed
    assert run({**spec, "mode": "any"}, "only bar").passed
    assert run({"type": "contains", "value": "FOO", "ignore_case": True}, "a foo").passed
    assert run({"type": "contains", "value": "x"}, "abc").passed is False


def test_regex_flags_and_bad_pattern():
    assert run({"type": "regex", "pattern": r"^\d+$", "flags": "m"}, "a\n12\nb").passed
    assert not run({"type": "regex", "pattern": "abc"}, "xyz").passed
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "regex", "pattern": "("}, "t", Path("."), [])
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "regex", "pattern": "a", "flags": "z"}, "t", Path("."), [])


def test_json_schema_extracts_from_fences_and_prose():
    spec = {"type": "json-schema", "schema": {"type": "object", "required": ["a"]}}
    assert run(spec, '{"a": 1}').passed
    assert run(spec, 'Here you go:\n```json\n{"a": 1}\n```\nDone').passed
    assert run(spec, 'Sure! {"a": 1} is the answer').passed
    assert not run(spec, '{"b": 1}').passed
    assert "no JSON" in run(spec, "nothing").reason


def test_json_schema_file(tmp_path):
    (tmp_path / "s.json").write_text('{"type": "array"}')
    spec = graders.normalise({"type": "json-schema", "schema_file": "s.json"}, "t", tmp_path, [])
    assert graders.grade(spec, Context("[1]", "", tmp_path, 5, {})).passed
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "json-schema", "schema_file": "missing.json"}, "t", tmp_path, [])


def test_numeric_tolerances_and_pick():
    assert run({"type": "numeric", "expected": 3.14, "tolerance": 0.01}, "3.141").passed
    assert not run({"type": "numeric", "expected": 3.14, "tolerance": 0.001}, "3.15").passed
    assert run({"type": "numeric", "expected": 100, "rel_tolerance": 0.05}, "104").passed
    assert run({"type": "numeric", "expected": 1234.5}, "1,234.5").passed
    assert not run({"type": "numeric", "expected": 5}, "the answer is 5").passed  # whole by default
    assert run({"type": "numeric", "expected": 5, "pick": "last"}, "we had 3, then 5").passed
    assert run({"type": "numeric", "expected": 3, "pick": "first"}, "we had 3, then 5").passed
    assert "no number" in run({"type": "numeric", "expected": 1}, "none").reason


def test_script_exit_code_and_message(tmp_path):
    assert run({"type": "script", "command": "grep -q ok"}, "all ok").passed
    bad = run({"type": "script", "command": "echo nope; exit 3"}, "x")
    assert not bad.passed and bad.reason == "nope"
    env = run({"type": "script", "command": 'test "$(cat "$EVALKIT_INPUT_FILE")" = question'}, "a", inp="question")
    assert env.passed
    slow = graders.normalise({"type": "script", "command": "sleep 5"}, "t", Path("."), [])
    assert "timed out" in graders.grade(slow, Context("", "", Path.cwd(), 0.3, {})).reason


def test_negate():
    assert run({"type": "contains", "value": "bad", "negate": True}, "good").passed
    assert not run({"type": "contains", "value": "bad", "negate": True}, "bad").passed


def test_unknown_type_and_missing_field():
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "nope"}, "t", Path("."), [])
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "exact"}, "t", Path("."), [])
    with pytest.raises(GraderConfigError):
        graders.normalise({"type": "llm-judge", "rubric": "x"}, "t", Path("."), [])


def test_llm_judge_with_shell_provider():
    verdict = ShellProvider("j", """printf '{"verdict": "pass", "reason": "fine"}'""", "stdin")
    g = run({"type": "llm-judge", "rubric": "be nice"}, "text", "task", {"j": verdict})
    assert g.passed and g.reason == "fine" and g.judge is not None
    fail = ShellProvider("j", """printf 'not json'""", "stdin")
    g = run({"type": "llm-judge", "rubric": "r"}, "text", "task", {"j": fail})
    assert not g.passed and "not parseable" in g.reason
    boom = ShellProvider("j", "exit 4", "stdin")
    g = run({"type": "llm-judge", "rubric": "r"}, "text", "task", {"j": boom})
    assert not g.passed and "judge j failed" in g.reason


def test_judge_prompt_contains_rubric_task_and_response():
    seen = ShellProvider("j", "cat > judge_prompt.txt; printf '{\"verdict\":\"pass\"}'", "stdin", Path.cwd())
    import os
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        seen.cwd = Path(tmp)
        run({"type": "llm-judge", "rubric": "RUBRIC-X"}, "RESP-Y", "TASK-Z", {"j": seen})
        text = (Path(tmp) / "judge_prompt.txt").read_text()
    assert "RUBRIC-X" in text and "RESP-Y" in text and "TASK-Z" in text
