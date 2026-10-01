#!/usr/bin/env python3
"""work-kit installer core. Started by kit/install. Standard library only (Python 3.8+)."""
import argparse
import fnmatch
import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modules as modmod  # noqa: E402
import state as statemod  # noqa: E402
import ui  # noqa: E402

FAIL_RE = re.compile(r"\b(error|failed|failure|fatal|cannot|can't|missing|not found|no such)\b", re.I)
BACKUP_RE = re.compile(r"\.bak-\d{8,14}(-\d+)?$")
STEP_RE = re.compile(r"(\b\d+/\d+\b|^\W*==>|\bstep\b)", re.I)


def say(text=""):
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def data_dir():
    return os.environ.get("KIT_DATA_DIR") or os.path.join(os.path.expanduser("~"), ".local", "share", "work-kit")


def run_env(options=None):
    """Environment for modules and checks. options: {"KIT_PERMISSIONS": "ask", ...} chosen in the installer."""
    env = dict(os.environ)
    env["PATH"] = os.path.join(os.path.expanduser("~"), ".local", "bin") + os.pathsep + env.get("PATH", "")
    env.update(options or {})
    return env


def _safe_offline_pattern(pattern):
    """A module.conf offline= value must stay below kit/offline."""
    pattern = pattern.replace("\\", "/").lstrip("./")
    if not pattern or pattern.startswith("/") or ".." in pattern.split("/"):
        return None
    return pattern


def module_fingerprint(mod, kit_dir):
    """Stable digest of module source and its declared offline manifest entries.

    Offline payloads can be many GB, so SHA256SUMS is the authoritative contribution
    for them; this deliberately never reads the payload files themselves.
    """
    digest = hashlib.sha256()

    def add(kind, rel, payload=b""):
        digest.update(kind.encode("utf-8") + b"\\0" + rel.encode("utf-8") + b"\\0")
        digest.update(payload)
        digest.update(b"\\0")

    for root, dirs, files in os.walk(mod.path, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in ("__pycache__", "tests"))
        rel_root = os.path.relpath(root, mod.path)
        if rel_root != ".":
            add("dir", rel_root.replace(os.sep, "/"))
        for name in list(dirs):
            path = os.path.join(root, name)
            if os.path.islink(path):
                rel = os.path.relpath(path, mod.path).replace(os.sep, "/")
                add("link", rel, os.readlink(path).encode("utf-8", "surrogateescape"))
                dirs.remove(name)
        for name in sorted(files):
            if name.endswith(".pyc"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, mod.path).replace(os.sep, "/")
            if os.path.islink(path):
                add("link", rel, os.readlink(path).encode("utf-8", "surrogateescape"))
            elif os.path.isfile(path):
                with open(path, "rb") as fh:
                    add("file", rel, fh.read())

    patterns = [_safe_offline_pattern(p) for p in mod.offline]
    patterns = [p for p in patterns if p]
    manifest = os.path.join(kit_dir, "offline", "SHA256SUMS")
    if patterns:
        try:
            with open(manifest, encoding="utf-8", errors="surrogateescape") as fh:
                lines = []
                for raw in fh:
                    line = raw.rstrip("\\r\\n")
                    bits = line.split(None, 1)
                    if len(bits) != 2:
                        continue
                    path = bits[1].lstrip("*").replace("\\", "/")
                    while path.startswith("./"):
                        path = path[2:]
                    if path.startswith("/") or ".." in path.split("/"):
                        continue
                    if any(fnmatch.fnmatchcase(path, p.rstrip("/") + ("/*" if p.endswith("/") else ""))
                           or fnmatch.fnmatchcase(path, p) for p in patterns):
                        lines.append(line)
                for line in sorted(lines):
                    add("offline", line)
        except OSError:
            pass
    return digest.hexdigest()


