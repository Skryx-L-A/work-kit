#!/usr/bin/env python3
"""Tests fuer wb-pruefschleife -- Massstab: nachtrag-echte-tests.md.

Drei Bedingungen, alle zusammen (Nachtrag, 01.09.2026): ueber die
Kommandozeile (subprocess.run, kein Import+Funktionsaufruf -- was ein Agent
nicht tippen kann, prueft der Test nicht), in einer echten Umgebung (echtes
git init, echte Skripte, echte Dateien), und geprueft wird auch, was NICHT
passieren durfte (der Laeuferbaum bleibt unberuehrt, ein verworfener Bau
wird wirklich zurueckgenommen).

Kein Modellaufruf: der bauende und die pruefenden Agenten sind in jedem
Probeprojekt echte, kleine Python-Skripte -- sie TUN etwas Echtes (schreiben
eine Datei, liefern ein JSON-Urteil, zaehlen ihre Aufrufe), nur ohne ein
Modell dahinter (Auftrag 01.09.2026: 'Der bauende und der pruefende Agent
werden dort durch Skripte ersetzt').

Abgrenzung zum Laeuferbaum-Check bei wb_autoresearch.py: dessen Repo ist ein
dediziertes Ein-Werkzeug-Repo, ~/AI/claude-workbench dagegen ein Monorepo mit
hundert anderen Werkzeugen -- eine Datei-fuer-Datei-Wanderung durch shell/
waere hier langsam und anfaellig fuer fremde, unabhaengige Aenderungen im
selben Baum. Der Check unten prueft stattdessen genau das, was ein
Zeigefehler im Laeufer wirklich veraendern wuerde: die Werkzeugdatei selbst
(Inhalt+mtime) und HEAD/Status des ganzen Repos -- das faengt jeden
git-Aufruf im falschen Baum genauso zuverlaessig.
"""
import atexit
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
SHELL_DIR = TESTS_DIR.parent
REPO = SHELL_DIR.parent
SKRIPT = SHELL_DIR / "wb-pruefschleife"

if not os.access(SKRIPT, os.X_OK):
    print(f"  FAIL {SKRIPT} fehlt oder ist nicht ausfuehrbar")
    sys.exit(1)

# Ein eigenes, kleines Modellverzeichnis fuer die ganze Datei -- dieselbe
# Gestalt wie ~/.claude/workbench/models.json, aber vier Eintraege statt
# tausend. Die Tests haengen damit nicht an der Registry dieser Maschine (die
# sich aendern darf, ohne dass ein Test rot wird), und sie fassen sie auch
# nicht an. `WB_MODELS_FILE` ist der Schalter, den die uebrigen Werkzeuge des
# Hauses schon benutzen; er wird vererbt, also gilt er auch fuer jeden
# Unterprozess unten. Ein einziger Test unten liest bewusst die ECHTE
# Registry, damit die Vorlage nicht nur gegen die Attrappe passt.
_VERZEICHNIS_ORDNER = tempfile.mkdtemp(prefix="pruefschleife-modelle-")
MODELLE_ATTRAPPE = Path(_VERZEICHNIS_ORDNER) / "models.json"
MODELLE_ATTRAPPE.write_text(json.dumps({"version": 1, "models": [
    {"id": "lmgamma-27b", "alias": "lmgamma", "label": "lmgamma-27b (lokal)"},
    {"id": "lmalpha-35b", "alias": "lmalpha", "label": "Lmalpha 1.0 35B (lokal)"},
    {"id": "lmbeta-27b", "alias": "lmbeta", "label": "lmbeta-27b (lokal)"},
    {"id": "claude-opus-5", "alias": "opus5", "label": "Claude Opus 5"},
    # Kit: the models of the shipped template (kit-llm), without aliases.
    {"id": "qwen3.5-4b", "label": "Qwen3.5 4B (kit-llm)"},
    {"id": "granite-4.0-micro", "label": "Granite 4.0 Micro (kit-llm)"},
]}, indent=2) + "\n", encoding="utf-8")
ECHTE_REGISTRY = Path.home() / ".claude/workbench/models.json"
os.environ["WB_MODELS_FILE"] = str(MODELLE_ATTRAPPE)
# Ueber atexit, nicht als letzte Zeile der Datei: bricht ein Test mit einer
# Ausnahme ab, bliebe der Ordner sonst liegen (einmal passiert beim Bau dieser
# Tests).
atexit.register(shutil.rmtree, _VERZEICHNIS_ORDNER, ignore_errors=True)

sys.path.insert(0, str(SHELL_DIR))  # fuer `import atomar_schreiben` in wb-pruefschleife --
                                     # beim Direktstart (python3 shell/wb-pruefschleife, wie in
                                     # jedem _cli()-Aufruf unten) traegt Python das automatisch
                                     # ein, beim Laden ueber importlib hier nicht.
spec = importlib.util.spec_from_loader(
    "wb_pruefschleife", importlib.machinery.SourceFileLoader("wb_pruefschleife", str(SKRIPT)))
ps = importlib.util.module_from_spec(spec)
# In sys.modules eintragen, BEVOR der Code laeuft -- ein regulaeres `import`
# taete das automatisch (autoresearch's Testdatei nutzt genau das, weil
# wb_autoresearch.py ein gueltiger Modulname ist); wb-pruefschleife hat
# keine .py-Endung und braucht darum SourceFileLoader. Ohne den Eintrag
# schlaegt dataclasses unter Python 3.9 zusammen mit
# `from __future__ import annotations` fehl (sys.modules.get(cls.__module__)
# waere None) -- Befund beim eigenen Testbau, 01.09.2026, per echtem Lauf
# belegt.
sys.modules["wb_pruefschleife"] = ps
spec.loader.exec_module(ps)

fehler = []


def pruefe(name, bedingung, hinweis=""):
    if bedingung:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {hinweis}")
        fehler.append(name)


def wirft(name, funktion, *args):
    try:
        funktion(*args)
    except Exception:  # noqa: BLE001
        print(f"  ok   {name}")
        return
    print(f"  FAIL {name} (kein Fehler geworfen)")
    fehler.append(name)


def _cli(*args, cwd=None, timeout=60, umgebung=None):
    umwelt = None
    if umgebung is not None:
        umwelt = {**os.environ, **umgebung}
        for name, wert in umgebung.items():
            if wert is None:
                umwelt.pop(name, None)
    return subprocess.run([sys.executable, str(SKRIPT), *args],
                          capture_output=True, text=True, cwd=cwd, timeout=timeout, env=umwelt)


