"""Tests for quassel_dictate.py against a fake whisper server.

Run: QUASSEL_APP=<dir with the quassel/ package> python3 -m pytest tests/
QUASSEL_APP defaults to the installed copy (~/.local/share/work-kit/quassel/app).
"""
import email.parser
import http.server
import os
import subprocess
import sys
import threading
import time
import wave

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "quassel_dictate.py")
APP = os.environ.get("QUASSEL_APP",
                     os.path.expanduser("~/.local/share/work-kit/quassel/app"))
pytestmark = pytest.mark.skipif(not os.path.isfile(os.path.join(APP, "quassel", "config.py")),
                                reason="Quassel app source not found (set QUASSEL_APP)")
sys.path.insert(0, os.path.dirname(SCRIPT))
import quassel_dictate as qd  # noqa: E402


class FakeWhisper(http.server.BaseHTTPRequestHandler):
    requests = []

    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        msg = email.parser.BytesParser().parsebytes(
            b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + body)
        fields = {p.get_param("name", header="content-disposition"): p.get_payload(decode=True)
                  for p in msg.get_payload()}
        FakeWhisper.requests.append((self.path, fields))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(" hallo welt\n".encode())

    def log_message(self, *a):
        pass


@pytest.fixture()
def server():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeWhisper)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    FakeWhisper.requests = []
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


@pytest.fixture()
def env(tmp_path, server):
    raw = tmp_path / "speech.raw"
    raw.write_bytes(b"\x00\x10" * 16000)            # one second of 16 kHz mono
    rec = tmp_path / "rec.sh"
    rec.write_text(f"#!/bin/sh\ncat '{raw}'\nexec sleep 30\n")
    rec.chmod(0o755)
    e = dict(os.environ, HOME=str(tmp_path / "home"), XDG_RUNTIME_DIR=str(tmp_path / "run"),
             XDG_CONFIG_HOME=str(tmp_path / "home/.config"),
             XDG_DATA_HOME=str(tmp_path / "home/.local/share"),
             PYTHONPATH=APP, QUASSEL_DICTATE_SERVER=server, QUASSEL_DICTATE_RECORD_CMD=str(rec),
             PATH=str(tmp_path / "nobin") + ":/usr/bin:/bin")   # no clipboard tool
    return e, tmp_path


def run(e, *args):
    return subprocess.run([sys.executable, SCRIPT, *args], env=e, capture_output=True,
                          text=True, timeout=30)


def wait_for(pred, seconds=15):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if pred():
            return True
        time.sleep(0.1)
    return False


def test_curl_args_roundtrip(tmp_path):
    wav = tmp_path / "a.wav"
    args = ["curl", "-fsS", "-m", "120", "http://127.0.0.1:8765/inference",
            "-F", f"file=@{wav}", "-F", "response_format=text", "-F", "prompt=a=b, c"]
    url, fields, path = qd.curl_args_to_request(args)
    assert url == "http://127.0.0.1:8765/inference"
    assert fields == [("response_format", "text"), ("prompt", "a=b, c")]
    assert path == str(wav)


def test_toggle_records_transcribes_and_falls_back_to_file(env):
    e, tmp = env
    assert run(e, "status").stdout.strip() == "idle"
    assert run(e, "toggle").returncode == 0
    assert wait_for(lambda: run(e, "status").stdout.strip() == "recording")
    time.sleep(0.5)
    assert run(e, "toggle").returncode == 0                 # second press stops
    last = tmp / "run" / "quassel-kit" / "last.txt"
    assert wait_for(last.exists)
    assert last.read_text().strip() == "Hallo welt"        # Quassel's own post-processing
    assert oct(last.stat().st_mode & 0o777) == "0o600"
    path, fields = FakeWhisper.requests[-1]
    assert path == "/inference"
    assert fields["response_format"] == b"text"
    with wave.open(__import__("io").BytesIO(fields["file"])) as w:
        assert (w.getframerate(), w.getnchannels()) == (16000, 1)
        assert w.getnframes() >= 16000
    assert wait_for(lambda: run(e, "status").stdout.strip() == "idle")


def test_cancel_sends_nothing(env):
    e, _ = env
    run(e, "start")
    assert wait_for(lambda: run(e, "status").stdout.strip() == "recording")
    run(e, "cancel")
    assert wait_for(lambda: run(e, "status").stdout.strip() == "idle")
    assert FakeWhisper.requests == []
