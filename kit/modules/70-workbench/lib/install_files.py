#!/usr/bin/env python3
"""Copy the workbench payload to its installed places, idempotent, with backups.

    install_files.py install   <payload-dir> <manifest>
    install_files.py uninstall <manifest>

Per file: missing -> copied; identical -> kept; still the version this installer wrote last
time -> replaced; changed by someone else -> moved to <file>.bak-<timestamp> below
~/.local/share/work-kit/backups/70-workbench/ (same path as below $HOME), then replaced.
A file the previous install recorded that the new payload no longer ships (a tool stripped in
a later kit) is removed when unchanged, else moved to the same backup folder.
The manifest records path and SHA-256 of every installed file, so uninstall removes only
files that are unchanged since installation and reports the others.
When /usr/bin/python3 does not exist, WB_PYTHON names the interpreter to use instead and every
installed text file gets that path in place of /usr/bin/python3.
The depersonalized payload marks the owner's GitHub handle as <your-github-user>; installed
files get WB_GITHUB_USER (install.sh: git config github.user) or the neutral "github-user".
The model registry is seeded (models.default.json -> ~/.claude/workbench/models.json) and is the
user's file afterwards: a later install replaces it only while it is unchanged since its seed.
"""
import hashlib
import json
import os
import shutil
import sys
import time
from pathlib import Path

from kit_backup import move_aside

HOME = Path(os.environ["HOME"])
# (source below payload/, destination, mode) -- mode "top": files of that folder only,
# "tree": whole folder, "file": one file.
MAP = [
    ("shell", HOME / ".local/bin", "top"),
    ("hooks", HOME / ".claude/hooks", "tree"),
    ("claude/statusline-command.sh", HOME / ".claude/statusline-command.sh", "file"),
    ("claude/chat-zuordnung.sh", HOME / ".claude/workbench/chat-zuordnung.sh", "file"),
    ("claude/roles", HOME / ".claude/roles", "tree"),
    ("claude/rules", HOME / ".claude/workbench/rules", "tree"),
    ("claude/commands", HOME / ".claude/commands", "tree"),
    ("pi/agent", HOME / ".pi/agent", "tree"),
    ("pi-extensions", HOME / ".pi/agent/extensions", "tree"),
    ("git-hooks", HOME / ".claude/git-hooks", "tree"),
]
SEED = [("shell/models.default.json", HOME / ".claude/workbench/models.json")]
SKIP = {"__pycache__", ".DS_Store"}


PY_OLD = b"/usr/bin/python3"
PY_NEW = os.environ.get("WB_PYTHON", "").encode()


GH_OLD = b"<your-github-user>"
GH_NEW = (os.environ.get("WB_GITHUB_USER") or "github-user").encode()


def content(path):
    """The bytes as they are installed: /usr/bin/python3 replaced when that path is missing,
    the GitHub-handle placeholder filled in."""
    data = Path(path).read_bytes()
    if b"\0" in data[:8192]:
        return data
    if PY_NEW and PY_NEW != PY_OLD and PY_OLD in data:
        data = data.replace(PY_OLD, PY_NEW)
    if GH_OLD in data:
        data = data.replace(GH_OLD, GH_NEW)
    return data


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 16), b""):
            h.update(block)
    return h.hexdigest()


# WB_SKIP_GIT_HOOKS=1: kit-sync (30-agent-setup) provides the one global git-hook dispatcher, so
# the workbench's own copy is not installed, and a copy an earlier run installed is removed.
SKIP_GIT_HOOKS = os.environ.get("WB_SKIP_GIT_HOOKS") == "1"
GIT_HOOKS_DIR = HOME / ".claude/git-hooks"


def pairs(payload):
    for src, dst, mode in MAP:
        if SKIP_GIT_HOOKS and dst == GIT_HOOKS_DIR:
            continue
        s = payload / src
        if mode == "file":
            if s.is_file():
                yield s, dst
        elif mode == "top":
            for f in sorted(s.iterdir()):
                if f.is_file() and f.name not in SKIP:
                    yield f, dst / f.name
        else:
            for f in sorted(s.rglob("*")):
                if f.is_file() and not SKIP.intersection(f.parts):
                    yield f, dst / f.relative_to(s)


ROOTS = {dst if mode != "file" else dst.parent for _, dst, mode in MAP}