def _git(ordner, *args):
    return subprocess.run(["git", "-C", str(ordner), *args], capture_output=True, text=True)


def _repo_abbild():
    inhalt = SKRIPT.read_text(encoding="utf-8")
    mtime = SKRIPT.stat().st_mtime_ns
    kopf = _git(REPO, "rev-parse", "HEAD").stdout.strip()
    status = _git(REPO, "status", "--porcelain").stdout
    return inhalt, mtime, kopf, status


def _neues_probeprojekt(ordner: Path) -> Path:
    """Ein echtes fremdes Projekt: eigenes git-Repo, ein Erbauer-Skript, das
    kern.py wirklich schreibt, zwei Pruefer-Skripte, die ein echtes JSON-Urteil
    liefern -- kein Monkeypatch, das im Ernstfall nicht mitliefe."""
    ordner.mkdir(parents=True, exist_ok=True)
    _git(ordner, "init", "-q")
    _git(ordner, "config", "user.email", "t@t")
    _git(ordner, "config", "user.name", "t")
    (ordner / "kern.py").write_text("WERT = 0\n", encoding="utf-8")
    (ordner / "erbauer.py").write_text(
        "import pathlib\n"
        "pathlib.Path('kern.py').write_text('WERT = 42\\n', encoding='utf-8')\n",
        encoding="utf-8")
    # Der Pruefer meldet das Modell, mit dem er geurteilt hat -- und zwar das
    # aus SEINEM EIGENEN Aufruf, so wie es ein ehrlicher Mantel taete. Genau
    # diese Rueckmeldung ist die Gegenprobe zu dem Modellnamen, den der
    # Laeufer aus dem Befehl liest (Befund B3).
    (ordner / "pruefer_ok.py").write_text(
        "import json, sys\n"
        "modell = sys.argv[sys.argv.index('--modell') + 1] if '--modell' in sys.argv else ''\n"
        "print(json.dumps({'bestanden': True, 'befund': 'ok', 'modell': modell}))\n",
        encoding="utf-8")
    (ordner / "bauauftrag.md").write_text("# Bauauftrag\nSetze WERT auf 42.\n", encoding="utf-8")
    # Ohne diese Zeile ist der Test von der Umgebung abhaengig statt vom Code
    # (Befund 2026-09-04): die Pruefstufe "ausfuehrbar" ruft `import kern` auf,
    # und Python legt dabei `__pycache__/kern.cpython-XX.pyc` an. `git status`
    # meldet danach "?? __pycache__/", und die beiden Zusagen unten, dass das
    # Probeprojekt sauber bleibt, fielen -- nicht weil der Laeufer etwas falsch
    # macht, sondern weil ein Python-Projekt OHNE .gitignore ueberhaupt nicht
    # sauber bleiben kann. Auf einer Maschine mit PYTHONDONTWRITEBYTECODE waeren
    # sie gruen gewesen, und genau solche Zusagen sagen nichts ueber den Code.
    # Der Laeufer selbst ist hier ausdruecklich unschuldig: er committet nur den
    # Arbeitsordner und die im Vertrag genannten Dateien, nie den ganzen Baum --
    # er wuerde `__pycache__` also auch dann nicht mit hineinziehen, wenn es da
    # ist. Die Zusagen bleiben streng: ein anderer Rest faellt weiter auf.
    (ordner / ".gitignore").write_text("__pycache__/\n", encoding="utf-8")
    vertrag = {
        "ziel": "WERT in kern.py auf 42 setzen",
        "fertig_wenn": "eine Runde behalten wurde",
        "bauauftrag_datei": "bauauftrag.md",
        "dateien": ["kern.py"],
        "runden_maximal": 5,
        "stillstand_abbruch": 3,
        "erbauer": {"modell": "lmgamma", "rolle": "erbauer", "maschine": "mac",
                    "befehl": ["python3", "erbauer.py", "--modell", "lmgamma"],
                    "frist_sekunden": 30},
        "stufen": [
            {"name": "formal", "typ": "befehl", "was_nicht_prueft": "ob es laeuft",
             "befehl": ["python3", "-c",
                        "import py_compile; py_compile.compile('kern.py', doraise=True)"],
             "frist_sekunden": 20},
            {"name": "ausfuehrbar", "typ": "befehl", "was_nicht_prueft": "ob es verstaendlich ist",
             "befehl": ["python3", "-c", "import kern; assert kern.WERT == 42"],
             "frist_sekunden": 20},
            # Drei verschiedene Modelle fuer drei Rollen: der Erbauer laeuft auf
            # lmgamma, die beiden agent-Stufen auf lmbeta und lmalpha. Weniger geht
            # seit dem 01.09.2026 nicht mehr -- schon ein gemeinsames Modell
            # zwischen zwei Rollen wird abgelehnt (Befund B3).
            {"name": "eigenschaften", "typ": "agent", "was_nicht_prueft": "Stilfragen",
             "befehl": ["python3", "pruefer_ok.py", "--modell", "lmbeta"], "modell": "lmbeta",
             "rolle": "pruefer-eigenschaften", "maschine": "mac", "frist_sekunden": 20},
            {"name": "urteil", "typ": "agent", "was_nicht_prueft": "alles Vorherige",
             "befehl": ["python3", "pruefer_ok.py", "--modell", "lmalpha"], "modell": "lmalpha",
             "rolle": "pruefer-urteil", "maschine": "host2", "frist_sekunden": 20},
        ],
    }
    (ordner / "pruefschleife.json").write_text(json.dumps(vertrag, indent=2) + "\n",
                                                encoding="utf-8")
    _git(ordner, "add", "kern.py", "erbauer.py", "pruefer_ok.py", "bauauftrag.md",
         "pruefschleife.json", ".gitignore")
    _git(ordner, "commit", "-q", "-m", "start")
    return ordner


def _vertrag_lesen(projekt):
    return json.loads((projekt / "pruefschleife.json").read_text(encoding="utf-8"))


def _vertrag_schreiben(projekt, roh, nachricht):
    (projekt / "pruefschleife.json").write_text(json.dumps(roh, indent=2) + "\n", encoding="utf-8")
    _git(projekt, "add", "pruefschleife.json")
    _git(projekt, "commit", "-q", "-m", nachricht)


# ──────────────────────────────────────────────────────────── projekt_bestimmen

