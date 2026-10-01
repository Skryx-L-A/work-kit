"""Argument handling of quassel_dictate.py: help and bad input must never start a recording.

Runs without the Quassel app source (no skip): python3 -m pytest tests/test_dictate_args.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "quassel_dictate.py")


def run(tmp_path, *args):
    e = dict(os.environ, XDG_RUNTIME_DIR=str(tmp_path / "run"), HOME=str(tmp_path))
    r = subprocess.run([sys.executable, SCRIPT, *args], env=e, capture_output=True,
                       text=True, timeout=30)
    return r, tmp_path / "run"


def test_help_prints_usage_and_touches_nothing(tmp_path):
    for flag in ("--help", "-h"):
        r, rundir = run(tmp_path, flag)
        assert r.returncode == 0 and "Usage:" in r.stdout
        assert not rundir.exists()


def test_no_argument_prints_usage_and_does_not_start(tmp_path):
    r, rundir = run(tmp_path)
    assert r.returncode == 2 and "Usage:" in r.stderr
    assert not rundir.exists()


def test_unknown_option_or_command_is_rejected(tmp_path):
    for args in (["--bogus"], ["-x"], ["bogus"], ["start", "stop"]):
        r, rundir = run(tmp_path, *args)
        assert r.returncode == 2, args
        assert "Usage:" in r.stderr
        assert not rundir.exists()


def test_status_needs_no_recorder(tmp_path):
    r, _ = run(tmp_path, "status")
    assert r.returncode == 0 and r.stdout.strip() == "idle"
