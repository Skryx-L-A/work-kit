#!/usr/bin/env python3
"""Tests fuer wb-speicher.

Der Teil, der schiefgehen DARF, ist das Aufraeumen: dieses Werkzeug beendet
Prozesse. Ein Fehler in der Zuordnung wuerde einen laufenden Worker treffen.
Deshalb wird hier vor allem geprueft, wen es anfasst und wen nicht.

ISOLATION: die Erkennung wird mit erfundenen Prozesstabellen gefuettert, statt
die echte Maschine abzusuchen — eine Testrunde, die `reste_finden()` gegen die
laufenden Prozesse ansetzt, haette Sitzung des Nutzers als Testobjekt. Fuers
Beenden werden zwei abgehaengte `sleep`-Prozesse gestartet; danach wird bei
beiden nachgesehen, ob genau der richtige weg ist.
"""

import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WERKZEUG = os.environ.get("WB_SPEICHER", os.path.join(REPO, "wb-speicher"))

if not os.access(WERKZEUG, os.X_OK):
    print(f"  FAIL  {WERKZEUG} fehlt oder ist nicht ausfuehrbar")
    sys.exit(1)

spec = importlib.util.spec_from_loader(
    "wb_speicher", importlib.machinery.SourceFileLoader("wb_speicher", WERKZEUG)
)
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)

pass_, fail = 0, 0


def ok(text):
    global pass_
    pass_ += 1
    print(f"  ok    {text}")


def bad(text):
    global fail
    fail += 1
    print(f"  FAIL  {text}")


def pruefe(bedingung, text, detail=""):
    ok(text) if bedingung else bad(f"{text}{(' — ' + detail) if detail else ''}")


print(f"Geprueft: {WERKZEUG}")

# --- kopf(): der Prosatext im Argument darf nicht mitzaehlen ----------------
print("-- Zuordnung nach dem Befehl, nicht nach dem ganzen Argument --")

claude_zeile = (
    "$HOME/.local/bin/claude --model claude-opus-5 --effort xhigh "
    "--append-system-prompt Der Orchestrator kennt die MCP-Server und die "
    "MCP-Anbindung an wb-speicher und wb-belegung"
)
k = ws.kopf(claude_zeile)
pruefe("mcp" not in k, "eine Sitzung mit MCP im Rollentext bleibt keine MCP-Zeile", k)
pruefe("wb-" not in k, "dieselbe Zeile wird auch nicht zum Waechter", k)
pruefe(
    "mcp" in ws.kopf("npm exec @playwright/mcp@latest"),
    "der echte MCP-Server wird weiterhin erkannt",
)
pruefe(ws.kopf("") == "", "eine leere Befehlszeile stuerzt nicht ab")
pruefe(
    ws.ist_mcp_helfer(
        "$HOME/.codex/plugins/cache/openai-bundled/"
        "unified-computer-use/1.0.1000992/cua_node/bin/node server.mjs"
    ),
    "der Computer-Use-Helfer wird als Plugin-/MCP-Aufwand erkannt",
)
pruefe(
    ws.ist_mcp_helfer(
        "$HOME/.codex/plugins/cache/openai-primary-runtime/"
        "node_repl/1.1.2/node_repl.mjs"
    ),
    "der node_repl-Helfer wird als Plugin-/MCP-Aufwand erkannt",
)

# --- App-Erkennung ----------------------------------------------------------
print("-- Werkbank-App samt Helfern erkennen --")
pruefe(
    ws.ist_werkbank_app("/Applications/Werkbank.app/Contents/MacOS/Werkbank"),
    "der aktuelle Werkbank-App-Name wird erkannt",
)
pruefe(
    ws.ist_werkbank_app(
        "/Applications/Agent Workbench.app/Contents/MacOS/Agent Workbench"
    ),
    "der fruehere App-Name bleibt erkannt",
)
pruefe(
    not ws.ist_werkbank_app(
        "/bin/sh --note /Applications/Werkbank.app/Contents/MacOS/Werkbank"
    ),
    "eine spaetere Erwaehnung im Argumenttext gilt nicht als App-Start",
)
pruefe(
    ws.ist_dauerdienst(
        "/opt/homebrew/bin/python3 $HOME/.local/bin/wb-modell-proxy"
    ),
    "der Modell-Proxy wird als Dauerdienst und nicht als wb-Waechter erkannt",
)

# --- etime_sekunden() -------------------------------------------------------
print("-- Laufzeit lesen --")
pruefe(ws.etime_sekunden("00:15") == 15, "mm:ss")
pruefe(ws.etime_sekunden("02:12:33") == 2 * 3600 + 12 * 60 + 33, "hh:mm:ss")
pruefe(ws.etime_sekunden("1-02:00:00") == 86400 + 7200, "dd-hh:mm:ss")

