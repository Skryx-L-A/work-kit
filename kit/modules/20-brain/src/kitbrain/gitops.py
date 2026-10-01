"""Git integration: init, commit per write, reindex hooks, sync."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

HOOKS = ("post-commit", "post-merge", "post-checkout")
MARKER = "# managed by brain (work-kit)"
# Written by kit-sync (30-agent-setup) into the global hooks dir; that dispatcher runs .git/hooks.
DISPATCHER_MARKER = "work-kit git-hook dispatcher"


def hook_body(name: str, chained: bool) -> str:
    lines = ["#!/bin/sh", MARKER]
    if chained:  # a hook that existed before brain was installed keeps running first
        lines.append(f'"$(dirname "$0")/{name}.local" "$@"')
    lines += [
        "# Incremental reindex in the background after git changed the notes.",
        '[ -n "$BRAIN_NO_HOOKS" ] && exit 0',
        "command -v brain >/dev/null 2>&1 || exit 0",
        'BRAIN_HOME="$(git rev-parse --show-toplevel)" nohup brain reindex --quiet >/dev/null 2>&1 &',
        "exit 0",
    ]
    return "\n".join(lines) + "\n"


GITIGNORE = ".brain/\n.DS_Store\n*.swp\n"


class GitError(Exception):
    pass


def run(home: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(["git", "-C", str(home), *args], capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise GitError(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc


def available() -> bool:
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def is_repo(home: Path) -> bool:
    return (home / ".git").exists()


def ensure_repo(home: Path) -> None:
    if not is_repo(home):
        run(home, "init", "-q")
    gi = home / ".gitignore"
    if not gi.exists():
        gi.write_text(GITIGNORE)
    elif ".brain/" not in gi.read_text():
        with gi.open("a") as fh:
            fh.write("\n.brain/\n")


def _identity_args(home: Path) -> list[str]:
    """Fallback identity so a commit never fails on a fresh machine."""
    if run(home, "config", "user.email", check=False).stdout.strip():
        return []
    return ["-c", "user.name=brain", "-c", "user.email=brain@localhost"]


def commit(home: Path, paths: list[Path], message: str) -> str | None:
    """Commit the given paths; return short hash or None when git is unavailable."""
    if not available() or not is_repo(home):
        return None
    rels = [str(p.relative_to(home)) for p in paths]
    run(home, "add", "--", *rels)
    if not run(home, "diff", "--cached", "--quiet", "--", *rels, check=False).returncode:
        return None  # nothing staged for these paths
    ident = _identity_args(home)
    proc = subprocess.run(["git", *ident, "-C", str(home), "commit", "-q", "-m", message, "--", *rels],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise GitError(f"git commit failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return run(home, "rev-parse", "--short", "HEAD").stdout.strip()


def hooks_dir(home: Path) -> Path:
    return home / ".git" / "hooks"


def hooks_path_override(home: Path) -> str | None:
    """core.hooksPath set (e.g. globally by a data guard) disables .git/hooks."""
    out = run(home, "config", "core.hooksPath", check=False).stdout.strip()
    return out or None


def hooks_path_is_dispatcher(override: str, home: Path) -> bool:
    """True if core.hooksPath points at kit-sync's dispatcher, which still runs .git/hooks."""
    d = Path(override).expanduser()
    if not d.is_absolute():
        d = home / d
    try:
        for name in HOOKS:
            with open(d / name, encoding="utf-8", errors="replace") as fh:
                if any(DISPATCHER_MARKER in line for _, line in zip(range(20), fh)):
                    return True
    except OSError:
        pass
    return False


def move_to_backup(home: Path, path: Path) -> Path:
    """Move path below <kit data dir>/backups/20-brain/, keeping its path relative to $HOME
    (or _root/... outside it); nothing is left next to the original. Returns the new place."""
    path = Path(os.path.abspath(path))
    data = Path(os.environ.get("KIT_DATA_DIR") or Path.home() / ".local/share/work-kit")
    try:
        rel = path.relative_to(Path.home())
    except ValueError:
        rel = Path("_root") / path.relative_to(path.anchor)
    dest = data / "backups" / "20-brain" / rel.parent / f"{rel.name}.bak-{time.strftime('%Y%m%d%H%M%S')}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(dest))
    return dest


