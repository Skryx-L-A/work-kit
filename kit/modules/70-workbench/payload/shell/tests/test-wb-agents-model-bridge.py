#!/usr/bin/env python3
"""Targeted socket tests for the agents model bridge."""
from __future__ import annotations

import socket
import contextlib
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
from agents_model_bridge import ModelBridge


def _read_exact(sock: socket.socket, size: int, timeout: float = 1.0) -> bytes:
    sock.settimeout(timeout)
    data = bytearray()
    deadline = time.time() + timeout
    while len(data) < size and time.time() < deadline:
        chunk = sock.recv(size - len(data))
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def _start_streaming_unix_server(path: Path, payload_chunk: int = 4096):
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    path.unlink(missing_ok=True)
    try:
        listener.bind(str(path))
    except OSError:
        listener.close()
        raise
    listener.listen(4)
    listener.settimeout(0.1)

    stopped = threading.Event()

    def _serve():
        try:
            while not stopped.is_set():
                try:
                    conn, _ = listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                with conn:
                    conn.settimeout(1.0)
                    try:
                        conn.sendall(b"hello")
                        while not stopped.is_set():
                            chunk = conn.recv(payload_chunk)
                            if not chunk:
                                return
                            for offset in range(0, len(chunk), payload_chunk):
                                if stopped.is_set():
                                    return
                                conn.sendall(chunk[offset:offset + payload_chunk])
                                time.sleep(0.002)
                    except OSError:
                        pass
                if stopped.is_set():
                    return
        finally:
            listener.close()
            with contextlib.suppress(OSError):
                path.unlink()
            stopped.set()

    thread = threading.Thread(target=_serve, daemon=True)
    thread.start()
    return listener, thread, stopped


class ModelBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="wb-mb-", dir="/tmp")
        self.sock_path = Path(self.tmp.name) / "m.sock"
        try:
            self.listener, self.server_thread, self.server_stopped = _start_streaming_unix_server(self.sock_path)
        except OSError:
            self.tmp.cleanup()
            raise
        self.clients = []
        self.bridge = ModelBridge(self.sock_path, max_connections=4, idle_timeout=0.4)
        _, port = self.bridge.url.split("://", 1)[1].split(":")
        self.port = int(port)

    def tearDown(self):
        self.bridge.close()
        for client in self.clients:
            client.close()
        self.server_stopped.set()
        with contextlib.suppress(OSError):
            self.listener.close()
        self.server_thread.join(timeout=1.0)
        self.assertFalse(self.server_thread.is_alive())
        self.tmp.cleanup()

    def test_duplex_streaming_small_payload(self):
        client = socket.create_connection(("127.0.0.1", self.port), timeout=1.0)
        self.clients.append(client)
        self.assertEqual(_read_exact(client, len(b"hello")), b"hello")

        send_payload = b"abcdef1234" * 7000
        got = bytearray()
        sender = threading.Thread(
            target=lambda: client.sendall(send_payload)
        )
        sender.start()

        while len(got) < len(send_payload):
            got.extend(client.recv(7))
        sender.join(timeout=1.0)
        self.assertFalse(sender.is_alive())

        self.assertEqual(bytes(got), send_payload)
        client.close()
        self._await_threads(include_accept=False)

    def test_close_with_active_client(self):
        client = socket.create_connection(("127.0.0.1", self.port), timeout=1.0)
        self.clients.append(client)
        self.assertEqual(_read_exact(client, 5), b"hello")

        self.bridge.close()
        client.settimeout(1.0)
        eof = client.recv(16)
        self.assertEqual(eof, b"")
        self._await_threads(include_accept=True)

    def test_idle_timeout_closes_connection_and_threads(self):
        client = socket.create_connection(("127.0.0.1", self.port), timeout=1.0)
        self.clients.append(client)
        self.assertEqual(_read_exact(client, 5), b"hello")
        client.settimeout(1.0)
        self.assertEqual(client.recv(1), b"")
        self._await_threads(include_accept=False)
        self.bridge.close()
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", self.port), timeout=0.2)

    def _await_threads(self, include_accept: bool = False):
        end = time.time() + 1.0
        while time.time() < end:
            active = False
            if include_accept and self.bridge._accept_thread.is_alive():
                active = True
            for thread in tuple(self.bridge._threads):
                if thread.is_alive():
                    active = True
            if not active:
                return
            time.sleep(0.05)
        if include_accept:
            self.assertFalse(self.bridge._accept_thread.is_alive())
        for thread in tuple(self.bridge._threads):
            self.assertFalse(thread.is_alive())


if __name__ == "__main__":
    unittest.main()
