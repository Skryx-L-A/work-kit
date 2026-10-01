"""Tests for the `meeting` CLI against a fake whisper server, a fake recorder and a fake brain.

Run: python3 -m pytest tests/   (no network, no audio hardware, no real whisper)
Every test uses its own HOME under tmp_path.
"""
import http.server
import json
import os
import socket
import stat
import subprocess
import sys
import threading
import time
import wave

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
MEETING = os.path.join(HERE, "..", "meeting")

FAKE_TEXT = "Wir beschliessen das Release am Freitag."


class FakeWhisper(http.server.BaseHTTPRequestHandler):
    requests = []
    auths = []  # Authorization header of every request ("" when absent)
    need_auth = None  # when set, summary requests without exactly this Authorization get 401
    fmt = "verbose_json"
    fail500 = None  # (log path, log text): answer /inference with 500 after appending the text to the log

    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        FakeWhisper.requests.append((self.path, body))
        auth = self.headers.get("Authorization") or ""
        FakeWhisper.auths.append(auth)
        if FakeWhisper.need_auth and self.path.endswith("/chat/completions") and auth != FakeWhisper.need_auth:
            self.send_response(401)
            self.end_headers()
            return
        if self.path.endswith("/chat/completions"):
            out = {"choices": [{"message": {"content": "SUMMARY: release on Friday"}}]}
            self._send(json.dumps(out))
            return
        if FakeWhisper.fail500:
            log, text = FakeWhisper.fail500
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a") as f:
                f.write(text)
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"whisper failed")
            return
        if FakeWhisper.fmt == "text":
            self._send(FAKE_TEXT)
            return
        out = {"text": FAKE_TEXT, "segments": [
            {"start": 0.0, "end": 2.0, "text": " Wir beschliessen"},
            {"start": 3725.0, "end": 3727.0, "text": " das Release am Freitag."}]}
        self._send(json.dumps(out))

    def _send(self, text):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(text.encode())

    def log_message(self, *a):
        pass


@pytest.fixture()
def server():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeWhisper)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    FakeWhisper.requests = []
    FakeWhisper.auths = []
    FakeWhisper.need_auth = None
    FakeWhisper.fmt = "verbose_json"
    yield "http://127.0.0.1:%d" % srv.server_address[1]
    srv.shutdown()


