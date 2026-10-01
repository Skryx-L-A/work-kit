"""Tests for llm_usage.py with a fake OpenAI-compatible upstream. Run: python3 -m pytest tests/"""

from __future__ import annotations

import http.server
import json
import subprocess
import sys
import threading
import urllib.request
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import llm_usage as lu  # noqa: E402


class FakeUpstream(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    seen: list[dict] = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        data = json.dumps({"data": [{"id": "fake-model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeUpstream.seen.append({"path": self.path, "auth": self.headers.get("Authorization"), "body": body})
        if body.get("model") == "boom":
            data = b'{"error": {"message": "fail"}}'
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            chunks = [
                {"id": "c1", "model": "fake-model", "choices": [{"delta": {"content": "Hal"}}]},
                {"id": "c1", "model": "fake-model", "choices": [{"delta": {"content": "lo"}, "finish_reason": "stop"}]},
                {"id": "c1", "model": "fake-model", "choices": [], "usage": {"prompt_tokens": 7, "completion_tokens": 2}},
            ]
            for c in chunks:
                line = f"data: {json.dumps(c)}\n\n".encode()
                self.wfile.write(f"{len(line):x}\r\n".encode() + line + b"\r\n")
            end = b"data: [DONE]\n\n"
            self.wfile.write(f"{len(end):x}\r\n".encode() + end + b"\r\n0\r\n\r\n")
            return
        data = json.dumps({
            "id": "chatcmpl-1", "model": "fake-model",
            "choices": [{"message": {"role": "assistant", "content": "Hallo Welt"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 11, "completion_tokens": 3,
                      "prompt_tokens_details": {"cached_tokens": 4}},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@pytest.fixture()
def upstream():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstream)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    FakeUpstream.seen = []
    yield f"http://127.0.0.1:{srv.server_address[1]}/v1"
    srv.shutdown()
    srv.server_close()


def start_proxy(upstream: str, folder: Path, **kw):
    cfg = lu.ProxyConfig(upstream, kw.get("provider", "llama.cpp"), kw.get("capture", False), kw.get("tag"),
                         folder, kw.get("prices", {}), 10.0, kw.get("free", False))
    srv = lu.make_proxy(cfg, "127.0.0.1", 0)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}/v1"


def post(url: str, body: dict, headers: dict | None = None):
    req = urllib.request.Request(url + "/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", **(headers or {})})
    return urllib.request.urlopen(req, timeout=10)


def records(folder: Path) -> list[dict]:
    return list(lu.read_records(folder))


def test_non_stream_call_is_recorded_with_genai_attributes(upstream, tmp_path):
    srv, url = start_proxy(upstream, tmp_path, tag="exp1")
    try:
        with post(url, {"model": "fake-model", "messages": [{"role": "user", "content": "Hi"}],
                        "temperature": 0.2, "max_tokens": 50}, {"Authorization": "Bearer sk-test"}) as r:
            data = json.load(r)
        assert data["choices"][0]["message"]["content"] == "Hallo Welt"
    finally:
        srv.shutdown(); srv.server_close()
    assert FakeUpstream.seen[0]["path"] == "/v1/chat/completions"
    assert FakeUpstream.seen[0]["auth"] == "Bearer sk-test"  # passed through
    [rec] = records(tmp_path)
    a = rec["attributes"]
    assert rec["name"] == "chat fake-model" and rec["status"] == "OK" and rec["kind"] == "CLIENT"
    assert a["gen_ai.operation.name"] == "chat"
    assert a["gen_ai.provider.name"] == "llama.cpp"
    assert a["gen_ai.request.model"] == "fake-model"
    assert a["gen_ai.response.id"] == "chatcmpl-1"
    assert a["gen_ai.usage.input_tokens"] == 11 and a["gen_ai.usage.output_tokens"] == 3
    assert a["gen_ai.usage.cache_read.input_tokens"] == 4
    assert a["gen_ai.response.finish_reasons"] == ["stop"]
    assert a["gen_ai.request.temperature"] == 0.2 and a["gen_ai.request.max_tokens"] == 50
    assert a["kit.tag"] == "exp1"
    assert a["kit.cost_usd"] is None if "kit.cost_usd" in a else True
    raw = (tmp_path / f"usage-{rec['start_time'][:7]}.jsonl").read_text()
    assert "sk-test" not in raw and "Hallo Welt" not in raw and '"Hi"' not in raw


def test_stream_is_relayed_and_usage_taken_from_last_chunk(upstream, tmp_path):
    srv, url = start_proxy(upstream, tmp_path, capture=True, free=True)
    try:
        with post(url, {"model": "fake-model", "stream": True,
                        "messages": [{"role": "user", "content": "Hi"}]}) as r:
            body = r.read().decode()
    finally:
        srv.shutdown(); srv.server_close()
    assert "Hal" in body and "[DONE]" in body
    [rec] = records(tmp_path)
    a = rec["attributes"]
    assert a["gen_ai.request.stream"] is True
    assert a["gen_ai.usage.input_tokens"] == 7 and a["gen_ai.usage.output_tokens"] == 2
    assert a["gen_ai.response.time_to_first_chunk"] >= 0
    assert a["gen_ai.output.messages"] == [{"role": "assistant", "content": "Hallo"}]
    assert a["gen_ai.input.messages"][0]["content"] == "Hi"
    assert a["kit.cost_usd"] == 0.0


def test_upstream_error_and_unreachable_are_errors(upstream, tmp_path):
    srv, url = start_proxy(upstream, tmp_path)
    try:
        with pytest.raises(urllib.error.HTTPError) as e:
            post(url, {"model": "boom", "messages": []})
        assert e.value.code == 500
    finally:
        srv.shutdown(); srv.server_close()
    srv2, url2 = start_proxy("http://127.0.0.1:9/v1", tmp_path)
    try:
        with pytest.raises(urllib.error.HTTPError) as e:
            post(url2, {"model": "x", "messages": []})
        assert e.value.code == 502
    finally:
        srv2.shutdown(); srv2.server_close()
    recs = records(tmp_path)
    assert [r["status"] for r in recs] == ["ERROR", "ERROR"]
    assert recs[0]["attributes"]["error.type"] == "500"
    assert recs[1]["attributes"]["error.type"] == "upstream_unreachable"


def test_get_models_passes_through_without_record(upstream, tmp_path):
    srv, url = start_proxy(upstream, tmp_path)
    try:
        with urllib.request.urlopen(url + "/models", timeout=5) as r:
            assert json.load(r)["data"][0]["id"] == "fake-model"
    finally:
        srv.shutdown(); srv.server_close()
    assert records(tmp_path) == []


def test_prices_and_cost(tmp_path, upstream):
    prices_file = tmp_path / "p.toml"
    prices_file.write_text('[models."fake-model"]\ninput_per_1m = 1.0\noutput_per_1m = 2.0\n')
    prices = lu.load_prices(prices_file)
    assert lu.compute_cost("fake-model", 1_000_000, 500_000, prices) == 2.0
    assert lu.compute_cost("other", 1, 1, prices) is None
    srv, url = start_proxy(upstream, tmp_path / "log", prices=prices)
    try:
        post(url, {"model": "fake-model", "messages": []}).read()
    finally:
        srv.shutdown(); srv.server_close()
    [rec] = records(tmp_path / "log")
    assert rec["attributes"]["kit.cost_usd"] == pytest.approx((11 * 1.0 + 3 * 2.0) / 1e6)


def _rec(model, start, dur, tin, tout, status="OK", cost=None, provider="llama.cpp"):
    import datetime as dt
    t = dt.datetime.fromisoformat(start).timestamp()
    attrs = {"gen_ai.usage.input_tokens": tin, "gen_ai.usage.output_tokens": tout, "kit.cost_usd": cost}
    return lu.new_record("chat", provider, model, t, t + dur, attrs, None if status == "OK" else "500")


def test_summary_groups_and_since(tmp_path):
    for r in [_rec("a", "2026-09-01T10:00:00+00:00", 2.0, 10, 20, cost=0.1),
              _rec("a", "2026-09-02T10:00:00+00:00", 4.0, 30, 40, cost=0.2),
              _rec("b", "2026-09-02T11:00:00+00:00", 1.0, None, None, status="ERR")]:
        lu.append_record(r, tmp_path)
    g = lu.summarize(lu.read_records(tmp_path), "model", None)
    assert g["a"]["calls"] == 2 and g["a"]["input_tokens"] == 40 and g["a"]["output_tokens"] == 60
    assert g["a"]["cost_usd"] == pytest.approx(0.3) and g["a"]["latency_mean_s"] == 3.0
    assert g["a"]["output_tokens_per_s"] == pytest.approx((10 + 10) / 2)
    assert g["b"]["errors"] == 1
    g2 = lu.summarize(lu.read_records(tmp_path), "day", lu.parse_since("2026-09-02"))
    assert list(g2) == ["2026-09-02"] and g2["2026-09-02"]["calls"] == 2
    table = lu.render_table(g, "model")
    assert "| a | 2 | 0 | 40 | 60 | 0.3000 |" in table


def test_cli_wrap_summary_export(tmp_path):
    env_dir = str(tmp_path)
    script = str(HERE.parent / "llm_usage.py")
    rc = subprocess.call([sys.executable, script, "wrap", "--log-dir", env_dir, "--provider", "cli",
                          "--model", "harness-x", "--tag", "t1", "--", sys.executable, "-c", "import sys; sys.exit(3)"])
    assert rc == 3
    out = subprocess.check_output([sys.executable, script, "summary", "--log-dir", env_dir, "--by", "tag", "--json"])
    g = json.loads(out)
    assert g["t1"]["calls"] == 1 and g["t1"]["errors"] == 1
    otlp = tmp_path / "spans.json"
    subprocess.check_call([sys.executable, script, "export", "--log-dir", env_dir, "--out", str(otlp)],
                          stdout=subprocess.DEVNULL)
    data = json.loads(otlp.read_text())
    span = data["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
    assert span["name"] == "invoke_agent harness-x" and span["status"]["code"] == 2
    keys = {a["key"] for a in span["attributes"]}
    assert {"gen_ai.operation.name", "gen_ai.provider.name", "kit.exit_code"} <= keys
    assert len(span["traceId"]) == 32 and len(span["spanId"]) == 16


def test_proxy_refuses_remote_bind():
    assert lu.main(["proxy", "--host", "0.0.0.0", "--upstream", "http://127.0.0.1:1/v1"]) == 2


def test_bad_since():
    with pytest.raises(SystemExit):
        lu.parse_since("yesterday")
