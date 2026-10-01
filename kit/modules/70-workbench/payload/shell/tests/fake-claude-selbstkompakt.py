#!/usr/bin/env python3
"""Stellvertreter fuer test-context-guard-selbstkompaktierung.sh.

Bildet einen Harness nach, der sich SELBST kompaktiert (codex tut das eingebaut):
die Auslastung faellt FAKE_SELBST_NACH Sekunden nach der ersten empfangenen
Eingabe -- also nach der Mahnung der Wache -- von FAKE_PCT auf FAKE_PCT_NACH,
ohne dass je ein Kompaktierbefehl getippt wurde. Geschrieben wird die echte
Claude-Code-Statuszeile ('820k/1.0M', Quelle 1 aus read_load()), damit die Wache
denselben Weg geht wie im Betrieb.

FAKE_BUSY=1  Der Pane zeigt dauerhaft einen laufenden Zug (Spinner + 'esc to
             interrupt'): der Worker arbeitet nach der Selbstkompaktierung von
             allein weiter, die Wache darf ihm NICHTS tippen.
FAKE_LOG     Bekommt je abgeschickter Eingabe eine Zeile 'SUBMIT <text>' -- daran
             misst der Test, ob (und was) die Wache getippt hat.
"""
import os
import select
import sys
import termios
import time
import tty

PCT = int(os.environ.get("FAKE_PCT", "82"))
PCT_NACH = int(os.environ.get("FAKE_PCT_NACH", "5"))
SELBST_NACH = float(os.environ.get("FAKE_SELBST_NACH", "1") or 0)
BUSY = os.environ.get("FAKE_BUSY", "") == "1"
LOG = os.environ.get("FAKE_LOG", "")

buf = ""
kompakt_um = 0.0   # Zeitpunkt der Selbstkompaktierung, 0 = noch nicht angestossen


def merke(text):
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("SUBMIT %s\n" % text.replace("\n", " "))
    except OSError:
        pass


def zeichne():
    zeilen = ["Fake-Claude (Selbstkompaktierung)", ""]
    if BUSY:
        zeilen.append("✳ Arbeitet… (esc to interrupt)")
        zeilen.append("")
    zeilen.append("  %dk/1.0M" % (PCT * 10))
    zeilen.append("❯ %s" % buf)
    sys.stdout.write("\x1b[H\x1b[2J" + "\r\n".join(zeilen))
    sys.stdout.flush()


def absenden():
    global buf, kompakt_um
    merke(buf)
    buf = ""
    if kompakt_um == 0.0:
        kompakt_um = time.time() + SELBST_NACH


def tick():
    global PCT, kompakt_um
    if kompakt_um and time.time() >= kompakt_um:
        PCT = PCT_NACH          # der Harness hat sich selbst kompaktiert
        kompakt_um = -1.0       # genau einmal


def main():
    global buf
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
        letzte_zeichnung = 0.0
        while True:
            r, _, _ = select.select([fd], [], [], 0.15)
            tick()
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
                    try:
                        buf += c.decode("utf-8", "ignore")
                    except Exception:
                        pass
                neu = True
            if neu or time.time() - letzte_zeichnung > 0.2:
                zeichne()
                letzte_zeichnung = time.time()
    finally:
        try:
            sys.stdout.write("\x1b[?2004l")
            sys.stdout.flush()
        except Exception:
            pass
        if alt is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, alt)
            except termios.error:
                pass


main()
