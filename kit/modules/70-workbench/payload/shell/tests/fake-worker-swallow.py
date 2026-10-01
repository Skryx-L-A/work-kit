#!/usr/bin/env python3
"""Stellvertreter fuer test-context-guard-absende-verschluckt.sh.

Eine raw-mode TUI wie fake-tui.py (Bracketed Paste erkannt, kein Zeilen-REPL --
der Text des Guards ist immer einzeilig, aber ein Zeilenmodus wuerde trotzdem
JEDES Zeichen als moegliches Absenden lesen, sobald etwas im Puffer landet, was
hier so falsch waere wie dort), zusaetzlich mit einer Statuszeile im erfundenen
Registry-Format 'KTX <n> %' (dasselbe Format wie test-context-guard-registry.sh),
damit der Guard eine Auslastung LESEN kann, waehrend die Eingabezeile das
Absenden schluckt.

FAKE_KIND:
  schluckt  Das ERSTE Enter auf frischen Text kommt an (FAKE_LOG bekommt eine
            Zeile 'ENTER'), bewirkt aber nichts -- der Text bleibt in der
            Eingabezeile stehen. Genau der Befund vom 2026-08-12 (Pane %86,
            Worker chatsdk): tmux send-keys hatte das Enter laengst
            abgeschickt, die TUI hat es nur nicht rechtzeitig verarbeitet. Das
            ZWEITE Enter auf denselben Text (die Nachhilfe der Absende-Pruefung
            in context-guard) wirkt normal.
  hart      Nichts wird je angenommen -- der dauerhaft haengende Fall.

FAKE_PCT ist die Auslastung, die die Statuszeile zeigt, bis ein abgeschickter
Text FAKE_COMPACT_TRIGGER enthaelt (der Kompaktierbefehl aus der Registry
dieses Laufs) -- danach zeigt sie FAKE_PCT_NACH.
"""
import os
import sys
import termios
import tty

KIND = os.environ.get("FAKE_KIND", "schluckt")
PROMPT = "❯"  # '❯', dasselbe Zeichen wie GUARD_PROMPT_RE in context-guard
PCT = int(os.environ.get("FAKE_PCT", "90"))
PCT_NACH = int(os.environ.get("FAKE_PCT_NACH", "10"))
COMPACT_TRIGGER = os.environ.get("FAKE_COMPACT_TRIGGER", "/verdichte")
LOG = os.environ.get("FAKE_LOG", "")

buf = ""
schluckt_uebrig = False


def merke_enter():
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("ENTER\n")
    except OSError:
        pass


def zeichne():
    sys.stdout.write("\x1b[H\x1b[2J")
    sys.stdout.write("Fake-Worker laeuft\r\nKTX %d %%\r\n" % PCT)
    sys.stdout.write("%s %s" % (PROMPT, buf))
    sys.stdout.flush()


def absenden():
    global buf, schluckt_uebrig, PCT
    merke_enter()
    if KIND == "hart":
        return                       # nichts geschieht, der Text bleibt stehen
    if KIND == "schluckt" and schluckt_uebrig:
        schluckt_uebrig = False      # verbraucht -- das naechste Enter auf DIESEN Text wirkt
        return
    text = buf
    buf = ""
    if COMPACT_TRIGGER and COMPACT_TRIGGER in text:
        PCT = PCT_NACH
    zeichne()


def main():
    global buf, schluckt_uebrig
    fd = sys.stdin.fileno()
    try:
        alt = termios.tcgetattr(fd)
    except termios.error:
        alt = None
    if alt is not None:
        tty.setraw(fd)
    try:
        sys.stdout.write("\x1b[?2004h")  # Klammer-Einfuege-Modus anfordern
        sys.stdout.flush()
        zeichne()
        im_paste = False
        rest = b""
        while True:
            try:
                daten = os.read(fd, 4096)
            except OSError:
                break
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
                if KIND == "schluckt" and not buf:
                    schluckt_uebrig = True
                try:
                    buf += c.decode("utf-8", "ignore")
                except Exception:
                    pass
            zeichne()
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