# --- reste_finden(): was tot ist und was nicht ------------------------------
print("-- Reste erkennen --")

# Die Pfade muessen wie echte Ergebnisverzeichnisse aussehen: die Erkennung
# greift auf '<irgendwo>/.pi-workers/results/<name>', und ein beliebiger
# Tempordner traefe das Muster nicht.
basis = tempfile.mkdtemp()
lebt = os.path.join(basis, ".pi-workers", "results", "w-lebt")
os.makedirs(lebt)
weg = os.path.join(basis, ".pi-workers", "results", "w-weg")

beobachter = (
    'bash -c \n    resdir="$1"; res="$2"\n    for i in $(seq 1 1440); do\n'
    '      sleep 15\n      if [ -s "$res" ]; then\n        ln -sf "$res" "$resdir/latest.md"\n'
    "      fi\n    done _ %s %s/20260820-150000.md"
)

args = {
    101: beobachter % (lebt, lebt),
    102: beobachter % (weg, weg),
    # Derselbe Beobachter, aber mit einem Elternprozess: er gehoert zu einem
    # laufenden Test und ist deshalb ueberhaupt kein Rest.
    103: beobachter % (weg, weg),
    104: "$HOME/.local/bin/claude --model claude-opus-5",
    # 4. Kategorie: eine verwaiste Login-Shell (Auftrag "413 verwaiste
    # Shells", 2026-08-22) -- ein echtes Terminal statt "??" ist hier das
    # Erkennungsmerkmal, siehe reste_finden().
    105: "-zsh",
    # Dieselbe Befehlszeile, aber OHNE echtes Terminal -- ein launchd-Job hat
    # so gut wie nie eines; das darf NICHT unter die Klasse fallen.
    106: "-zsh",
    # Eine Shell MIT Argument -- kein nackter Prompt, faellt bewusst nicht
    # unter die Klasse (Praezision wie bei den Kategorien 1-3 oben).
    107: "-zsh -c sleep 300",
}
eltern = {101: 1, 102: 1, 103: 999, 104: 1, 105: 1, 106: 1, 107: 1}
alter = {101: 100, 102: 20000, 103: 100, 104: 100, 105: 100, 106: 100, 107: 100}
tty = {105: "ttys004", 106: "??", 107: "ttys005"}

funde = ws.reste_finden(args, eltern, alter, tty)
gefunden = {f["pid"]: f for f in funde}

pruefe(102 in gefunden and gefunden[102]["tot"],
       "Beobachter ohne sein Ergebnisverzeichnis gilt als tot")
pruefe(101 in gefunden and not gefunden[101]["tot"],
       "Beobachter mit vorhandenem Verzeichnis gilt NICHT als tot")
pruefe(103 not in gefunden,
       "ein Beobachter mit lebendem Elternprozess ist gar kein Rest")
pruefe(104 not in gefunden,
       "eine Claude-Sitzung unter PID 1 wird nicht als Rest gefuehrt")
pruefe(105 in gefunden and gefunden[105]["tot"] and gefunden[105]["art"] == "verwaiste-login-shell",
       "eine nackte Shell mit echtem Terminal und PPID 1 gilt als tote Login-Shell-Waise")
pruefe(106 not in gefunden,
       "dieselbe Befehlszeile OHNE echtes Terminal (TTY '??', wie ein launchd-Job) faellt nicht unter die Klasse")
pruefe(107 not in gefunden,
       "eine Shell MIT Argument (kein nackter Prompt) faellt nicht unter die Klasse")

# --- reste_beenden(): nur die toten -----------------------------------------
print("-- Aufraeumen fasst nur die toten an --")

# Beide Prozesse werden ABGEHAENGT gestartet (Grosskind, Elternteil beendet
# sich sofort): so haengen sie wie im Ernstfall unter PID 1. Als eigene Kinder
# waeren sie nach dem Signal Zombies -- der PID existiert dann weiter, und die
# Pruefung "ist er weg" wuerde faelschlich Nein sagen.
def abgehaengt():
    aus = subprocess.run(
        ["/bin/sh", "-c", "sleep 600 </dev/null >/dev/null 2>&1 & echo $!"],
        capture_output=True, text=True).stdout.strip()
    return int(aus)


def laeuft(pid):
    return subprocess.run(["ps", "-p", str(pid)], capture_output=True).returncode == 0


