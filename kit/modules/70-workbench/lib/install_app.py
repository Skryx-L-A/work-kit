#!/usr/bin/env python3
"""Install the Agent Workbench desktop app (Electron) on Linux x86_64. Offline, no sudo.

    install_app.py install   <payload-dir> <offline-dir> <state.json>
    install_app.py uninstall <state.json>

install puts the app below ~/.local/share/work-kit/workbench-app/:
    electron/          Electron for linux-x64 (offline zip, sha256 from pins.conf)
    app/               payload/app: package.json, dist/ (built at port time), bin/awb-ctl,
                       node_modules/node-pty (npm tarball: lib/ and the linux-x64 prebuild)
    extension/media/   payload/extension/media (symbols of the start page)
and writes the launcher ~/.local/bin/agent-workbench, the menu entry
~/.local/share/applications/agent-workbench.desktop and hicolor icons. A launcher, menu entry or
icon that someone else wrote is moved to ~/.local/share/work-kit/backups/70-workbench/ first.
The state file records every file with its SHA-256; uninstall removes the app folder and every
recorded file that is unchanged, and reports the others.

Exit codes of install: 0 installed, 3 skipped (not Linux x86_64, or the offline artifacts are
missing; the reason is printed), 1 error.
"""
import hashlib
import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit_backup import move_aside  # noqa: E402

HOME = Path(os.environ["HOME"])
DATA = Path(os.environ.get("KIT_DATA_DIR") or HOME / ".local/share/work-kit")
DEST = DATA / "workbench-app"
BIN = HOME / ".local/bin"
LAUNCHER = BIN / "agent-workbench"
APPS = HOME / ".local/share/applications"
DESKTOP = APPS / "agent-workbench.desktop"
ICONS = HOME / ".local/share/icons/hicolor"
MARK = "work-kit 70-workbench desktop app"
MODULE = Path(__file__).resolve().parent.parent


def log(msg):
    print(f"[workbench] {msg}", flush=True)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def pins():
    out = {}
    for line in (MODULE / "pins.conf").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "|" in line:
            path, _url, digest = line.split("|")
            out[path] = digest
    return out


def skip(reason):
    log(f"desktop app skipped: {reason}")
    sys.exit(3)


def extract_zip(archive, dest):
    """Unpack with the file modes of the archive (zipfile alone drops the executable bits)."""
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            target = dest / info.filename
            if not str(target.resolve()).startswith(str(dest.resolve())):
                raise SystemExit(f"install_app: unsafe path in {archive.name}: {info.filename}")
            mode = info.external_attr >> 16
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if stat.S_ISLNK(mode):
                os.symlink(zf.read(info).decode(), target)
                continue
            with zf.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            if mode & 0o777:
                target.chmod(mode & 0o777)


def extract_node_pty(archive, dest):
    """package.json, lib/ and the linux-x64 prebuild of the npm tarball; no build step."""
    keep = ("package/package.json", "package/LICENSE", "package/lib/", "package/prebuilds/linux-x64/")
    with tarfile.open(archive, "r:gz") as tf:
        for m in tf.getmembers():
            if not m.isfile() or not m.name.startswith(keep) or ".." in m.name.split("/"):
                continue
            target = dest / m.name[len("package/"):]
            target.parent.mkdir(parents=True, exist_ok=True)
            with tf.extractfile(m) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            target.chmod(0o755 if m.name.endswith(".node") else 0o644)
    if not (dest / "prebuilds/linux-x64/pty.node").is_file():
        raise SystemExit(f"install_app: {archive.name} has no prebuilds/linux-x64/pty.node")


def content_stamp(trees, extra):
    """One hash over the files that make up the installed app: a reinstall of the same kit
    skips unpacking Electron again."""
    h = hashlib.sha256()
    for tree in trees:
        for p in sorted(tree.rglob("*")) if tree.is_dir() else []:
            if p.is_file() and "__pycache__" not in p.parts:
                h.update(p.relative_to(tree).as_posix().encode() + b"\0" + sha(p).encode())
    for e in extra:
        h.update(e.encode())
    return h.hexdigest()


