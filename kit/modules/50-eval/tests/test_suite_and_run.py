import json
import os
import stat
import textwrap
from pathlib import Path

import pytest

from evalkit import runner
from evalkit.report import summarize, to_markdown
from evalkit.suite import SuiteError, load_suite

SIMPLE = textwrap.dedent(
    """\
    name: t
    repetitions: 2
    providers:
      - {id: cat, type: shell, command: cat}
      - {id: spare, type: shell, command: cat, default: false}
    cases:
      - id: a
        input: hello
        graders: [{type: contains, value: hello}]
      - id: b
        input: hello
        graders: [{type: exact, value: nope}]
    """
)


def test_load_and_defaults(write_suite):
    s = load_suite(write_suite(SIMPLE))
    assert s.name == "t" and s.repetitions == 2 and s.timeout == 60
    assert [c.id for c in s.cases] == ["a", "b"]
    assert len(s.sha256) == 64


@pytest.mark.parametrize(
    "mutation,match",
    [
        (lambda t: t.replace("cases:", "kases:"), "unknown top-level"),
        (lambda t: t.replace("repetitions: 2", "repetitions: 0"), "positive integer"),
        (lambda t: t.replace("id: b", "id: a"), "duplicate case id"),
        (lambda t: t.replace("{type: exact, value: nope}", "{type: wat}"), "unknown grader type"),
        (lambda t: t.replace("input: hello\n    graders: [{type: exact", "graders: [{type: exact"), "exactly one of"),
        (lambda t: t.replace("[{type: contains, value: hello}]", "[]"), "non-empty list"),
        (lambda t: t.replace("{id: cat, type: shell, command: cat}", "{id: cat, type: shell, command: cat}\n  - {id: cat, type: shell, command: cat}"), "duplicate provider"),
        (lambda t: "- just a list", "top level must be a mapping"),
        (lambda t: "a: [unclosed", "invalid YAML"),
    ],
)
def test_invalid_suites(write_suite, mutation, match):
    with pytest.raises(SuiteError, match=match):
        load_suite(write_suite(mutation(SIMPLE)))


def test_missing_file_and_input_file(write_suite, tmp_path):
    with pytest.raises(SuiteError, match="cannot read"):
        load_suite(tmp_path / "nope.yaml")
    (tmp_path / "in.txt").write_text("from file")
    text = SIMPLE.replace("input: hello\n    graders: [{type: contains, value: hello}]",
                          "input_file: in.txt\n    graders: [{type: contains, value: file}]")
    s = load_suite(write_suite(text))
    assert s.cases[0].input == "from file"
    with pytest.raises(SuiteError, match="cannot read input_file"):
        load_suite(write_suite(text.replace("in.txt", "missing.txt")))


def test_prompt_needs_placeholder(write_suite):
    with pytest.raises(SuiteError, match="must contain"):
        load_suite(write_suite(SIMPLE + "prompt: no placeholder\n"))


def test_llm_judge_needs_judges(write_suite):
    text = SIMPLE.replace("{type: exact, value: nope}", "{type: llm-judge, rubric: r}")
    with pytest.raises(SuiteError, match="judges"):
        load_suite(write_suite(text))


def test_run_repetitions_pass_rate_and_default_filter(write_suite):
    s = load_suite(write_suite(SIMPLE))
    provs = runner.select_providers(s, None)
    assert [p.id for p in provs] == ["cat"]
    result = runner.run_suite(s, provs, s.cases, 3)
    assert len(result["runs"]) == 6
    summ = summarize(result)
    assert summ["pass_rate"] == 0.5
    assert summ["providers"]["cat"]["cases"] == {"a": {"runs": 3, "passed": 3}, "b": {"runs": 3, "passed": 0}}
    assert [p.id for p in runner.select_providers(s, ["spare"])] == ["spare"]
    with pytest.raises(runner.RunError, match="unknown provider"):
        runner.select_providers(s, ["zzz"])
    with pytest.raises(runner.RunError, match="unknown case"):
        runner.select_cases(s, ["zzz"])


def test_parallel_jobs_keep_order(write_suite):
    s = load_suite(write_suite(SIMPLE))
    provs = runner.select_providers(s, None)
    seq = runner.run_suite(s, provs, s.cases, 4, jobs=1)["runs"]
    par = runner.run_suite(s, provs, s.cases, 4, jobs=4)["runs"]
    key = lambda r: (r["provider"], r["case"], r["rep"], r["passed"])
    assert [key(r) for r in seq] == [key(r) for r in par]


def test_provider_error_fails_run_and_skips_graders(write_suite):
    text = SIMPLE.replace("command: cat}\n  - {id: spare", "command: 'exit 2'}\n  - {id: spare")
    s = load_suite(write_suite(text))
    result = runner.run_suite(s, runner.select_providers(s, None), s.cases[:1], 1)
    r = result["runs"][0]
    assert not r["passed"] and r["error"].startswith("exit code 2") and r["graders"] == []
    assert summarize(result)["providers"]["cat"]["errors"] == 1


def test_prompt_template_applied(write_suite):
    text = SIMPLE.replace("cases:", "prompt: 'Q: {input}'\ncases:", 1).replace(
        "[{type: contains, value: hello}]", "[{type: exact, value: 'Q: hello'}]")
    s = load_suite(write_suite(text))
    result = runner.run_suite(s, runner.select_providers(s, None), s.cases[:1], 1)
    assert result["runs"][0]["passed"]


def test_judge_flow_with_http_provider_reports_tokens_cost_and_skips_judge_on_cheap_failure(write_suite, fake_server):
    text = textwrap.dedent(
        f"""\
        name: j
        providers:
          - id: llm
            type: openai
            base_url: {fake_server.url}
            model: m
            price: {{input_per_1m: 1000000, output_per_1m: 1000000}}
        judges:
          - id: judge
            type: openai
            base_url: {fake_server.url}
            model: jm
            price: {{input_per_1m: 1000000, output_per_1m: 1000000}}
        cases:
          - id: ok
            input: q
            graders:
              - {{type: llm-judge, rubric: mentions seconds}}
              - {{type: contains, value: Returns}}
          - id: cheap-fails
            input: q
            graders:
              - {{type: contains, value: MISSING}}
              - {{type: llm-judge, rubric: r}}
        """
    )
    s = load_suite(write_suite(text))
    result = runner.run_suite(s, runner.select_providers(s, None), s.cases, 1)
    ok, cheap = result["runs"]
    assert ok["passed"] and ok["tokens_in"] == 100 and ok["tokens_out"] == 10
    assert ok["cost"] == pytest.approx(110.0) and ok["judge"]["cost"] == pytest.approx(110.0)
    assert not cheap["passed"] and "judge" not in cheap
    assert cheap["graders"][1]["reason"].startswith("skipped")
    assert len(fake_server.requests) == 3  # candidate x2 + one judge call
    md = to_markdown({**result, "summary": summarize(result)})
    assert "Judge cost" in md and "110.0000" in md


def test_markdown_and_failure_section(write_suite):
    s = load_suite(write_suite(SIMPLE))
    result = runner.run_suite(s, runner.select_providers(s, None), s.cases, 2)
    md = to_markdown(result)
    assert "| cat | 50% | 2/4 |" in md
    assert "| a | 2/2 |" in md and "| b | 0/2 |" in md
    assert "## Failures" in md and "`cat` / `b`" in md and md.count("`cat` / `b`") == 1
    json.dumps(result)  # serialisable