print("projekt_bestimmen: die vier Faelle, in der vorgeschriebenen Reihenfolge")
with tempfile.TemporaryDirectory() as basis:
    basis = Path(basis)
    projekt_dir = basis / "projekt"; projekt_dir.mkdir()
    konfig_dir = basis / "konfig"; konfig_dir.mkdir()
    konfig_datei = konfig_dir / "pruefschleife.json"
    konfig_datei.write_text("{}", encoding="utf-8")
    pruefe("Fall 1: --projekt gewinnt gegen --konfiguration",
           ps.projekt_bestimmen(projekt_dir, konfig_datei) == projekt_dir.resolve())
    pruefe("Fall 2: ohne --projekt gewinnt das Verzeichnis von --konfiguration",
           ps.projekt_bestimmen(None, konfig_datei) == konfig_dir.resolve())
    alt_cwd = Path.cwd()
    cwd_mit = basis / "cwd-mit"; cwd_mit.mkdir()
    (cwd_mit / "pruefschleife.json").write_text("{}", encoding="utf-8")
    try:
        os.chdir(cwd_mit)
        pruefe("Fall 3: sonst das Arbeitsverzeichnis, wenn dort eine pruefschleife.json liegt",
               ps.projekt_bestimmen(None, None) == cwd_mit.resolve())
    finally:
        os.chdir(alt_cwd)
    cwd_ohne = basis / "cwd-ohne"; cwd_ohne.mkdir()
    try:
        os.chdir(cwd_ohne)
        pruefe("Fall 4: sonst das Skriptverzeichnis (Vorgabefall)",
               ps.projekt_bestimmen(None, None) == ps.SKRIPT_VERZEICHNIS)
    finally:
        os.chdir(alt_cwd)


# ──────────────────────────────────────────────────────────── vertrag_laden

def _mini_projekt(basis: Path, **override) -> Path:
    projekt = basis / "p"
    projekt.mkdir(exist_ok=True)
    (projekt / "bauauftrag.md").write_text("Kontext", encoding="utf-8")
    (projekt / "kern.py").write_text("WERT=0\n", encoding="utf-8")
    v = {
        "ziel": "x", "fertig_wenn": "y", "bauauftrag_datei": "bauauftrag.md",
        "dateien": ["kern.py"],
        "erbauer": {"modell": "lmgamma", "rolle": "erbauer", "maschine": "mac",
                    "befehl": ["python3", "e.py", "--modell", "lmgamma"]},
        "stufen": [{"name": "formal", "typ": "befehl", "was_nicht_prueft": "z",
                    "befehl": ["python3", "f.py"]}],
    }
    v.update(override)
    (projekt / "pruefschleife.json").write_text(json.dumps(v), encoding="utf-8")
    return projekt


