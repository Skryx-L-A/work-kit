import os

from kitdesign import doc


def _fake(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o755)


def _isolate(monkeypatch, tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    empty = tmp_path / "empty"
    empty.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("PATH", str(empty))
    monkeypatch.delenv("KIT_DESIGN_BROWSER", raising=False)
    monkeypatch.delenv("KIT_BIN_DIR", raising=False)
    monkeypatch.setattr(doc, "BROWSERS", doc.BROWSERS[:1])
    return home


def test_finds_bundled_browser_in_local_bin_outside_path(tmp_path, monkeypatch):
    home = _isolate(monkeypatch, tmp_path)
    assert doc.find_browser() is None
    _fake(home / ".local" / "bin" / "kit-chrome-headless")
    assert doc.find_browser() == str(home / ".local" / "bin" / "kit-chrome-headless")


def test_kit_bin_dir_is_searched(tmp_path, monkeypatch):
    _isolate(monkeypatch, tmp_path)
    kbin = tmp_path / "kbin"
    _fake(kbin / "kit-chrome-headless")
    monkeypatch.setenv("KIT_BIN_DIR", str(kbin))
    assert doc.find_browser() == str(kbin / "kit-chrome-headless")


def test_env_override_wins(tmp_path, monkeypatch):
    home = _isolate(monkeypatch, tmp_path)
    _fake(home / ".local" / "bin" / "kit-chrome-headless")
    monkeypatch.setenv("KIT_DESIGN_BROWSER", "/custom/chrome")
    assert doc.find_browser() == "/custom/chrome"


def test_bundled_beats_system_browser_on_path(tmp_path, monkeypatch):
    home = _isolate(monkeypatch, tmp_path)
    _fake(home / ".local" / "bin" / "kit-chrome-headless")
    sysbin = tmp_path / "sysbin"
    _fake(sysbin / "chromium")
    monkeypatch.setenv("PATH", str(sysbin))
    monkeypatch.setattr(doc, "BROWSERS", ("kit-chrome-headless", "chromium"))
    assert os.path.basename(doc.find_browser()) == "kit-chrome-headless"
