#!/usr/bin/env python3
"""druck-erzeugen.py -- echten Speicherdruck herstellen, in Stufen, bis eine
Schwelle wirklich unterschritten ist.

    druck-erzeugen.py <schwelle-mib> <hoechstens-gib> <spurdatei>

Fuer test-notbremse.sh, Fall 6. Ein Test STELLT seine Voraussetzung HER, statt sie
zu hoffen (regeln/tests-und-eingriffe.md). Der erste Anlauf jenes Falls belegte
eine FESTE Menge und verglich gegen eine Schwelle, die aus einer Minuten alten
Messung stammte -- auf einer beschaeftigten Maschine reichte der Druck dann nicht
bis unter die Schwelle, und der Test meldete einen Fehlschlag der Notbremse,
obwohl der Ernstfall nie eingetreten war (gemeldet vom Orchestrator, 2026-08-21).

Deshalb hier: nach JEDER Stufe wird nachgemessen, und es wird so lange belegt, bis
der freie Speicher wirklich unter der Schwelle liegt -- hoechstens aber bis zur
angegebenen Obergrenze. Jede Stufe steht in der Spurdatei, samt der letzten Zeile
"ZUSTAND HERGESTELLT" oder "ZUSTAND NICHT HERGESTELLT". Damit kann der Test einen
Fehlschlag des WERKZEUGS von einem Fehlschlag des AUFBAUS unterscheiden, statt
beide gleich zu benennen.

Die Seiten werden wirklich beruehrt: ein `bytearray` allein ist auf macOS noch
nicht belegter Speicher, es wird erst beim Schreiben eingelagert.

Danach haelt der Prozess den Speicher noch kurz und gibt ihn dann von selbst
wieder frei -- ein Druckerzeuger, der haengenbleibt, waere genau das Problem, das
er nachstellt.
"""
import json
import os
import re
import subprocess
import sys
import time

STUFE_MIB = 512
HALTEN_S = 40
# Abstand zur Schwelle: die Messung schwankt um einige hundert MiB, und ein Druck,
# der die Schwelle nur streift, macht den Fall zum Muenzwurf.
ABSTAND_MIB = 256

# DIESELBE QUELLE WIE DIE BREMSE, NICHT EINE VIERTE FORMEL (Nachtrag 21.08.2026).
# Bis hierher massen sich Test, Werkzeug (wb-notbremse) UND dieser Druckerzeuger
# je EIGENSTAENDIG dieselbe strenge vm_stat-Formel nach -- drei unabhaengige
# Fassungen, deren einzige Klammer ein Kommentar war ("dieselbe Formel wie...").
# Genau diese Bauart hat den Befund erst erzeugt, den dieser Umbau behebt (siehe
# ~/.pi-workers/results/hafenmeister/20260821-045339.md, Befund 2): eine Fassung
# zieht weiter, die anderen bleiben stehen, und niemand merkt es, weil alle
# plausible Zahlen liefern. wb-notbremse fragt seit demselben Umbau zuerst
# check-resources -- der Druckerzeuger muss also GENAU DAS messen, was die
# Bremse gleich pruefen wird, sonst kann "ZUSTAND HERGESTELLT" hier wahr sein,
# waehrend die Bremse (mit der grosszuegigeren check-resources-Zahl) noch
# komfortabel ueber der Schwelle steht -- gemessen, live: strenge Formel 33408
# MiB, check-resources zur selben Zeit deutlich mehr, die Bremse blieb aus.
_CHECK_RESOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                                "check-resources")


def frei_mib_streng():
    seite = int(subprocess.run(["/usr/sbin/sysctl", "-n", "hw.pagesize"],
                               capture_output=True, text=True).stdout)
    vms = subprocess.run(["/usr/bin/vm_stat"], capture_output=True, text=True).stdout
    return sum(int(re.search(re.escape(k) + r":\s*(\d+)", vms).group(1))
               for k in ("Pages free", "Pages inactive", "Pages speculative",
                         "Pages purgeable")) * seite / 1048576.0


def frei_mib():
    """check-resources zuerst -- dieselbe Quelle, die wb-notbremse jetzt selbst
    zuerst befragt (siehe Kopfkommentar). Nur wenn das ausfaellt, der strenge
    Rueckfall, damit dieser Druckerzeuger nie ganz stehenbleibt."""
    try:
        p = subprocess.run([_CHECK_RESOURCES, "--json"], capture_output=True,
                           text=True, timeout=2)
        if p.returncode == 0:
            wert = json.loads(p.stdout).get("ram", {}).get("free_mib")
            if isinstance(wert, (int, float)) and not isinstance(wert, bool) and wert >= 0:
                return float(wert)
    except (subprocess.TimeoutExpired, OSError, ValueError,
            json.JSONDecodeError, AttributeError, TypeError):
        pass
    return frei_mib_streng()


def main():
    schwelle = int(sys.argv[1])
    hoechstens_gib = float(sys.argv[2])
    spur = sys.argv[3]

    def notiz(text):
        with open(spur, "a", encoding="utf-8") as f:
            f.write(text + "\n")

    stufen = max(1, int(hoechstens_gib * 1024 / STUFE_MIB))
    brocken = []
    hergestellt = False
    for i in range(stufen):
        b = bytearray(STUFE_MIB * 1024 * 1024)
        b[::4096] = b"x" * len(b[::4096])
        brocken.append(b)
        frei = frei_mib()
        notiz("belegt %.1f GiB, frei %.0f MiB (Ziel: unter %d)"
              % ((i + 1) * STUFE_MIB / 1024.0, frei, schwelle))
        if frei < schwelle - ABSTAND_MIB:
            hergestellt = True
            break
    notiz("ZUSTAND HERGESTELLT" if hergestellt else "ZUSTAND NICHT HERGESTELLT")
    time.sleep(HALTEN_S)


if __name__ == "__main__":
    main()
