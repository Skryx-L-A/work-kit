#!/usr/bin/env python3
"""frei-mitschreiben.py -- den freien Speicher im Sekundentakt mitschreiben.

    frei-mitschreiben.py <datei> [<sekunden>] [<takt>]

Fuer den echten Verifikationslauf der Notbremse (Vorgabe des Nutzers, 2026-08-21:
"protokolliere den freien Speicher im Sekundentakt in eine Datei, damit hinterher
nachlesbar ist, was passiert ist -- auch wenn die Sitzung selbst dabei stirbt").

Drei Dinge, die dieses Skript deshalb anders macht als eine Schleife in der Shell:

  Es schreibt und LEERT DEN PUFFER bei jeder Zeile (flush + os.fsync). Ein Lauf,
  der die Maschine an den Rand bringt, darf seine letzten Sekunden nicht in einem
  Schreibpuffer verlieren -- genau die letzten Sekunden sind die interessanten.

  Es misst mit derselben Formel wie check-resources und wb-notbremse (frei +
  inaktiv + spekulativ + freigebbar). Zwei Waechter mit zwei Definitionen von
  "frei" waeren nicht vergleichbar.

  Es notiert neben dem freien Speicher, WELCHE Modellprozesse gerade leben (PID
  und Art). Damit steht der Zeitpunkt des Eingriffs in derselben Zeitreihe wie
  der Speicherverlauf, und niemand muss zwei Protokolle uebereinanderlegen.

Es endet nach <sekunden> von selbst (Vorgabe 600). Ein Mitschreiber, der laenger
laeuft als sein Anlass, waere selbst ein Verstoss gegen die Regel, dass kein
Prozess auf Vorrat laeuft.
"""
import json
import os
import re
import subprocess
import sys
import time

MUSTER = [
    (re.compile(r"\bmlx_lm\.(server|generate|chat|benchmark|evaluate)\b"), "mlx-lm"),
    (re.compile(r"\bmlx[-_]dspark\b"), "mlx-dspark"),
    (re.compile(r"\bmtplx\b"), "mtplx"),
    (re.compile(r"\bvllm\b.*\b(serve|entrypoints)\b"), "vllm"),
    (re.compile(r"\bllama-(server|cli)\b"), "llama.cpp"),
    (re.compile(r"\bollama\s+runner\b"), "ollama-runner"),
]


def frei_mib():
    try:
        seite = int(subprocess.run(["/usr/sbin/sysctl", "-n", "hw.pagesize"],
                                   capture_output=True, text=True, timeout=5).stdout)
        vms = subprocess.run(["/usr/bin/vm_stat"], capture_output=True,
                             text=True, timeout=5).stdout
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    n = 0
    for name in ("Pages free", "Pages inactive", "Pages speculative", "Pages purgeable"):
        m = re.search(re.escape(name) + r":\s*(\d+)", vms)
        if m:
            n += int(m.group(1))
    return round(n * seite / 1048576.0, 1)


def modelle():
    try:
        p = subprocess.run(["/bin/ps", "-Ao", "pid=,command="],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    aus = []
    for z in p.stdout.splitlines():
        teile = z.strip().split(None, 1)
        if len(teile) < 2:
            continue
        for muster, art in MUSTER:
            if muster.search(teile[1]):
                aus.append({"pid": int(teile[0]), "art": art})
                break
    return aus


def main():
    datei = sys.argv[1]
    dauer = float(sys.argv[2]) if len(sys.argv) > 2 else 600.0
    takt = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
    ende = time.time() + dauer
    with open(datei, "a", encoding="utf-8") as f:
        while time.time() < ende:
            zeile = json.dumps({
                "t": round(time.time(), 3),
                "uhr": time.strftime("%H:%M:%S"),
                "frei_mib": frei_mib(),
                "modelle": modelle(),
            }, ensure_ascii=False)
            f.write(zeile + "\n")
            f.flush()
            os.fsync(f.fileno())
            time.sleep(takt)


if __name__ == "__main__":
    main()
