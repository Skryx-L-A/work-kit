#!/usr/bin/env python3
"""Deterministic fake OpenAI-compatible server for testing the packs without a model.

Usage: fake_openai.py [--port N] [--port-file F] [--delay S] [--answers FILE.json]
Answers: JSON list of [substring, reply]; the first substring found in the last user message
wins, else the reply is "I do not know.". Supports stream=true (SSE, usage in the last chunk).
"""

from __future__ import annotations

import argparse
import http.server
import json
import time
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=0)
ap.add_argument("--port-file")
ap.add_argument("--delay", type=float, default=0.0, help="seconds per output token")
ap.add_argument("--answers")
ap.add_argument("--model", default="fake-model")
args = ap.parse_args()
ANSWERS = json.loads(Path(args.answers).read_text(encoding="utf-8")) if args.answers else []


def reply_for(text: str) -> str:
    for needle, reply in ANSWERS:
        if needle in text:
            return reply
    return "I do not know."


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        d = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._json({"object": "list", "data": [{"id": args.model, "object": "model"}]})
        else:
            self._json({"status": "ok"})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        msgs = body.get("messages") or []
        text = msgs[-1]["content"] if msgs else ""
        reply = reply_for(text if isinstance(text, str) else json.dumps(text))
        words = reply.split(" ")
        tin, tout = max(1, len(str(text).split())), len(words)
        if not body.get("stream"):
            time.sleep(args.delay * tout)
            self._json({"id": "fake-1", "object": "chat.completion", "model": args.model,
                        "choices": [{"index": 0, "message": {"role": "assistant", "content": reply},
                                     "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": tin, "completion_tokens": tout, "total_tokens": tin + tout}})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def send(obj):
            line = f"data: {obj if isinstance(obj, str) else json.dumps(obj)}\n\n".encode()
            self.wfile.write(f"{len(line):x}\r\n".encode() + line + b"\r\n")
            self.wfile.flush()

        for i, w in enumerate(words):
            time.sleep(args.delay)
            send({"id": "fake-1", "model": args.model,
                  "choices": [{"index": 0, "delta": {"content": w if i == 0 else " " + w}, "finish_reason": None}]})
        send({"id": "fake-1", "model": args.model, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        if (body.get("stream_options") or {}).get("include_usage"):
            send({"id": "fake-1", "model": args.model, "choices": [],
                  "usage": {"prompt_tokens": tin, "completion_tokens": tout, "total_tokens": tin + tout}})
        send("[DONE]")
        self.wfile.write(b"0\r\n\r\n")


srv = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), H)
if args.port_file:
    Path(args.port_file).write_text(str(srv.server_address[1]))
print(f"fake openai on http://127.0.0.1:{srv.server_address[1]}/v1", flush=True)
try:
    srv.serve_forever()
except KeyboardInterrupt:
    pass
