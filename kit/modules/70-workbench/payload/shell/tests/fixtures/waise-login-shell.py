#!/usr/bin/env python3
"""Baut den Zustand, den `wb-waisen` als "Login-Shell (verwaist)" melden soll:
eine NACKTE Anmelde-Shell (argv[0] == '-zsh', keine Argumente), deren Vater
weg ist (PPID 1), an einem ECHTEN Pseudoterminal.

WARUM NICHT DAS RENNEN NACHSTELLEN (2026-08-24, Auftrag "was bei zwanzig
gleichzeitig passiert"): Bis dahin baute test-waisen.sh diesen Fall, indem es
achtmal zwoelf tmux-Sitzungen anlegte und den Server sofort erschoss, in der
Hoffnung, dass wenigstens eine Pane-Shell das SIGHUP-Rennen ueberlebt. Das ist
Umgebung, nicht Pruefgegenstand -- und es traf nicht mehr: in vier vollen
Laeufen hintereinander ueberlebte keine einzige Shell, und der Fall meldete
sich jedesmal als FAIL, obwohl an `wb-waisen` nichts falsch war. Nachgemessen
ohne jede Last: 0 von 56 und 0 von 70 Panes ueberlebten ein `kill-session`,
0 von 96 ein `kill-server`. Gepruefte Sache ist, ob `wb-waisen` diesen Zustand
erkennt; ihn direkt zu bauen prueft genau das, jedesmal, in einer Sekunde
statt in hundert.

WIE: Ein Halterprozess haelt die MASTER-Seite des Pseudoterminals offen -- ohne
ihn liest die Shell sofort ein Dateiende und beendet sich, und genau daran
scheiterte der naheliegende Nachbau ueber `trap '' HUP` in einem tmux-Pane.
Im Betrieb spielt diese Rolle irgendein anderer Prozess, der die Master-Seite
geerbt hat; hier ist sie ausdruecklich besetzt.

Ausgabe: eine Zeile 'shell <pid> halter <pid>'. Beide Prozesse gehoeren dem
Aufrufer -- er beendet sie.
Aufruf: waise-login-shell.py [lebensdauer-des-halters-in-sekunden]
"""
import os
import pty
import sys
import time
import signal
import fcntl
import termios

master, slave = pty.openpty()

halter = os.fork()
if halter == 0:
    os.close(slave)
    os.setsid()
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    # STDIN/STDOUT/STDERR LOSWERDEN, und zwar sofort: der Aufrufer liest diese
    # Fixture ueblicherweise per Kommandoersetzung -- `$( … )` wartet auf das
    # SCHLIESSEN der Pipe, nicht auf das Ende des Elternprozesses. Ein Halter,
    # der die geerbte Pipe offen behaelt, laesst den Aufrufer bis zu seinem
    # eigenen Lebensende haengen (gemessen: zwei Minuten), und wenn der Aufruf
    # endlich zurueckkommt, ist der Halter weg, die Master-Seite geschlossen
    # und die Shell mit ihr -- die Fixture haette dann genau das nicht
    # hinterlassen, wofuer es sie gibt.
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    if devnull > 2:
        os.close(devnull)
    time.sleep(float(sys.argv[1]) if len(sys.argv) > 1 else 600)
    os._exit(0)

shell = os.fork()
if shell == 0:
    os.close(master)
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    if slave > 2:
        os.close(slave)
    # argv[0] mit fuehrendem Strich: genau so meldet sich eine Anmelde-Shell,
    # und genau darauf sieht `ist_login_shell` in wb-waisen.
    os.execv("/bin/zsh", ["-zsh"])
    os._exit(127)

os.close(slave)
print("shell %d halter %d" % (shell, halter))
sys.stdout.flush()
# Der Elternprozess endet sofort -- damit bekommen beide Kinder PPID 1.
os._exit(0)
