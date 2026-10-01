#!/usr/bin/env python3
"""Stellvertreter fuer test-context-guard-anschluss-nach-kompaktierung.sh.

Bildet zwei Race-Symptome nach, die zusammen den Vorfall vom 2026-09-03 (Worker
'neubau', Pane %138, 20:18-20:52) ausmachten -- und benutzt dabei absichtlich die
ECHTE Claude-Code-Statuszeilen-Schreibweise ('820k/1.0M'), nicht das erfundene
'KTX N %'-Format der Schwestertests: dieselbe Quelle 1 aus read_load() soll greifen,
die auch im Betrieb greift, und der Guard soll ohne eigene Registry-Eintragung auf
seinen eingebauten Vorgabewert '/compact' fallen (siehe context-guard: harness_info(),
"Unbekannter Harness ... also /compact").

FAKE_KIND:
  zug     Beim Eintreffen des Kompaktierbefehls steckt der Pane FAKE_BUSY Sekunden
          in einem fremden, schon laufenden Zug: Spinner + 'esc to interrupt', UND
          die Eingabezeile zeigt in genau diesem Fenster weiterhin den zuletzt
          getippten Text (wie im Vorfall: "Text stand nach Enter noch in der
          Eingabezeile"). Erst danach faellt die Auslastung. Prueft den Fix in
          absenden_verifizieren(): ein sichtbarer Zug gilt als "angenommen", auch
          wenn die Eingabezeile im selben Sekundenfenster noch haengt.
  spaet   Das Enter auf den Kompaktierbefehl wirkt scheinbar UEBERHAUPT NICHT (die
          Eingabezeile bleibt stehen, KEIN Zug sichtbar) -- absenden_verifizieren()
          MUSS hier ehrlich 'NICHT verifiziert' melden, es gibt nichts, das sie
          anders lesen duerfte. Nach FAKE_SPAET Sekunden wird der Befehl trotzdem
          im Hintergrund verarbeitet (Eingabezeile leert sich, Auslastung faellt)
          -- der beobachtete Fall aus dem Vorfall: der Guard hat den Erfolg
          verpasst, der Erfolg kam trotzdem.

FAKE_PCT / FAKE_PCT_NACH: Auslastung in Prozent vor/nach dem Kompaktieren.
FAKE_COMPACT_TRIGGER: der Text, der als Kompaktierbefehl gilt (Vorgabe '/compact').
FAKE_LOG: bekommt eine Zeile 'ENTER' je empfangenem Enter.
"""
import os
import select
import sys
import termios
import time
import tty

KIND = os.environ.get("FAKE_KIND", "zug")
PCT = int(os.environ.get("FAKE_PCT", "82"))
PCT_NACH = int(os.environ.get("FAKE_PCT_NACH", "5"))
TRIGGER = os.environ.get("FAKE_COMPACT_TRIGGER", "/compact")
LOG = os.environ.get("FAKE_LOG", "")
BUSY_SEK = float(os.environ.get("FAKE_BUSY", "3") or 0)
SPAET_SEK = float(os.environ.get("FAKE_SPAET", "3") or 0)

buf = ""
verzoegert_bis = 0.0   # beide Arten: wann der (verzoegerte) Effekt eintritt
verzoegert_text = ""


def merke_enter():
    if not LOG:
        return
    try:
        with open(LOG, "a") as f:
            f.write("ENTER\n")
    except OSError:
        pass


def zeichne():
    jetzt = time.time()
    im_zug = KIND == "zug" and jetzt < verzoegert_bis
    zeilen = ["Fake-Claude laeuft (%s)" % KIND, ""]
    if im_zug:
        zeilen.append("✳ Arbeitet… (esc to interrupt)")
        zeilen.append("")
    zeilen.append("  %dk/1.0M" % (PCT * 10))
    zeilen.append("❯ %s" % buf)
    sys.stdout.write("\x1b[H\x1b[2J" + "\r\n".join(zeilen))
    sys.stdout.flush()


def absenden():
    global buf, verzoegert_bis, verzoegert_text
    merke_enter()
    text = buf
    if TRIGGER and TRIGGER in text:
        verzoegert_bis = time.time() + (BUSY_SEK if KIND == "zug" else SPAET_SEK)
        verzoegert_text = text
        return   # buf bleibt stehen -- siehe Kopfkommentar, beide Spielarten
    buf = ""


def tick():
    """Wird von der Hauptschleife regelmaessig aufgerufen, auch ohne neue Eingabe --
    der verzoegerte Effekt tritt unabhaengig vom naechsten Tastendruck ein."""
    global buf, verzoegert_bis, PCT
    if verzoegert_bis and time.time() >= verzoegert_bis:
        if TRIGGER and TRIGGER in verzoegert_text:
            PCT = PCT_NACH
        buf = ""
        verzoegert_bis = 0.0


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
