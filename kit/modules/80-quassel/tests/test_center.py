"""Tests for quassel_center.py: shortcut text, keyboard check, the clipboard-mode strings.

Run: python3 -m pytest tests/test_center.py   (no Quassel app and no Qt needed: those are imported
only when the control center starts)
"""
import os
import stat
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "bin"))
import quassel_center as qc  # noqa: E402


@pytest.fixture
def fake_gsettings(tmp_path, monkeypatch):
    def make(reply):
        exe = tmp_path / "gsettings"
        exe.write_text(f"#!/bin/sh\necho \"{reply}\"\n")
        exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
        monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    return make


@pytest.mark.parametrize("reply,label", [
    ("'<Control><Alt>d'", "Ctrl + Alt + D"),
    ("'<Super>F9'", "Super + F9"),
    ("''", None),
])
def test_shortcut_label(fake_gsettings, reply, label):
    fake_gsettings(reply)
    assert qc.shortcut_label() == label


def test_shortcut_label_without_gsettings(monkeypatch, tmp_path):
    monkeypatch.setenv("PATH", str(tmp_path))
    assert qc.shortcut_label() is None


def test_keyboard_ready(monkeypatch):
    monkeypatch.setattr(qc.os, "access", lambda p, m: False)
    assert not qc.keyboard_ready()
    monkeypatch.setattr(qc.os, "access", lambda p, m: p == "/dev/uinput")
    monkeypatch.setattr(qc.glob, "glob", lambda pat: ["/dev/input/event0"])
    assert not qc.keyboard_ready()        # uinput alone is not enough: the daemon must read events too
    monkeypatch.setattr(qc.os, "access", lambda p, m: True)
    assert qc.keyboard_ready()


@pytest.mark.parametrize("shortcut", ["Ctrl + Alt + D", None])
def test_clipboard_texts_are_truthful_and_formattable(shortcut):
    texts = qc.clipboard_texts(shortcut)
    for key in ("ob_body", "hint"):
        for lang_text in texts[key]:
            out = lang_text.format(chord="Ctrl + Meta")          # the app formats with chord=...
            assert "Ctrl + Meta" in out
            assert "nothing you must configure" not in out.lower()
    en = texts["ob_body"][0]
    if shortcut:
        assert shortcut in en and shortcut in texts["hint"][0]
    else:
        assert "work-kit-quassel-dictate toggle" in en
    assert "Hold Ctrl" not in texts["hint"][0].split("\n")[0]     # first line no longer promises the hold key
