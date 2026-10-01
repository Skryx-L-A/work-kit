import time
from pathlib import Path

import pytest

from evalkit.providers import OpenAIProvider, ProviderError, ShellProvider, build_provider, expand_env
from fake_server import FakeServer


def test_shell_stdin_mode_is_auto_without_placeholder():
    r = ShellProvider("s", "cat").complete("héllo\nworld", 5)
    assert r.error is None and r.text == "héllo\nworld" and r.latency >= 0


def test_shell_arg_mode_quotes_dangerous_input():
    nasty = "it's $(touch pwned) `id` \"x\""
    r = ShellProvider("s", "printf %s {input}", cwd=Path.cwd()).complete(nasty, 5)
    assert r.text == nasty and r.error is None
    assert not Path("pwned").exists()


def test_shell_explicit_input_mode_and_python_placeholder():
    r = ShellProvider("s", "{python} -c 'import sys; print(sys.stdin.read().upper())'", "stdin").complete("abc", 5)
    assert r.text.strip() == "ABC"


def test_shell_braces_not_touched():
    r = ShellProvider("s", "awk '{print $1}'").complete("first second", 5)
    assert r.text.strip() == "first"


def test_shell_nonzero_exit_and_timeout():
    r = ShellProvider("s", "echo out; echo bad >&2; exit 3").complete("", 5)
    assert r.error == "exit code 3: bad" and r.text.strip() == "out"
    t0 = time.monotonic()
    r = ShellProvider("s", "sleep 30").complete("", 0.3)
    assert "timeout" in r.error and time.monotonic() - t0 < 5


def test_shell_timeout_kills_children(tmp_path):
    marker = tmp_path / "alive"
    ShellProvider("s", f"(sleep 1; touch {marker}) & sleep 30").complete("", 0.3)
    time.sleep(1.5)
    assert not marker.exists()


def test_openai_success_usage_and_cost(fake_server, monkeypatch):
    monkeypatch.setenv("MY_KEY", "test-key-not-real")
    p = OpenAIProvider("o", fake_server.url, "m1", api_key_env="MY_KEY", system="be brief",
                       temperature=0, price_in_per_1m=1.0, price_out_per_1m=2.0)
    r = p.complete("hi", 5)
    assert r.error is None and r.text
    assert (r.tokens_in, r.tokens_out) == (100, 10)
    assert r.cost == pytest.approx((100 * 1.0 + 10 * 2.0) / 1e6)
    body, headers = fake_server.requests[0]
    assert headers["authorization"] == "Bearer test-key-not-real"
    assert body["model"] == "m1" and body["temperature"] == 0
    assert body["messages"][0] == {"role": "system", "content": "be brief"}
    assert body["messages"][1] == {"role": "user", "content": "hi"}


def test_openai_no_price_means_no_cost_and_reported_cost_wins(fake_server):
    assert OpenAIProvider("o", fake_server.url, "m").complete("x", 5).cost is None

    def h(body, headers):
        return 200, {"choices": [{"message": {"content": "ok"}}], "usage": {"cost": 0.5}}

    with FakeServer(h) as srv:
        r = OpenAIProvider("o", srv.url, "m", price_in_per_1m=1, price_out_per_1m=1).complete("x", 5)
    assert r.cost == 0.5 and r.tokens_in is None


def test_openai_missing_key_env_is_reported_without_request(fake_server, monkeypatch):
    monkeypatch.delenv("NOPE_KEY", raising=False)
    r = OpenAIProvider("o", fake_server.url, "m", api_key_env="NOPE_KEY").complete("x", 5)
    assert "NOPE_KEY" in r.error and not fake_server.requests


def test_openai_retries_5xx_then_succeeds(monkeypatch):
    monkeypatch.setattr(time, "sleep", lambda s: None)
    calls = []

    def h(body, headers):
        calls.append(1)
        if len(calls) < 3:
            return 503, {"error": "busy"}
        return 200, {"choices": [{"message": {"content": "finally"}}]}

    with FakeServer(h) as srv:
        r = OpenAIProvider("o", srv.url, "m", retries=2).complete("x", 5)
    assert r.text == "finally" and len(calls) == 3


def test_openai_4xx_no_retry_and_connection_error():
    with FakeServer(lambda b, h: (401, {"error": "no"})) as srv:
        r = OpenAIProvider("o", srv.url, "m").complete("x", 5)
        assert "HTTP 401" in r.error and len(srv.requests) == 1
    r = OpenAIProvider("o", "http://127.0.0.1:9/v1", "m", retries=0).complete("x", 2)
    assert r.error and r.error.startswith("request failed")


def test_env_expansion(monkeypatch):
    monkeypatch.setenv("A_URL", "http://x/v1")
    monkeypatch.delenv("A_MODEL", raising=False)
    assert expand_env("${A_URL}", "t") == "http://x/v1"
    assert expand_env("${A_MODEL:-fallback}", "t") == "fallback"
    with pytest.raises(ProviderError, match="A_MODEL"):
        expand_env("${A_MODEL}", "t")
    p = build_provider({"id": "o", "type": "openai", "base_url": "${A_URL}", "model": "${A_MODEL:-m}"}, Path("."), "t")
    p.prepare()
    assert (p.base_url, p.model) == ("http://x/v1", "m")


@pytest.mark.parametrize(
    "spec,match",
    [
        ({"id": "o", "type": "openai", "base_url": "u", "model": "m", "api_key": "not-a-real-key"}, "literal API keys"),
        ({"id": "o", "type": "openai", "base_url": "u", "model": "m", "api_key_env": "lowercase-key-like"}, "NAME of an environment"),
        ({"id": "o", "type": "openai", "base_url": "u"}, "needs 'model'"),
        ({"id": "s", "type": "shell"}, "needs 'command'"),
        ({"id": "s", "type": "shell", "command": "x", "input_mode": "pipe"}, "input_mode"),
        ({"id": "x", "type": "grpc"}, "type must be"),
        ({"type": "shell", "command": "x"}, "needs a string 'id'"),
    ],
)
def test_build_provider_rejects_bad_specs(spec, match):
    with pytest.raises(ProviderError, match=match):
        build_provider(spec, Path("."), "t")
