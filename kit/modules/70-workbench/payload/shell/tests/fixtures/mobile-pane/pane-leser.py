#!/usr/bin/python3
# Ein Pane-Inhalt, der sich messen laesst: liest die Rohbytes seiner Eingabe (Raw-Modus,
# kein Echo, keine Zeilenpufferung) und haengt sie unveraendert an eine Datei. Schaltet
# vorher den Klammer-Einfuege-Modus (?2004h) ein, wie es eine TUI tut -- erst dann setzt
# `paste-buffer -p` die Rahmen ESC[200~ ... ESC[201~ um den Text.
import os
import sys
import tty

ziel = sys.argv[1]
out = os.open(ziel, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
tty.setraw(0)
os.write(1, b"\x1b[?2004h")
while True:
    b = os.read(0, 4096)
    if not b:
        break
    os.write(out, b)
