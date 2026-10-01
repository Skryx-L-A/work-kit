#!/usr/bin/env python3
"""Ein Stellvertreter fuer eine Claude-Code-SITZUNG mit Socket-Inbox --
das Gegenstueck zu fake-tui.py fuer den zweiten Zustellweg.

WOZU (2026-08-20, Stresstest der Zustellung). Der Inbox-Weg (shell/wb-inbox)
liess sich bisher nicht in der Suite messen: er braucht eine echte,
ANGEMELDETE Claude-Sitzung, und mit umgelenktem HOME meldet Claude Code
"Not logged in" (gemessen, siehe Kopf von test-inbox-zustellung.sh). Damit war
genau der Weg ungetestet, der im Betrieb ab heute der Normalfall ist -- und
jeder Zustellfehler dieser Sitzung ist im BETRIEB aufgefallen, nicht im Test.

Dieser Stellvertreter schliesst die Luecke. Er tut genau das, woran wb-inbox
eine Sitzung erkennt und woran pi-worker die Ankunft belegt, und sonst nichts:

  * er traegt sich in $HOME/.claude/sessions/<pid>.json ein (pid, sessionId,
    cwd, tmux, messagingSocketPath, name, status) und legt die Schluesseldatei
    <pid>.<hash>.key mit dem peerToken daneben, beide 0600,
  * er BINDET den Socket wirklich und liest die zwei Zeilen des Protokolls
    (auth, dann user), so wie die CLI sie erwartet,
  * er ZEIGT den empfangenen Text im Pane (dort sucht pi-worker den Marker)
    und schreibt ihn in die Gespraechsdatei
    $HOME/.claude/projects/<ordner>/<sessionId>.jsonl (die zweite Belegquelle),
  * und er legt jede empfangene Nachricht WORTGLEICH als eigene Datei ab --
    0001.txt, 0002.txt, ... in Ankunftsreihenfolge. Erst das macht die zwei
    Fragen messbar, die unter Last zaehlen: kam jede an, und kam sie in der
    richtigen Reihenfolge an.

Er ist ausdruecklich KEIN Claude: er beantwortet nichts, er arbeitet nicht, er
denkt nicht. Er ist die Empfangsstelle, gegen die sich die Zustellung messen
laesst.

Spielarten (FAKE_CC_MODE):
  normal        Wie oben beschrieben.
  taub          Sitzung eingetragen, Socket gebunden, Nachricht wird
                ENTGEGENGENOMMEN -- und dann verschluckt: nichts im Pane,
                nichts in der Gespraechsdatei. Das gemessene Schadensbild der
                Nacht auf den 20.08., auf den Socketweg uebertragen. Erwartung
                an pi-worker: lauter Fehlschlag, kein Platzhalter.
  totersocket   Registereintrag zeigt auf einen Pfad, an dem NIEMAND lauscht
                (eine gewoehnliche Datei). `wb-inbox finde` findet die Sitzung,
                `sende` muss daran scheitern.
  fremde-pid    Ein ANDERER Prozess (ein Kind) haelt den Socket, im Register
                steht die pid des Elternprozesses. Die Gegenstellen-Pruefung
                von wb-inbox (LOCAL_PEERPID) muss das bemerken.
  kein-eintrag  Socket gebunden, aber kein Registereintrag -- niemand kann die
                Sitzung finden, und niemand darf sie raten.

Weitere Umgebungsvariablen:
  FAKE_CC_SOCK     Socketpfad (Vorgabe: /tmp/wb-fakecc-<pid>.sock). Kurz halten,
                   AF_UNIX-Pfade sind auf macOS auf ~104 Zeichen begrenzt.
  FAKE_CC_NAME     Sitzungsname im Register (Vorgabe: fake-<pid>).
  FAKE_CC_STATUS   idle|busy -- was das Register meldet (Vorgabe: idle).
  FAKE_CC_RECV     Ordner fuer die wortgleichen Empfangsdateien.
  FAKE_CC_DELAY    Sekunden, die zwischen Empfang und Anzeige im Pane liegen --
                   die Turn-Grenze einer beschaeftigten Sitzung (Vorgabe: 0).
  FAKE_CC_READY    Zeile, die beim Start gedruckt wird (readyPattern des Harness).
  FAKE_CC_ALT      1 = in den ALTERNATE SCREEN wechseln, wie Claude Code es tut.
                   Das ist keine Kosmetik: tmux fuehrt fuer den Alternate Screen
                   KEINEN Verlauf (gemessen 2026-08-20: alternate_on=1 ergibt
                   history_size=0), und damit liefert `capture-pane -S -2000`
                   nur noch das sichtbare Bild. Ein Marker, der aus dem Bild
                   gescrollt ist, ist fuer die Pane-Pruefung endgueltig weg.
  FAKE_CC_ARBEIT   Zeilen, die nach der Anzeige gedruckt werden -- so viele, dass
                   der Marker aus dem sichtbaren Bild wandert. Bildet nach, dass
                   eine Sitzung nach dem Empfang sofort zu arbeiten anfaengt.
  FAKE_CC_TRANSCRIPT_NACH
                   Sekunden, die vergehen, bevor die Gespraechsdatei ueberhaupt
                   ANGELEGT wird (Vorgabe 0, also sofort beim Start -- so macht
                   es die echte Sitzung, gemessen: Datei zwei Sekunden nach dem
                   Start da). Ein hoher Wert bildet den frischen Spawn nach, bei
                   dem pi-worker die Datei sucht, bevor es sie gibt.
  FAKE_CC_SCHLUCK  Pfad einer Schaltdatei. Existiert sie im Moment des Empfangs,
                   verhaelt sich diese eine Nachricht wie unter 'taub': sie wird
                   entgegengenommen und danach verschluckt. Damit laesst sich das
                   Verschlucken MITTEN in einer laufenden Sitzung ausloesen -- der
                   Fall, den eine feste Spielart nicht abbilden kann.
"""

