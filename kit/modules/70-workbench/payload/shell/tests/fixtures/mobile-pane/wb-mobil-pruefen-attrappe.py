#!/usr/bin/python3
# Attrappe fuer $HOME/.local/bin/wb-mobil-pruefen -- NUR fuer test-mobile-pane-write.sh.
#
# Sie ist kein Pruefprogramm: sie prueft keine Signatur und kennt keinen Schluessel. Sie
# spielt die Nahtstelle Paket 2 <-> Paket 3 nach (stdin: {"umschlag","body_b64","erwartet"},
# stdout: genau eine JSON-Zeile) und protokolliert, was sie bekommen hat. Gesteuert wird
# sie ausschliesslich ueber Dateien unter $HOME/attrappe/ des Test-HOME -- nie ueber
# argv oder Umgebung, damit der Test genau die Schnittstelle nutzt, die auch das echte
# Programm hat.
#
#   steuerung.json  {"modus": "gebunden" | "roh" | "haengt", ...}
#     gebunden  verhaelt sich wie das echte Programm gegenueber einer Bindung: nimmt
#               `erwartet` nur an, wenn es der "erwartung" der Steuerung entspricht
#               (Aktion, Maschine, Socket, Pane -- das, was der signierte Body bindet),
#               verbraucht die request_id einmalig (zweiter Verbrauch: nonce_replayed)
#               und antwortet mit "nutzlast" (text_b64 oder tasten).
#     roh       gibt "roh" unveraendert aus und beendet sich mit "exit".
#     haengt    schreibt seine PID nach haengt.pid und antwortet nie.
#   aufrufe.jsonl   je Aufruf eine Zeile: argv, PID, stdin wortwoertlich.
#   verbraucht.txt  die verbrauchten request_ids.
import json
import os
import sys
import time

STEUER = os.path.join(os.path.expanduser("~"), "attrappe")


def lesen(name, standard):
    try:
        with open(os.path.join(STEUER, name), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return standard


def nein(code):
    sys.stdout.write(json.dumps({"ok": False, "code": code}) + "\n")
    sys.exit(1)


roh_stdin = sys.stdin.read()
with open(os.path.join(STEUER, "aufrufe.jsonl"), "a", encoding="utf-8") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "pid": os.getpid(), "stdin": roh_stdin,
                        "env": dict(os.environ)}) + "\n")

steuer = lesen("steuerung.json", {})
modus = steuer.get("modus", "gebunden")

if modus == "haengt":
    with open(os.path.join(STEUER, "haengt.pid"), "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    time.sleep(120)
    sys.exit(0)

if modus == "roh":
    sys.stdout.write(steuer.get("roh", ""))
    sys.exit(steuer.get("exit", 0))

try:
    eingabe = json.loads(roh_stdin)
except ValueError:
    nein("invalid_envelope")
if not isinstance(eingabe, dict) or set(eingabe) != {"umschlag", "body_b64", "erwartet"}:
    nein("invalid_envelope")
erwartet = eingabe["erwartet"]
soll = steuer.get("erwartung", {})
if not isinstance(erwartet, dict) or set(erwartet) != {"aktion", "maschine", "socket", "pane"} \
        or any(erwartet.get(k) != soll.get(k) for k in ("aktion", "maschine", "socket", "pane")):
    nein("invalid_signature")   # der Body bindet ein anderes Ziel -- die Signatur passt nicht
request_id = eingabe["umschlag"].get("request_id", "")
ledger = os.path.join(STEUER, "verbraucht.txt")
try:
    with open(ledger, encoding="utf-8") as f:
        verbraucht = f.read().split()
except FileNotFoundError:
    verbraucht = []
if request_id in verbraucht:
    nein("nonce_replayed")
with open(ledger, "a", encoding="utf-8") as f:
    f.write(request_id + "\n")
antwort = {"ok": True, "geraet": "geraet-1", "request_id": request_id, "aktion": erwartet["aktion"]}
antwort.update(steuer.get("nutzlast", {}))
sys.stdout.write(json.dumps(antwort) + "\n")
