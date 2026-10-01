import json
import subprocess

import pytest

from kitbrain import cli, gitops
from conftest import git


def run(capsys, *argv):
    rc = cli.main(list(argv))
    out = capsys.readouterr()
    return rc, out.out, out.err


def test_new_search_read_append_recent(env, capsys):
    rc, out, _ = run(capsys, "new", "decision", "Use PostgreSQL for audit log", "--project", "Billing",
                     "--body", "Audit entries need transactions.", "--tags", "db,audit")
    assert rc == 0 and "decisions/0001-use-postgresql-for-audit-log.md" in out
    # The home was initialised from the template on first write.
    assert (env / "README.md").is_file() and (env / "inbox").is_dir()
    log = git(env, "log", "--pretty=%s")
    assert 'brain: new decision "Use PostgreSQL for audit log"' in log
    assert "brain: initialize notes" in log

    rc, out, err = run(capsys, "search", "audit transactions", "--json")
    res = json.loads(out)
    assert res["mode"] == "bm25" and "BM25 only" in err
    assert res["results"][0]["path"] == "decisions/0001-use-postgresql-for-audit-log.md"
    assert res["results"][0]["project"] == "billing"

    rc, out, err = run(capsys, "search", "audit")
    assert "Use PostgreSQL for audit log" in out and err == ""  # warned only once

    rc, out, _ = run(capsys, "read", "Use PostgreSQL for audit log")
    assert "Audit entries need transactions." in out and "status: proposed" in out

    rc, out, _ = run(capsys, "append", "decisions/0001-use-postgresql-for-audit-log.md",
                     "--body", "Accepted in the architecture board.")
    assert rc == 0
    assert 'brain: append to "Use PostgreSQL for audit log"' in git(env, "log", "-1", "--pretty=%s")
    rc, out, _ = run(capsys, "search", "architecture board", "--json")
    assert json.loads(out)["results"][0]["path"].startswith("decisions/0001")

    rc, out, _ = run(capsys, "recent", "-n", "2", "--json")
    items = json.loads(out)
    assert items[0]["path"] == "decisions/0001-use-postgresql-for-audit-log.md"
    assert git(env, "status", "--porcelain") == ""


def test_append_from_stdin(env, capsys, monkeypatch):
    run(capsys, "new", "note", "Scratch")
    import io
    monkeypatch.setattr("sys.stdin", io.StringIO("piped text\n"))
    rc, _, _ = run(capsys, "append", "inbox/scratch.md", "--body", "-")
    assert rc == 0 and "piped text" in (env / "inbox" / "scratch.md").read_text()


def test_errors_are_clean(env, capsys):
    rc, _, err = run(capsys, "new", "session", "No project")
    assert rc == 1 and "--project" in err
    rc, _, err = run(capsys, "read", "does not exist")
    assert rc == 1 and "no note found" in err
    rc, _, err = run(capsys, "read", "/etc/passwd")
    assert rc == 1 and "outside" in err


def test_status_reindex_doctor_sync(env, capsys):
    run(capsys, "init")
    rc, out, _ = run(capsys, "status", "--json")
    info = json.loads(out)
    assert info["git"] and info["remote"] is False and info["search_mode"] == "bm25"
    rc, out, _ = run(capsys, "reindex", "--full")
    assert "search=bm25 only" in out
    rc, out, _ = run(capsys, "doctor")
    assert rc == 0 and "[OK  ] hooks" in out and "[WARN] model" in out
    rc, out, _ = run(capsys, "sync")
    assert "no git remote" in out


def test_non_search_commands_do_not_load_the_embedding_model(env, capsys, monkeypatch):
    run(capsys, "new", "note", "Fast metadata", "--body", "No model needed.")
    monkeypatch.setattr("kitbrain.index.try_load",
                        lambda *_: (_ for _ in ()).throw(AssertionError("model was loaded")))
    for args in (("status",), ("recent",), ("read", "Fast metadata"), ("week",), ("doctor",)):
        rc, _, _ = run(capsys, *args)
        assert rc == 0


def test_sync_with_remote(env, capsys, tmp_path):
    remote = tmp_path / "remote.git"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    run(capsys, "init")
    git(env, "remote", "add", "origin", str(remote))
    git(env, "push", "-q", "-u", "origin", "HEAD")
    run(capsys, "new", "note", "Pushed")
    rc, out, _ = run(capsys, "sync")
    assert rc == 0 and "synced" in out
    assert "Pushed" in subprocess.run(["git", "-C", str(remote), "log", "--pretty=%s"],
                                      capture_output=True, text=True).stdout


def test_init_is_idempotent_and_keeps_user_files(env, capsys):
    run(capsys, "init")
    (env / "README.md").write_text("mine\n")
    run(capsys, "init")
    assert (env / "README.md").read_text() == "mine\n"