import json
import os
import socket
import sys
import threading
import time
import uuid

MODE = os.environ.get("FAKE_CC_MODE", "normal")
SOCK = os.environ.get("FAKE_CC_SOCK") or "/tmp/wb-fakecc-%d.sock" % os.getpid()
NAME = os.environ.get("FAKE_CC_NAME") or "fake-%d" % os.getpid()
STATUS = os.environ.get("FAKE_CC_STATUS", "idle")
RECV = os.environ.get("FAKE_CC_RECV", "")
DELAY = float(os.environ.get("FAKE_CC_DELAY", "0") or 0)
READY = os.environ.get("FAKE_CC_READY", "fake-claude bereit")
SCHLUCK = os.environ.get("FAKE_CC_SCHLUCK", "")
ALT = os.environ.get("FAKE_CC_ALT", "") == "1"
ARBEIT = int(os.environ.get("FAKE_CC_ARBEIT", "0") or 0)
TRANSCRIPT_NACH = float(os.environ.get("FAKE_CC_TRANSCRIPT_NACH", "0") or 0)

HOME = os.path.expanduser("~")
SESSIONS = os.path.join(HOME, ".claude", "sessions")
SESSION_ID = str(uuid.uuid4())
TOKEN = uuid.uuid4().hex + uuid.uuid4().hex
PROJEKT = os.path.join(HOME, ".claude", "projects", "fake-cc")
TRANSCRIPT = os.path.join(PROJEKT, "%s.jsonl" % SESSION_ID)

zaehler = 0
schloss = threading.Lock()
# Die Gespraechsdatei EXISTIERT ab einem bestimmten Moment -- vorher gibt es sie
# nicht, auch nicht halb. Wer hineinschreiben will, wartet darauf. Ohne dieses
# Signal wuerde eine empfangene Nachricht die Datei sofort anlegen und die
# Verzoegerung waere wirkungslos (2026-08-20, erste Reproduktion lief deshalb ins
# Leere: pi-worker fand die Datei doch, und der Fehlalarm blieb aus).
transcript_da = threading.Event()


