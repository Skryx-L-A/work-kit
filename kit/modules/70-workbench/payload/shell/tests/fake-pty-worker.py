#!/usr/bin/env python3
"""Stellvertreter fuer einen Agenten, der AUF EINEM PSEUDO-TERMINAL laeuft --
fuer test-pty-wache.sh (Probe fuer Option E, 04.09.2026).

Absichtlich eng an fake-claude-anschluss.py gebaut, denn die Probe vergleicht
zwei Wege gegen DENSELBEN Inhalt: derselbe Stellvertreter laeuft einmal in einem
tmux-Pane und einmal auf einem Pseudo-Terminal, und die Wache muss beide Male
dieselbe Auslastung melden. Waeren es zwei verschiedene Stellvertreter, waere der
Vergleich keiner.

Er benutzt die ECHTE Claude-Code-Statuszeilen-Schreibweise ('820k/1.0M'), damit
Quelle 1 aus read_load() greift -- dieselbe, die im Betrieb greift.

Umgebung:
  FAKE_PCT        Auslastung in Prozent (Vorgabe 82).
  FAKE_PCT_NACH   Auslastung nach dem Kompaktieren (Vorgabe 5).
  FAKE_LAGE       Datei, aus der die Lage gelesen wird: 'normal' oder 'dialog'.
                  Wird bei JEDEM Zeichnen neu gelesen, damit die Suite die Lage
                  umschalten kann, ohne den Prozess neu zu starten.
  FAKE_LOG        bekommt je Enter eine Zeile 'ENTER <text>'.
  FAKE_MERKWORT   Steht nach dem Start auf dem Schirm. Die Wiederaufnahme-Probe
                  prueft daran, ob nach einem Neustart DIESELBE Unterhaltung
                  wieder da ist.
  FAKE_SITZUNGEN  Ordner der Sitzungsdateien -- der Stellvertreter fuer
                  ~/.claude/projects/<slug>/<sessionId>.jsonl.

Aufrufform, genau die eines Harness mit Fortsetzung:
  fake-pty-worker.py                  frische Sitzung: legt <zufall>.jsonl an und
                                      schreibt FAKE_MERKWORT hinein
  fake-pty-worker.py --resume <id>    setzt fort: liest <id>.jsonl und zeigt das
                                      Merkwort, das darin steht
"""
import os
import select
import sys
import termios
import time
import tty

PCT = int(os.environ.get("FAKE_PCT", "82"))
PCT_NACH = int(os.environ.get("FAKE_PCT_NACH", "5"))
LAGE_DATEI = os.environ.get("FAKE_LAGE", "")
LOG = os.environ.get("FAKE_LOG", "")
MERKWORT = os.environ.get("FAKE_MERKWORT", "")
SITZUNGEN = os.environ.get("FAKE_SITZUNGEN", "")
RESUME_ID = ""
if "--resume" in sys.argv:
    i = sys.argv.index("--resume")
    if i + 1 < len(sys.argv):
        RESUME_ID = sys.argv[i + 1]

buf = ""
gesehen = ""   # die Unterhaltung, so weit sie auf dem Schirm steht


def merke_enter(text):
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("ENTER %s\n" % text)
    except OSError:
        pass


def lage():
    if not LAGE_DATEI:
        return "normal"
    try:
        with open(LAGE_DATEI) as f:
            return f.read().strip() or "normal"
    except OSError:
        return "normal"


def zeichne():
    zeilen = ["Stellvertreter auf einem Pseudo-Terminal", ""]
    if gesehen:
        zeilen.append(gesehen)
        zeilen.append("")
    if lage() == "dialog":
        # Genau die Form, an der pane_dialog_question() einen wartenden
        # Auswahldialog erkennt: eine Frage, die auf '?' endet, darunter
        # nummerierte Punkte, einer davon mit dem Auswahlzeiger.
        zeilen.append("Dangerous rm operation. Do you want to proceed?")
        zeilen.append("❯ 1. Ja, einmal")
        zeilen.append("  2. Nein, abbrechen")
        zeilen.append("")
    zeilen.append("  %dk/1.0M" % (PCT * 10))
    zeilen.append("❯ %s" % buf)
    sys.stdout.write("\x1b[H\x1b[2J" + "\r\n".join(zeilen))
    sys.stdout.flush()


def absenden():
    global buf, PCT, gesehen
    text = buf
    merke_enter(text)
    if "/compact" in text:
        PCT = PCT_NACH
    elif text.strip():
        gesehen = "gesehen: %s" % text.strip()
    buf = ""


def merkwort_holen():
    """Die Unterhaltung ueber einen Neustart hinweg -- genau der Weg, den ein
    echter Harness geht: sie liegt in einer Sitzungsdatei, deren NAME die
    Sitzungskennung ist, und '--resume <id>' holt sie zurueck."""
    if not SITZUNGEN:
        return MERKWORT
    if RESUME_ID:
        try:
            with open(os.path.join(SITZUNGEN, RESUME_ID + ".jsonl")) as f:
                return f.read().strip()
        except OSError:
            return ""
    try:
        os.makedirs(SITZUNGEN, exist_ok=True)
        sid = "%d-%d" % (int(time.time()), os.getpid())
        with open(os.path.join(SITZUNGEN, sid + ".jsonl"), "w") as f:
            f.write(MERKWORT + "\n")
    except OSError:
        pass
    return MERKWORT


def main():
    global buf, gesehen
    wort = merkwort_holen()
    if wort:
        gesehen = "Merkwort: %s" % wort
    fd = sys.stdin.fileno()
    try:
        alt = termios.tcgetattr(fd)
    except termios.error:
        alt = None
    if alt is not None:
        tty.setraw(fd)
    try:
        sys.stdout.write("\x1b[?2004h")
        sys.stdout.flush()
        zeichne()
        im_paste = False
        rest = b""
        letzte = 0.0
        while True:
            r, _, _ = select.select([fd], [], [], 0.15)
            neu = False
            if r:
                daten = os.read(fd, 4096)
                if not daten:
                    break
                daten = rest + daten
                rest = b""
                i = 0
                while i < len(daten):
                    if daten[i:i + 6] == b"\x1b[200~":
                        im_paste = True
                        i += 6
                        continue
                    if daten[i:i + 6] == b"\x1b[201~":
                        im_paste = False
                        i += 6
                        continue
                    if daten[i:i + 1] == b"\x1b" and len(daten) - i < 6:
                        rest = daten[i:]
                        i = len(daten)
                        break
                    c = daten[i:i + 1]
                    i += 1
                    if c in (b"\r", b"\n"):
                        if im_paste:
                            buf += " "
                            continue
                        absenden()
                        continue
                    if c == b"\x1b":
                        continue
                    buf += c.decode("utf-8", "ignore")
                neu = True
            if neu or time.time() - letzte > 0.2:
                zeichne()
                letzte = time.time()
    finally:
        try:
            sys.stdout.write("\x1b[?2004l")
            sys.stdout.flush()
        except Exception:
            pass
        if alt is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, alt)
            except Exception:
                pass


main()