def update_modules(mods, st, kit_dir):
    """{id: current fingerprint} for installed modules changed since their last run."""
    updates = {}
    for mod in mods:
        if st.status(mod.id) != statemod.INSTALLED:
            continue
        current = module_fingerprint(mod, kit_dir)
        if st.entry(mod.id).get("fingerprint") != current:
            updates[mod.id] = current
    return updates


# Modules that read KIT_PERMISSIONS (approval mode of the AI harnesses); the installer asks once for these.
PERMISSION_MODULES = ("30-agent-setup",)
PERMISSION_MODES = ("bypass", "ask")


def saved_permissions():
    """The mode kit-sync saved in kit.conf earlier, or None."""
    conf = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
                        "work-kit", "kit.conf")
    try:
        with open(conf, encoding="utf-8") as fh:
            for line in fh:
                key, sep, value = line.partition("=")
                if sep and key.strip() == "permissions" and value.strip() in PERMISSION_MODES:
                    return value.strip()
    except OSError:
        pass
    return None


def module_options(args, run_ids, interactive):
    """Options passed to the modules as environment. Returns (options, note or None).

    permissions: --permissions, else KIT_PERMISSIONS from the environment, else (menu mode, first time
    30-agent-setup is installed) one question. Without an answer nothing is passed and kit-sync uses
    its saved mode or the default (bypass)."""
    if not any(m in PERMISSION_MODULES for m in run_ids):
        return {}, None
    mode, why = args.permissions, "--permissions"
    if not mode and os.environ.get("KIT_PERMISSIONS") in PERMISSION_MODES:
        mode, why = os.environ["KIT_PERMISSIONS"], "KIT_PERMISSIONS"
    if not mode and interactive and not args.dry_run and saved_permissions() is None:
        mode, why = ui.ask_permissions(PERMISSION_MODES), "your answer"
    if not mode:
        return {}, "permissions: %s (saved setting or default; --permissions bypass|ask changes it)" % (
            saved_permissions() or "bypass")
    return {"KIT_PERMISSIONS": mode}, "permissions: %s (%s)" % (mode, why)


def one_line(text, limit=200):
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def failure_details(lines, code):
    """Reason = last line that looks like an error; step = last progress line before it."""
    lines = [ln.rstrip() for ln in lines if ln.strip()]
    if not lines:
        return "exit code %s, no output" % code, "start (no output)"
    idx = next((i for i in range(len(lines) - 1, -1, -1) if FAIL_RE.search(lines[i])), None)
    if idx is None:
        # No error line: the module stopped right after its last output line (e.g. under set -e).
        return "stopped without an error message (exit code %s)" % code, one_line(lines[-1])
    reason = one_line(lines[idx])
    step = ""
    for i in range(idx, -1, -1):
        if i != idx and STEP_RE.search(lines[i]) and not FAIL_RE.search(lines[i]):
            step = lines[i]
            break
    if not step:
        step = next((lines[i] for i in range(idx - 1, -1, -1) if not FAIL_RE.search(lines[i])), "start")
    return "%s (exit code %s)" % (reason, code), one_line(step)


SKIP_MARK = "KIT_MODULE_SKIPPED:"