print("vertrag_laden: Pflichtfelder, Typpruefungen, Pfadsicherung")
with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis))
    v = ps.vertrag_laden(projekt)
    pruefe("gueltiger Minimal-Vertrag laedt durch", v.ziel == "x" and len(v.stufen) == 1)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis), dateien=["../ausserhalb"])
    wirft("dateien: '..' wird abgelehnt", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis), dateien=["/tmp/ausserhalb"])
    wirft("dateien: absoluter Pfad wird abgelehnt", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis))
    roh = _vertrag_lesen(projekt)
    roh["erbauer"]["befehl"] = ["/bin/sh", "-c", "echo x", "--modell", "lmgamma"]
    (projekt / "pruefschleife.json").write_text(json.dumps(roh), encoding="utf-8")
    wirft("erbauer.befehl: fremder Interpreter ausserhalb des Projekts wird abgelehnt "
          "(Hintertuer-Schutz)", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis))
    roh = _vertrag_lesen(projekt)
    roh["erbauer"]["befehl"] = "python3 e.py --modell lmgamma"
    (projekt / "pruefschleife.json").write_text(json.dumps(roh), encoding="utf-8")
    wirft("erbauer.befehl: Shell-String statt Liste wird abgelehnt", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis),
                             stufen=[{"name": "e", "typ": "agent", "was_nicht_prueft": "z",
                                      "befehl": ["python3", "f.py", "--modell", "lmalpha"]}])
    wirft("agent-Stufe ohne modell/rolle wird abgelehnt", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis),
                             stufen=[{"name": "e", "typ": "befehl", "was_nicht_prueft": "",
                                      "befehl": ["python3", "f.py"]}])
    wirft("Stufe ohne was_nicht_prueft wird abgelehnt (Regel 1 der Spec)",
          ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis))
    roh = _vertrag_lesen(projekt)
    del roh["fertig_wenn"]
    (projekt / "pruefschleife.json").write_text(json.dumps(roh), encoding="utf-8")
    wirft("fehlendes Pflichtfeld wird abgelehnt", ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = Path(basis) / "leer"
    projekt.mkdir()
    wirft("fehlende Vertragsdatei wirft ValueError (kein Traceback im Aufrufer noetig)",
          ps.vertrag_laden, projekt)


# ──────────────────────────────────────────────────────────── die zwei Bedingungen

def _agent_stufe(name, modell_kanonisch, rolle):
    return ps.Stufe(name=name, typ="agent", was_nicht_prueft="x", befehl=["python3"],
                    frist_sekunden=1, modell=modell_kanonisch, rolle=rolle, maschine="mac",
                    modell_kanonisch=modell_kanonisch)


print("modell_aus_befehl: das Modell wird AUS dem Befehl gelesen, nicht daneben geglaubt")
_verzeichnis = ps.modell_verzeichnis(MODELLE_ATTRAPPE)
pruefe("Alias im Befehl -> kanonische Kennung",
       ps.modell_aus_befehl(["python3", "p.py", "--modell", "lmalpha"], _verzeichnis, "t")
       == "lmalpha-35b")
pruefe("kanonische Kennung im Befehl -> dieselbe Kennung",
       ps.modell_aus_befehl(["python3", "p.py", "lmalpha-35b"], _verzeichnis, "t") == "lmalpha-35b")
wirft("Befehl ohne Modell wird abgelehnt (zwei Stufen waeren sonst derselbe Pruefer)",
      ps.modell_aus_befehl, ["python3", "pruefer_aufrufen.py"], _verzeichnis, "t")
wirft("Befehl mit zwei verschiedenen Modellen ist mehrdeutig und wird abgelehnt",
      ps.modell_aus_befehl, ["python3", "p.py", "--modell", "lmalpha", "--zweit", "lmbeta"],
      _verzeichnis, "t")
wirft("unbekannter Modellname wird abgelehnt (Tippfehler ist keine zweite Stimme)",
      ps.modell_aufloesen, "opus", _verzeichnis, "t")
pruefe("bekannter Alias loest auf", ps.modell_aufloesen("opus5", _verzeichnis, "t")
       == "claude-opus-5")
wirft("Etikett, das dem Befehl widerspricht, wird abgelehnt",
      ps.rolle_modell_pruefen, ["python3", "p.py", "--modell", "lmalpha"], "lmbeta",
      _verzeichnis, "t")
pruefe("modell_kurznamen liefert die Aliase, nicht die kanonischen Kennungen",
       ps.modell_kurznamen(_verzeichnis) == sorted(["lmbeta", "opus5", "lmalpha", "lmgamma"]),  # Kit: aliases renamed (port/neutralise.py)
       ps.modell_kurznamen(_verzeichnis))
pruefe("ausweg_text nennt Angebot, Registry-Befehl und den Weg ueber Pruefcode",
       all(teil in ps.ausweg_text(_verzeichnis)
           for teil in ("lmgamma", "6 Kennungen", "wb-state models table", "typ='befehl'")),  # Kit: + 2 kit-llm ids
       ps.ausweg_text(_verzeichnis))

print("pruefer_kollision (Bedingung 1): zwei Stufen brauchen anderes Modell UND andere Rolle")
pruefe("keine Kollision -> None",
       ps.pruefer_kollision([_agent_stufe("a", "lmgamma-27b", "eigenschaften"),
                             _agent_stufe("b", "lmalpha-35b", "urteil")]) is None)
pruefe("gleiches Modell, andere Rolle -> ABGELEHNT (verschaerft 01.09.2026, Befund B3)",
       ps.pruefer_kollision([_agent_stufe("a", "lmgamma-27b", "eigenschaften"),
                             _agent_stufe("b", "lmgamma-27b", "urteil")]) is not None)
pruefe("anderes Modell, gleiche Rolle -> abgelehnt (reine Modellvielfalt reicht nicht)",
       ps.pruefer_kollision([_agent_stufe("a", "lmgamma-27b", "pruefer"),
                             _agent_stufe("b", "lmalpha-35b", "pruefer")]) is not None)
pruefe("gleiches Modell UND gleiche Rolle -> abgelehnt",
       ps.pruefer_kollision([_agent_stufe("a", "lmgamma-27b", "pruefer"),
                             _agent_stufe("b", "lmgamma-27b", "pruefer")]) is not None)

print("erbauer_prueft_nicht_selbst (Bedingung 2, Regel 4): Pruefstufe darf nicht der Erbauer sein")
erbauer = ps.Erbauer(modell="lmgamma", rolle="erbauer", maschine="mac", befehl=["python3"],
                      frist_sekunden=1, modell_kanonisch="lmgamma-27b")
pruefe("keine Ueberschneidung -> None",
       ps.erbauer_prueft_nicht_selbst(erbauer, [_agent_stufe("a", "lmalpha-35b", "pruefer")])
       is None)
pruefe("dasselbe Modell wie der Erbauer -> ABGELEHNT, auch bei anderer Rolle "
       "(verschaerft 01.09.2026, Befund B3)",
       ps.erbauer_prueft_nicht_selbst(erbauer, [_agent_stufe("a", "lmgamma-27b", "pruefer")])
       is not None)
pruefe("dieselbe Rolle wie der Erbauer -> abgelehnt",
       ps.erbauer_prueft_nicht_selbst(erbauer, [_agent_stufe("a", "lmalpha-35b", "erbauer")])
       is not None)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis), stufen=[
        {"name": "a", "typ": "agent", "was_nicht_prueft": "x",
         "befehl": ["python3", "f.py", "--modell", "lmalpha"], "modell": "lmalpha",
         "rolle": "pruefer-a"},
        {"name": "b", "typ": "agent", "was_nicht_prueft": "x",
         "befehl": ["python3", "f.py", "--modell", "lmalpha"], "modell": "lmalpha",
         "rolle": "pruefer-b"},
    ])
    wirft("vertrag_laden lehnt zwei Pruefstufen auf demselben Modell ab",
          ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis), stufen=[
        {"name": "a", "typ": "agent", "was_nicht_prueft": "x",
         "befehl": ["python3", "f.py", "--modell", "lmgamma"], "modell": "lmgamma",
         "rolle": "pruefer"},
    ])
    wirft("vertrag_laden lehnt eine Pruefstufe auf dem Erbauer-Modell ab",
          ps.vertrag_laden, projekt)

with tempfile.TemporaryDirectory() as basis:
    projekt = _mini_projekt(Path(basis), stufen=[
        {"name": "a", "typ": "agent", "was_nicht_prueft": "x",
         "befehl": ["python3", "f.py", "--modell", "opus"], "modell": "opus",
         "rolle": "pruefer"},
    ])
    wirft("vertrag_laden lehnt einen unbekannten Modellnamen ab",
          ps.vertrag_laden, projekt)


# ──────────────────────────────────────────────────────────── auftrag_text

print("auftrag_text: die sechs Teile, der Pruefer sieht nicht wer gebaut hat")
with tempfile.TemporaryDirectory() as basis:
    # Das Erbauer-Modell ist jetzt ein ECHTER Registry-Name (ein erfundener wird
    # abgelehnt) -- die Leck-Pruefung unten sucht darum nach 'lmbeta' statt nach
    # einer Phantasiemarke und ist damit schaerfer als vorher.
    projekt = _mini_projekt(Path(basis), erbauer={
        "modell": "lmbeta", "rolle": "ERBAUERROLLEXYZ", "maschine": "mac",
        "befehl": ["python3", "e.py", "--modell", "lmbeta"]},
        stufen=[{"name": "urteil", "typ": "agent", "was_nicht_prueft": "z",
                 "befehl": ["python3", "f.py", "--modell", "lmalpha"], "modell": "lmalpha",
                 "rolle": "pruefer-urteil"}])
    v = ps.vertrag_laden(projekt)

teile = ("## 1. Was zu tun ist", "## 2. Woran gemessen wird", "## 3. Wo gearbeitet werden darf",
         "## 4. Was verboten ist", "## 5. Wie das Ergebnis aussieht", "## 6. Was bei Unklarheit gilt")