def prune_dirs(d):
    """Remove d and its parents while empty, up to (not including) an installation root."""
    d = Path(d)
    while d not in ROOTS and HOME in d.parents:
        cache = d / "__pycache__"
        if cache.is_dir() and all(f.suffix == ".pyc" for f in cache.iterdir()):
            shutil.rmtree(cache)
        try:
            d.rmdir()
        except OSError:
            return
        d = d.parent


def install(payload, manifest_path):
    payload = Path(payload)
    manifest_path = Path(manifest_path)
    old = {}
    if manifest_path.exists():
        old = json.loads(manifest_path.read_text(encoding="utf-8")).get("files", {})
    stamp = time.strftime("%Y%m%d%H%M%S")
    new, counts = {}, {"copied": 0, "unchanged": 0, "updated": 0, "backed up": 0}
    for src, dst in pairs(payload):
        data = content(src)
        want = sha_bytes(data)
        key = str(dst)
        if dst.is_file() and sha(dst) == want:
            counts["unchanged"] += 1
        else:
            if dst.exists():
                if old.get(key) and sha(dst) == old[key]:
                    counts["updated"] += 1
                else:
                    print(f"   backup: {move_aside(dst, stamp)}")
                    counts["backed up"] += 1
            else:
                counts["copied"] += 1
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
            shutil.copymode(src, dst)
        new[key] = want
    # Files the previous install wrote that this payload no longer has (stripped tools, the
    # workbench's own git-hook dispatcher when kit-sync's is used): removed when unchanged since
    # then, moved to the backup folder when someone changed them.
    gone, hooks_gone = 0, 0
    for key, digest in old.items():
        f = Path(key)
        if key in new or not f.is_file() or HOME not in f.parents:
            continue
        if sha(f) == digest:
            f.unlink()
        else:
            print(f"   backup (no longer shipped, changed since installation): {move_aside(f, stamp)}")
            counts["backed up"] += 1
        if f.parent == GIT_HOOKS_DIR:
            hooks_gone += 1
        else:
            gone += 1
        prune_dirs(f.parent)
    if SKIP_GIT_HOOKS:
        try:
            GIT_HOOKS_DIR.rmdir()
        except OSError:
            pass
        if hooks_gone:
            print(f"   removed the workbench's own git-hook dispatcher ({hooks_gone} files); kit-sync's is used")
    if gone:
        print(f"   removed {gone} files the new payload no longer ships")
    seeded = {}
    prev_seeded = {}
    if manifest_path.exists():
        prev_seeded = json.loads(manifest_path.read_text(encoding="utf-8")).get("seeded", {})
    for src, dst in SEED:
        s = payload / src
        if not s.is_file():
            continue
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, dst)
            seeded[str(dst)] = sha(dst)
            print(f"   seeded {dst}")
        elif sha(dst) != sha(s) and prev_seeded.get(str(dst)) == sha(dst):
            # Still the seed of an earlier install, untouched since: take the new default.
            shutil.copy2(s, dst)
            seeded[str(dst)] = sha(dst)
            print(f"   updated {dst} (unchanged since the last seed)")
        elif sha(dst) != sha(s):
            print(f"   kept {dst} (your file); new default: {s}")
    prev_seeded.update(seeded)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps({"files": new, "seeded": prev_seeded}, indent=1) + "\n",
                             encoding="utf-8")
    print("   files: " + ", ".join(f"{v} {k}" for k, v in counts.items()))


def uninstall(manifest_path):
    manifest_path = Path(manifest_path)
    if not manifest_path.exists():
        print("   no manifest, nothing to remove")
        return
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    removed, kept = 0, []
    for group in ("files", "seeded"):
        for key, digest in data.get(group, {}).items():
            p = Path(key)
            if not p.is_file():
                continue
            if sha(p) == digest:
                p.unlink()
                removed += 1
            else:
                kept.append(key)
    dirs = {str(Path(k).parent) for k in data.get("files", {})}
    for key in dirs:
        # Bytecode python wrote next to installed modules (hooks/lib): only .pyc, so ours.
        cache = Path(key) / "__pycache__"
        if cache.is_dir() and all(f.suffix == ".pyc" for f in cache.iterdir()):
            shutil.rmtree(cache)
    for key in sorted(dirs, key=len, reverse=True):
        try:
            Path(key).rmdir()
        except OSError:
            pass
    manifest_path.unlink()
    print(f"   removed {removed} files")
    for k in kept:
        print(f"   kept (changed since installation): {k}")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "install":
        install(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "uninstall":
        uninstall(sys.argv[2])
    else:
        sys.exit(__doc__)