def run_module(mod, log_path, verbose, timeout, options=None, script=None):
    """Run the module's install script (or `script`, e.g. uninstall.sh). Returns (ok, reason, step, exit_code).
    A module that prints a line "KIT_MODULE_SKIPPED: <reason>" and exits 0 skipped itself:
    step is then "skipped" and reason its message."""
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    if os.path.exists(log_path):
        os.replace(log_path, log_path + ".prev")
    tail = []
    started = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        log.write("# %s %s run %s\n" % (mod.id, "install" if script is None else script, statemod.now()))
        log.flush()
        proc = subprocess.Popen(["bash", script or mod.install], cwd=mod.path, env=run_env(options), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                                errors="replace", start_new_session=True)
        timed_out = []

        def kill(*_):
            timed_out.append(1)
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass

        if timeout:
            signal.signal(signal.SIGALRM, kill)
            signal.alarm(int(timeout))
        done = threading.Event()

        def heartbeat():
            # a long module must not look like a hang: one line per HEARTBEAT seconds
            # the log path comes once, on a line of its own ("~" keeps it inside 80 columns)
            home = os.path.expanduser("~")
            shown = "~" + log_path[len(home):] if log_path.startswith(home + os.sep) else log_path
            first = True
            while not done.wait(HEARTBEAT):
                mins = round((time.time() - started) / 60)
                if first:
                    say("      still running (%d min), details in the log:\n        %s" % (mins, shown))
                    first = False
                else:
                    say("      still running (%d min)" % mins)

        if not verbose:
            threading.Thread(target=heartbeat, daemon=True).start()
        try:
            for line in proc.stdout:
                log.write(line)
                log.flush()
                tail.append(line)
                if verbose:
                    sys.stdout.write("    | " + line)
                    sys.stdout.flush()
            proc.wait()
        except KeyboardInterrupt:
            # the module runs in its own session, so Ctrl+C does not reach it: stop it here
            done.set()
            for sig, wait in ((signal.SIGTERM, 10), (signal.SIGKILL, 5)):
                try:
                    os.killpg(proc.pid, sig)
                except OSError:
                    break
                try:
                    proc.wait(timeout=wait)
                    break
                except subprocess.TimeoutExpired:
                    continue
            log.write("# interrupted (Ctrl+C)\n")
            raise
        finally:
            done.set()
            if timeout:
                signal.alarm(0)
    code = proc.returncode
    if timed_out:
        step = one_line(next((ln for ln in reversed(tail) if ln.strip()), "start"))
        return False, "timeout after %ss" % timeout, step, code
    if code == 0:
        skip = next((ln.strip()[len(SKIP_MARK):].strip() for ln in tail if ln.strip().startswith(SKIP_MARK)), None)
        if skip is not None:
            return True, skip or "nothing to do here", "skipped", 0
        return True, "", "", 0
    reason, step = failure_details(tail, code)
    return False, reason, step, code