erbauer_text = ps.auftrag_text(v, "erbauer")
for teil in teile:
    pruefe(f"Erbauer-Auftrag enthaelt Teil {teil!r}", teil in erbauer_text)
pruefer_text = ps.auftrag_text(v, "pruefer", stufe=v.stufen[0])
for teil in teile:
    pruefe(f"Pruefer-Auftrag enthaelt Teil {teil!r}", teil in pruefer_text)
pruefe("Pruefer-Auftrag verlangt Widerlegen statt Bewerten", "widerlege" in pruefer_text)
pruefe("Pruefer-Auftrag verraet NICHT das Erbauer-Modell (Regel 3 der Spec)",
       "lmbeta" not in pruefer_text)
pruefe("Pruefer-Auftrag verraet NICHT die Erbauer-Rolle (Regel 3 der Spec)",
       "ERBAUERROLLEXYZ" not in pruefer_text)
pruefe("Pruefer-Auftrag nennt die EIGENE Rolle (das Etikett wirkt, statt nur dazustehen)",
       "pruefer-urteil" in pruefer_text, pruefer_text)
pruefe("Pruefer-Auftrag verlangt die Angabe, womit geurteilt wurde",
       '"modell"' in pruefer_text and "lmalpha-35b" in pruefer_text, pruefer_text)
pruefe("Erbauer sieht die Stufe im Wortlaut (Regel 3, zweite Haelfte)",
       v.stufen[0].was_nicht_prueft in erbauer_text)


# ──────────────────────────────────────────────────────────── pfad_verstoss / zuruecknehmen

print("pfad_verstoss: Aenderungen ausserhalb der erlaubten Pfade")
with tempfile.TemporaryDirectory() as basis:
    projekt = Path(basis)
    _git(projekt, "init", "-q")
    _git(projekt, "config", "user.email", "t@t")
    _git(projekt, "config", "user.name", "t")
    (projekt / "kern.py").write_text("a\n", encoding="utf-8")
    _git(projekt, "add", "kern.py")
    _git(projekt, "commit", "-q", "-m", "start")
    (projekt / "kern.py").write_text("b\n", encoding="utf-8")
    pruefe("Aenderung INNERHALB der erlaubten Pfade -> keine Verletzung",
           ps.pfad_verstoss(projekt, ["kern.py"]) == [])
    (projekt / "fremd.py").write_text("x\n", encoding="utf-8")
    verstoss = ps.pfad_verstoss(projekt, ["kern.py"])
    pruefe("neue Datei AUSSERHALB der erlaubten Pfade -> Verletzung gemeldet, Pfad vollstaendig "
           "(kein abgeschnittenes Zeichen aus dem Statuscode)",
           verstoss == ["fremd.py"], verstoss)

print("zuruecknehmen: stellt den Stand vor der Runde wieder her, auch neu angelegte Dateien")
with tempfile.TemporaryDirectory() as basis:
    projekt = Path(basis)
    _git(projekt, "init", "-q")
    _git(projekt, "config", "user.email", "t@t")
    _git(projekt, "config", "user.name", "t")
    (projekt / "kern.py").write_text("a\n", encoding="utf-8")
    _git(projekt, "add", "kern.py")
    _git(projekt, "commit", "-q", "-m", "start")
    vorher = _git(projekt, "rev-parse", "HEAD").stdout.strip()
    (projekt / "kern.py").write_text("b\n", encoding="utf-8")
    (projekt / "neu.py").write_text("neu\n", encoding="utf-8")
    ps.zuruecknehmen(projekt, vorher, ["kern.py", "neu.py"])
    pruefe("kern.py zurueckgesetzt", (projekt / "kern.py").read_text(encoding="utf-8") == "a\n")
    pruefe("neu.py entfernt (git clean)", not (projekt / "neu.py").exists())


# ──────────────────────────────────────────────────────────── echte Tests, ueber die CLI

print("Jeder Unterbefehl im fremden Projekt -- der Laeuferbaum bleibt unberuehrt")
befehle = ps.unterbefehle()
pruefe("alle fuenf bekannten Unterbefehle gefunden (kein Unterbefehl vergessen -- aus dem "
       "Parser gelesen, nicht aus einer Konstanten)",
       set(befehle) == {"vorlage", "lauf", "schleife", "stand", "fortsetzen"}, befehle)

vor_lauf = _repo_abbild()
with tempfile.TemporaryDirectory() as basis:
    basis = Path(basis)
    for befehl in befehle:
        projekt = basis / f"p-{befehl}"
        if befehl == "vorlage":
            projekt.mkdir(parents=True)
            ergebnis = _cli("vorlage", "--projekt", str(projekt))
            pruefe("Unterbefehl 'vorlage' schreibt in das fremde Projekt, nicht in den Laeufer",
                   ergebnis.returncode == 0 and (projekt / "pruefschleife.json").exists(),
                   (ergebnis.returncode, ergebnis.stdout, ergebnis.stderr))
            continue
        _neues_probeprojekt(projekt)
        ergebnis = _cli("--projekt", str(projekt), befehl)
        # 'fortsetzen' ohne laufende Runde meldet sich sauber ab (rc 1) --
        # das beweist gerade, dass es GEGEN das frische Probeprojekt lief.
        ok = ergebnis.returncode == 0 or (befehl == "fortsetzen"
                                          and "Kein abgebrochener Lauf" in ergebnis.stdout)
        pruefe(f"Unterbefehl '{befehl}' im Probeprojekt aufgerufen, kein Traceback",
               ok and "Traceback" not in ergebnis.stderr,
               (ergebnis.returncode, ergebnis.stdout, ergebnis.stderr))
nach_lauf = _repo_abbild()
pruefe("Laeuferdatei selbst unveraendert (Inhalt+mtime)",
       vor_lauf[0] == nach_lauf[0] and vor_lauf[1] == nach_lauf[1])
pruefe("HEAD des Laeufer-Repos unveraendert", vor_lauf[2] == nach_lauf[2])
pruefe("kein neuer git-Rest im Laeufer-Repo", vor_lauf[3] == nach_lauf[3],
       (vor_lauf[3], nach_lauf[3]))

print("Vorgabefall: kein --projekt, kein Vertrag im Arbeitsverzeichnis")
vor_c = _repo_abbild()
with tempfile.TemporaryDirectory() as leer:
    ergebnis = _cli("lauf", cwd=leer)
