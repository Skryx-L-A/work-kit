"""Fake OpenAI-compatible, Azure and Anthropic-compatible servers for the kit-models tests.

Each server records every request (path, headers, JSON body) and answers with a fixed text or,
when the request offers tools and the last message is from the user, with a tool call.
"""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Fake:
    def __init__(self, style: str, models=("m1", "m2"), key: str = "sk-test-123", port: int = 0):
        self.style = style  # openai | azure | anthropic
        self.models = list(models)
        self.key = key
        self.requests = []
        fake = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _send(self, status, obj, ctype="application/json"):
                data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
                self.send_response(status)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _authorized(self):
                h = {k.lower(): v for k, v in self.headers.items()}
                if fake.style == "anthropic":
                    return h.get("x-api-key") == fake.key or h.get("authorization") == f"Bearer {fake.key}"
                if fake.style == "azure":
                    return h.get("api-key") == fake.key
                return h.get("authorization") == f"Bearer {fake.key}"

            def do_GET(self):
                fake.requests.append({"method": "GET", "path": self.path,
                                      "headers": dict(self.headers), "body": None})
                if not self._authorized():
                    return self._send(401, {"error": {"message": "bad key"}})
                self._send(200, {"object": "list", "data": [{"id": m, "object": "model"} for m in fake.models]})

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n) or b"{}")
                fake.requests.append({"method": "POST", "path": self.path,
                                      "headers": dict(self.headers), "body": body})
                if not self._authorized():
                    return self._send(401, {"error": {"message": "bad key"}})
                if fake.style == "anthropic":
                    return self._anthropic(body)
                return self._openai(body)

            def _openai(self, body):
                msgs = body.get("messages") or []
                wants_tool = body.get("tools") and msgs and msgs[-1].get("role") == "user"
                if wants_tool:
                    fn = body["tools"][0]["function"]["name"]
                    msg = {"role": "assistant", "content": None, "tool_calls": [
                        {"id": "call_1", "type": "function",
                         "function": {"name": fn, "arguments": json.dumps({"path": "a.txt"})}}]}
                    finish = "tool_calls"
                else:
                    msg = {"role": "assistant", "content": "OK from " + fake.style}
                    finish = "stop"
                resp = {"id": "chatcmpl-1", "object": "chat.completion", "created": 1,
                        "model": body.get("model"),
                        "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
                        "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8}}
                if body.get("stream"):
                    chunks = [{"id": "c", "object": "chat.completion.chunk", "created": 1,
                               "model": body.get("model"),
                               "choices": [{"index": 0, "delta": {"content": part}, "finish_reason": None}]}
                              for part in ("OK ", "stream")]
                    chunks.append({"id": "c", "object": "chat.completion.chunk", "created": 1,
                                   "model": body.get("model"),
                                   "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                                   "usage": {"prompt_tokens": 5, "completion_tokens": 2, "total_tokens": 7}})
                    data = b"".join(b"data: " + json.dumps(c).encode() + b"\n\n" for c in chunks)
                    return self._send(200, data + b"data: [DONE]\n\n", "text/event-stream")
                self._send(200, resp)

            def _anthropic(self, body):
                msgs = body.get("messages") or []
                last = msgs[-1] if msgs else {}
                last_is_text = last.get("role") == "user" and (
                    isinstance(last.get("content"), str)
                    or all(b.get("type") == "text" for b in last.get("content") or []))
                if body.get("tools") and last_is_text:
                    content = [{"type": "tool_use", "id": "toolu_1", "name": body["tools"][0]["name"],
                                "input": {"path": "a.txt"}}]
                    stop = "tool_use"
                else:
                    content = [{"type": "text", "text": "OK from anthropic"}]
                    stop = "end_turn"
                resp = {"id": "msg_1", "type": "message", "role": "assistant", "model": body.get("model"),
                        "content": content, "stop_reason": stop, "stop_sequence": None,
                        "usage": {"input_tokens": 7, "output_tokens": 2}}
                if body.get("stream"):
                    ev = [("message_start", {"type": "message_start", "message": dict(resp, content=[])}),
                          ("content_block_start", {"type": "content_block_start", "index": 0,
                                                   "content_block": {"type": "text", "text": ""}}),
                          ("content_block_delta", {"type": "content_block_delta", "index": 0,
                                                   "delta": {"type": "text_delta", "text": "OK stream"}}),
                          ("content_block_stop", {"type": "content_block_stop", "index": 0}),
                          ("message_delta", {"type": "message_delta",
                                             "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                                             "usage": {"output_tokens": 2}}),
                          ("message_stop", {"type": "message_stop"})]
                    data = b"".join(f"event: {n}\ndata: {json.dumps(d)}\n\n".encode() for n, d in ev)
                    return self._send(200, data, "text/event-stream")
                self._send(200, resp)

        self.server = ThreadingHTTPServer(("127.0.0.1", port), H)
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()