def write_wav(path, seconds=1.0, value=1000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(value.to_bytes(2, "little", signed=True) * int(16000 * seconds))


FAKE_RECORDER = '''#!/usr/bin/env python3
# Fake pw-record: waits, writes a WAV on SIGINT/SIGTERM like the real tools do.
import signal, sys, time, wave
out = sys.argv[1]
value = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
def done(*_):
    with wave.open(out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(value.to_bytes(2, "little", signed=True) * 16000)
    sys.exit(0)
signal.signal(signal.SIGINT, done)
signal.signal(signal.SIGTERM, done)
open(out + ".ready", "w").close()          # handlers are installed: safe to stop now
time.sleep(60)
'''

FAKE_BRAIN = '''#!/bin/sh
# Fake brain: records its arguments and stdin.
printf '%s\\n' "$*" >> "$FAKE_BRAIN_LOG"
cat > "$FAKE_BRAIN_LOG.stdin"
echo "projects/x/note.md"
[ -n "$FAKE_BRAIN_FAIL" ] && { echo "brain broke" >&2; exit 1; }
exit 0
'''

# Fake whisper-server binary for 80-quassel's server.env: serves the fake reply on --port.
FAKE_ENGINE = '''#!/usr/bin/env python3
import http.server, json, sys
port = int(sys.argv[sys.argv.index("--port") + 1])
open(sys.argv[0] + ".args", "w").write(" ".join(sys.argv[1:]))
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(200); self.end_headers()
        self.wfile.write(json.dumps({"text": "engine started on demand"}).encode())
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
'''


def make_exe(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


@pytest.fixture()
def env(tmp_path, server):
    home = tmp_path / "home"
    (home / ".config/work-kit").mkdir(parents=True)
    rec = make_exe(tmp_path / "rec.py", FAKE_RECORDER)
    e = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
             KIT_DATA_DIR=str(home / ".local/share/work-kit"),
             MEETING_WHISPER_URL=server, MEETING_RECORD_CMD="%s {out}" % rec,
             PATH=str(tmp_path / "nobin") + ":/usr/bin:/bin")
    for k in ("MEETING_STORE", "MEETING_SUMMARY_URL", "MEETING_SUMMARY_KEY", "KIT_MODELS_PROXY_KEY",
              "QUASSEL_KIT_HOME"):
        e.pop(k, None)
    return e, tmp_path, home


def run(e, *args, stdin=""):
    return subprocess.run([sys.executable, MEETING, *args], env=e, capture_output=True,
                          text=True, timeout=60, input=stdin)


def start(e, *args):
    """`meeting start` with consent, then wait until the fake recorders are ready for SIGINT
    (a python3 shim can start slowly, and a signal before the handler exists kills it)."""
    r = run(e, "start", "--consent-given", *args)
    want = 2 if "both" in args else 1
    home = e["HOME"]
    d = os.path.join(home, ".local/share/work-kit/meeting-capture/state/audio")
    end = time.time() + 20
    while r.returncode == 0 and time.time() < end:
        if os.path.isdir(d) and len([f for f in os.listdir(d) if f.endswith(".ready")]) >= want:
            break
        time.sleep(0.05)
    return r


def audio_dir(home):
    return home / ".local/share/work-kit/meeting-capture/state/audio"


def meetings(home):
    d = home / "work/meetings"
    return sorted(d.glob("*.md")) if d.exists() else []


def test_consent_reminder_shown_and_required(env):
    e, _, home = env
    r = run(e, "start", stdin="n\n")                # stdin is not a tty: no prompt possible
    assert "CONSENT REMINDER" in r.stderr
    assert r.returncode == 1 and "--consent-given" in r.stderr
    assert not audio_dir(home).exists() or not list(audio_dir(home).iterdir())
    assert run(e, "status").stdout.strip() == "idle"


def test_start_stop_writes_file_note_without_brain(env):
    e, _, home = env
    r = start(e, "--title", "Sprint review",
            "--participants", "Anna, Ben")
    assert r.returncode == 0, r.stderr
    assert "CONSENT REMINDER" in r.stderr           # shown on every start, also with the flag
    assert run(e, "status").stdout.startswith("recording since")
    assert run(e, "start", "--consent-given").returncode == 1     # second start refused
    r = run(e, "stop")
    assert r.returncode == 0, r.stderr
    notes = meetings(home)
    assert len(notes) == 1 and "sprint-review" in notes[0].name
    text = notes[0].read_text()
    assert "Meeting: Sprint review" in text and "Participants: Anna, Ben" in text
    assert "Consent: confirmed" in text
    assert "[00:00:00] Wir beschliessen" in text and "[01:02:05] das Release am Freitag." in text
    assert "## Summary" in text and "Not generated" in text
    assert stat.S_IMODE(notes[0].stat().st_mode) == 0o600
    assert not list(audio_dir(home).glob("*.wav"))       # audio deleted after the transcript
    assert run(e, "status").stdout.strip() == "idle"
    reqs = [b for p, b in FakeWhisper.requests if p == "/inference"]
    assert len(reqs) == 1 and b"RIFF" in reqs[0] and b"verbose_json" in reqs[0]


def test_plain_text_reply_and_language(env):
    e, _, home = env
    FakeWhisper.fmt = "text"
    start(e)
    r = run(e, "stop", "--language", "de")
    assert r.returncode == 0, r.stderr
    assert FAKE_TEXT in meetings(home)[0].read_text()
    assert b'name="language"\r\n\r\nde' in FakeWhisper.requests[-1][1]


def test_note_goes_to_brain_when_available(env):
    e, tmp, home = env
    bindir = tmp / "bin"
    bindir.mkdir()
    make_exe(bindir / "brain", FAKE_BRAIN)
    e["PATH"] = str(bindir) + ":" + e["PATH"]
    e["FAKE_BRAIN_LOG"] = str(tmp / "brain.log")
    start(e, "--title", "Kickoff", "--project", "billing")
    r = run(e, "stop")
    assert r.returncode == 0, r.stderr
    assert "brain note" in r.stdout
    args = (tmp / "brain.log").read_text()
    assert args.startswith("new note Meeting: Kickoff (") and "--project billing" in args
    assert args.strip().endswith("--body -")
    body = (tmp / "brain.log.stdin").read_text()
    assert "## Transcript" in body and "Wir beschliessen" in body
    assert meetings(home) == []                      # nothing written to files


def test_brain_failure_falls_back_to_files(env):
    e, tmp, home = env
    bindir = tmp / "bin"
    bindir.mkdir()
    make_exe(bindir / "brain", FAKE_BRAIN)
    e.update(PATH=str(bindir) + ":" + e["PATH"], FAKE_BRAIN_LOG=str(tmp / "b.log"),
             FAKE_BRAIN_FAIL="1")
    start(e)
    r = run(e, "stop")
    assert r.returncode == 0 and "instead" in r.stderr
    assert len(meetings(home)) == 1


def test_transcript_kept_out_of_brain(env):
    e, tmp, home = env
    bindir = tmp / "bin"
    bindir.mkdir()
    make_exe(bindir / "brain", FAKE_BRAIN)
    e.update(PATH=str(bindir) + ":" + e["PATH"], FAKE_BRAIN_LOG=str(tmp / "b.log"),
             MEETING_TRANSCRIPT_IN_BRAIN="no")
    start(e, "--title", "Secret")
    assert run(e, "stop").returncode == 0
    body = (tmp / "b.log.stdin").read_text()
    assert "Wir beschliessen" not in body and "Stored outside the brain" in body
    assert any("Wir beschliessen" in p.read_text() for p in (home / "work/meetings").glob("*.transcript.md"))


def test_no_engine_prints_install_hint_and_keeps_audio(env):
    e, _, home = env
    e.pop("MEETING_WHISPER_URL")
    start(e)
    r = run(e, "stop")
    assert r.returncode == 3
    assert "80-quassel" in r.stderr and "Audio kept" in r.stderr
    wavs = list(audio_dir(home).glob("*.wav"))
    assert len(wavs) == 1
    assert "meeting transcribe" in r.stderr and str(wavs[0]) in r.stderr
    assert meetings(home) == []


def test_engine_started_on_demand_from_quassel_env_and_stopped(env):
    e, tmp, home = env
    e.pop("MEETING_WHISPER_URL")
    binary = make_exe(tmp / "run-server.py", FAKE_ENGINE)
    model = tmp / "ggml-small.bin"
    model.write_bytes(b"model")
    cdir = home / ".config/quassel"
    cdir.mkdir(parents=True)
    (cdir / "server.env").write_text("SERVER_BIN=%s\nMODEL_PATH=%s\nWHISPER_THREADS=2\n"
                                     "WHISPER_DECODE=-nf\n" % (binary, model))
    start(e)
    r = run(e, "stop", "--keep-audio")
    assert r.returncode == 0, r.stderr
    assert "engine started on demand" in meetings(home)[0].read_text()
    args = open(str(binary) + ".args").read()
    assert "-m %s" % model in args and "-t 2" in args and "-l auto" in args
    assert "--host 127.0.0.1" in args
    port = args.split("--port ")[1].split()[0]
    time.sleep(0.3)
    with socket.socket() as s:                       # engine must be gone after the run
        assert s.connect_ex(("127.0.0.1", int(port))) != 0
    assert list(audio_dir(home).glob("*.wav"))       # --keep-audio


def test_remote_whisper_url_refused(env):
    e, _, home = env
    e["MEETING_WHISPER_URL"] = "http://whisper.example.com:8765"
    start(e)
    r = run(e, "stop")
    assert r.returncode == 1 and "not on this machine" in r.stderr
    assert list(audio_dir(home).glob("*.wav"))       # audio kept for a retry


def test_source_both_mixes_two_tracks(env):
    e, tmp, home = env
    rec = tmp / "rec2.py"
    make_exe(rec, FAKE_RECORDER)
    # {source} decides the sample value: mic 1000, system 2000
    wrapper = make_exe(tmp / "rec-by-source.sh", '#!/bin/sh\nv=1000\n[ "$2" = system ] && v=2000\n'
                       'exec %s "$1" $v\n' % rec)
    e["MEETING_RECORD_CMD"] = "%s {out} {source}" % wrapper
    e["MEETING_STORE"] = "files"
    assert start(e, "--source", "both").returncode == 0
    r = run(e, "stop", "--keep-audio")
    assert r.returncode == 0, r.stderr
    mixed = list(audio_dir(home).glob("mixed-*.wav"))
    assert len(mixed) == 1
    with wave.open(str(mixed[0])) as w:
        assert int.from_bytes(w.readframes(1), "little", signed=True) == 3000
    assert len(list(audio_dir(home).glob("*.wav"))) == 3


def test_both_deletes_all_tracks_without_keep(env):
    e, tmp, home = env
    e["MEETING_RECORD_CMD"] = "%s {out}" % (tmp / "rec.py")
    start(e, "--source", "both")
    assert run(e, "stop").returncode == 0
    assert not list(audio_dir(home).glob("*.wav"))


def test_cancel_deletes_recording(env):
    e, _, home = env
    start(e)
    assert run(e, "cancel").returncode == 0
    assert not list(audio_dir(home).glob("*.wav"))
    assert run(e, "status").stdout.strip() == "idle"
    assert meetings(home) == []


def test_no_recorder_reports_install_hint(env):
    e, _, _ = env
    e.pop("MEETING_RECORD_CMD")
    r = run(e, "start", "--consent-given")
    assert r.returncode == 1 and "pw-record or parecord" in r.stderr


def test_real_recorder_command_lines(env, tmp_path):
    e, tmp, _ = env
    e.pop("MEETING_RECORD_CMD")
    bindir = tmp / "bin"
    bindir.mkdir()
    for name in ("pw-record", "parecord"):
        make_exe(bindir / name, '#!/bin/sh\necho "$0 $*" > "%s/$(basename $0).args"\nexec sleep 30\n' % tmp)
        e["PATH"] = str(bindir) + ":" + e["PATH"]
        assert run(e, "start", "--consent-given", "--source", "system").returncode == 0
        args = (tmp / (name + ".args")).read_text()
        assert "16000" in args
        assert ("stream.capture.sink=true" if name == "pw-record" else "@DEFAULT_MONITOR@") in args
        run(e, "cancel")
        (bindir / name).unlink()


def test_transcribe_existing_file_keeps_unmanaged_audio(env):
    e, tmp, home = env
    wav = tmp / "call.wav"
    write_wav(wav)
    r = run(e, "transcribe", str(wav), "--title", "Imported call")
    assert r.returncode == 0, r.stderr
    assert wav.exists() and "not recorded by `meeting`" in r.stderr
    assert "Imported call" in meetings(home)[0].read_text()


def whisper_log(home):
    return str(home / ".local/share/work-kit/meeting-capture/state/whisper-server.log")


def test_transcribe_without_speech_is_not_an_error(env):
    e, tmp, home = env
    wav = tmp / "tone.wav"
    write_wav(wav)
    FakeWhisper.fail500 = (whisper_log(home), "whisper_vad_segments_from_probs: Final speech segments after filtering: 0\n")
    try:
        r = run(e, "transcribe", str(wav))
    finally:
        FakeWhisper.fail500 = None
    assert "No speech recognized" in r.stderr and "HTTP" not in r.stderr, r.stderr
    assert wav.exists()


def test_transcribe_server_error_names_code_body_and_log(env):
    e, tmp, home = env
    wav = tmp / "call.wav"
    write_wav(wav)
    FakeWhisper.fail500 = (whisper_log(home), "some other failure\n")
    try:
        r = run(e, "transcribe", str(wav))
    finally:
        FakeWhisper.fail500 = None
    assert r.returncode == 1
    assert "HTTP 500: whisper failed" in r.stderr and "whisper-server.log" in r.stderr, r.stderr
    assert wav.exists()


def test_transcribe_rejects_non_wav(env):
    e, tmp, _ = env
    bad = tmp / "x.m4a"
    bad.write_bytes(b"not a wav")
    r = run(e, "transcribe", str(bad))
    assert r.returncode == 1 and "ffmpeg" in r.stderr


def test_summary_with_local_model(env, server):
    e, tmp, home = env
    e["MEETING_SUMMARY_URL"] = server
    start(e)
    r = run(e, "stop", "--summarize")
    assert r.returncode == 0, r.stderr
    text = meetings(home)[0].read_text()
    assert "SUMMARY: release on Friday" in text and "Machine-made" in text
    assert any(p == "/chat/completions" for p, _ in FakeWhisper.requests)


def summary_auths():
    """Authorization headers of the summary requests only (the transcription request has none)."""
    return [a for (p, _), a in zip(FakeWhisper.requests, FakeWhisper.auths) if p.endswith("/chat/completions")]


def summarize_with(e, url):
    e["MEETING_SUMMARY_URL"] = url
    start(e)
    return run(e, "stop", "--summarize")


def test_summary_sends_meeting_summary_key_and_never_prints_it(env, server):
    e, _, home = env
    e["MEETING_SUMMARY_KEY"] = "sk-meeting-secret"
    FakeWhisper.need_auth = "Bearer sk-meeting-secret"
    r = summarize_with(e, server)
    assert r.returncode == 0, r.stderr
    assert summary_auths() == ["Bearer sk-meeting-secret"]
    assert "SUMMARY: release on Friday" in meetings(home)[0].read_text()
    for out in (r.stdout, r.stderr, meetings(home)[0].read_text()):
        assert "sk-meeting-secret" not in out
    for p in home.rglob("*"):
        if p.is_file():
            assert b"sk-meeting-secret" not in p.read_bytes(), p


def test_summary_without_any_key_sends_no_authorization(env, server):
    e, _, _ = env
    e["KIT_MODELS_PROXY_KEY"] = "kit-token"  # not the kit-models proxy URL: must not leave the machine part
    r = summarize_with(e, server)  # loopback, but not under /e/<endpoint>
    assert r.returncode == 0, r.stderr
    assert summary_auths() == [""]


def test_summary_via_kit_models_proxy_uses_the_token_from_the_environment(env, server):
    e, _, home = env
    e["KIT_MODELS_PROXY_KEY"] = "kit-token-env"
    FakeWhisper.need_auth = "Bearer kit-token-env"
    r = summarize_with(e, server + "/e/corp/v1")
    assert r.returncode == 0, r.stderr
    assert summary_auths() == ["Bearer kit-token-env"]
    assert "SUMMARY: release on Friday" in meetings(home)[0].read_text()
    assert "kit-token-env" not in r.stdout + r.stderr


def test_summary_via_kit_models_proxy_reads_the_token_file(env, server):
    e, _, home = env
    tok = home / ".local/share/work-kit/model-endpoints/proxy.token"
    tok.parent.mkdir(parents=True)
    tok.write_text("kit-token-file\n")
    FakeWhisper.need_auth = "Bearer kit-token-file"
    r = summarize_with(e, server + "/e/corp/v1")
    assert r.returncode == 0, r.stderr
    assert summary_auths() == ["Bearer kit-token-file"]


def test_meeting_summary_key_wins_over_the_proxy_token(env, server):
    e, _, _ = env
    e["MEETING_SUMMARY_KEY"] = "explicit"
    e["KIT_MODELS_PROXY_KEY"] = "kit-token-env"
    summarize_with(e, server + "/e/corp/v1")
    assert summary_auths() == ["Bearer explicit"]


def test_summary_401_names_the_fix_without_the_key(env, server):
    e, _, home = env
    e["MEETING_SUMMARY_KEY"] = "wrong-key"
    FakeWhisper.need_auth = "Bearer right-key"
    r = summarize_with(e, server)
    assert r.returncode == 0
    assert "Summary failed" in r.stderr and "MEETING_SUMMARY_KEY" in r.stderr
    assert "wrong-key" not in r.stdout + r.stderr
    assert "Not generated" in meetings(home)[0].read_text()


def test_summary_refuses_remote_model(env):
    e, _, home = env
    e["MEETING_SUMMARY_URL"] = "https://api.example.com/v1"
    start(e)
    r = run(e, "stop", "--summarize")
    assert r.returncode == 0 and "not on this machine" in r.stderr
    assert "Not generated" in meetings(home)[0].read_text()


def test_engine_report(env):
    e, _, _ = env
    r = run(e, "engine")
    assert r.returncode == 0 and "configured server" in r.stdout and "recorder:" in r.stdout
    e.pop("MEETING_WHISPER_URL")
    r = run(e, "engine")
    assert r.returncode == 1 and "80-quassel" in r.stdout


def test_purge(env):
    e, tmp, home = env
    d = home / "work/meetings"
    d.mkdir(parents=True)
    old, new = d / "old.md", d / "new.md"
    old.write_text("x")
    new.write_text("y")
    ancient = time.time() - 200 * 86400
    os.utime(old, (ancient, ancient))
    r = run(e, "purge")
    assert r.returncode == 1 and "retention" in r.stderr.lower()
    r = run(e, "purge", "--days", "90")
    assert r.returncode == 0 and not old.exists() and new.exists()


def test_policy_todo_lists_open_questions(env):
    e, _, home = env
    assert run(e, "policy").returncode == 1          # not installed in this HOME
    src = os.path.join(HERE, "..", "policy", "meeting-ai-policy.md")
    (home / ".config/work-kit/meeting-ai-policy.md").write_text(open(src).read())
    r = run(e, "policy", "--todo")
    assert r.returncode == 0 and "TODO(ask IT)" in r.stdout and "open question(s) for IT" in r.stdout


def test_policy_template_covers_required_topics():
    text = open(os.path.join(HERE, "..", "policy", "meeting-ai-policy.md")).read()
    for needle in ("every participant", "works council", "TODO(ask IT)", "Retention",
                   "Where audio and transcripts may be stored", "Which models may summarize",
                   "research-company-ai-setups.md", "section 12"):
        assert needle.lower() in text.lower(), needle
