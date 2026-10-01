#!/usr/bin/env python3
"""llm-usage: record token, cost and latency of LLM calls as OpenTelemetry GenAI spans in local JSONL.

Standard library only (Python >= 3.10). Commands:

  proxy    local OpenAI-compatible logging proxy in front of any endpoint
  wrap     run a command (e.g. a CLI harness) and record its duration and exit code
  summary  aggregate the log by model, provider, day, operation or tag
  tail     print the last records
  export   convert records to OTLP/JSON traces for an OpenTelemetry collector

One JSONL line per call. Attribute names follow the OpenTelemetry GenAI semantic conventions
(gen_ai.*, server.*, error.type); kit-specific values use the kit.* prefix. Prompt and response
text is NOT stored unless --capture-content is given (the conventions make content opt-in).
"""

from __future__ import annotations

import argparse
import datetime as dt
import http.client
import http.server
import json
import os
import secrets
import socketserver
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path
from typing import Any, Iterable

VERSION = "1.0.0"
SCHEMA = "kit.llm-usage/1"

OPERATIONS = {
    "chat/completions": "chat",
    "completions": "text_completion",
    "embeddings": "embeddings",
    "responses": "chat",
}


# --- storage --------------------------------------------------------------------------------

def data_dir() -> Path:
    env = os.environ.get("LLM_USAGE_HOME")
    if env:
        return Path(env)
    base = os.environ.get("KIT_DATA_DIR") or str(Path.home() / ".local/share/work-kit")
    return Path(base) / "llm-usage"


def prices_file() -> Path:
    env = os.environ.get("LLM_USAGE_PRICES")
    if env:
        return Path(env)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "work-kit/llm-prices.toml"


_write_lock = threading.Lock()


def append_record(rec: dict[str, Any], folder: Path | None = None) -> Path:
    folder = folder or data_dir()
    folder.mkdir(parents=True, exist_ok=True)
    month = rec["start_time"][:7]
    path = folder / f"usage-{month}.jsonl"
    line = json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n"
    with _write_lock, open(path, "a", encoding="utf-8") as fh:
        fh.write(line)
    return path