def test_existing_hook_is_chained(env, capsys):
    env.mkdir()
    git(env, "init", "-q")
    hook = env / ".git" / "hooks" / "post-commit"
    hook.parent.mkdir(parents=True, exist_ok=True)
    hook.write_text("#!/bin/sh\necho custom\n")
    run(capsys, "init")
    assert (env / ".git" / "hooks" / "post-commit.local").read_text() == "#!/bin/sh\necho custom\n"
    body = hook.read_text()
    assert gitops.MARKER in body and "post-commit.local" in body
    assert gitops.install_hooks(env) == []  # second run changes nothing


def test_second_foreign_hook_is_backed_up_under_the_data_dir(env, capsys, tmp_path, monkeypatch):
    monkeypatch.setenv("KIT_DATA_DIR", str(tmp_path / "kitdata"))
    env.mkdir()
    git(env, "init", "-q")
    hooks = env / ".git" / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    (hooks / "post-commit").write_text("#!/bin/sh\necho first\n")
    run(capsys, "init")                                   # first hook is chained as .local
    (hooks / "post-commit").write_text("#!/bin/sh\necho second\n")
    gitops.install_hooks(env)                             # a new foreign hook: kept aside
    assert (hooks / "post-commit.local").read_text() == "#!/bin/sh\necho first\n"
    assert gitops.MARKER in (hooks / "post-commit").read_text()
    assert not [p for p in hooks.iterdir() if ".bak-" in p.name]     # nothing beside the hook
    baks = list((tmp_path / "kitdata" / "backups" / "20-brain").rglob("post-commit.bak-*"))
    assert len(baks) == 1 and baks[0].read_text() == "#!/bin/sh\necho second\n"


def test_commit_without_git_identity(env, capsys, tmp_path):
    (tmp_path / "gitconfig").write_text("[init]\n\tdefaultBranch = main\n")
    rc, out, _ = run(capsys, "new", "note", "Anonymous")
    assert rc == 0 and "commit" in out


@pytest.mark.parametrize("args", [["--version"], ["search", "--help"]])
def test_help_and_version(capsys, args):
    with pytest.raises(SystemExit) as e:
        cli.main(args)
    assert e.value.code == 0


def _remote_line(capsys):
    _, out, _ = run(capsys, "doctor")
    return next(ln for ln in out.splitlines() if ln[7:].startswith("remote:"))


def test_backup_writes_a_restorable_bundle(env, capsys, tmp_path):
    run(capsys, "new", "note", "Keep me", "--body", "important text")
    dest = tmp_path / "it-approved" / "backups"
    rc, out, _ = run(capsys, "backup", str(dest))
    assert rc == 0 and "backup written" in out
    bundles = list(dest.glob("brain-*.bundle"))
    assert len(bundles) == 1 and not list(dest.glob("*.part"))
    clone = tmp_path / "restored"
    subprocess.run(["git", "clone", "-q", str(bundles[0]), str(clone)], check=True)
    assert any("Keep me" in p.read_text() for p in clone.rglob("*.md"))
    rc, _, _ = run(capsys, "backup", str(dest))   # same day: replaced, not a second file
    assert rc == 0 and len(list(dest.glob("brain-*.bundle"))) == 1


def test_backup_without_commits_or_repo_is_an_error(env, capsys, tmp_path):
    env.mkdir()
    rc, _, err = run(capsys, "backup", str(tmp_path / "b"))
    assert rc == 1 and "not a git repository" in err
    git(env, "init", "-q")
    rc, _, err = run(capsys, "backup", str(tmp_path / "b"))
    assert rc == 1 and "no commit" in err


def test_doctor_warns_without_remote_and_backup(env, capsys, tmp_path):
    run(capsys, "init")
    line = _remote_line(capsys)
    assert line.startswith("[WARN]") and "no backup yet" in line and "brain backup" in line
    run(capsys, "backup", str(tmp_path / "b"))
    line = _remote_line(capsys)
    assert line.startswith("[OK  ]") and "last backup 0 day" in line


def test_doctor_warns_when_the_backup_is_older_than_a_week(env, capsys, tmp_path):
    import os
    import time
    run(capsys, "init")
    run(capsys, "backup", str(tmp_path / "b"))
    bundle = next((tmp_path / "b").glob("*.bundle"))
    old = time.time() - 8 * 86400
    os.utime(bundle, (old, old))
    line = _remote_line(capsys)
    assert line.startswith("[WARN]") and "last backup 8 days ago" in line
    bundle.unlink()
    assert "no backup yet" in _remote_line(capsys)


def test_doctor_is_quiet_with_a_remote(env, capsys, tmp_path):
    remote = tmp_path / "remote.git"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    run(capsys, "init")
    git(env, "remote", "add", "origin", str(remote))
    assert _remote_line(capsys) == "[OK  ] remote: remote configured"
