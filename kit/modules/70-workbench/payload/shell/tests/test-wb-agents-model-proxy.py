#!/usr/bin/env python3
"""Isolated fake-backend tests for the run-bound Agents model proxy."""

from __future__ import annotations

import http.client
import json
import multiprocessing
import os
import signal
import socket
import socketserver
import stat
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_model_proxy as amp


MARKER = "PROXY_FIXTURE_OK"


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path: Path, timeout: float = 2.0):
        super().__init__("localhost", timeout=timeout)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(self.path))


class FakeBackend(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), FakeBackendHandler)
        self.records = []
        self.records_lock = threading.Lock()
        self.second_chunk = threading.Event()
        self.first_chunk_sent = threading.Event()
        self.redirect = False
        self.redirect_target_hits = 0


class FakeUnixBackend(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def __init__(self, path):
        super().__init__(str(path), FakeBackendHandler)
        self.records = []
        self.records_lock = threading.Lock()
        self.second_chunk = threading.Event()
        self.first_chunk_sent = threading.Event()
        self.redirect = False
        self.redirect_target_hits = 0
        self.server_port = 0


class FakeBackendHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    @property
    def fixture(self):
        return self.server

    def log_message(self, _format, *_args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        with self.fixture.records_lock:
            self.fixture.records.append({"path": self.path, "headers": dict(self.headers), "body": json.loads(body)})
        if self.path == "/redirect-target":
            self.fixture.redirect_target_hits += 1
        if self.fixture.redirect:
            self.send_response(307)
            self.send_header("Location", "http://127.0.0.1:%d/redirect-target" % self.server.server_port)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = json.loads(body)
        if payload.get("stream") is False:
            response = json.dumps({"content": [{"type": "text", "text": MARKER}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)
            return
        first = b"event: response.created\ndata: {}\n\n"
        second = ("event: response.completed\ndata: {\"marker\":\"%s\"}\n\n" % MARKER).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(first)
        self.wfile.flush()
        self.fixture.first_chunk_sent.set()
        self.fixture.second_chunk.wait(2.0)
        try:
            self.wfile.write(second)
            self.wfile.flush()
        except BrokenPipeError:
            pass
        self.close_connection = True


def child_proxy_process(controller_root, socket_path, backend_port, ready):
    binding = amp.ProxyBinding("world", "agent", "run", "provider", "model")
    backend = amp.BackendConfig(
        "provider", "model", "openai-responses", "local", f"http://127.0.0.1:{backend_port}", "mac", "mac",
        local_only=True
    )
    proxy = amp.AgentsModelProxy(binding, backend, Path(socket_path), Path(controller_root), (), lambda _binding: True)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda _signum, _frame: stop.set())
    try:
        proxy.start()
        ready.send(proxy.endpoint())
        stop.wait(5.0)
    finally:
        proxy.stop()
        ready.close()


class AgentsModelProxyTests(unittest.TestCase):
    def test_socket_rejects_unsafe_intermediate_directory_and_ancestor_symlink(self):
        middle = self.controller_root / 'middle'
        middle.mkdir(mode=0o700)
        leaf = middle / 'leaf'
        leaf.mkdir(mode=0o700)
        alias = self.controller_root / 'alias'
        alias.symlink_to(middle, target_is_directory=True)
        original = self.make_proxy()
        original_path = original.socket_path
        try:
            original.socket_path = leaf / 'unused.sock'
            original._validate_socket_location()
            middle.chmod(0o777)
            with self.assertRaises(amp.ModelProxyError):
                original._validate_socket_location()
            middle.chmod(0o700)
            original.socket_path = alias / 'leaf' / 'unused.sock'
            with self.assertRaises(amp.ModelProxyError):
                original._validate_socket_location()
        finally:
            middle.chmod(0o700)
            original.socket_path = original_path

    def test_connection_limit_rejects_overflow_and_releases_slot(self):
        proxy = self.make_proxy(max_connections=1)
        first = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(first.close)
        first.connect(str(proxy.socket_path))
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            with proxy._server._active_lock:
                if proxy._server._active_clients:
                    break
            time.sleep(0.01)
        else:
            self.fail('First connection was not admitted')
        overflow = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(overflow.close)
        overflow.settimeout(2)
        overflow.connect(str(proxy.socket_path))
        self.assertEqual(overflow.recv(1), b'')
        first.close()
        deadline = time.monotonic() + 2
        while not proxy._server._client_slots.acquire(blocking=False):
            if time.monotonic() >= deadline:
                self.fail('Closed connection did not release capacity')
            time.sleep(0.01)
        proxy._server._client_slots.release()
        connection, response = self.request(proxy, '/v1/responses', {'model': 'model', 'stream': False})
        self.assertEqual(response.status, 200)
        response.read()
        connection.close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="amp-", dir="/tmp")
        self.root = Path(self.tmp.name).resolve()
        self.controller_root = self.root / "controller"
        self.agent_write_root = self.root / "agent-work"
        self.controller_root.mkdir(mode=0o700)
        self.agent_write_root.mkdir()
        self.backend = FakeBackend()
        self.backend_thread = threading.Thread(target=self.backend.serve_forever, daemon=False)
        self.backend_thread.start()
        self.proxies = []
        self.current = True
        self.checked_bindings = []

    def tearDown(self):
        self.backend.second_chunk.set()
        for proxy in self.proxies:
            proxy.stop()
        self.backend.shutdown()
        self.backend.server_close()
        self.backend_thread.join(2.0)
        self.assertFalse(self.backend_thread.is_alive())
        self.tmp.cleanup()

    def make_proxy(self, protocol="openai-responses", **kwargs):
        binding = amp.ProxyBinding("world", "agent", "run", "provider", "model")
        backend = amp.BackendConfig(
            "provider",
            "model",
            protocol,
            "local",
            "http://127.0.0.1:%d" % self.backend.server_port,
            "mac",
            "mac",
            (("Authorization", "Bearer controller-secret"), ("X-Api-Key", "controller-key")),
            True,
        )
        socket_path = self.controller_root / ("proxy-%d.sock" % len(self.proxies))
        io_timeout = kwargs.pop("io_timeout", 2.0)

        def check_run(checked):
            self.checked_bindings.append(checked)
            return self.current

        proxy = amp.AgentsModelProxy(
            binding,
            backend,
            socket_path,
            self.controller_root,
            (self.agent_write_root,),
            check_run,
            io_timeout=io_timeout,
            **kwargs,
        )
        proxy.start()
        self.proxies.append(proxy)
        return proxy

    def request(self, proxy, path, payload, headers=None, method="POST"):
        connection = UnixHTTPConnection(proxy.socket_path)
        body = json.dumps(payload).encode()
        request_headers = {"Content-Type": "application/json", "Content-Length": str(len(body))}
        request_headers.update(headers or {})
        connection.request(method, path, body=body, headers=request_headers)
        response = connection.getresponse()
        return connection, response

    def test_anthropic_exact_beta_route_sse_and_normal_json_retry(self):
        proxy = self.make_proxy("anthropic-messages")
        self.backend.second_chunk.set()
        connection, response = self.request(proxy, "/v1/messages?beta=true", {"model": "model", "stream": True})
        self.assertEqual(response.status, 200)
        self.assertIn(MARKER, response.read().decode())
        connection.close()

        connection, response = self.request(proxy, "/v1/messages?beta=true", {"model": "model", "stream": False})
        self.assertEqual(response.status, 200)
        self.assertEqual(json.loads(response.read())["content"][0]["text"], MARKER)
        connection.close()
        self.assertEqual([item["path"] for item in self.backend.records], [
            "/v1/messages?beta=true", "/v1/messages?beta=true"
        ])

    def test_openai_responses_stream_is_forwarded_before_backend_finishes(self):
        proxy = self.make_proxy()
        connection, response = self.request(proxy, "/v1/responses", {"model": "model", "stream": True})
        self.assertEqual(response.status, 200)
        self.assertTrue(self.backend.first_chunk_sent.wait(1.0))
        started = time.monotonic()
        first = response.read(len(b"event: response.created\ndata: {}\n\n"))
        self.assertLess(time.monotonic() - started, 0.25)
        self.assertIn(b"response.created", first)
        self.backend.second_chunk.set()
        self.assertIn(MARKER.encode(), response.read())
        connection.close()

    def test_route_model_size_encoding_and_methods_are_closed(self):
        proxy = self.make_proxy(max_request_bytes=80)
        for path, payload, expected in (
            ("/v1/responses?target=elsewhere", {"model": "model"}, 404),
            ("/v1/responses", {"model": "other-model"}, 409),
            ("/v1/responses", {"model": "model", "provider": "other-provider"}, 400),
            ("/v1/messages?beta=true", {"model": "model"}, 404),
        ):
            connection, response = self.request(proxy, path, payload)
            self.assertEqual(response.status, expected)
            response.read()
            connection.close()
        oversized = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        oversized.settimeout(2.0)
        oversized.connect(str(proxy.socket_path))
        oversized.sendall(
            b"POST /v1/responses HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
            b"Content-Length: 81\r\nConnection: close\r\n\r\n"
        )
        self.assertIn(b" 413 ", oversized.recv(4096))
        oversized.close()
        connection, response = self.request(proxy, "/v1/responses", {"model": "model"}, {"Content-Encoding": "gzip"})
        self.assertEqual(response.status, 400)
        response.read()
        connection.close()
        raw = UnixHTTPConnection(proxy.socket_path)
        raw.request("CONNECT", "example.invalid:443")
        connect_response = raw.getresponse()
        self.assertEqual(connect_response.status, 405)
        connect_response.read()
        raw.close()
        self.assertEqual(self.backend.records, [])

    def test_client_cannot_change_backend_auth_host_target_or_model(self):
        proxy = self.make_proxy()
        self.assertEqual(proxy.endpoint(), str(proxy.socket_path))
        self.assertEqual(stat.S_IMODE(proxy.socket_path.stat().st_mode), 0o660)
        self.backend.second_chunk.set()
        connection, response = self.request(
            proxy,
            "/v1/responses",
            {"model": "model", "stream": True},
            {
                "Authorization": "Bearer client-value",
                "X-Api-Key": "client-key",
                "Host": "attacker.invalid",
                "X-Backend-URL": "http://attacker.invalid",
            },
        )
        self.assertEqual(response.status, 200)
        response.read()
        connection.close()
        record = self.backend.records[-1]
        lowered = {name.lower(): value for name, value in record["headers"].items()}
        self.assertEqual(lowered["authorization"], "Bearer controller-secret")
        self.assertEqual(lowered["x-api-key"], "controller-key")
        self.assertEqual(lowered["host"], "127.0.0.1:%d" % self.backend.server_port)
        self.assertNotIn("x-backend-url", lowered)
        self.assertEqual(record["body"]["model"], "model")
        self.assertTrue(self.checked_bindings)
        self.assertTrue(all(checked == proxy.binding for checked in self.checked_bindings))

    def test_redirect_is_refused_without_following_location(self):
        proxy = self.make_proxy()
        self.backend.redirect = True
        connection, response = self.request(proxy, "/v1/responses", {"model": "model", "stream": True})
        self.assertEqual(response.status, 502)
        self.assertEqual(json.loads(response.read())["error"]["type"], "backend_redirect_refused")
        connection.close()
        self.assertEqual(len(self.backend.records), 1)
        self.assertEqual(self.backend.redirect_target_hits, 0)

    def test_revoked_run_closes_listener_and_stop_closes_active_stream(self):
        revoked = self.make_proxy()
        self.current = False
        body = json.dumps({"model": "model", "stream": True}).encode()
        revoked_client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        revoked_client.settimeout(2.0)
        revoked_client.connect(str(revoked.socket_path))
        revoked_client.sendall(
            b"POST /v1/responses HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
            + ("Content-Length: %d\r\nConnection: close\r\n\r\n" % len(body)).encode()
            + body
        )
        self.assertIn(b" 410 ", revoked_client.recv(4096))
        revoked_client.close()
        deadline = time.monotonic() + 2.0
        while revoked.socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertFalse(revoked.socket_path.exists())
        self.current = True

        active = self.make_proxy()
        connection, response = self.request(active, "/v1/responses", {"model": "model", "stream": True})
        self.assertEqual(response.status, 200)
        self.assertTrue(self.backend.first_chunk_sent.wait(1.0))
        active.stop()
        self.assertNotIn(MARKER.encode(), response.read())
        connection.close()
        self.assertFalse(active.socket_path.exists())

    def test_revocation_during_backend_read_drops_late_chunk(self):
        proxy = self.make_proxy()
        reading = threading.Event()
        release = threading.Event()
        original_factory = proxy._new_upstream

        def upstream_factory():
            connection = original_factory()
            original_response = connection.getresponse

            def getresponse():
                response = original_response()
                original_read = response.read1
                calls = 0

                def read1(size):
                    nonlocal calls
                    calls += 1
                    if calls == 2:
                        reading.set()
                        release.wait(1.0)
                    return original_read(size)

                response.read1 = read1
                return response

            connection.getresponse = getresponse
            return connection

        proxy._new_upstream = upstream_factory
        connection, response = self.request(proxy, "/v1/responses", {"model": "model", "stream": True})
        try:
            self.assertTrue(reading.wait(1.0))
            self.current = False
            self.backend.second_chunk.set()
            release.set()
            self.assertNotIn(MARKER.encode(), response.read())
        finally:
            release.set()
            connection.close()

    def test_local_only_and_private_socket_policy_refuse_unsafe_configuration(self):
        for base_url, kind in (
            ("https://api.example.invalid", "cloud"),
            ("http://localhost:1234", "local"),
            ("http://192.0.2.1:1234", "local"),
        ):
            with self.assertRaises(amp.ModelProxyError):
                amp.BackendConfig(
                    "provider", "model", "openai-responses", kind, base_url, "mac", "mac", local_only=True
                )
        with self.assertRaises(amp.ModelProxyError):
            amp.BackendConfig(
                "provider", "model", "openai-responses", "cloud", "https://api.example.invalid", "ltfserver", "cloud",
                local_only=True
            )
        with self.assertRaises(amp.ModelProxyError):
            amp.BackendConfig(
                "provider", "model", "openai-responses", "local", "http://127.0.0.1:1234", "ltfserver", "ltfserver"
            )
        with self.assertRaises(amp.ModelProxyError):
            amp.BackendConfig(
                "provider", "model", "openai-responses", "local", "http://127.0.0.1:1234", "ltfserver", "mac"
            )

        binding = amp.ProxyBinding("world", "agent", "run", "provider", "model")
        backend = amp.BackendConfig(
            "provider", "model", "openai-responses", "local", "http://127.0.0.1:%d" % self.backend.server_port,
            "mac", "mac"
        )
        unsafe = amp.AgentsModelProxy(
            binding,
            backend,
            self.agent_write_root / "model.sock",
            self.root,
            (self.agent_write_root,),
            lambda _binding: True,
        )
        with self.assertRaises(amp.ModelProxyError):
            unsafe.start()

        public_root = self.root / "public-controller"
        public_root.mkdir(mode=0o755)
        public_proxy = amp.AgentsModelProxy(
            binding,
            backend,
            public_root / "model.sock",
            public_root,
            (self.agent_write_root,),
            lambda _binding: True,
        )
        with self.assertRaises(amp.ModelProxyError):
            public_proxy.start()

    def test_request_body_has_total_io_deadline(self):
        proxy = self.make_proxy(io_timeout=0.1)
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(1.0)
        client.connect(str(proxy.socket_path))
        client.sendall(
            b"POST /v1/responses HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
            b"Content-Length: 2\r\nConnection: close\r\n\r\n{"
        )
        self.assertIn(b" 408 ", client.recv(4096))
        client.close()
        self.assertEqual(self.backend.records, [])

    def test_local_only_unix_backend_uses_explicit_socket_without_dns(self):
        backend_path = self.root / "local-backend.sock"
        unix_backend = FakeUnixBackend(backend_path)
        backend_thread = threading.Thread(target=unix_backend.serve_forever, daemon=False)
        backend_thread.start()
        binding = amp.ProxyBinding("world", "agent", "run", "provider", "model")
        backend = amp.BackendConfig(
            "provider", "model", "openai-responses", "local", f"unix://{backend_path}", "mac", "mac",
            local_only=True
        )
        proxy = amp.AgentsModelProxy(
            binding,
            backend,
            self.controller_root / "unix-proxy.sock",
            self.controller_root,
            (self.agent_write_root,),
            lambda _binding: True,
            io_timeout=2.0,
        )
        proxy.start()
        self.proxies.append(proxy)
        unix_backend.second_chunk.set()
        try:
            connection, response = self.request(proxy, "/v1/responses", {"model": "model", "stream": True})
            self.assertEqual(response.status, 200)
            self.assertIn(MARKER.encode(), response.read())
            connection.close()
            self.assertEqual([record["path"] for record in unix_backend.records], ["/v1/responses"])
        finally:
            unix_backend.shutdown()
            unix_backend.server_close()
            backend_thread.join(2.0)
            self.assertFalse(backend_thread.is_alive())

    def test_child_process_sigterm_removes_owned_socket(self):
        child_root = self.root / "child-controller"
        child_root.mkdir(mode=0o700)
        child_socket = child_root / "model.sock"
        context = multiprocessing.get_context("spawn")
        receive, send = context.Pipe(duplex=False)
        process = context.Process(
            target=child_proxy_process,
            args=(str(child_root), str(child_socket), self.backend.server_port, send),
        )
        process.start()
        send.close()
        self.assertTrue(receive.poll(5.0))
        self.assertEqual(receive.recv(), str(child_socket))
        receive.close()
        self.assertTrue(child_socket.exists())
        os.kill(process.pid, signal.SIGTERM)
        process.join(5.0)
        if process.is_alive():
            process.kill()
            process.join(2.0)
        self.assertEqual(process.exitcode, 0)
        self.assertFalse(child_socket.exists())

    def test_auth_provider_is_read_per_request_and_failure_forwards_nothing(self):
        binding = amp.ProxyBinding("world", "agent", "run", "provider", "model")
        backend = amp.BackendConfig("provider", "model", "anthropic-messages", "local",
                                    "http://127.0.0.1:%d" % self.backend.server_port, "mac", "mac", (), True)
        tokens = ["first-controller-token"]

        def provider():
            if not tokens:
                raise RuntimeError("source unavailable")
            return (("Authorization", "Bearer " + tokens[0]),)

        with self.assertRaises(amp.ModelProxyError):
            amp.AgentsModelProxy(binding, amp.BackendConfig(
                "provider", "model", "anthropic-messages", "local",
                "http://127.0.0.1:%d" % self.backend.server_port, "mac", "mac",
                (("Authorization", "Bearer fixed"),), True),
                self.controller_root / "both.sock", self.controller_root, (), lambda _b: True,
                auth_headers_provider=provider)
        proxy = amp.AgentsModelProxy(binding, backend, self.controller_root / "provided.sock", self.controller_root,
                                     (self.agent_write_root,), lambda _b: True, io_timeout=2.0,
                                     auth_headers_provider=provider)
        proxy.start()
        self.proxies.append(proxy)
        route = "/v1/messages?beta=true"
        payload = {"model": "model", "stream": False}
        for expected in ("first-controller-token", "rotated-controller-token"):
            tokens[0] = expected
            connection, response = self.request(proxy, route, payload, {"Authorization": "Bearer placeholder"})
            self.assertEqual(response.status, 200)
            response.read()
            connection.close()
            self.assertEqual(self.backend.records[-1]["headers"].get("Authorization"), "Bearer " + expected)
        tokens.clear()
        before = len(self.backend.records)
        connection, response = self.request(proxy, route, payload)
        body = response.read()
        connection.close()
        self.assertEqual(response.status, 503)
        self.assertIn(b"controller_auth_unavailable", body)
        self.assertEqual(len(self.backend.records), before)
        tokens.append(("bad\r\nheader"))
        connection, response = self.request(proxy, route, payload)
        response.read()
        connection.close()
        self.assertEqual(response.status, 503)
        self.assertEqual(len(self.backend.records), before)
        self.assertEqual(proxy.upstream_counts(), {"200": 2, "controller_auth_unavailable": 2})
        self.assertIsNone(proxy.upstream_limit())
        # Nur weitergeleitete Anfragen zaehlen je Denkstufe; unbekannte Werte erscheinen nie im Klartext.
        self.assertEqual(proxy.request_shapes(), {"effort=- thinking=-": 2})
        tokens.clear()
        tokens.append("shape-token")
        for effort, thinking in (("xhigh", {"type": "adaptive"}), ("<secret>", {"type": "x"})):
            connection, response = self.request(proxy, route, dict(payload, output_config={"effort": effort},
                                                                   thinking=thinking))
            response.read()
            connection.close()
        self.assertEqual(proxy.request_shapes(), {"effort=- thinking=-": 3, "effort=xhigh thinking=adaptive": 1})

    def test_rate_limit_headers_reach_the_harness_and_last_rejection_is_recorded(self):
        class LimitHandler(FakeBackendHandler):
            def do_POST(inner):
                inner.rfile.read(int(inner.headers.get("Content-Length", "0")))
                body = b'{"type":"error","error":{"type":"rate_limit_error"}}'
                inner.send_response(429)
                inner.send_header("Content-Type", "application/json")
                inner.send_header("retry-after", "120")
                inner.send_header("anthropic-ratelimit-unified-status", "rejected")
                inner.send_header("anthropic-ratelimit-unified-reset", "1800000000")
                inner.send_header("anthropic-ratelimit-unified-overage-note", "bad\u00e4value".encode().decode("latin-1"))
                inner.send_header("x-internal-secret", "never-forwarded")
                inner.send_header("Content-Length", str(len(body)))
                inner.end_headers()
                inner.wfile.write(body)

        self.backend.RequestHandlerClass = LimitHandler
        proxy = self.make_proxy("anthropic-messages")
        connection, response = self.request(proxy, "/v1/messages?beta=true", {"model": "model", "stream": True})
        response.read()
        headers = {name.lower(): value for name, value in response.getheaders()}
        connection.close()
        self.assertEqual(response.status, 429)
        self.assertEqual(headers.get("retry-after"), "120")
        self.assertEqual(headers.get("anthropic-ratelimit-unified-status"), "rejected")
        self.assertEqual(headers.get("anthropic-ratelimit-unified-reset"), "1800000000")
        self.assertNotIn("x-internal-secret", headers)
        self.assertNotIn("anthropic-ratelimit-unified-overage-note", headers)
        limit = proxy.upstream_limit()
        self.assertEqual((limit["status"], limit["headers"]["anthropic-ratelimit-unified-reset"]), (429, "1800000000"))
        self.assertEqual(proxy.upstream_counts(), {"429": 1})


if __name__ == "__main__":
    unittest.main()