pruefe("klare Meldung statt Traceback",
       ergebnis.returncode == 1 and "Kein Vertrag" in ergebnis.stdout
       and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
nach_c = _repo_abbild()
pruefe("der Laeuferbaum bleibt unveraendert", vor_c == nach_c)

print("Ende-zu-Ende: ein vollstaendiger Lauf, der bauende Agent ist ein Skript, das eine Datei schreibt")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "e2e")
    vor_e2e = _repo_abbild()

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("lauf: durchgelaufen, kein Traceback",
           ergebnis.returncode == 0 and "Traceback" not in ergebnis.stderr,
           (ergebnis.stdout, ergebnis.stderr))
    pruefe("lauf: 'behalten' gemeldet", "behalten" in ergebnis.stdout, ergebnis.stdout)
    pruefe("lauf: kern.py wurde ECHT vom Erbauer-Skript geschrieben (kein simulierter Bau)",
           "WERT = 42" in (projekt / "kern.py").read_text(encoding="utf-8"))

    zeilen = (projekt / ".pruefschleife" / "runden.tsv").read_text(encoding="utf-8").splitlines()
    pruefe("runden.tsv hat Kopf + eine behaltene Runde",
           len(zeilen) == 2 and zeilen[1].split("\t")[3] == "behalten", zeilen)

    log = _git(projekt, "log", "--oneline").stdout
    pruefe("der Commit steht IM PROBEPROJEKT (echtes git, kein Mock)",
           "Runde 1 behalten" in log, log)
    status = _git(projekt, "status", "--porcelain").stdout
    pruefe("Probeprojekt ist nach der behaltenen Runde sauber (Stand mitcommittet)",
           status == "", status)

    nach_e2e = _repo_abbild()
    pruefe("der Laeuferbaum bleibt sauber, obwohl im Probeprojekt echt committet wurde",
           vor_e2e == nach_e2e)

print("Eine Runde, die an Stufe 2 scheitert -- Befund festgehalten, Datei zurueckgenommen")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "stufe2-scheitert")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][1]["befehl"] = ["python3", "-c", "raise SystemExit(1)"]
    _vertrag_schreiben(projekt, roh, "Stufe 2 absichtlich kaputt (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("lauf meldet den Abbruch bei der richtigen Stufe",
           "abgebrochen bei Stufe ausfuehrbar" in ergebnis.stdout, ergebnis.stdout)
    pruefe("kern.py bleibt UNVERAENDERT (Rollback nach gefallener Stufe)",
           (projekt / "kern.py").read_text(encoding="utf-8") == "WERT = 0\n")
    zeilen = (projekt / ".pruefschleife" / "runden.tsv").read_text(encoding="utf-8").splitlines()
    pruefe("runden.tsv haelt die abgebrochene Runde fest",
           zeilen[-1].split("\t")[3] == "abgebrochen", zeilen)
    letzte_zeile = (projekt / ".pruefschleife" / "runden.jsonl").read_text(
        encoding="utf-8").splitlines()[-1]
    eintrag = json.loads(letzte_zeile)
    pruefe("runden.jsonl haelt den vollen Befund fest (Stufenname im Befund)",
           "ausfuehrbar" in eintrag["befund"], eintrag)
    status = _git(projekt, "status", "--porcelain").stdout
    pruefe("Probeprojekt bleibt sauber (Bookkeeping-Commit trotz Abbruch)", status == "", status)

print("Abbruch mitten in Stufe 3 -- 'fortsetzen' wiederholt nicht, was schon durch ist")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "abbruch-fortsetzen")
    (projekt / "zaehlen.py").write_text(
        "import pathlib, sys\n"
        "p = pathlib.Path(sys.argv[1])\n"
        "n = (int(p.read_text()) + 1) if p.exists() else 1\n"
        "p.write_text(str(n))\n",
        encoding="utf-8")
    (projekt / "pruefer_langsam.py").write_text(
        "import time, json, sys\n"
        "time.sleep(1.5)\n"
        "modell = sys.argv[sys.argv.index('--modell') + 1] if '--modell' in sys.argv else ''\n"
        "print(json.dumps({'bestanden': True, 'befund': 'ok, spaet', 'modell': modell}))\n",
        encoding="utf-8")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][0]["befehl"] = ["python3", "-c",
        "import subprocess; subprocess.run(['python3','zaehlen.py','c1.txt'], check=True); "
        "import py_compile; py_compile.compile('kern.py', doraise=True)"]
    roh["stufen"][1]["befehl"] = ["python3", "-c",
        "import subprocess; subprocess.run(['python3','zaehlen.py','c2.txt'], check=True); "
        "import kern; assert kern.WERT == 42"]
    roh["stufen"][2]["befehl"] = ["python3", "pruefer_langsam.py", "--modell",
                                  roh["stufen"][2]["modell"]]
    _git(projekt, "add", "zaehlen.py", "pruefer_langsam.py")
    _vertrag_schreiben(projekt, roh, "Stufe 3 verlangsamt fuer den Abbruch-Test")

    prozess = subprocess.Popen([sys.executable, str(SKRIPT), "--projekt", str(projekt), "lauf"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(0.7)  # Stufe 1+2 sind in Bruchteilen einer Sekunde durch, Stufe 3 schlaeft noch
    prozess.kill()
    prozess.wait(timeout=5)
    time.sleep(2.0)  # der verwaiste pruefer_langsam.py-Kindprozess laeuft seinen kurzen Schlaf
                      # von selbst zu Ende (Prozess-Hygiene: nichts bleibt haengen, weil nichts
                      # laenger lebt als 1,5s)

    zustand = json.loads((projekt / ".pruefschleife" / "stand.json").read_text(encoding="utf-8"))
    pruefe("Zustand zeigt genau Stufe 1+2 durch, Stufe 3 noch nicht verzeichnet",
           zustand.get("laufend") is True and len(zustand.get("stufen_ergebnisse", [])) == 2,
           zustand)

    ergebnis = _cli("--projekt", str(projekt), "fortsetzen")
    pruefe("fortsetzen: durchgelaufen, kein Traceback",
           ergebnis.returncode == 0 and "Traceback" not in ergebnis.stderr,
           (ergebnis.stdout, ergebnis.stderr))
    pruefe("fortsetzen: meldet die Fortsetzung mit 2 von 4 Stufen",
           "wird fortgesetzt (2 von 4" in ergebnis.stdout, ergebnis.stdout)
    pruefe("fortsetzen: Runde am Ende behalten", "behalten" in ergebnis.stdout, ergebnis.stdout)

    c1 = int((projekt / "c1.txt").read_text(encoding="utf-8"))
    c2 = int((projekt / "c2.txt").read_text(encoding="utf-8"))
    pruefe("Stufe 1 wurde genau EINMAL ausgefuehrt (nicht wiederholt)", c1 == 1, c1)
    pruefe("Stufe 2 wurde genau EINMAL ausgefuehrt (nicht wiederholt)", c2 == 1, c2)

print("Zwei Pruefstufen auf demselben Modell werden ueber die CLI abgelehnt")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "kollision")
    roh = _vertrag_lesen(projekt)
    # Verschiedene ROLLEN, gleiches Modell -- genau der Fall, den der Laeufer
    # bis zum 01.09.2026 angenommen hat (Befund B3, erster Teil).
    roh["stufen"][3]["modell"] = roh["stufen"][2]["modell"]
    roh["stufen"][3]["befehl"] = list(roh["stufen"][2]["befehl"])
    _vertrag_schreiben(projekt, roh, "Kollision absichtlich einbauen (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("CLI lehnt zwei Stufen auf einem Modell ab, obwohl die Rollen verschieden sind "
           "(rc 1, klare Meldung, kein Traceback)",
           ergebnis.returncode == 1 and "Panel gleichartiger Pruefer" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
    # Eine Sperre ohne Ausweg schickt den naechsten Agenten ins Raten oder in
    # die Umgehung. Die Meldung muss also sagen, was diese Maschine anbietet
    # UND dass Pruefcode keine Rolle besetzt.
    pruefe("die Ablehnung nennt die Kurznamen, die diese Maschine anbietet",
           all(name in ergebnis.stdout for name in ("lmgamma", "lmalpha", "lmbeta", "opus5")),
           ergebnis.stdout)
    pruefe("die Ablehnung nennt den Ausweg ueber Pruefcode (typ='befehl')",
           "typ='befehl'" in ergebnis.stdout
           and "auch mit einem einzigen Modell" in ergebnis.stdout, ergebnis.stdout)
    pruefe("die Ablehnung nennt den vollstaendigen Weg zur Registry",
           "wb-state models table" in ergebnis.stdout, ergebnis.stdout)

print("Zwei Stufen mit demselben Befehl und verschiedenen Etiketten werden abgelehnt")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "gleicher-befehl")
    roh = _vertrag_lesen(projekt)
    # Der Fall aus der ALTEN Vorlage: zwei Stufen fuehren dieselbe Zeile aus und
    # tragen daneben verschiedene Modellnamen. Der Laeufer liest das Modell aus
    # dem Befehl -- damit widerspricht das Etikett dem Aufruf und faellt auf.
    roh["stufen"][3]["befehl"] = list(roh["stufen"][2]["befehl"])
    _vertrag_schreiben(projekt, roh, "Gleicher Befehl, andere Etiketten (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("CLI lehnt den identischen Befehl ab (rc 1, nennt den Widerspruch, kein Traceback)",
           ergebnis.returncode == 1 and "widerspricht dem Befehl" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))