def read_records(folder: Path | None = None) -> Iterable[dict[str, Any]]:
    folder = folder or data_dir()
    if not folder.is_dir():
        return
    for path in sorted(folder.glob("usage-*.jsonl")):
        with open(path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    print(f"llm-usage: skipping bad line {path.name}:{n}", file=sys.stderr)


# --- prices ---------------------------------------------------------------------------------

def load_prices(path: Path | None = None) -> dict[str, dict[str, float]]:
    """[models."<name>"] input_per_1m / output_per_1m (USD). Missing file = no prices."""
    path = path or prices_file()
    if not path.is_file():
        return {}
    import tomllib

    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    out: dict[str, dict[str, float]] = {}
    for name, p in (data.get("models") or {}).items():
        if isinstance(p, dict):
            out[str(name)] = {k: float(v) for k, v in p.items() if k in ("input_per_1m", "output_per_1m")}
    return out


def compute_cost(model: str | None, tin: int | None, tout: int | None,
                 prices: dict[str, dict[str, float]]) -> float | None:
    if not model or tin is None or tout is None:
        return None
    p = prices.get(model)
    if not p or "input_per_1m" not in p or "output_per_1m" not in p:
        return None
    return round(tin * p["input_per_1m"] / 1e6 + tout * p["output_per_1m"] / 1e6, 8)


# --- record building ------------------------------------------------------------------------

def now_iso(ts: float) -> str:
    return dt.datetime.fromtimestamp(ts, dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def new_record(operation: str, provider: str, model: str | None, start: float, end: float,
               attrs: dict[str, Any], error: str | None = None, tag: str | None = None) -> dict[str, Any]:
    a: dict[str, Any] = {
        "gen_ai.operation.name": operation,
        "gen_ai.provider.name": provider,
    }
    if model:
        a["gen_ai.request.model"] = model
    a.update({k: v for k, v in attrs.items() if v is not None})
    if error:
        a["error.type"] = error
    if tag:
        a["kit.tag"] = tag
    return {
        "schema": SCHEMA,
        "trace_id": secrets.token_hex(16),
        "span_id": secrets.token_hex(8),
        "name": f"{operation} {model}" if model else operation,
        "kind": "CLIENT",
        "start_time": now_iso(start),
        "end_time": now_iso(end),
        "duration_s": round(end - start, 4),
        "status": "ERROR" if error else "OK",
        "attributes": a,
    }


def usage_attrs(usage: dict[str, Any] | None) -> dict[str, Any]:
    """Map OpenAI chat/completions and responses usage objects to gen_ai.usage.*."""
    if not isinstance(usage, dict):
        return {}
    tin = usage.get("prompt_tokens", usage.get("input_tokens"))
    tout = usage.get("completion_tokens", usage.get("output_tokens"))
    out: dict[str, Any] = {"gen_ai.usage.input_tokens": tin, "gen_ai.usage.output_tokens": tout}
    details = usage.get("prompt_tokens_details") or usage.get("input_tokens_details") or {}
    if isinstance(details, dict) and details.get("cached_tokens") is not None:
        out["gen_ai.usage.cache_read.input_tokens"] = details["cached_tokens"]
    odet = usage.get("completion_tokens_details") or usage.get("output_tokens_details") or {}
    if isinstance(odet, dict) and odet.get("reasoning_tokens") is not None:
        out["gen_ai.usage.reasoning.output_tokens"] = odet["reasoning_tokens"]
    if isinstance(usage.get("cost"), (int, float)):
        out["kit.cost_usd"] = usage["cost"]
    return out


def request_attrs(body: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, attr in (("temperature", "gen_ai.request.temperature"), ("top_p", "gen_ai.request.top_p"),
                      ("seed", "gen_ai.request.seed")):
        if isinstance(body.get(key), (int, float)):
            out[attr] = body[key]
    mt = body.get("max_tokens", body.get("max_completion_tokens", body.get("max_output_tokens")))
    if isinstance(mt, int):
        out["gen_ai.request.max_tokens"] = mt
    if body.get("stream") is True:
        out["gen_ai.request.stream"] = True
    return out


def response_attrs(payload: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    if payload.get("id"):
        out["gen_ai.response.id"] = payload["id"]
    if payload.get("model"):
        out["gen_ai.response.model"] = payload["model"]
    reasons = [c.get("finish_reason") for c in payload.get("choices") or [] if isinstance(c, dict) and c.get("finish_reason")]
    if reasons:
        out["gen_ai.response.finish_reasons"] = reasons
    out.update(usage_attrs(payload.get("usage")))
    return out


def output_text(payload: dict[str, Any]) -> str:
    parts = []
    for c in payload.get("choices") or []:
        msg = c.get("message") or {}
        parts.append(msg.get("content") or c.get("text") or "")
    return "".join(p for p in parts if isinstance(p, str))


# --- proxy ----------------------------------------------------------------------------------

HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te",
               "trailers", "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}


class ProxyConfig:
    def __init__(self, upstream: str, provider: str, capture: bool, tag: str | None,
                 folder: Path | None, prices: dict[str, dict[str, float]], timeout: float,
                 free: bool = False):
        u = urllib.parse.urlsplit(upstream.rstrip("/"))
        if u.scheme not in ("http", "https") or not u.hostname:
            raise ValueError(f"bad upstream URL: {upstream}")
        self.scheme = u.scheme
        self.host = u.hostname
        self.port = u.port or (443 if u.scheme == "https" else 80)
        self.base_path = u.path  # e.g. /v1
        self.provider = provider
        self.capture = capture
        self.tag = tag
        self.folder = folder
        self.prices = prices
        self.timeout = timeout
        self.free = free

    def connect(self) -> http.client.HTTPConnection:
        cls = http.client.HTTPSConnection if self.scheme == "https" else http.client.HTTPConnection
        return cls(self.host, self.port, timeout=self.timeout)


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    server_version = f"llm-usage/{VERSION}"
    protocol_version = "HTTP/1.1"
    cfg: ProxyConfig

    def log_message(self, fmt: str, *args: Any) -> None:  # quiet by default
        if os.environ.get("LLM_USAGE_DEBUG"):
            super().log_message(fmt, *args)

    def do_GET(self) -> None:
        self._forward(None)

    def do_POST(self) -> None:
        n = int(self.headers.get("Content-Length") or 0)
        self._forward(self.rfile.read(n) if n else b"")

    def do_DELETE(self) -> None:
        self._forward(None)

    def _upstream_path(self) -> str:
        # Client base URL is http://127.0.0.1:<port>/v1; the path after /v1 is appended to the
        # upstream base (which usually also ends in /v1).
        path = self.path
        rest = path[3:] if path.startswith("/v1/") or path == "/v1" else path
        return self.cfg.base_path + rest

    def _operation(self) -> str | None:
        p = urllib.parse.urlsplit(self.path).path.rstrip("/")
        for suffix, op in OPERATIONS.items():
            if p.endswith("/" + suffix):
                return op
        return None

    def _forward(self, body: bytes | None) -> None:
        cfg = self.cfg
        op = self._operation() if self.command == "POST" else None
        req_json: dict[str, Any] = {}
        if op and body:
            try:
                req_json = json.loads(body)
            except (json.JSONDecodeError, UnicodeDecodeError):
                req_json = {}
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
        headers["Host"] = f"{cfg.host}:{cfg.port}"
        if body is not None:
            headers["Content-Length"] = str(len(body))
        start = time.time()
        conn = cfg.connect()
        try:
            conn.request(self.command, self._upstream_path(), body=body, headers=headers)
            resp = conn.getresponse()
        except OSError as exc:
            self._send_error(502, f"upstream unreachable: {exc}")
            if op:
                self._record(op, req_json, start, time.time(), {}, "upstream_unreachable", None, None)
            return
        streaming = "text/event-stream" in (resp.getheader("Content-Type") or "")
        self.send_response(resp.status, resp.reason)
        for k, v in resp.getheaders():
            if k.lower() not in HOP_HEADERS:
                self.send_header(k, v)
        if streaming:
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.close_connection = True
            self.end_headers()
            self._relay_stream(resp, op, req_json, start)
        else:
            data = resp.read()
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            if op:
                payload: dict[str, Any] = {}
                try:
                    payload = json.loads(data) if data else {}
                except (json.JSONDecodeError, UnicodeDecodeError):
                    payload = {}
                err = None if resp.status < 400 else str(resp.status)
                self._record(op, req_json, start, time.time(), payload if isinstance(payload, dict) else {},
                             err, None, resp.status)
        conn.close()

    def _relay_stream(self, resp: http.client.HTTPResponse, op: str | None, req_json: dict[str, Any],
                      start: float) -> None:
        first: float | None = None
        merged: dict[str, Any] = {}
        text: list[str] = []
        reasons: list[str] = []
        err = None
        try:
            while True:
                line = resp.readline()
                if not line:
                    break
                if first is None:
                    first = time.time()
                self.wfile.write(f"{len(line):x}\r\n".encode() + line + b"\r\n")
                self.wfile.flush()
                s = line.strip()
                if not s.startswith(b"data:"):
                    continue
                chunk = s[5:].strip()
                if chunk == b"[DONE]":
                    continue
                try:
                    obj = json.loads(chunk)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                if not isinstance(obj, dict):
                    continue
                for key in ("id", "model"):
                    if obj.get(key):
                        merged[key] = obj[key]
                if obj.get("usage"):
                    merged["usage"] = obj["usage"]
                for c in obj.get("choices") or []:
                    if c.get("finish_reason"):
                        reasons.append(c["finish_reason"])
                    delta = c.get("delta") or {}
                    if isinstance(delta.get("content"), str):
                        text.append(delta["content"])
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            err = "client_disconnected"
        end = time.time()
        if reasons:
            merged["choices"] = [{"finish_reason": r} for r in reasons]
        if op:
            ttfc = round(first - start, 4) if first else None
            if self.cfg.capture:
                merged["_text"] = "".join(text)
            self._record(op, req_json, start, end, merged, err or (None if resp.status < 400 else str(resp.status)),
                         ttfc, resp.status)

    def _record(self, op: str, req: dict[str, Any], start: float, end: float, payload: dict[str, Any],
                err: str | None, ttfc: float | None, status: int | None) -> None:
        cfg = self.cfg
        attrs = request_attrs(req)
        attrs.update(response_attrs(payload))
        attrs["server.address"] = cfg.host
        attrs["server.port"] = cfg.port
        if status is not None:
            attrs["http.response.status_code"] = status
        if ttfc is not None:
            attrs["gen_ai.response.time_to_first_chunk"] = ttfc
        model = req.get("model") if isinstance(req.get("model"), str) else None
        if cfg.free:
            attrs["kit.cost_usd"] = 0.0
        elif "kit.cost_usd" not in attrs:
            attrs["kit.cost_usd"] = compute_cost(attrs.get("gen_ai.response.model") or model,
                                                 attrs.get("gen_ai.usage.input_tokens"),
                                                 attrs.get("gen_ai.usage.output_tokens"), cfg.prices) \
                or compute_cost(model, attrs.get("gen_ai.usage.input_tokens"),
                                attrs.get("gen_ai.usage.output_tokens"), cfg.prices)
        if cfg.capture:
            if isinstance(req.get("messages"), list):
                attrs["gen_ai.input.messages"] = req["messages"]
            elif "input" in req:
                attrs["gen_ai.input.messages"] = req["input"]
            out = payload.get("_text") if "_text" in payload else output_text(payload)
            if out:
                attrs["gen_ai.output.messages"] = [{"role": "assistant", "content": out}]
        append_record(new_record(op, cfg.provider, model, start, end, attrs, err, cfg.tag), cfg.folder)

    def _send_error(self, code: int, msg: str) -> None:
        data = json.dumps({"error": {"message": msg, "type": "llm_usage_proxy"}}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def make_proxy(cfg: ProxyConfig, host: str, port: int) -> ThreadingServer:
    handler = type("Handler", (ProxyHandler,), {"cfg": cfg})
    return ThreadingServer((host, port), handler)


# --- summary --------------------------------------------------------------------------------

def parse_since(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    v = value.strip()
    units = {"h": 3600, "d": 86400, "w": 604800}
    if v[-1:] in units and v[:-1].isdigit():
        return dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=int(v[:-1]) * units[v[-1]])
    try:
        d = dt.datetime.fromisoformat(v)
    except ValueError:
        raise SystemExit(f"llm-usage: --since takes 7d, 12h, 2w or a date like 2026-10-01, not {value!r}")
    return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)


def rec_time(rec: dict[str, Any]) -> dt.datetime:
    return dt.datetime.fromisoformat(rec["start_time"].replace("Z", "+00:00"))


def group_key(rec: dict[str, Any], by: str) -> str:
    a = rec.get("attributes") or {}
    if by == "model":
        return str(a.get("gen_ai.response.model") or a.get("gen_ai.request.model") or "?")
    if by == "provider":
        return str(a.get("gen_ai.provider.name") or "?")
    if by == "day":
        return rec["start_time"][:10]
    if by == "operation":
        return str(a.get("gen_ai.operation.name") or "?")
    if by == "tag":
        return str(a.get("kit.tag") or "-")
    raise SystemExit(f"llm-usage: unknown --by {by}")


def p95(values: list[float]) -> float | None:
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, int(round(0.95 * (len(s) - 1))))]


def summarize(records: Iterable[dict[str, Any]], by: str, since: dt.datetime | None) -> dict[str, dict[str, Any]]:
    groups: dict[str, dict[str, Any]] = {}
    for rec in records:
        if since and rec_time(rec) < since:
            continue
        a = rec.get("attributes") or {}
        g = groups.setdefault(group_key(rec, by), {
            "calls": 0, "errors": 0, "input_tokens": 0, "output_tokens": 0, "tokens_unknown": 0,
            "cost_usd": 0.0, "cost_unknown": 0, "_lat": [], "_tps": [], "_ttfc": []})
        g["calls"] += 1
        if rec.get("status") == "ERROR":
            g["errors"] += 1
        tin, tout = a.get("gen_ai.usage.input_tokens"), a.get("gen_ai.usage.output_tokens")
        if isinstance(tin, int) and isinstance(tout, int):
            g["input_tokens"] += tin
            g["output_tokens"] += tout
            if tout and rec.get("duration_s"):
                gen_time = rec["duration_s"] - (a.get("gen_ai.response.time_to_first_chunk") or 0)
                if gen_time > 0:
                    g["_tps"].append(tout / gen_time)
        elif rec.get("status") != "ERROR" and a.get("gen_ai.operation.name") != "invoke_agent":
            g["tokens_unknown"] += 1
        cost = a.get("kit.cost_usd")
        if isinstance(cost, (int, float)):
            g["cost_usd"] += cost
        else:
            g["cost_unknown"] += 1
        if isinstance(rec.get("duration_s"), (int, float)):
            g["_lat"].append(rec["duration_s"])
        if isinstance(a.get("gen_ai.response.time_to_first_chunk"), (int, float)):
            g["_ttfc"].append(a["gen_ai.response.time_to_first_chunk"])
    for g in groups.values():
        lat, tps, ttfc = g.pop("_lat"), g.pop("_tps"), g.pop("_ttfc")
        g["latency_mean_s"] = round(sum(lat) / len(lat), 3) if lat else None
        g["latency_p95_s"] = round(p95(lat), 3) if lat else None
        g["ttfc_mean_s"] = round(sum(ttfc) / len(ttfc), 3) if ttfc else None
        g["output_tokens_per_s"] = round(sum(tps) / len(tps), 1) if tps else None
        g["cost_usd"] = round(g["cost_usd"], 6)
    return dict(sorted(groups.items()))


def render_table(groups: dict[str, dict[str, Any]], by: str) -> str:
    def f(v: Any) -> str:
        return "-" if v is None else str(v)
    head = f"| {by} | calls | errors | tokens in | tokens out | cost USD | latency mean s | p95 s | TTFC s | out tok/s |"
    lines = [head, "|" + "---|" * 10]
    for key, g in groups.items():
        cost = f"{g['cost_usd']:.4f}" + ("*" if g["cost_unknown"] else "")
        tok_in = str(g["input_tokens"]) + ("*" if g["tokens_unknown"] else "")
        lines.append(f"| {key} | {g['calls']} | {g['errors']} | {tok_in} | {g['output_tokens']} | {cost} | "
                     f"{f(g['latency_mean_s'])} | {f(g['latency_p95_s'])} | {f(g['ttfc_mean_s'])} | "
                     f"{f(g['output_tokens_per_s'])} |")
    if any(g["cost_unknown"] or g["tokens_unknown"] for g in groups.values()):
        lines.append("")
        lines.append("* some calls had no token usage or no price (see llm-prices.toml); they count as 0 here.")
    return "\n".join(lines)


# --- OTLP export ----------------------------------------------------------------------------

def _otlp_value(v: Any) -> dict[str, Any]:
    if isinstance(v, bool):
        return {"boolValue": v}
    if isinstance(v, int):
        return {"intValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, list) and all(isinstance(x, str) for x in v):
        return {"arrayValue": {"values": [{"stringValue": x} for x in v]}}
    if isinstance(v, (list, dict)):
        return {"stringValue": json.dumps(v, ensure_ascii=False)}
    return {"stringValue": str(v)}


def to_otlp(records: Iterable[dict[str, Any]], service: str) -> dict[str, Any]:
    spans = []
    for rec in records:
        start_ns = int(rec_time(rec).timestamp() * 1e9)
        end_ns = start_ns + int(float(rec.get("duration_s") or 0) * 1e9)
        span = {
            "traceId": rec["trace_id"], "spanId": rec["span_id"], "name": rec["name"],
            "kind": 3,  # SPAN_KIND_CLIENT
            "startTimeUnixNano": str(start_ns), "endTimeUnixNano": str(end_ns),
            "attributes": [{"key": k, "value": _otlp_value(v)} for k, v in (rec.get("attributes") or {}).items()],
            "status": {"code": 2} if rec.get("status") == "ERROR" else {"code": 1},
        }
        spans.append(span)
    return {"resourceSpans": [{
        "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": service}}]},
        "scopeSpans": [{"scope": {"name": "llm-usage", "version": VERSION}, "spans": spans}],
    }]}