def took(secs):
    """Duration for the progress lines: seconds up to 2 minutes, then minutes like the heartbeat."""
    secs = int(round(secs))
    return "%ds" % secs if secs < 120 else "%d min %02d s" % (secs // 60, secs % 60)


HEARTBEAT = int(os.environ.get("KIT_INSTALL_HEARTBEAT", "60"))  # seconds between "still running" lines
CHECK_TIMEOUT = 300   # generous: a timeout marks the module failed; slow laptops exist
VERIFY_TIMEOUT = 15
TIMEOUT_PREFIX = "check timed out"


def run_check(mod, timeout=CHECK_TIMEOUT):
    """Returns (ok, message). Empty check counts as ok."""
    if not mod.check:
        return True, "no check defined"
    try:
        proc = subprocess.run(["bash", "-c", mod.check], cwd=mod.path, env=run_env(), stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                              errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "%s after %ds" % (TIMEOUT_PREFIX, timeout)
    if proc.returncode == 0:
        return True, "check ok"
    out = one_line(proc.stdout.strip().splitlines()[-1]) if proc.stdout.strip() else ""
    return False, "check failed (exit %d): %s%s" % (proc.returncode, mod.check, (" -> " + out) if out else "")


def sudo_ok():
    cmd = os.environ.get("KIT_INSTALL_SUDO_CMD", "sudo -n true")
    return subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def parse_args(argv):
    p = argparse.ArgumentParser(prog="install", description="work-kit installer")
    p.add_argument("--all", action="store_true", help="show every module, also installed ones")
    p.add_argument("--update", action="store_true", help="reinstall installed modules whose kit files changed")
    p.add_argument("--select", metavar="LIST", help="no menu: comma list of module ids (or numeric prefixes), or 'all'")
    p.add_argument("--uninstall", metavar="LIST",
                   help="remove installed modules (ids, numeric prefixes or 'all') in reverse install order")
    p.add_argument("-y", "--yes", action="store_true", help="--uninstall: no confirmation question")
    p.add_argument("--dry-run", action="store_true", help="show the plan, change nothing")
    p.add_argument("--status", action="store_true", help="show recorded state and exit")
    p.add_argument("-v", "--verbose", action="store_true", help="show module output while it runs")
    p.add_argument("--permissions", choices=PERMISSION_MODES,
                   help="approval mode of the AI harnesses (30-agent-setup): bypass (default) or ask; "
                        "without it the menu asks once")
    p.add_argument("--timeout", type=int, default=7200, metavar="SEC", help="per module limit (default 7200, 0 = none)")
    p.add_argument("--kit-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
    p.add_argument("--modules-dir", default=os.environ.get("KIT_MODULES_DIR"))
    return p.parse_args(argv)


def stale_modules(mods, st):
    """{id: message} for modules recorded as installed whose check fails now (removed by hand, for example).
    Checks run in parallel with a short limit; one that times out proves nothing and is not counted."""
    todo = [m for m in mods if st.status(m.id) == statemod.INSTALLED and m.check]
    if not todo:
        return {}
    with ThreadPoolExecutor(max_workers=min(8, len(todo))) as pool:
        results = list(pool.map(lambda m: run_check(m, VERIFY_TIMEOUT), todo))
    return {m.id: msg for m, (ok, msg) in zip(todo, results) if not ok and not msg.startswith(TIMEOUT_PREFIX)}


def is_installed(st, stale, mid):
    return st.status(mid) == statemod.INSTALLED and mid not in stale


def visible_modules(mods, st, show_all, stale=(), updates=()):
    """Menu entries: not installed, or recorded as installed but no longer passing its check.
    A group with a working installed member is hidden."""
    if show_all:
        return list(mods)
    hidden_groups = {m.group for m in mods if m.group and is_installed(st, stale, m.id)}
    return [m for m in mods if (m.id in updates or not is_installed(st, stale, m.id))
            and (not m.group or m.id in updates or m.group not in hidden_groups)]


def parse_select(text, mods, visible):
    """Returns (ids, error)."""
    ids = []
    for ref in [r.strip() for r in text.split(",") if r.strip()]:
        if ref == "all":
            ids += [m.id for m in visible if not m.group]
            continue
        m = modmod.resolve_ref(ref, mods)
        if not m:
            return None, "unknown module '%s'" % ref
        ids.append(m.id)
    return list(dict.fromkeys(ids)), None


def group_conflicts(ids, by_id):
    seen = {}
    for i in ids:
        g = by_id[i].group
        if g:
            if g in seen:
                return "%s and %s are alternatives (group '%s'): pick one" % (seen[g], i, g)
            seen[g] = i
    return None


def plan_dependencies(ids, mods, st, interactive):
    """Add missing dependencies; returns (ordered ids, immediate failures {id: (reason, step)}, notes)."""
    by_id = {m.id: m for m in mods}
    selected = list(ids)
    notes, failures = [], {}
    changed = True
    while changed:
        changed = False
        for mid in list(selected):
            if mid in failures:
                continue
            for dep in by_id[mid].depends:
                if dep in selected:
                    continue
                if dep not in by_id:
                    failures[mid] = ("dependency %s is not in this kit" % dep, "dependency check")
                    break
                ok = st.status(dep) == statemod.INSTALLED or run_check(by_id[dep])[0]
                if ok:
                    continue
                if interactive:
                    say("%s needs %s (not installed). Adding it." % (mid, dep))
                selected.append(dep)
                notes.append("added %s (required by %s)" % (dep, mid))
                changed = True
    return [m.id for m in modmod.order(mods, set(selected))], failures, notes


def nothing_shown(mods, st, stale, updates=()):
    """Message when the menu has no entry: true for the modules that are really not installed."""
    missing = [m for m in mods if not is_installed(st, stale, m.id)]
    if not missing:
        return "Nothing to install: all %d modules are installed (--all shows them)." % len(mods)
    hidden = {m.group for m in mods if m.group and is_installed(st, stale, m.id)}
    alt = [m.id for m in missing if m.group in hidden]
    text = "Nothing selected: %d of %d modules are not installed: %s. Add them with --select or --all." % (
        len(missing), len(mods), ", ".join(m.id for m in missing))
    if alt:
        text += "\n(%s: alternatives to an installed module of the same group; --select adds one anyway.)" % ", ".join(alt)
    return text


def stray_backups():
    """Backups an older kit version left directly in $HOME (name.bak-<timestamp>); never deleted here."""
    home = os.path.expanduser("~")
    try:
        names = sorted(os.listdir(home))
    except OSError:
        return []
    return [os.path.join(home, n) for n in names
            if BACKUP_RE.search(n) and os.path.isfile(os.path.join(home, n))]


def say_stray_backups():
    found = stray_backups()
    if not found:
        return
    home = os.path.expanduser("~")
    say("\nOld kit backups found beside your files in %s (kept, delete them by hand once checked):" % home)
    for path in found:
        say("  %s" % path)
    say("New backups go to %s/backups/<module>/." % data_dir())


def print_status(mods, st, stale, updates):
    for m in mods:
        e = st.entry(m.id)
        status = e.get("status", statemod.NOT_SELECTED)
        line = "%-24s %s" % (m.id, status)
        if m.id in stale:
            line += ", check failed (removed by hand?)  %s" % stale[m.id]
        if m.id in updates:
            line += ", update available"
        elif status == statemod.FAILED:
            line += "  step: %s | reason: %s | log: %s" % (e.get("step", ""), e.get("reason", ""), e.get("log", ""))
        elif status == statemod.SKIPPED:
            line += "  %s" % e.get("reason", "")
        say(line)
    say_stray_backups()


def uninstall(args, mods, by_id, st):
    """--uninstall: run uninstall.sh of the installed modules among the requested ones, dependents first."""
    if args.select is not None:
        say("install: --uninstall and --select cannot be combined")
        return 2
    installed = {m.id for m in mods if st.status(m.id) == statemod.INSTALLED}
    ids = []
    refs = [r.strip() for r in args.uninstall.split(",") if r.strip()]
    if not refs:
        say("install: --uninstall needs module ids or 'all'")
        return 2
    for ref in refs:
        if ref == "all":
            ids += sorted(installed)
            continue
        m = modmod.resolve_ref(ref, mods)
        if not m:
            say("install: unknown module '%s'" % ref)
            return 2
        ids.append(m.id)
    ids = list(dict.fromkeys(ids))
    notes = ["%s: not installed, nothing to remove" % i for i in ids if i not in installed]
    ids = [i for i in ids if i in installed]
    # An installed module that is not removed and depends on a removed one keeps it in place.
    kept = {}
    for m in mods:
        if m.id in installed and m.id not in ids:
            for d in m.depends:
                if d in ids:
                    kept.setdefault(d, []).append(m.id)
    for d, users in sorted(kept.items()):
        notes.append("%s kept: needed by %s (remove those too, or use 'all')" % (d, ", ".join(users)))
    ids = [i for i in ids if i not in kept]
    run_ids = [m.id for m in reversed(modmod.order(mods, set(ids)))]
    for n in notes:
        say("  note: " + n)
    if not run_ids:
        say("Nothing to remove.")
        return 0
    say(ui.wrap_list("Remove %d module(s), in this order: " % len(run_ids), run_ids))
    say("Notes and data folders (for example ~/work/brain) and ~/work/kit stay; each module README says what it keeps.")
    if args.dry_run:
        say("(dry run, nothing changed)")
        return 0
    if not args.yes:
        if not sys.stdin.isatty():
            say("install: not a terminal; add --yes to remove without a question")
            return 2
        sys.stdout.write("Remove them now? Type yes to continue [no]: ")
        sys.stdout.flush()
        if sys.stdin.readline().strip().lower() not in ("y", "yes"):
            say("Aborted, nothing changed.")
            return 1
    log_dir = os.path.join(data_dir(), "install-logs")
    failed = 0
    for n, mid in enumerate(run_ids, 1):
        m = by_id[mid]
        say("[%d/%d] removing %s ..." % (n, len(run_ids), mid))
        if not os.path.exists(os.path.join(m.path, "uninstall.sh")):
            failed += 1
            say("      FAILED: %s has no uninstall.sh (state unchanged)" % mid)
            continue
        log_path = os.path.join(log_dir, mid + ".uninstall.log")
        ok, reason, step, _ = run_module(m, log_path, args.verbose, args.timeout, script="uninstall.sh")
        if ok:
            st.set(mid, statemod.NOT_SELECTED)
            say("      removed")
        else:
            failed += 1
            say("      FAILED at: %s\n      reason: %s\n      log: %s (state unchanged)" % (step, reason, log_path))
        st.save()
    if failed:
        say("%d module(s) could not be removed; fix the cause and run the command again." % failed)
    return 1 if failed else 0


def main(argv):
    args = parse_args(argv)
    modules_dir = args.modules_dir or os.path.join(args.kit_dir, "modules")
    mods = modmod.discover(modules_dir)
    if not mods:
        say("install: no modules found in %s" % modules_dir)
        return 2
    by_id = {m.id: m for m in mods}
    st = statemod.State(os.path.join(data_dir(), "install-state.json"))
    if st.warning:
        say("warning: " + st.warning)
    for problem in modmod.validate(mods):
        say("warning: " + problem)

    if args.update and (args.all or args.select is not None or args.uninstall is not None or args.status):
        say("install: --update cannot be combined with --all, --select, --uninstall or --status")
        return 2

    stale = stale_modules(mods, st)
    updates = update_modules(mods, st, args.kit_dir)
    if args.status:
        print_status(mods, st, stale, updates)
        return 0

    if args.uninstall is not None:
        return uninstall(args, mods, by_id, st)

    visible = visible_modules(mods, st, args.all, stale, updates)
    hidden = len(mods) - len(visible)
    interactive = args.select is None

    if args.update:
        ids = [m.id for m in mods if m.id in updates]
        interactive = False
        if not ids:
            say("All installed modules are up to date.")
            return 0
    elif args.select is not None:
        ids, err = parse_select(args.select, mods, visible)
        if err:
            say("install: " + err)
            return 2
    elif visible:
        singles = [m for m in visible if not m.group]
        groups = {}
        for m in visible:
            if m.group:
                groups.setdefault(m.group, []).append(m)
        notes = ["work-kit installer: %d of %d modules shown." % (len(visible), len(mods))]
        n_upd = sum(1 for m in visible if m.id in updates)
        if n_upd:
            notes.append("%d installed module(s) have an update (marked UPDATE, preselected)." % n_upd)
        shown = {m.id for m in visible}
        n_inst = sum(1 for m in mods if m.id not in shown and is_installed(st, stale, m.id))
        n_alt = sum(1 for m in mods if m.id not in shown and not is_installed(st, stale, m.id))
        if n_inst:
            notes.append("%d already installed and up to date, hidden (--all shows them)." % n_inst)
        if n_alt:
            notes.append("%d hidden as alternatives to an installed module (--all shows them)." % n_alt)
        if args.all and any(is_installed(st, stale, m.id) and m.id not in updates for m in visible):
            notes.append("Installed modules start unticked: tick the ones to install again.")
        entries = {}
        for m in visible:
            if m.id in updates:
                entries[m.id] = {"status": "update", "stale": stale.get(m.id, "")}
            elif m.id in stale:
                entries[m.id] = {"status": "stale"}
            else:
                entries[m.id] = st.entry(m.id)
        ids = ui.choose(singles, groups, entries, notes)
        if ids is None:
            say("Aborted, nothing changed.")
            return 1
    else:
        ids = []
        say(nothing_shown(mods, st, stale, updates))

    err = group_conflicts(ids, by_id)
    if err:
        say("install: " + err)
        return 2
    try:
        run_ids, failures, notes = plan_dependencies(ids, mods, st, interactive)
    except ValueError as exc:
        say("install: " + str(exc))
        return 2
    err = group_conflicts(run_ids, by_id)
    if err:
        say("install: " + err)
        return 2

    for mid in run_ids:
        m = by_id[mid]
        other = [x.id for x in mods if x.group and x.group == m.group and x.id != mid and is_installed(st, stale, x.id)]
        if other:
            notes.append("%s is in group '%s' with %s (already installed)" % (mid, m.group, ", ".join(other)))
    options, perm_note = module_options(args, run_ids, interactive)
    if perm_note:
        notes.append(perm_note)
    if args.dry_run:
        say("Plan (dry run, nothing changed):")
        for mid in run_ids:
            say("  install %s%s" % (mid, "  [blocked: %s]" % failures[mid][0] if mid in failures else ""))
        for n in notes:
            say("  note: " + n)
        skipped = [m.id for m in visible if m.id not in run_ids]
        if skipped:
            say("  not selected: " + ", ".join(skipped))
        return 0
    if run_ids:
        say("\n" + ui.wrap_list("Installing %d module(s): " % len(run_ids), run_ids))
        for n in notes:
            say("  note: " + n)

    log_dir = os.path.join(data_dir(), "install-logs")
    result = {}
    skipped_now = set()
    for n, mid in enumerate(run_ids, 1):
        m = by_id[mid]
        log_path = os.path.join(log_dir, mid + ".log")
        say("[%d/%d] %s ..." % (n, len(run_ids), mid))
        t0 = time.time()
        blocked = failures.get(mid)
        if not blocked:
            bad_dep = next((d for d in m.depends if result.get(d, (True,))[0] is False), None)
            if bad_dep:
                blocked = ("dependency %s failed" % bad_dep, "dependency check")
        if not blocked and m.needs_sudo and not sudo_ok():
            blocked = ("needs sudo but no cached credentials; run 'sudo -v' first, then install again", "sudo check")
        if blocked:
            ok, reason, step, code = False, blocked[0], blocked[1], None
            os.makedirs(log_dir, exist_ok=True)
            with open(log_path, "w", encoding="utf-8") as fh:
                fh.write("# not run: %s\n" % reason)
        else:
            try:
                ok, reason, step, code = run_module(m, log_path, args.verbose, args.timeout, options)
            except KeyboardInterrupt:
                st.set(mid, statemod.FAILED, reason="interrupted (Ctrl+C)", step="interrupted", log=log_path, exit_code=130)
                st.save()
                say("\nStopped (Ctrl+C) during %s; it was stopped too. Run the same command again to finish." % mid)
                return 130
        result[mid] = (ok,)
        if ok and step == "skipped":
            skipped_now.add(mid)
            st.set(mid, statemod.SKIPPED, reason=reason, step=step, log=log_path, exit_code=0)
            say("      skipped, nothing changed: %s" % reason)
        elif ok:
            st.set(mid, statemod.INSTALLED, log=log_path, exit_code=0,
                   fingerprint=module_fingerprint(m, args.kit_dir))
            say("      installed (%s)" % took(time.time() - t0))
        else:
            st.set(mid, statemod.FAILED, reason=reason, step=step, log=log_path, exit_code=code)
            say("      FAILED at: %s\n      reason: %s\n      log: %s" % (step, reason, log_path))
        st.save()

    for m in visible:
        if m.id not in run_ids and st.status(m.id) == statemod.NOT_SELECTED:
            st.set(m.id, statemod.NOT_SELECTED)
    st.save()

    report(mods, st)
    if result.get("95-desktop", (False,))[0] and "95-desktop" not in skipped_now:
        offer_logout(interactive)
    return 1 if any(st.status(mid) == statemod.FAILED for mid in run_ids) else 0


DESKTOP_MODULE = "95-desktop"
LOGOUT_TEXT = "Log out and back in now to finish the desktop setup"


def desktop_session():
    """'gnome', 'kde' or None, from XDG_CURRENT_DESKTOP (a colon list such as 'ubuntu:GNOME')."""
    names = (os.environ.get("XDG_CURRENT_DESKTOP", "") + ":" + os.environ.get("DESKTOP_SESSION", "")).lower()
    if "gnome" in names:
        return "gnome"
    if "kde" in names or "plasma" in names:
        return "kde"
    return None


def logout_command(kind):
    """Argument list that ends the desktop session, or None if the tool is missing.
    KIT_INSTALL_LOGOUT_CMD replaces it (tests)."""
    forced = os.environ.get("KIT_INSTALL_LOGOUT_CMD")
    if forced:
        return ["bash", "-c", forced]
    if kind == "gnome":
        return ["gnome-session-quit", "--logout", "--no-prompt"] if shutil.which("gnome-session-quit") else None
    for tool in ("qdbus", "qdbus6", "qdbus-qt5"):
        if shutil.which(tool):
            return [tool, "org.kde.Shutdown", "/Shutdown", "logout"]
    return None


def offer_logout(interactive):
    """After 95-desktop ran in this run: a final box, and a logout only after an explicit yes."""
    kind = desktop_session()
    if not kind:
        return
    line = "  %s  " % LOGOUT_TEXT
    say("\n+%s+\n|%s|\n+%s+" % ("-" * len(line), line, "-" * len(line)))
    cmd = logout_command(kind)
    if cmd is None or not (interactive or sys.stdin.isatty()):
        say("Save your work, then log out from the desktop menu.")
        return
    sys.stdout.write("Log out now? Unsaved work in open windows is lost. Type yes to log out [no]: ")
    sys.stdout.flush()
    answer = sys.stdin.readline().strip().lower()
    if answer not in ("y", "yes"):
        say("Not logging out. Do it yourself when you are ready.")
        return
    say("Logging out ...")
    subprocess.run(cmd, stdin=subprocess.DEVNULL)


def report(mods, st):
    """Check every installed module (a failing check marks it failed) and print the report."""
    say("\nCheck report")
    bad = False
    for m in mods:
        e = st.entry(m.id)
        status = e.get("status", statemod.NOT_SELECTED)
        if status == statemod.INSTALLED:
            ok, msg = run_check(m)
            if not ok:
                st.set(m.id, statemod.FAILED, reason=msg, step="check", log=e.get("log", ""))
                st.save()
                status = statemod.FAILED
                e = st.entry(m.id)
            else:
                say("  %-24s installed   %s" % (m.id, msg))
                continue
        if status == statemod.SKIPPED:
            say("  %-24s skipped     %s" % (m.id, e.get("reason", "")))
            continue
        if status == statemod.FAILED:
            bad = True
            say("  %-24s FAILED" % m.id)
            say("      step:   %s\n      reason: %s\n      log:    %s" % (e.get("step", ""), e.get("reason", ""), e.get("log", "")))
        else:
            say("  %-24s not selected" % m.id)
    say("State: %s" % st.path)
    say_stray_backups()
    if bad:
        say("Some modules failed. Fix the cause and run kit/install again: it shows only failed and unselected modules.")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        say("\nStopped (Ctrl+C).")
        sys.exit(130)