print("Ein agent-Befehl, der gar kein Modell nennt, wird abgelehnt")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "kein-modell-im-befehl")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][3]["befehl"] = ["python3", "pruefer_ok.py"]
    _vertrag_schreiben(projekt, roh, "Modell aus dem Befehl entfernt (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("CLI verlangt das Modell IM Befehl (rc 1, klare Meldung, kein Traceback)",
           ergebnis.returncode == 1 and "nennt kein bekanntes Modell" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))

print("Ein unbekannter Modellname faellt ueber die CLI auf -- ein Tippfehler ist kein Pruefer")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "tippfehler")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][3]["modell"] = "opus"          # 'opus5' waere richtig
    roh["stufen"][3]["befehl"] = ["python3", "pruefer_ok.py", "--modell", "opus"]
    _vertrag_schreiben(projekt, roh, "Tippfehler im Modellnamen (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("CLI lehnt den unbekannten Modellnamen ab (rc 1, klare Meldung, kein Traceback)",
           ergebnis.returncode == 1
           and "steht in keinem Modellverzeichnis" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
    pruefe("die Meldung nennt die Kurznamen, unter denen 'opus5' zu finden ist",
           "opus5" in ergebnis.stdout and "wb-state models table" in ergebnis.stdout,
           ergebnis.stdout)

print("Der Ausweg aus der Ablehnung traegt wirklich: ein Modell plus Pruefcode laeuft durch")
with tempfile.TemporaryDirectory() as basis:
    # Genau die Kette, auf die die Ablehnungsmeldung verweist -- eine Maschine
    # mit einem einzigen Modell. Ohne diesen Test waere der Ausweg eine
    # Behauptung in einem Fehlertext.
    projekt = _neues_probeprojekt(Path(basis) / "ein-modell")
    roh = _vertrag_lesen(projekt)
    roh["stufen"] = [s for s in roh["stufen"] if s["typ"] == "befehl"] + [
        {"name": "eigenschaften", "typ": "befehl", "was_nicht_prueft": "Stilfragen",
         "befehl": ["python3", "-c", "import kern; assert kern.WERT % 2 == 0"],
         "frist_sekunden": 20}]
    _vertrag_schreiben(projekt, roh, "Kette aus einem Erbauer und Pruefcode (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("die Runde laeuft durch und wird behalten",
           ergebnis.returncode == 0 and "behalten" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
    pruefe("der Bau ist wirklich passiert",
           "WERT = 42" in (projekt / "kern.py").read_text(encoding="utf-8"))

print("Eine Pruefstufe auf dem Erbauer-Modell wird ueber die CLI abgelehnt")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "selbstpruefung")
    roh = _vertrag_lesen(projekt)
    # Nur das MODELL wird geteilt, die Rolle bleibt verschieden -- der Fall der
    # alten ausgelieferten Vorlage.
    roh["stufen"][2]["modell"] = roh["erbauer"]["modell"]
    roh["stufen"][2]["befehl"] = ["python3", "pruefer_ok.py", "--modell",
                                  roh["erbauer"]["modell"]]
    _vertrag_schreiben(projekt, roh, "Selbstpruefung absichtlich einbauen (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("CLI lehnt die Selbstpruefung ab (rc 1, klare Meldung, kein Traceback)",
           ergebnis.returncode == 1 and "wer prueft, baut nicht" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
    pruefe("auch diese Ablehnung traegt den Ausweg (Kurznamen und Pruefcode)",
           "lmgamma" in ergebnis.stdout and "typ='befehl'" in ergebnis.stdout, ergebnis.stdout)

print("Ein Pruefer, der mit einem ANDEREN Modell urteilt als vorgesehen, laesst die Stufe fallen")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "luegender-pruefer")
    # Der Mantel bekommt '--modell lmalpha', fragt aber lmbeta: von aussen ist das
    # nur an seiner eigenen Meldung zu erkennen -- genau dafuer ist sie da.
    (projekt / "pruefer_luegt.py").write_text(
        "import json\n"
        "print(json.dumps({'bestanden': True, 'befund': 'ok', 'modell': 'lmbeta'}))\n",
        encoding="utf-8")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][3]["befehl"] = ["python3", "pruefer_luegt.py", "--modell", "lmalpha"]
    _git(projekt, "add", "pruefer_luegt.py")
    _vertrag_schreiben(projekt, roh, "Pruefer meldet ein anderes Modell (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("die Runde bricht bei der Urteilsstufe ab",
           "abgebrochen bei Stufe urteil" in ergebnis.stdout, ergebnis.stdout)
    letzte_zeile = (projekt / ".pruefschleife" / "runden.jsonl").read_text(
        encoding="utf-8").splitlines()[-1]
    pruefe("der Befund nennt das gemeldete und das vorgesehene Modell",
           "lmbeta-27b" in json.loads(letzte_zeile)["befund"]
           and "lmalpha-35b" in json.loads(letzte_zeile)["befund"], letzte_zeile)
    pruefe("kern.py bleibt UNVERAENDERT (der Bau wird zurueckgenommen)",
           (projekt / "kern.py").read_text(encoding="utf-8") == "WERT = 0\n")