def registrieren(pid):
    """Der Eintrag, an dem wb-inbox eine Sitzung ueberhaupt erst erkennt."""
    os.makedirs(SESSIONS, exist_ok=True)
    jetzt = int(time.time() * 1000)
    eintrag = {
        "pid": pid,
        "sessionId": SESSION_ID,
        "cwd": os.getcwd(),
        "startedAt": jetzt,
        "version": "fake",
        "host2Protocol": 1,
        "kind": "interactive",
        "entrypoint": "cli",
        "tmux": os.environ.get("FAKE_CC_TMUX", ""),
        "messagingSocketPath": SOCK,
        "name": NAME,
        "status": STATUS,
        "updatedAt": jetzt,
        "statusUpdatedAt": jetzt,
    }
    pfad = os.path.join(SESSIONS, "%d.json" % pid)
    with open(pfad, "w") as f:
        json.dump(eintrag, f)
    os.chmod(pfad, 0o600)
    schluessel = os.path.join(SESSIONS, "%d.%s.key" % (pid, uuid.uuid4().hex))
    with open(schluessel, "w") as f:
        json.dump({"peerToken": TOKEN}, f)
    os.chmod(schluessel, 0o600)
    return pfad, schluessel


def merken(text):
    """Die empfangene Nachricht WORTGLEICH und in Ankunftsreihenfolge ablegen."""
    global zaehler
    if not RECV:
        return 0
    with schloss:
        zaehler += 1
        n = zaehler
    os.makedirs(RECV, exist_ok=True)
    # Erst vollstaendig schreiben, dann an den endgueltigen Namen umbenennen --
    # sonst sieht ein gleichzeitig zaehlender Test eine halb geschriebene Datei
    # und haelt eine angekommene Nachricht fuer verstuemmelt.
    roh = os.path.join(RECV, ".%04d.teil" % n)
    with open(roh, "w", encoding="utf-8") as f:
        f.write(text)
    os.rename(roh, os.path.join(RECV, "%04d.txt" % n))
    return n


def transcript_anlegen():
    """Die Gespraechsdatei anlegen, wie eine echte Sitzung es beim Start tut.

    Gemessen am eigenen Fehlalarm (2026-08-20): die Datei der um 14:41:38
    gestarteten Sitzung wurde um 14:41:40 angelegt, und der Auftrag stand
    15 Millisekunden nach dem Enqueue als user-Turn darin. Die Datei ist also
    fast sofort da -- aber eben nicht in derselben Sekunde, und pi-worker
    fragte genau in dieser Luecke.
    """
    if TRANSCRIPT_NACH > 0:
        time.sleep(TRANSCRIPT_NACH)
    os.makedirs(PROJEKT, exist_ok=True)
    with open(TRANSCRIPT, "a", encoding="utf-8"):
        pass
    transcript_da.set()


def in_transcript(text):
    # Solange es die Datei noch nicht gibt, gibt es auch keinen Eintrag darin.
    transcript_da.wait(300)
    os.makedirs(PROJEKT, exist_ok=True)
    zeile = json.dumps({
        "type": "user",
        "sessionId": SESSION_ID,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "message": {"role": "user", "content": text},
    })
    with open(TRANSCRIPT, "a", encoding="utf-8") as f:
        f.write(zeile + "\n")


def anzeigen(n, text):
    """Im Pane sichtbar machen -- dort sucht pi-worker seinen Marker."""
    sys.stdout.write("\r\n--- Nachricht %d ---\r\n" % n)
    for zeile in text.split("\n"):
        sys.stdout.write(zeile + "\r\n")
    sys.stdout.write("--- Ende %d ---\r\n" % n)
    for i in range(ARBEIT):
        sys.stdout.write("arbeitet, Zeile %03d\r\n" % i)
    sys.stdout.flush()