def install_hooks(home: Path) -> list[str]:
    """Install reindex hooks; an existing foreign hook is kept as <name>.local and chained."""
    d = hooks_dir(home)
    d.mkdir(parents=True, exist_ok=True)
    done = []
    for name in HOOKS:
        path, local = d / name, d / f"{name}.local"
        if path.exists() and MARKER not in path.read_text(errors="replace"):
            if local.exists():
                move_to_backup(home, path)   # the chained .local hook stays; this one is kept aside
            else:
                path.rename(local)
        body = hook_body(name, (d / f"{name}.local").exists())
        if path.exists() and path.read_text(errors="replace") == body:
            continue
        path.write_text(body)
        path.chmod(0o755)
        done.append(name)
    return done


def hooks_status(home: Path) -> dict[str, bool]:
    d = hooks_dir(home)
    return {n: (d / n).is_file() and MARKER in (d / n).read_text(errors="replace")
            and os.access(d / n, os.X_OK) for n in HOOKS}


def has_remote(home: Path) -> bool:
    return bool(run(home, "remote", check=False).stdout.strip())


def sync(home: Path) -> str:
    if not is_repo(home):
        return "not a git repository; nothing to sync"
    if not has_remote(home):
        return "no git remote configured; nothing to sync (local only)"
    pull = run(home, "pull", "--rebase", "--autostash", check=False)
    if pull.returncode != 0:
        raise GitError(f"git pull --rebase failed: {pull.stderr.strip()}")
    push = run(home, "push", check=False)
    if push.returncode != 0:
        raise GitError(f"git push failed: {push.stderr.strip()}")
    return "synced with remote"


BACKUP_MARK = "last-backup"
BACKUP_MAX_AGE_DAYS = 7


def backup(home: Path, dest: Path) -> Path:
    """Write a git bundle of every branch and tag to <dest>/brain-<date>.bundle (a second one on the
    same day is replaced). The path is remembered in .brain/last-backup for `brain doctor`."""
    if not available() or not is_repo(home):
        raise GitError("brain home is not a git repository; run 'brain init'")
    if not run(home, "rev-parse", "--verify", "-q", "HEAD", check=False).stdout.strip():
        raise GitError("nothing to back up yet: the notes repo has no commit")
    dest = Path(dest).expanduser()
    dest.mkdir(parents=True, exist_ok=True)
    target = dest / f"brain-{time.strftime('%Y-%m-%d')}.bundle"
    tmp = target.with_name(target.name + ".part")
    try:
        run(home, "bundle", "create", str(tmp), "--all")
        run(home, "bundle", "verify", str(tmp))
        os.replace(tmp, target)
    finally:
        tmp.unlink(missing_ok=True)
    state = home / ".brain"
    state.mkdir(exist_ok=True)
    (state / BACKUP_MARK).write_text(str(target.resolve()) + "\n")
    return target


def backup_age_days(home: Path) -> float | None:
    """Age in days of the newest bundle made by `brain backup` (still on disk), else None."""
    try:
        path = Path((home / ".brain" / BACKUP_MARK).read_text().strip())
        return max(0.0, (time.time() - path.stat().st_mtime) / 86400)
    except (OSError, ValueError):
        return None


def recent(home: Path, n: int) -> list[dict]:
    """Most recently committed notes (by commit time); falls back to mtime."""
    if is_repo(home) and available():
        out = run(home, "log", "--name-only", "--pretty=format:@@%ct", "--diff-filter=AM",
                  "-n", str(n * 5), "--", "*.md", check=False).stdout
        seen, items, ts = set(), [], 0
        for line in out.splitlines():
            if line.startswith("@@"):
                ts = int(line[2:])
            elif line.strip() and line not in seen and (home / line).is_file():
                seen.add(line)
                items.append({"path": line, "time": ts})
        if items:
            return items[:n]
    files = sorted(home.rglob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True)
    return [{"path": p.relative_to(home).as_posix(), "time": int(p.stat().st_mtime)}
            for p in files if ".git" not in p.parts and ".brain" not in p.parts][:n]


def fmt_time(ts: int) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))
