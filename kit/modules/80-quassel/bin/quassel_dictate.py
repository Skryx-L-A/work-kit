#!/usr/bin/env python3
"""work-kit-quassel-dictate: dictation without keyboard access (no root needed).

Bind `work-kit-quassel-dictate toggle` to a desktop keyboard shortcut. First press starts recording,
second press stops it, the local whisper server transcribes, and the text lands in the
clipboard (paste with Ctrl+V). When Quassel's virtual keyboard (ydotoold) is usable, the
text is pasted directly instead.

It reuses the installed Quassel modules (recording command, request fields, dictionary,
text replacements, history) and never needs /dev/input or /dev/uinput.

Usage: work-kit-quassel-dictate <toggle|start|stop|cancel|status> [--no-paste]
       work-kit-quassel-dictate -h | --help
"""
import os
import signal
import subprocess
import sys
import time
import urllib.request
import uuid
import wave

MAX_SECONDS = int(os.environ.get("QUASSEL_DICTATE_MAX_SECONDS", "300"))
SERVER_WAIT = 90          # seconds: first request after start loads the model
RUNDIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/quassel-kit-{os.getuid()}",
                      "quassel-kit")
PIDFILE = os.path.join(RUNDIR, "dictate.pid")
RAW = os.path.join(RUNDIR, "dictate.raw")
WAV = os.path.join(RUNDIR, "dictate.wav")
LAST = os.path.join(RUNDIR, "last.txt")
LOG = os.path.join(RUNDIR, "dictate.log")


def log(msg):
    os.makedirs(RUNDIR, mode=0o700, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")


def notify(text, ms=4000):
    try:
        subprocess.run(["notify-send", "-a", "Quassel", "-t", str(ms), "Quassel", text],
                       check=False, timeout=5, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass
    print(text, file=sys.stderr)


def session_pid():
    try:
        with open(PIDFILE, encoding="ascii") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


# --- HTTP ------------------------------------------------------------------------------

def curl_args_to_request(args):
    """Turn Quassel's curl argument list into (url, fields, filepath).

    Keeps the exact form fields Quassel sends (language, prompt, audio_ctx, ...), so this
    helper behaves like the app, without needing curl on the system."""
    url, fields, filepath = None, [], None
    it = iter(range(len(args)))
    for i in it:
        a = args[i]
        if a == "-F" and i + 1 < len(args):
            key, _, val = args[i + 1].partition("=")
            if val.startswith("@"):
                filepath = val[1:]
            else:
                fields.append((key, val))
            next(it, None)
        elif a == "-m":
            next(it, None)
        elif a.startswith("http://") or a.startswith("https://"):
            url = a
    return url, fields, filepath


def multipart(fields, filepath):
    boundary = "----quassel-kit-" + uuid.uuid4().hex
    parts = []
    for k, v in fields:
        parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n'
                      f"{v}\r\n").encode("utf-8"))
    with open(filepath, "rb") as f:
        data = f.read()
    name = os.path.basename(filepath)
    parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
                  f'filename="{name}"\r\nContent-Type: audio/wav\r\n\r\n').encode("utf-8")
                 + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def post_inference(args, timeout=None):
    url, fields, filepath = curl_args_to_request(args)
    if not url or not filepath:
        raise ValueError("cannot read the request from Quassel's arguments")
    if timeout is None:
        # Generous: a slow laptop CPU transcribes slower than real time (measured ~20x in an
        # emulated VM). 10 minutes plus 20 s per second of audio.
        try:
            with wave.open(filepath) as w:
                secs = w.getnframes() / float(w.getframerate() or 16000)
        except Exception:
            secs = 60
        timeout = 600 + 20 * secs
    body, ctype = multipart(fields, filepath)
    req = urllib.request.Request(url, data=body, headers={"Content-Type": ctype})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=timeout) as r:
        return r.read().decode("utf-8", errors="replace")


# --- session ---------------------------------------------------------------------------

def write_wav(raw_path, wav_path, rate):
    with open(raw_path, "rb") as f:
        pcm = f.read()
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    return len(pcm) / (2 * rate)


def refine(text, cfg):
    from quassel import config, textproc, textreplace
    kind, out = textproc.postprocess(text, cfg)
    if kind is None:
        return ""
    if kind == "command":          # spoken commands need a target window; keep the words
        out = " ".join(text.split())
    if getattr(cfg, "programmer_mode", False):
        from quassel import progmode
        out = progmode.apply(out)
    if getattr(cfg, "text_replace", False):
        rules = config.replacement_rules()
        if rules:
            out = textreplace.apply_rules(out, rules)
    return out


def can_type():
    sock = os.environ.get("YDOTOOL_SOCKET") or os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", ""), ".ydotool_socket")
    return os.path.exists(sock) and os.access("/dev/uinput", os.W_OK)


def deliver(text, allow_paste):
    from quassel import platform_linux as pl
    try:
        if allow_paste and can_type():
            pl.paste(text)
            return "pasted"
        pl.clip_copy(text)
        time.sleep(0.3)
        if pl.clip_read().strip() == text.strip():
            return "clipboard"
    except OSError as e:                  # clipboard tool missing: never lose the text
        log(f"clipboard failed: {e}")
    return "file"