def launcher_text():
    return f"""#!/usr/bin/env bash
# Agent Workbench, the desktop app of the agent workbench ({MARK}).
#   agent-workbench [args]            open the window; a second start while it runs does nothing
#   agent-workbench --ctl <command>   talk to the running app (awb-ctl), e.g. --ctl state
#   agent-workbench --version         Electron version (loads its libraries, needs no display)
# Written by kit/modules/70-workbench/install.sh; removed by its uninstall.sh.
set -euo pipefail
root="{DEST}"
e="$root/electron/electron"
if [ ! -x "$e" ]; then
  echo "agent-workbench: $e is missing; reinstall with: bash <kit>/modules/70-workbench/install.sh" >&2
  exit 1
fi
# Same rule as the VS Code wrapper of 01-prereqs: Ubuntu 23.10+ blocks unprivileged user namespaces
# for programs without an AppArmor profile, and chrome-sandbox below $HOME cannot be setuid root.
# Then Electron only starts without its sandbox.
flags=()
if [ ! -u "$root/electron/chrome-sandbox" ] \\
   && [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ]; then
  flags+=(--no-sandbox)
fi
case "${{1:-}}" in
  --ctl) shift; ELECTRON_RUN_AS_NODE=1 exec "$e" "$root/app/bin/awb-ctl" "$@" ;;
  --version) exec "$e" "${{flags[@]}}" --version ;;
esac
# Started from the menu, the app still finds the kit tools (wb-code, wb-state, tmux wrappers).
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH"; export PATH ;; esac
# Already open? A second main process would find the control socket taken.
if pgrep -u "$(id -u)" -f -- "^$e( --no-sandbox)? $root/app --show" >/dev/null 2>&1; then
  echo "Agent Workbench is already running." >&2
  exit 0
fi
exec "$e" "${{flags[@]}}" "$root/app" --show "$@"
"""


def desktop_text():
    return f"""[Desktop Entry]
Type=Application
Name=Agent Workbench
GenericName=Workbench
Comment=Sessions, workers and approvals of the agent workbench
Keywords=workbench;werkbank;agents;
Exec={LAUNCHER}
Icon=agent-workbench
Terminal=false
Categories=Development;
StartupWMClass=agent-workbench
# {MARK}
"""


def ours(path, state):
    """A file we may replace: the one we wrote (unchanged), or one that carries our mark."""
    if not path.exists():
        return True
    rec = state.get("files", {}).get(str(path))
    if rec and path.is_file() and sha(path) == rec:
        return True
    try:
        return MARK in path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False


def place(path, data, mode, state, written):
    if path.exists() or path.is_symlink():
        if path.is_file() and not path.is_symlink() and path.read_bytes() == data:
            path.chmod(mode)
            written[str(path)] = sha(path)
            return
        if not ours(path, state):
            log(f"backup of {path}: {move_aside(path)}")
        else:
            path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".kit-new")
    tmp.write_bytes(data)
    tmp.chmod(mode)
    os.replace(tmp, path)
    written[str(path)] = sha(path)