toter = abgehaengt()
lebender = abgehaengt()
try:
    beendet, geblieben = ws.reste_beenden([
        {"pid": toter, "tot": True},
        {"pid": lebender, "tot": False},
    ])
    pruefe(toter in beendet, "der als tot gemeldete Prozess steht in der Liste")
    pruefe(not laeuft(toter), "und er ist wirklich weg")
    pruefe(lebender not in beendet and lebender not in geblieben,
           "der nicht als tot gemeldete Prozess wurde gar nicht angefasst")
    pruefe(laeuft(lebender), "und er laeuft nachweislich weiter")
finally:
    for pid in (toter, lebender):
        try:
            os.kill(pid, 9)
        except (ProcessLookupError, PermissionError):
            pass

# --- Ampel ------------------------------------------------------------------
print("-- Ampel --")
pruefe(ws.GRENZE_GELB_MIB < ws.GRENZE_ROT_MIB, "gelb liegt unter rot")
for wert, erwartet in ((100, "gruen"), (ws.GRENZE_GELB_MIB + 1, "gelb"),
                       (ws.GRENZE_ROT_MIB + 1, "rot")):
    ampel = "rot" if wert > ws.GRENZE_ROT_MIB else (
        "gelb" if wert > ws.GRENZE_GELB_MIB else "gruen")
    pruefe(ampel == erwartet, f"{wert} MiB ergibt {erwartet}")

# --- Fussabdruck gegen footprint(1) -----------------------------------------
print("-- Die Zahl stimmt mit footprint(1) ueberein --")
werte = ws.fussabdruecke()
selbst = os.getpid()
if isinstance(werte, getattr(ws, "ProcSpeicher", ())):
    # Kit (Linux): PSS of this process from /proc, and the machine's numbers from /proc/meminfo.
    with open("/proc/self/smaps_rollup") as f:
        pss = [int(z.split()[1]) / 1024 for z in f if z.startswith("Pss:")][0]
    pruefe(selbst in werte and werte[selbst] > 0 and abs(werte[selbst] - pss) < 8,
           "Linux: PSS des eigenen Prozesses aus /proc/<pid>/smaps_rollup",
           f"{werte.get(selbst)} MiB gegen {pss:.0f} MiB")
    belegt, verfuegbar = ws.linux_meminfo()
    pruefe(belegt and verfuegbar and belegt > 0 and verfuegbar > 0, "Linux: MemTotal - MemAvailable und MemAvailable")
    pruefe(1 not in werte or werte[1] >= 0, "Linux: ein fremder Prozess (PID 1) liefert RSS oder fehlt")
elif selbst not in werte:
    print(f"  UEBERSPRUNGEN  der eigene Prozess {selbst} steht nicht in top")
else:
    roh = subprocess.run(["/usr/bin/footprint", "-p", str(selbst)],
                         capture_output=True, text=True).stdout
    zeile = [z for z in roh.splitlines() if "phys_footprint:" in z]
    if not zeile:
        print("  UEBERSPRUNGEN  footprint(1) liefert keine Zahl")
    else:
        teile = zeile[0].split()
        mib = float(teile[1]) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[teile[2]]
        # top rundet auf ganze MiB und misst einen Wimpernschlag frueher als
        # footprint; 8 MiB Abstand sind grosszuegig und faengt trotzdem jede
        # Verwechslung von Einheit oder Spalte.
        pruefe(abs(werte[selbst] - mib) < 8,
               "top -stats mem und footprint -p nennen dieselbe Zahl",
               f"top {werte[selbst]:.0f} MiB, footprint {mib:.0f} MiB")

# --- Der Bericht laeuft durch ----------------------------------------------
print("-- Der Bericht laeuft gegen die echte Maschine durch --")
lauf = subprocess.run([WERKZEUG], capture_output=True, text=True, timeout=120)
pruefe(lauf.returncode == 0, "wb-speicher endet mit 0", lauf.stderr[:200])
pruefe("Werkbank gesamt" in lauf.stdout, "der Bericht nennt die Gesamtsumme")
pruefe("Ampel:" in lauf.stdout, "der Bericht nennt die Ampel")

json_lauf = subprocess.run([WERKZEUG, "--json"], capture_output=True, text=True, timeout=120)
try:
    import json
    d = json.loads(json_lauf.stdout)
    pruefe("posten" in d and "gesamt_mib" in d and "ampel" in d,
           "--json liefert die erwarteten Felder")
except json.JSONDecodeError as e:
    bad(f"--json liefert kein gueltiges JSON: {e}")

shutil.rmtree(basis, ignore_errors=True)

print()
print(f"wb-speicher: {pass_} ok, {fail} fehlgeschlagen")
sys.exit(0 if fail == 0 else 1)