# --- CLI ------------------------------------------------------------------------------------

def cmd_proxy(args: argparse.Namespace) -> int:
    if args.host not in ("127.0.0.1", "localhost", "::1") and not args.allow_remote:
        print("llm-usage: refusing to listen on a non-loopback address without --allow-remote", file=sys.stderr)
        return 2
    cfg = ProxyConfig(args.upstream, args.provider, args.capture_content, args.tag,
                      Path(args.log_dir) if args.log_dir else None, load_prices(), args.timeout, args.free)
    srv = make_proxy(cfg, args.host, args.port)
    folder = cfg.folder or data_dir()
    print(f"llm-usage proxy: http://{args.host}:{srv.server_address[1]}/v1 -> {args.upstream} "
          f"(log {folder}, content {'ON' if cfg.capture else 'off'})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


def cmd_wrap(args: argparse.Namespace) -> int:
    cmd = args.command
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        print("llm-usage wrap: give a command after --", file=sys.stderr)
        return 2
    start = time.time()
    try:
        rc = subprocess.call(cmd)
        err = None if rc == 0 else f"exit_{rc}"
    except FileNotFoundError:
        rc, err = 127, "command_not_found"
    end = time.time()
    attrs: dict[str, Any] = {"kit.command": os.path.basename(cmd[0]), "kit.exit_code": rc}
    if args.input_tokens is not None:
        attrs["gen_ai.usage.input_tokens"] = args.input_tokens
    if args.output_tokens is not None:
        attrs["gen_ai.usage.output_tokens"] = args.output_tokens
    attrs["kit.cost_usd"] = args.cost
    append_record(new_record(args.operation, args.provider, args.model, start, end, attrs, err, args.tag),
                  Path(args.log_dir) if args.log_dir else None)
    return rc


def filtered(args: argparse.Namespace) -> list[dict[str, Any]]:
    since = parse_since(getattr(args, "since", None))
    folder = Path(args.log_dir) if getattr(args, "log_dir", None) else None
    return [r for r in read_records(folder) if not since or rec_time(r) >= since]


def cmd_summary(args: argparse.Namespace) -> int:
    folder = Path(args.log_dir) if args.log_dir else None
    groups = summarize(read_records(folder), args.by, parse_since(args.since))
    if args.json:
        print(json.dumps(groups, indent=2))
    elif not groups:
        print(f"no records{' since ' + args.since if args.since else ''} in {folder or data_dir()}")
    else:
        print(render_table(groups, args.by))
    return 0


def cmd_tail(args: argparse.Namespace) -> int:
    recs = filtered(args)[-args.n:]
    if not recs:
        since = f" since {args.since}" if args.since else ""
        print(f"no records{since} in {args.log_dir or data_dir()}")
        return 0
    for r in recs:
        a = r.get("attributes") or {}
        print(f"{r['start_time']}  {r['status']:5}  {r['duration_s']:>8.2f}s  "
              f"{a.get('gen_ai.provider.name', '?')}  {r['name']}  "
              f"in={a.get('gen_ai.usage.input_tokens', '-')} out={a.get('gen_ai.usage.output_tokens', '-')}")
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    data = to_otlp(filtered(args), args.service)
    text = json.dumps(data, ensure_ascii=False)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
        print(f"wrote {len(data['resourceSpans'][0]['scopeSpans'][0]['spans'])} spans to {args.out}")
    else:
        print(text)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="llm-usage", description=__doc__.split("\n\n")[0],
        epilog="background proxy (llm-usage launcher only):\n"
               "  start [proxy options]   run the proxy in the background\n"
               "  stop                    stop it\n"
               "  status                  is it running?",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", action="version", version=f"llm-usage {VERSION}")
    sub = p.add_subparsers(dest="cmd", required=True)

    x = sub.add_parser("proxy", help="logging proxy in front of an OpenAI-compatible endpoint")
    x.add_argument("--upstream", default=os.environ.get("LLM_USAGE_UPSTREAM", "http://127.0.0.1:8080/v1"),
                   help="upstream base URL including /v1 (default: kit-llm on port 8080)")
    x.add_argument("--port", type=int, default=int(os.environ.get("LLM_USAGE_PORT", "4011")))
    x.add_argument("--host", default="127.0.0.1")
    x.add_argument("--allow-remote", action="store_true", help=argparse.SUPPRESS)
    x.add_argument("--provider", default="llama.cpp", help="gen_ai.provider.name value, e.g. openai, azure.ai.openai")
    x.add_argument("--tag", help="free label stored as kit.tag (experiment, project)")
    x.add_argument("--capture-content", action="store_true", help="also store prompts and responses (off by default)")
    x.add_argument("--free", action="store_true", help="record cost 0 (local engine without a price)")
    x.add_argument("--timeout", type=float, default=600.0)
    x.add_argument("--log-dir")
    x.set_defaults(fn=cmd_proxy)

    w = sub.add_parser("wrap", help="run a command and record duration and exit code")
    w.add_argument("--provider", default="cli")
    w.add_argument("--model")
    w.add_argument("--operation", default="invoke_agent")
    w.add_argument("--tag")
    w.add_argument("--input-tokens", type=int)
    w.add_argument("--output-tokens", type=int)
    w.add_argument("--cost", type=float)
    w.add_argument("--log-dir")
    w.add_argument("command", nargs=argparse.REMAINDER)
    w.set_defaults(fn=cmd_wrap)

    s = sub.add_parser("summary", help="aggregate the log")
    s.add_argument("--by", default="model", choices=["model", "provider", "day", "operation", "tag"])
    s.add_argument("--since", help="7d, 12h, 2w or a date (UTC)")
    s.add_argument("--json", action="store_true")
    s.add_argument("--log-dir")
    s.set_defaults(fn=cmd_summary)

    t = sub.add_parser("tail", help="last records")
    t.add_argument("-n", type=int, default=20)
    t.add_argument("--since")
    t.add_argument("--log-dir")
    t.set_defaults(fn=cmd_tail)

    e = sub.add_parser("export", help="OTLP/JSON traces for an OpenTelemetry collector")
    e.add_argument("--since")
    e.add_argument("--service", default="work-kit")
    e.add_argument("--out")
    e.add_argument("--log-dir")
    e.set_defaults(fn=cmd_export)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