def refresh_caches():
    """Only caches that already exist: a menu entry without MIME types and icons in a folder
    without a cache need none, and a cache this installer created would stay after uninstall."""
    for cache, cmd in ((APPS / "mimeinfo.cache", ["update-desktop-database", str(APPS)]),
                       (ICONS / "icon-theme.cache", ["gtk-update-icon-cache", "-f", "-t", "-q", str(ICONS)])):
        if cache.exists() and shutil.which(cmd[0]):
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install(payload, offline, state_path):
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        skip(f"built for Linux x86_64, this is {platform.system()} {platform.machine()}")
    app = payload / "app"
    if not (app / "dist/main/main.js").is_file():
        raise SystemExit(f"install_app: {app}/dist/main/main.js missing (payload incomplete)")
    build = json.loads((app / "kit-build.json").read_text(encoding="utf-8"))
    names = {"electron": f"electron-v{build['electron']}-linux-x64.zip",
             "node-pty": f"node-pty-{build['nodePty']}.tgz"}
    pinned = pins()
    src = offline / "workbench-app"
    for key, name in names.items():
        f = src / name
        if name not in pinned:
            raise SystemExit(f"install_app: {name} is not pinned in pins.conf (app built for {key} "
                             f"{build['electron' if key == 'electron' else 'nodePty']})")
        if not f.is_file():
            skip(f"{f} missing (build host: bash kit/modules/70-workbench/fetch.sh)")
        if sha(f) != pinned[name]:
            raise SystemExit(f"install_app: {f} does not match its sha256 in pins.conf")

    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.is_file() else {}
    media = payload / "extension/media"
    stamp = content_stamp([app, media], [pinned[n] for n in names.values()])
    if state.get("stamp") == stamp and (DEST / "electron/electron").is_file() \
       and (DEST / "app/dist/main/main.js").is_file():
        log(f"desktop app: {DEST} is current")
    else:
        new = DEST.with_name(DEST.name + ".new")
        shutil.rmtree(new, ignore_errors=True)
        new.mkdir(parents=True)
        log(f"desktop app: Electron {build['electron']} (linux-x64)")
        extract_zip(src / names["electron"], new / "electron")
        shutil.copytree(app, new / "app", ignore=shutil.ignore_patterns("icons", "__pycache__"))
        extract_node_pty(src / names["node-pty"], new / "app/node_modules/node-pty")
        if media.is_dir():
            shutil.copytree(media, new / "extension/media")
        old = DEST.with_name(DEST.name + ".old")
        shutil.rmtree(old, ignore_errors=True)
        if DEST.exists():
            DEST.rename(old)
        new.rename(DEST)
        shutil.rmtree(old, ignore_errors=True)

    written = {}
    place(LAUNCHER, launcher_text().encode(), 0o755, state, written)
    place(DESKTOP, desktop_text().encode(), 0o644, state, written)
    for icon in sorted((app / "icons").glob("*/agent-workbench.png")):
        place(ICONS / icon.parent.name / "apps/agent-workbench.png", icon.read_bytes(), 0o644, state,
              written)
    # Files of an earlier install that this one no longer writes (another icon size, say).
    for path, digest in state.get("files", {}).items():
        p = Path(path)
        if path not in written and p.is_file() and sha(p) == digest:
            p.unlink()
    refresh_caches()
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps({
        "dest": str(DEST), "stamp": stamp, "source": build.get("source", ""), "electron": build["electron"],
        "nodePty": build["nodePty"], "files": written,
    }, indent=2) + "\n", encoding="utf-8")
    log(f"desktop app: {DEST}, launcher {LAUNCHER}, menu entry 'Agent Workbench'")


def uninstall(state_path):
    if not state_path.is_file():
        return
    state = json.loads(state_path.read_text(encoding="utf-8"))
    for path, digest in state.get("files", {}).items():
        p = Path(path)
        if not p.is_file():
            continue
        if sha(p) == digest:
            p.unlink()
        else:
            log(f"kept (changed since install): {p}")
    for d in sorted({Path(p).parent for p in state.get("files", {})}, reverse=True):
        if str(d).startswith(str(ICONS)):
            try:
                d.rmdir()
                d.parent.rmdir()
            except OSError:
                pass
    dest = Path(state.get("dest") or DEST)
    if dest == DEST:
        shutil.rmtree(dest, ignore_errors=True)
        for extra in (".new", ".old"):
            shutil.rmtree(dest.with_name(dest.name + extra), ignore_errors=True)
    refresh_caches()
    state_path.unlink()
    log("desktop app removed")


def main(argv):
    if len(argv) == 4 and argv[0] == "install":
        install(Path(argv[1]), Path(argv[2]), Path(argv[3]))
    elif len(argv) == 2 and argv[0] == "uninstall":
        uninstall(Path(argv[1]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