def bedienen(verbindung):
    verbindung.settimeout(10)
    puffer = b""
    try:
        while b"\n" not in puffer or len(puffer.split(b"\n")) < 3:
            try:
                teil = verbindung.recv(65536)
            except socket.timeout:
                break
            if not teil:
                break
            puffer += teil
            if puffer.count(b"\n") >= 2:
                break
    finally:
        try:
            verbindung.close()
        except OSError:
            pass
    for zeile in puffer.split(b"\n"):
        if not zeile.strip():
            continue
        try:
            d = json.loads(zeile.decode("utf-8"))
        except Exception:
            continue
        if d.get("type") != "user":
            continue
        inhalt = d.get("message", {}).get("content", "")
        if not isinstance(inhalt, str):
            inhalt = json.dumps(inhalt)
        n = merken(inhalt)
        if MODE == "taub" or (SCHLUCK and os.path.exists(SCHLUCK)):
            # Entgegengenommen und verschluckt. Genau das Schadensbild, gegen
            # das der Beleg in pi-worker gebaut ist.
            continue
        if DELAY > 0:
            time.sleep(DELAY)
        anzeigen(n, inhalt)
        in_transcript(inhalt)


def lauschen(server):
    while True:
        try:
            verbindung, _ = server.accept()
        except OSError:
            return
        # Nacheinander bedienen, nicht nebenlaeufig: die Ankunftsreihenfolge
        # ist eine der beiden Fragen, die dieser Stellvertreter beantworten
        # soll, und ein Thread je Verbindung wuerde sie selbst verwuerfeln.
        bedienen(verbindung)


def binden():
    try:
        os.makedirs(os.path.dirname(SOCK), exist_ok=True)
    except OSError:
        pass
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK)
    server.listen(16)
    return server


def main():
    if ALT:
        sys.stdout.write("\x1b[?1049h")
    sys.stdout.write("%s\r\n" % READY)
    sys.stdout.write("Sitzung %s, Socket %s, Modus %s\r\n" % (NAME, SOCK, MODE))
    sys.stdout.flush()

    if MODE == "totersocket":
        # Ein Pfad, an dem niemand lauscht: die Datei existiert (wb-inbox
        # prueft os.path.exists), connect() muss daran scheitern.
        try:
            os.makedirs(os.path.dirname(SOCK), exist_ok=True)
        except OSError:
            pass
        with open(SOCK, "w") as f:
            f.write("")
        registrieren(os.getpid())
    elif MODE == "fremde-pid":
        # Der Socket gehoert einem KIND, das Register nennt den Elternprozess.
        eltern = os.getpid()
        kind = os.fork()
        if kind == 0:
            try:
                server = binden()
                lauschen(server)
            except Exception:
                pass
            os._exit(0)
        # Warten, bis das Kind wirklich gebunden hat -- sonst misst der Test
        # den Wettlauf statt die Zusage.
        frist = time.time() + 5
        while time.time() < frist and not os.path.exists(SOCK):
            time.sleep(0.05)
        registrieren(eltern)
    elif MODE == "kein-eintrag":
        server = binden()
        threading.Thread(target=lauschen, args=(server,), daemon=True).start()
    else:
        server = binden()
        threading.Thread(target=lauschen, args=(server,), daemon=True).start()
        registrieren(os.getpid())

    # Die Gespraechsdatei im Hintergrund anlegen -- verzoegerbar, siehe oben.
    if MODE not in ("totersocket",):
        threading.Thread(target=transcript_anlegen, daemon=True).start()

    # Am Leben bleiben und wie eine TUI von stdin lesen, ohne darauf zu
    # reagieren -- der Prozess muss laufen, sonst raeumt wb-inbox die Sitzung
    # zu Recht als tot ab.
    try:
        while True:
            daten = os.read(sys.stdin.fileno(), 4096)
            if not daten:
                time.sleep(0.5)
    except (OSError, KeyboardInterrupt):
        while True:
            time.sleep(1)


main()
