"""Tiny OpenAI-compatible server for tests. Also runnable by hand: python tests/fake_server.py 8765"""

from __future__ import annotations

import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Callable

Handler = Callable[[dict, dict], tuple[int, dict]]


def default_handler(body: dict, headers: dict) -> tuple[int, dict]:
    prompt = body["messages"][-1]["content"]
    if "strict evaluator" in prompt:
        answer = prompt.split("RESPONSE:", 1)[-1]
        text = json.dumps({"verdict": "pass" if "seconds" in answer else "fail", "reason": "fake judge"})
    else:
        text = "Returns the duration in seconds."
    return 200, {
        "choices": [{"message": {"role": "assistant", "content": text}}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 10},
    }


class FakeServer:
    def __init__(self, handler: Handler = default_handler):
        self.handler = handler
        self.requests: list[tuple[dict, dict]] = []
        outer = self

        class H(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                headers = {k.lower(): v for k, v in self.headers.items()}
                outer.requests.append((body, headers))
                status, payload = outer.handler(body, headers)
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        self.httpd = HTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.httpd.server_port}/v1"
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def __enter__(self) -> "FakeServer":
        self.thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = FakeServer()
    srv.httpd = HTTPServer(("127.0.0.1", port), srv.httpd.RequestHandlerClass)
    print(f"fake OpenAI server on http://127.0.0.1:{port}/v1", flush=True)
    srv.httpd.serve_forever()
