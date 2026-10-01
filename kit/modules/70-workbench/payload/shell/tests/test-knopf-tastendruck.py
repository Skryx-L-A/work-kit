#!/usr/bin/env python3
"""Prueft den Knopf (Prefix + S) mit einem ECHTEN Client — auf eigenem Socket.

`tmux send-keys` taugt dafuer nicht: es schreibt in das Pseudo-Terminal des Panes und
laeuft damit an der Tastenbelegung vorbei. Tastenbindungen wertet tmux nur fuer Eingaben
eines angehaengten CLIENTS aus. Hier haengt sich deshalb ein echter Client ueber ein
Pseudo-Terminal an, und die Tasten gehen in dessen Eingabe.

Es wird die INSTALLIERTE ~/.tmux.conf geladen (-f), aber auf einem eigenen Socket, damit
keine laufende Session beruehrt wird.
"""
import os
import pty
import shutil
import signal
import subprocess
import sys
import tempfile
import time

SOCKET = "wbtest-knopf-%d" % os.getpid()
BASE = "wb-knopfprobe"
READY_TIMEOUT = 5.0
COMMAND_TIMEOUT = 5.0


def main():
    # Resolve the installed configuration before replacing HOME with the disposable
    # test HOME. The configuration itself is the behaviour under test; all tmux state
    # belongs to this run through the private socket and TMUX_TMPDIR.
    tmux_conf = os.path.expanduser("~/.tmux.conf")
    test_home = tempfile.mkdtemp(prefix="wb-knopf-home-")
    # macOS limits the complete UNIX socket path. A short /tmp root keeps the
    # PID-derived socket name readable while still giving this run its own
    # TMUX_TMPDIR.
    tmux_tmpdir = tempfile.mkdtemp(prefix="wbk-", dir="/tmp")
    env = dict(os.environ)
    env.pop("TMUX", None)
    env.pop("TMUX_PANE", None)
    env["HOME"] = test_home
    env["TMUX_TMPDIR"] = tmux_tmpdir
    # `env -i` (the launchd-like invocation used by this suite) has no TERM,
    # but tmux still needs a terminal type once the pty client is attached.
    if not env.get("TERM"):
        env["TERM"] = "xterm-256color"
    os.environ.clear()
    os.environ.update(env)

    client_pid = None
    client_fd = None
    ok = False
    try:
        print("Geprueft: installierte %s (Ausnahme -- die Tastenbindung selbst laeuft nur "
              "aus der echten, geladenen Konfiguration; siehe Kopfkommentar)" % tmux_conf)

        if not shutil.which("tmux"):
            print("FEHLGESCHLAGEN: tmux ist nicht im PATH", file=sys.stderr)
            return 1
        if not os.path.isfile(tmux_conf):
            # Kit: ~/.tmux.conf comes from kit module 60-terminal, not from the workbench.
            print("UEBERSPRUNGEN: nicht auf dieser Maschine: keine %s (Kit-Modul 60-terminal)" % tmux_conf)
            return 77

        def tm(*args):
            try:
                return subprocess.run(
                    ["tmux", "-L", SOCKET, *args],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=COMMAND_TIMEOUT,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                print("tmux-Aufruf fehlgeschlagen: %s" % exc, file=sys.stderr)
                return None

        def sessions():
            result = tm("list-sessions", "-F", "#{session_name}")
            if result is None:
                return None
            return sorted(s for s in result.stdout.split() if s)

        def clients():
            result = tm("list-clients", "-F", "#{client_tty}\t#{client_session}")
            if result is None or result.returncode != 0:
                return []
            return [line for line in result.stdout.splitlines() if line]

        def fail(reason):
            print("FEHLGESCHLAGEN: %s" % reason, file=sys.stderr)
            return 1

        # A stale server with this PID-derived name is not expected, but removing it
        # keeps reruns deterministic without touching any other tmux server.
        tm("kill-server")
        created = tm("-f", tmux_conf, "new-session", "-d", "-s", BASE, "-c", "/tmp")
        if created is None or created.returncode != 0:
            detail = "" if created is None else (created.stderr or created.stdout).strip()
            return fail("eigene tmux-Session liess sich nicht anlegen%s" %
                        (": " + detail if detail else ""))
        view = tm("new-session", "-d", "-t", BASE, "-s", BASE + "-view")
        if view is None or view.returncode != 0:
            detail = "" if view is None else (view.stderr or view.stdout).strip()
            return fail("eigene Sicht-Session liess sich nicht anlegen%s" %
                        (": " + detail if detail else ""))
        vorher = sessions()
        if vorher is None:
            return fail("eigene tmux-Sessions konnten nicht gelesen werden")
        print("vorher:", vorher)

        # Echten Client an die Sicht-Session haengen, so wie das VS-Code-Terminal es tut.
        try:
            client_pid, client_fd = pty.fork()
        except (OSError, RuntimeError) as exc:
            return fail("kein Pseudoterminal fuer den tmux-Client verfuegbar: %s" % exc)
        if client_pid == 0:                       # Kind: IST der Client
            os.execvp("tmux", ["tmux", "-L", SOCKET, "attach", "-t", BASE + "-view"])
            os._exit(1)

        deadline = time.monotonic() + READY_TIMEOUT
        sicht_client = []
        while time.monotonic() < deadline:
            sicht_client = [line for line in clients() if line.endswith("\t" + BASE + "-view")]
            if sicht_client:
                break
            try:
                waited, status = os.waitpid(client_pid, os.WNOHANG)
            except ChildProcessError:
                return fail("tmux-Client verschwand vor der Bereitschaft")
            if waited == client_pid:
                return fail("tmux-Client endete vor der Bereitschaft (Status %s)" % status)
            time.sleep(0.1)
        print("Client:", sicht_client[0] if sicht_client else "(keiner)")
        if not sicht_client:
            return fail("tmux-Client wurde innerhalb von %.1fs nicht sichtbar" % READY_TIMEOUT)

        # Die bestehenden Pruefungen bleiben unveraendert: echte Tasten, Rueckfrage,
        # anschliessend sind beide eigenen Sessions verschwunden.
        os.write(client_fd, b"\x02")       # Prefix C-b
        time.sleep(0.7)
        os.write(client_fd, b"S")          # die Bindung
        time.sleep(1.5)
        frage_result = tm("display-message", "-p", "-t", BASE, "#{client_prompt}")
        frage = "" if frage_result is None else frage_result.stdout.strip()
        print("Rueckfrage im Client:", frage or "(nicht auslesbar)")
        os.write(client_fd, b"y")           # bestaetigen
        time.sleep(3)

        danach = sessions()
        if danach is None:
            return fail("eigene tmux-Sessions konnten nach dem Tastendruck nicht gelesen werden")
        print("nachher:", danach)
        ok = danach == []
        print("ERGEBNIS:", "Knopf schliesst die eigene Session samt Sicht — bestanden" if ok
              else "FEHLGESCHLAGEN, es leben noch: %s" % danach)
        return 0 if ok else 1
    except (OSError, subprocess.SubprocessError) as exc:
        print("FEHLGESCHLAGEN: Test konnte den eigenen tmux-Client nicht steuern: %s" % exc,
              file=sys.stderr)
        return 1
    finally:
        # Client zuerst beenden -- er haengt ueber das PTY weiter und ueberlebt sonst
        # den kill-server-Aufruf (haelt den Socket ggf. noch offen).
        if client_pid is not None:
            try:
                os.kill(client_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + READY_TIMEOUT
            while time.monotonic() < deadline:
                try:
                    waited, _ = os.waitpid(client_pid, os.WNOHANG)
                except ChildProcessError:
                    client_pid = None
                    break
                if waited == client_pid:
                    client_pid = None
                    break
                time.sleep(0.1)
            if client_pid is not None:
                try:
                    os.kill(client_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    os.waitpid(client_pid, 0)
                except ChildProcessError:
                    pass
        if client_fd is not None:
            try:
                os.close(client_fd)
            except OSError:
                pass

        def cleanup_tmux():
            try:
                subprocess.run(
                    ["tmux", "-L", SOCKET, "kill-server"],
                    env=env,
                    capture_output=True,
                    timeout=COMMAND_TIMEOUT,
                )
            except (OSError, subprocess.SubprocessError):
                pass

        cleanup_tmux()
        deadline = time.monotonic() + READY_TIMEOUT
        while time.monotonic() < deadline:
            try:
                still_running = subprocess.run(
                    ["tmux", "-L", SOCKET, "list-sessions"],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=COMMAND_TIMEOUT,
                ).returncode == 0
            except (OSError, subprocess.SubprocessError):
                still_running = False
            if not still_running:
                break
            cleanup_tmux()
            time.sleep(0.3)
        if still_running:
            print("WARNUNG: eigener tmux-Server auf Socket %s laeuft noch" % SOCKET,
                  file=sys.stderr)
        else:
            print("tmux-Server: beendet")
            try:
                shutil.rmtree(tmux_tmpdir)
                shutil.rmtree(test_home)
            except OSError as exc:
                print("WARNUNG: Testverzeichnisse liessen sich nicht entfernen: %s" % exc,
                      file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
