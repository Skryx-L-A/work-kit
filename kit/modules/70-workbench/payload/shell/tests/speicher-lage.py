#!/usr/bin/env python3
"""speicher-lage.py -- was auf diesem Mac wirklich frei ist, aus vier Quellen.

    speicher-lage.py [--json] [--marke <text>]

Befund des Nutzers vom 21.08.2026: "der verfuegbare speicher ist immer zu niedrig
angesetzt ... da sind die ganze zeit fast 40gb frei wenn gerade kein modell
geladen ist, schau was wirklich frei ist deine zahlen scheinen falsch zu sein um
>=10gb."

Die bisherige Formel (`check-resources`, und darueber `wb-belegung`) lautet
frei + inaktiv + spekulativ + freigebbar. Sie laesst einen ganzen Posten aus:
DATEI-GESTUETZTE SEITEN, die gerade AKTIV sind. Das sind Kopien von Dateien --
Programmcode, gelesene Modelldateien, Caches --, und sie sind jederzeit
verwerfbar, weil ihr Inhalt auf der Platte steht. macOS gibt sie unter Druck her,
ohne dass jemand etwas verliert.

Deshalb zeigt dieses Werkzeug vier Zahlen nebeneinander:

  eng      frei + inaktiv + spekulativ + freigebbar   (die heutige Formel)
  weit     gesamt - anonym - wired - Kompressor       (alles Datei-Gestuetzte gilt
                                                       als verfuegbar)
  gpu      iogpu.wired_limit_mb - bereits wired       (was der Treiber selbst als
                                                       Deckel fuer GPU-Speicher nennt)
  druck    memory_pressure, die Prozentzahl des Systems

"anonym" ist der Speicher, der NICHT auf der Platte steht -- Heap, Stack,
Metal-Puffer. Nur er, das Gewired und der Kompressor sind unverzichtbar; alles
andere ist Kopie.

Die Zahlen sind eine Lagebeschreibung und keine Erlaubnis. Was eine Buchung
daraus macht, entscheidet wb-belegung.
"""
import argparse
import json
import re
import subprocess
import sys

MIB = 1048576.0


def vm_stat():
    seite = int(subprocess.run(["/usr/sbin/sysctl", "-n", "hw.pagesize"],
                               capture_output=True, text=True, timeout=10).stdout)
    roh = subprocess.run(["/usr/bin/vm_stat"], capture_output=True,
                         text=True, timeout=10).stdout
    werte = {}
    for zeile in roh.splitlines():
        m = re.match(r'\s*"?([A-Za-z][^:"]*)"?:\s*(\d+)', zeile)
        if m:
            werte[m.group(1).strip()] = int(m.group(2))
    return seite, werte


def gesamt_mib():
    return int(subprocess.run(["/usr/sbin/sysctl", "-n", "hw.memsize"],
                              capture_output=True, text=True, timeout=10).stdout) / MIB


def gpu_deckel_mib():
    """Was der Treiber selbst als Obergrenze fuer gewired GPU-Speicher nennt.
    Auf diesem Geraet 43008 MiB = 42,0 GiB -- dieselbe Zahl, die vllm-metal als
    max_recommended_working_set_size meldet."""
    try:
        p = subprocess.run(["/usr/sbin/sysctl", "-n", "iogpu.wired_limit_mb"],
                           capture_output=True, text=True, timeout=10)
        wert = int((p.stdout or "0").strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    # 0 heisst "kein eigener Deckel gesetzt, der Treiber nimmt seine Vorgabe".
    return wert or None


def druck_prozent():
    try:
        p = subprocess.run(["/usr/bin/memory_pressure"], capture_output=True,
                           text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"System-wide memory free percentage:\s*(\d+)", p.stdout)
    return int(m.group(1)) if m else None


def lage():
    seite, v = vm_stat()
    def mib(*namen):
        return sum(v.get(n, 0) for n in namen) * seite / MIB
    gesamt = gesamt_mib()
    eng = mib("Pages free", "Pages inactive", "Pages speculative", "Pages purgeable")
    anonym = mib("Anonymous pages")
    datei = mib("File-backed pages")
    wired = mib("Pages wired down")
    kompressor = mib("Pages occupied by compressor")
    weit = gesamt - anonym - wired - kompressor
    deckel = gpu_deckel_mib()
    return {
        "gesamt_mib": round(gesamt, 1),
        "eng_mib": round(eng, 1),
        "weit_mib": round(weit, 1),
        "unterschied_mib": round(weit - eng, 1),
        "anonym_mib": round(anonym, 1),
        "datei_mib": round(datei, 1),
        "wired_mib": round(wired, 1),
        "kompressor_mib": round(kompressor, 1),
        "frei_mib": round(mib("Pages free"), 1),
        "inaktiv_mib": round(mib("Pages inactive"), 1),
        "aktiv_mib": round(mib("Pages active"), 1),
        "spekulativ_mib": round(mib("Pages speculative"), 1),
        "gpu_deckel_mib": deckel,
        "gpu_rest_mib": None if deckel is None else round(deckel - wired, 1),
        "druck_frei_prozent": druck_prozent(),
    }


def main():
    p = argparse.ArgumentParser(prog="speicher-lage")
    p.add_argument("--json", action="store_true")
    p.add_argument("--marke", default="", help="Text, der in der Ausgabe mitlaeuft")
    a = p.parse_args()
    d = lage()
    if a.marke:
        d["marke"] = a.marke
    if a.json:
        print(json.dumps(d, ensure_ascii=False))
        return 0
    if a.marke:
        print(a.marke)
    print("  gesamt        %8.0f MiB" % d["gesamt_mib"])
    print("  ENG           %8.0f MiB   frei %.0f + inaktiv %.0f + spekulativ %.0f + freigebbar"
          % (d["eng_mib"], d["frei_mib"], d["inaktiv_mib"], d["spekulativ_mib"]))
    print("  WEIT          %8.0f MiB   gesamt - anonym %.0f - wired %.0f - Kompressor %.0f"
          % (d["weit_mib"], d["anonym_mib"], d["wired_mib"], d["kompressor_mib"]))
    print("  Unterschied   %8.0f MiB   (datei-gestuetzt und AKTIV, also verwerfbar)"
          % d["unterschied_mib"])
    print("  davon Datei   %8.0f MiB   gesamt datei-gestuetzt" % d["datei_mib"])
    if d["gpu_deckel_mib"]:
        print("  GPU-Deckel    %8.0f MiB   iogpu.wired_limit_mb, davon noch %.0f MiB offen"
              % (d["gpu_deckel_mib"], d["gpu_rest_mib"]))
    if d["druck_frei_prozent"] is not None:
        print("  memory_pressure  %5d %%    'System-wide memory free percentage'"
              % d["druck_frei_prozent"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