def run_session(allow_paste):
    from quassel import audio, config, whisperclient
    stop = {"why": None}
    signal.signal(signal.SIGUSR1, lambda *_: stop.__setitem__("why", "stop"))
    signal.signal(signal.SIGTERM, lambda *_: stop.__setitem__("why", "cancel"))
    if os.environ.get("QUASSEL_DICTATE_SERVER"):       # tests use their own port
        whisperclient.SERVER = os.environ["QUASSEL_DICTATE_SERVER"]
    cfg = config.Cfg()
    cmd = os.environ.get("QUASSEL_DICTATE_RECORD_CMD")
    cmd = cmd.split() if cmd else audio.record_command(cfg.mic)
    if not cmd:
        notify("No recorder found (pw-record or parecord). Install PipeWire or PulseAudio tools.")
        return 1
    if not whisperclient.server_up(timeout=1):
        whisperclient.STARTER()          # load the model while the user speaks
    os.makedirs(RUNDIR, mode=0o700, exist_ok=True)
    with open(RAW, "wb") as raw:
        rec = subprocess.Popen(cmd, stdout=raw, stderr=subprocess.DEVNULL)
    notify("Recording. Press the shortcut again to stop.", 2500)
    started = time.monotonic()
    while stop["why"] is None and rec.poll() is None:
        if time.monotonic() - started > MAX_SECONDS:
            stop["why"] = "stop"
            break
        time.sleep(0.05)
    if rec.poll() is None:
        rec.terminate()
        try:
            rec.wait(timeout=3)
        except subprocess.TimeoutExpired:
            rec.kill()
    if stop["why"] == "cancel":
        notify("Dictation canceled.", 2000)
        return 0
    seconds = write_wav(RAW, WAV, audio.RATE)
    os.remove(RAW)
    if seconds < 0.3:
        notify("Nothing recorded (check the microphone).")
        return 1
    deadline = time.monotonic() + SERVER_WAIT
    while not whisperclient.server_up(timeout=1):
        if time.monotonic() > deadline:
            notify("Speech server is not running: systemctl --user status work-kit-quassel-server")
            return 1
        time.sleep(0.5)
    args = whisperclient.build_inference_args(WAV, cfg, config.dictionary_words())
    try:
        text = refine(post_inference(args), cfg)
    except (OSError, ValueError) as e:
        log(f"transcription failed: {e}")
        notify("Transcription failed, see " + LOG)
        return 1
    finally:
        try:
            os.remove(WAV)
        except OSError:
            pass
    if not text:
        notify("No speech recognized.")
        return 0
    if cfg.history_enabled:
        config.history_append(text)
    how = deliver(text, allow_paste)
    if how == "pasted":
        notify("Text inserted.", 1500)
    elif how == "clipboard":
        notify("Copied. Press Ctrl+V to paste.", 3000)
    else:
        with open(LAST, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        os.chmod(LAST, 0o600)
        notify("Clipboard not reachable. Text saved to " + LAST, 8000)
    return 0


def start(allow_paste):
    if session_pid():
        return 0
    os.makedirs(RUNDIR, mode=0o700, exist_ok=True)
    argv = [sys.executable, os.path.abspath(__file__), "_session"]
    if not allow_paste:
        argv.append("--no-paste")
    with open(LOG, "a", encoding="utf-8") as logf:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=logf, stderr=logf,
                             start_new_session=True)
    with open(PIDFILE, "w", encoding="ascii") as f:
        f.write(str(p.pid))
    return 0


USAGE = __doc__.strip().splitlines()[-2:]


def usage(stream):
    print("\n".join(USAGE), file=stream)


def main(argv):
    # Help first: nothing below may start a recording for an unknown or missing argument.
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__.strip())
        return 0
    unknown = [a for a in argv if a.startswith("-") and a != "--no-paste"]
    args = [a for a in argv if not a.startswith("-")]
    if unknown or len(args) != 1:
        if unknown:
            print("work-kit-quassel-dictate: unknown option: " + unknown[0], file=sys.stderr)
        usage(sys.stderr)
        return 2
    allow_paste = "--no-paste" not in argv
    cmd = args[0]
    if cmd == "_session":
        try:
            return run_session(allow_paste)
        finally:
            try:
                if session_pid() in (None, os.getpid()):
                    os.remove(PIDFILE)
            except OSError:
                pass
    pid = session_pid()
    if cmd == "toggle":
        cmd = "stop" if pid else "start"
    if cmd == "start":
        return start(allow_paste)
    if cmd in ("stop", "cancel"):
        if pid:
            os.kill(pid, signal.SIGUSR1 if cmd == "stop" else signal.SIGTERM)
        return 0
    if cmd == "status":
        print("recording" if pid else "idle")
        return 0
    print("work-kit-quassel-dictate: unknown command: " + cmd, file=sys.stderr)
    usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