print("Ein Pruefer, der gar kein Modell meldet, laesst die Stufe fallen")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "schweigender-pruefer")
    (projekt / "pruefer_stumm.py").write_text(
        "import json\nprint(json.dumps({'bestanden': True, 'befund': 'ok'}))\n",
        encoding="utf-8")
    roh = _vertrag_lesen(projekt)
    roh["stufen"][3]["befehl"] = ["python3", "pruefer_stumm.py", "--modell", "lmalpha"]
    _git(projekt, "add", "pruefer_stumm.py")
    _vertrag_schreiben(projekt, roh, "Pruefer ohne Modellangabe (fuer diesen Test)")

    ergebnis = _cli("--projekt", str(projekt), "lauf")
    pruefe("die Runde bricht bei der Urteilsstufe ab",
           "abgebrochen bei Stufe urteil" in ergebnis.stdout, ergebnis.stdout)
    letzte_zeile = (projekt / ".pruefschleife" / "runden.jsonl").read_text(
        encoding="utf-8").splitlines()[-1]
    pruefe("der Befund sagt, dass die Modellangabe fehlt",
           "nennt kein Modell" in json.loads(letzte_zeile)["befund"], letzte_zeile)

print("Die AUSGELIEFERTE Vorlage verletzt die Regel nicht -- der Laeufer nimmt sie an")
with tempfile.TemporaryDirectory() as basis:
    projekt = Path(basis) / "vorlage-sauber"
    projekt.mkdir(parents=True)
    ergebnis = _cli("vorlage", "--projekt", str(projekt))
    pruefe("vorlage geschrieben", ergebnis.returncode == 0, (ergebnis.stdout, ergebnis.stderr))
    # 'stand' laedt den Vertrag vollstaendig (main() -> vertrag_laden) und
    # meldet danach, dass noch nichts lief. Wird die Vorlage abgelehnt, kommt
    # stattdessen rc 1 mit der Begruendung.
    ergebnis = _cli("--projekt", str(projekt), "stand")
    pruefe("die ausgelieferte Vorlage wird ANGENOMMEN (rc 0, kein Widerspruch)",
           ergebnis.returncode == 0 and "Noch keine Runde gelaufen" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))
    vorlage = json.loads((projekt / "pruefschleife.json").read_text(encoding="utf-8"))
    agenten = [s for s in vorlage["stufen"] if s["typ"] == "agent"]
    modelle = [vorlage["erbauer"]["modell"]] + [s["modell"] for s in agenten]
    pruefe("kein Modell der Vorlage besetzt zwei Rollen (das schlechte Beispiel ist weg)",
           len(set(modelle)) == len(modelle), modelle)
    pruefe("jeder Agenten-Befehl der Vorlage nennt sein Modell selbst",
           all(s["modell"] in s["befehl"] for s in agenten)
           and vorlage["erbauer"]["modell"] in vorlage["erbauer"]["befehl"], vorlage)

print("Die ausgelieferte Vorlage passt auch gegen die ECHTE Registry, nicht nur gegen die Attrappe")
if not ECHTE_REGISTRY.exists():
    print(f"  ---  uebersprungen: {ECHTE_REGISTRY} gibt es auf dieser Maschine nicht")
else:
    with tempfile.TemporaryDirectory() as basis:
        projekt = Path(basis) / "vorlage-echt"
        projekt.mkdir(parents=True)
        _cli("vorlage", "--projekt", str(projekt), umgebung={"WB_MODELS_FILE": None})
        ergebnis = _cli("--projekt", str(projekt), "stand", umgebung={"WB_MODELS_FILE": None})
        pruefe("die Vorlage laedt gegen ~/.claude/workbench/models.json",
               ergebnis.returncode == 0 and "Noch keine Runde gelaufen" in ergebnis.stdout,
               (ergebnis.stdout, ergebnis.stderr))

print("Ohne Modellverzeichnis sagt der Laeufer, was fehlt -- statt es einfach zu glauben")
with tempfile.TemporaryDirectory() as basis:
    projekt = _neues_probeprojekt(Path(basis) / "ohne-verzeichnis")
    ergebnis = _cli("--projekt", str(projekt), "lauf",
                    umgebung={"WB_MODELS_FILE": str(Path(basis) / "gibt-es-nicht.json")})
    pruefe("klare Meldung statt Traceback",
           ergebnis.returncode == 1 and "Modellverzeichnis" in ergebnis.stdout
           and "Traceback" not in ergebnis.stderr, (ergebnis.stdout, ergebnis.stderr))

print()
if fehler:
    print(f"{len(fehler)} Fehler: {', '.join(fehler)}")
    sys.exit(1)
print("Alle Tests bestanden.")
