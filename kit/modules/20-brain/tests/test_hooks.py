import os
import stat
import subprocess
import sys
import time

from conftest import git
from kitbrain import cli, config
from kitbrain.index import Index


def test_post_commit_hook_reindexes_in_background(env, tmp_path, capsys, monkeypatch):
    cli.main(["init"])
    capsys.readouterr()
    # A `brain` on PATH that runs this checkout, like the installed tool would.
    bindir = tmp_path / "bin"
    bindir.mkdir()
    shim = bindir / "brain"
    shim.write_text(f"#!/bin/sh\nexec {sys.executable} -m kitbrain \"$@\"\n")
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.delenv("BRAIN_NO_HOOKS")

    note = env / "inbox" / "manual.md"
    note.write_text("---\ntitle: Written by hand\n---\n\ncommitted outside brain\n")
    git(env, "add", "inbox/manual.md")
    git(env, "commit", "-q", "-m", "manual edit")

    idx = Index(config.load())
    deadline = time.monotonic() + 30
    found = False
    while time.monotonic() < deadline:
        if idx.find_title("Written by hand"):
            found = True
            break
        time.sleep(0.2)
    # Wait for the background reindex to release its lock before the tmp dir goes away.
    with idx.lock(timeout=30):
        pass
    idx.close()
    assert found


def _doctor_hooks_line(capsys):
    cli.main(["doctor"])
    out = capsys.readouterr().out
    return next(line for line in out.splitlines() if "] hooks" in line)


def test_doctor_accepts_the_kit_sync_dispatcher(env, tmp_path, capsys):
    cli.main(["init"])
    capsys.readouterr()
    hooks = tmp_path / "kit-hooks"
    hooks.mkdir()
    for name in ("pre-commit", "post-commit"):
        (hooks / name).write_text("#!/usr/bin/env bash\n# work-kit git-hook dispatcher\nexit 0\n")
    git(env, "config", "core.hooksPath", str(hooks))
    line = _doctor_hooks_line(capsys)
    assert line.startswith("[OK  ]") and "kit-sync dispatcher" in line


def test_doctor_still_warns_about_a_foreign_hooks_path(env, tmp_path, capsys):
    cli.main(["init"])
    capsys.readouterr()
    hooks = tmp_path / "other-hooks"
    hooks.mkdir()
    (hooks / "post-commit").write_text("#!/bin/sh\nexit 0\n")
    git(env, "config", "core.hooksPath", str(hooks))
    line = _doctor_hooks_line(capsys)
    assert line.startswith("[WARN]") and "bypasses .git/hooks" in line
    # a hooksPath dir that does not exist is foreign too
    git(env, "config", "core.hooksPath", str(tmp_path / "missing"))
    assert _doctor_hooks_line(capsys).startswith("[WARN]")


def test_doctor_dispatcher_with_missing_repo_hooks_warns_separately(env, tmp_path, capsys):
    cli.main(["init"])
    capsys.readouterr()
    (env / ".git" / "hooks" / "post-merge").unlink()
    hooks = tmp_path / "kit-hooks"
    hooks.mkdir()
    (hooks / "post-commit").write_text("# work-kit git-hook dispatcher\n")
    git(env, "config", "core.hooksPath", str(hooks))
    cli.main(["doctor"])
    out = capsys.readouterr().out
    assert "[OK  ] hooks" in out and "[WARN] hooks" in out and "post-merge" in out
