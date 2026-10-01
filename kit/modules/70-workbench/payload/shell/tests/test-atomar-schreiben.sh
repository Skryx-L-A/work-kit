#!/bin/bash
# test-atomar-schreiben.sh — die drei Fundstellen aus dem Prüfpass vom 21.08.
# (~/.pi-workers/results/hafenmeister/20260821-045339.md, Befund gemeldet unter
# Punkt 2 von Auftrag 4) schreiben nach demselben Muster wie das gefixte
# `wb-ausrollen`: mit `atomar_schreiben.schreiben()` unteilbar, nicht mehr
# direkt aufs Ziel.
#
# ANLASS (Auftrag 5): `shell/wb-harness-config` (apply_one, Zeile ~362),
# `shell/wb-instructions` (write_generated, Zeile ~355, plus die Routing-Block-
# Einfügung) und `shell/mcp-shared` (cmd_apply, Zeile ~229) schrieben alle
# direkt auf ihr Ziel — `open(ziel,"w")`, `shutil.copymode` danach, oder
# `Path.write_text`. Ein Leser (eine startende Harness-Sitzung, ein anderer
# Prozess) konnte in genau diesem Moment eine halb geschriebene Datei sehen,
# dasselbe Muster wie beim `pi-worker`-Vorfall, der Auftrag 4 ausgelöst hat.
# Die Lösung liegt jetzt an EINER Stelle (`shell/atomar_schreiben.py`), von
# allen vier Werkzeugen benutzt.
#
# WORAN EIN LESER MERKEN WÜRDE, DASS ER EINE HALBE DATEI HAT: bei
# `wb-ausrollen` (bash-Skripte) reichte `bash -n` — ein Bruch mitten in einer
# Funktion ist fast immer ein Syntaxfehler. Für die drei Stellen hier gilt das
# NICHT: ein halber Rollen-Prompt, ein halbes JSON, ein halbes TOML ist
# oft syntaktisch gültiger Text oder zumindest keine Zeichenkette, die
# zuverlässig einen Parser bricht. Geprüft wird deshalb allgemeiner und
# schärfer: das aktuell LESBARE liegt entweder BYTEIDENTISCH auf der alten
# ODER byteidentisch auf der neuen Fassung — alles andere IST die halbe
# Datei, ganz gleich, ob sie zufällig noch "aussieht" wie gültiger Text.
#
# ISOLATION: jede Sektion arbeitet in einem eigenen mktemp-Verzeichnis, mit
# HOME auf dieses Verzeichnis umgelenkt (wo eine der drei Funktionen HOME
# selbst braucht, z.B. für ihre Schnappschüsse). Kein echter Dienst wird
# gestartet oder beendet, das echte ~/.local/bin, ~/.claude.json und
# ~/.claude/CLAUDE.md werden nie gelesen oder geschrieben — Abschnitt 4 prüft
# das für jede Sektion ausdrücklich nach.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"      # …/claude-workbench/shell
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

echo "Geprueft: atomar_schreiben.py ueber wb-harness-config, wb-instructions, mcp-shared"

SPIEL="$(mktemp -d "${TMPDIR:-/tmp}/wb-atomar-test.XXXXXX")"
cleanup() {
  case "$SPIEL" in
    /tmp/wb-atomar-test.*|/private/tmp/wb-atomar-test.*|/var/folders/*/wb-atomar-test.*)
      rm -rf "$SPIEL" ;;
    *) echo "WARNUNG: SPIEL='$SPIEL' sieht nicht nach einem Testverzeichnis aus — NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

# ── gemeinsamer Wettlauf-Treiber ─────────────────────────────────────────────
# Nimmt eine Python-Quelldatei, die eine Funktion namens 'lauf(alt_pfad)'
# definiert (fuellt 'alt_pfad' mit ALT, schreibt dann NEU -- ueber welchen
# Mechanismus, entscheidet die jeweilige Fassung), fuehrt sie in einem
# Hintergrund-Thread aus, waehrend der Hauptthread im Sekundenbruchteil-Takt
# den Inhalt von 'alt_pfad' abtastet. 'gruen' bedeutet: JEDE Abtastung war
# entweder byteidentisch ALT oder byteidentisch NEU.
cat > "$SPIEL/wettlauf.py" <<'PY'
import sys
import threading
import time
import types

fassung_pfad, ziel, alt_datei, neu_datei = sys.argv[1:5]
ALT = open(alt_datei, encoding="utf-8").read()
NEU = open(neu_datei, encoding="utf-8").read()

with open(ziel, "w", encoding="utf-8") as f:
    f.write(ALT)

quelltext = open(fassung_pfad, encoding="utf-8").read()
mod = types.ModuleType("fassungstest")
mod.__file__ = fassung_pfad
exec(compile(quelltext, fassung_pfad, "exec"), mod.__dict__)

t = threading.Thread(target=mod.lauf, args=(ziel, NEU))
t.start()
abtastungen = 0
korrupt_gesehen = False
korrupt_beispiel = ""
while t.is_alive():
    abtastungen += 1
    with open(ziel, encoding="utf-8") as f:
        aktuell = f.read()
    if aktuell not in (ALT, NEU):
        korrupt_gesehen = True
        korrupt_beispiel = aktuell[:60].replace("\n", "\\n")
t.join()

print("ABTASTUNGEN=%d" % abtastungen)
print("KORRUPT_GESEHEN=%s" % korrupt_gesehen)
print("KORRUPT_BEISPIEL=%s" % korrupt_beispiel)
with open(ziel, encoding="utf-8") as f:
    endinhalt = f.read()
print("ENDINHALT_GLEICH_NEU=%s" % (endinhalt == NEU))
PY

# Grosser, in sich variierender Text -- ein 60-mal wiederholtes "NEU" waere
# theoretisch an vielen Abschnittsgrenzen zufaellig wieder gueltig; individuell
# nummerierte Zeilen machen jede Praefix-Laenge einzigartig, damit der
# Gleichheitsvergleich wirklich jede Zwischenstufe von ALT unterscheidet.
python3 - "$SPIEL/alt.txt" "$SPIEL/neu.txt" <<'PY'
import sys
alt_pfad, neu_pfad = sys.argv[1:3]
open(alt_pfad, "w", encoding="utf-8").write("# Rolle\nDu bist knapp und hilfreich.\n")
zeilen = ["# Rolle"] + ["Regel %d: sei genau und nenne die Quelle." % i for i in range(80)]
open(neu_pfad, "w", encoding="utf-8").write("\n".join(zeilen) + "\n")
PY

echo
echo "=== 1. shell/wb-harness-config: apply_one() schreibt unteilbar ==============="

cat > "$SPIEL/alt_harness_config.py" <<'PY'
# Die VORHERIGE Fassung von apply_one()s Schreibschritt, wortgetreu: open()
# direkt aufs Ziel, dann shutil.copymode() -- KEINE Nebendatei, KEIN os.replace.
import shutil
import time


def lauf(ziel, neu_inhalt):
    haeppchen = 24
    with open(ziel, "w", encoding="utf-8", newline="") as fh:
        for i in range(0, len(neu_inhalt), haeppchen):
            fh.write(neu_inhalt[i:i + haeppchen])
            fh.flush()
            time.sleep(0.01)
    # shutil.copymode wuerde hier eine echte Quelldatei brauchen; fuer den
    # Wettlauf selbst ist es ohne Bedeutung -- der Inhalt steht zu diesem
    # Zeitpunkt schon (moeglicherweise korrupt) am Ziel.
PY

cat > "$SPIEL/neu_harness_config.py" <<PY
# Die AKTUELLE Fassung: importiert echtes atomar_schreiben, mit kuenstlich
# verlangsamtem open() (siehe unten), damit derselbe Wettlauf beobachtbar wird
# -- ohne die Verlangsamung waere ein einzelner Schreibvorgang in
# Mikrosekunden fertig und die Abtastung faende so gut wie nie ein Fenster,
# unabhaengig davon, ob der Code atomar ist oder nicht.
import sys
import time

sys.path.insert(0, "$REPO")
import atomar_schreiben

_orig_open = atomar_schreiben.open if hasattr(atomar_schreiben, "open") else open


def _langsames_open(pfad, *a, **kw):
    f = _orig_open(pfad, *a, **kw)
    modus = a[0] if a else kw.get("mode", "r")
    if "w" in modus:
        echt_write = f.write

        def langsames_write(s):
            for i in range(0, len(s), 24):
                echt_write(s[i:i + 24])
                f.flush()
                time.sleep(0.01)
            return len(s)

        f.write = langsames_write
    return f


atomar_schreiben.open = _langsames_open


def lauf(ziel, neu_inhalt):
    atomar_schreiben.schreiben(ziel, neu_inhalt, modus=0o644, newline="")
PY

echo
echo "-- 1a: ROT gegen die alte Fassung --"
AUS1A="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/alt_harness_config.py" "$SPIEL/ziel1a.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
if printf '%s' "$AUS1A" | grep -q '^KORRUPT_GESEHEN=True'; then
    ok "1a: die alte Schreibweise von apply_one() zeigt waehrend des Schreibens eine weder-alt-noch-neue Fassung"
else
    bad "1a: die alte Fassung haette korrupt sein muessen, der Test misst nichts: $AUS1A"
fi
printf '%s' "$AUS1A" | grep -q '^ABTASTUNGEN=[1-9]' \
    && ok "1a: genug Abtastungen fuer einen Beweis ($(printf '%s' "$AUS1A" | sed -n 's/^ABTASTUNGEN=//p'))" \
    || bad "1a: zu wenige Abtastungen: $AUS1A"

echo
echo "-- 1b: GRUEN gegen die AKTUELLE Fassung (echtes atomar_schreiben), dreimal --"
for LAUF in 1 2 3; do
    AUS1B="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/neu_harness_config.py" "$SPIEL/ziel1b-$LAUF.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
    if printf '%s' "$AUS1B" | grep -q '^KORRUPT_GESEHEN=False'; then
        ok "1b Lauf $LAUF: nie eine weder-alt-noch-neue Fassung sichtbar ($(printf '%s' "$AUS1B" | sed -n 's/^ABTASTUNGEN=//p') Abtastungen)"
    else
        bad "1b Lauf $LAUF: eine korrupte Zwischenfassung war sichtbar: $AUS1B"
    fi
    printf '%s' "$AUS1B" | grep -q '^ENDINHALT_GLEICH_NEU=True' \
        && ok "1b Lauf $LAUF: am Ende steht wirklich die neue Fassung" \
        || bad "1b Lauf $LAUF: Endinhalt weicht ab: $AUS1B"
done

echo
echo "=== 2. shell/wb-instructions: write_generated() schreibt unteilbar ============"
echo "    (besonders wichtig, siehe Kopfkommentar: ein halber Rollen-Prompt ist"
echo "    syntaktisch gueltiger Text -- geprueft wird Byte-Gleichheit, nicht Syntax)"

cat > "$SPIEL/alt_instructions.py" <<'PY'
# Die VORHERIGE Fassung von write_generated()s Schreibschritt: open() direkt
# aufs Ziel, kein modus, kein Umweg.
import time


def lauf(ziel, neu_inhalt):
    haeppchen = 24
    with open(ziel, "w", encoding="utf-8") as f:
        for i in range(0, len(neu_inhalt), haeppchen):
            f.write(neu_inhalt[i:i + haeppchen])
            f.flush()
            time.sleep(0.01)
PY

cat > "$SPIEL/neu_instructions.py" <<PY
import sys
import time

sys.path.insert(0, "$REPO")
import atomar_schreiben

_orig_open = atomar_schreiben.open if hasattr(atomar_schreiben, "open") else open


def _langsames_open(pfad, *a, **kw):
    f = _orig_open(pfad, *a, **kw)
    modus = a[0] if a else kw.get("mode", "r")
    if "w" in modus:
        echt_write = f.write

        def langsames_write(s):
            for i in range(0, len(s), 24):
                echt_write(s[i:i + 24])
                f.flush()
                time.sleep(0.01)
            return len(s)

        f.write = langsames_write
    return f


atomar_schreiben.open = _langsames_open


def lauf(ziel, neu_inhalt):
    # Wie write_generated() es wirklich aufruft: modus=0o644 (siehe dort,
    # Begruendung -- dieselben Rechte, die ein gewoehnliches open(path,'w')
    # unter dem hier ueblichen umask ohnehin ergeben haette).
    atomar_schreiben.schreiben(ziel, neu_inhalt, modus=0o644)
PY

echo
echo "-- 2a: ROT gegen die alte Fassung --"
AUS2A="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/alt_instructions.py" "$SPIEL/ziel2a.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
if printf '%s' "$AUS2A" | grep -q '^KORRUPT_GESEHEN=True'; then
    ok "2a: die alte Schreibweise von write_generated() zeigt eine weder-alt-noch-neue Fassung"
else
    bad "2a: die alte Fassung haette korrupt sein muessen: $AUS2A"
fi

echo
echo "-- 2b: GRUEN gegen die AKTUELLE Fassung, dreimal --"
for LAUF in 1 2 3; do
    AUS2B="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/neu_instructions.py" "$SPIEL/ziel2b-$LAUF.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
    if printf '%s' "$AUS2B" | grep -q '^KORRUPT_GESEHEN=False'; then
        ok "2b Lauf $LAUF: nie eine weder-alt-noch-neue Fassung sichtbar ($(printf '%s' "$AUS2B" | sed -n 's/^ABTASTUNGEN=//p') Abtastungen)"
    else
        bad "2b Lauf $LAUF: eine korrupte Zwischenfassung war sichtbar: $AUS2B"
    fi
    printf '%s' "$AUS2B" | grep -q '^ENDINHALT_GLEICH_NEU=True' \
        && ok "2b Lauf $LAUF: am Ende steht wirklich die neue Fassung" \
        || bad "2b Lauf $LAUF: Endinhalt weicht ab: $AUS2B"
    # Die Rechte werden mit python3 gelesen, nicht mit stat: GNU 'stat -f' ist NICHT das
    # BSD 'stat -f'. Bei GNU heisst -f "Dateisystem-Status", das Format wird als zweiter
    # DATEINAME gelesen, und der Aufruf endet mit Exit 0 -- der '||'-Zweig greift also nie,
    # und verglichen wird Muell. Gemessen am 2026-08-21 auf Linux: die Zusage war dort rot,
    # obwohl die Datei die verlangten 0644 trug.
    RECHTE2B="$(python3 -c 'import os,stat,sys; print("%04o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$SPIEL/ziel2b-$LAUF.txt" 2>/dev/null)"
    if [ -e "$SPIEL/ziel2b-$LAUF.txt" ] && [ "$RECHTE2B" = "0644" ]; then
        ok "2b Lauf $LAUF: die Rechte stehen auf 0644, wie es ein gewoehnliches open(path,'w') ergeben haette"
    else
        bad "2b Lauf $LAUF: die Rechte weichen von 0644 ab (gemessen: ${RECHTE2B:-nichts})"
    fi
done

echo
echo "=== 3. shell/mcp-shared: cmd_apply() schreibt claude.json unteilbar ==========="
echo "    (dieselbe sys.path-Einspeisung wie im echten Skript, siehe SKRIPT_VERZ dort)"

cat > "$SPIEL/alt_mcp.py" <<'PY'
# Die VORHERIGE Fassung: pathlib.Path.write_text() direkt aufs Ziel.
import pathlib
import time


def lauf(ziel, neu_inhalt):
    p = pathlib.Path(ziel)
    haeppchen = 24
    with open(p, "w", encoding="utf-8") as f:
        for i in range(0, len(neu_inhalt), haeppchen):
            f.write(neu_inhalt[i:i + haeppchen])
            f.flush()
            time.sleep(0.01)
PY

cat > "$SPIEL/neu_mcp.py" <<PY
# Dieselbe Einspeisung wie im echten mcp-shared: sys.path.insert(0, SKRIPT_VERZ),
# dann 'import atomar_schreiben' -- hier durch die Konstante ersetzt, im echten
# Skript kommt sie aus \$SKRIPT_VERZ (siehe Kopf von shell/mcp-shared).
import sys
import time

sys.path.insert(0, "$REPO")
import atomar_schreiben

_orig_open = atomar_schreiben.open if hasattr(atomar_schreiben, "open") else open


def _langsames_open(pfad, *a, **kw):
    f = _orig_open(pfad, *a, **kw)
    modus = a[0] if a else kw.get("mode", "r")
    if "w" in modus:
        echt_write = f.write

        def langsames_write(s):
            for i in range(0, len(s), 24):
                echt_write(s[i:i + 24])
                f.flush()
                time.sleep(0.01)
            return len(s)

        f.write = langsames_write
    return f


atomar_schreiben.open = _langsames_open


def lauf(ziel, neu_inhalt):
    # Wie cmd_apply() es wirklich aufruft: atomar_schreiben.schreiben(cfg, ..., modus=0o644)
    atomar_schreiben.schreiben(ziel, neu_inhalt, modus=0o644)
PY

echo
echo "-- 3a: ROT gegen die alte Fassung --"
AUS3A="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/alt_mcp.py" "$SPIEL/ziel3a.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
if printf '%s' "$AUS3A" | grep -q '^KORRUPT_GESEHEN=True'; then
    ok "3a: die alte write_text()-Schreibweise zeigt eine weder-alt-noch-neue Fassung"
else
    bad "3a: die alte Fassung haette korrupt sein muessen: $AUS3A"
fi

echo
echo "-- 3b: GRUEN gegen die AKTUELLE Fassung, dreimal --"
for LAUF in 1 2 3; do
    AUS3B="$(HOME="$SPIEL" python3 "$SPIEL/wettlauf.py" "$SPIEL/neu_mcp.py" "$SPIEL/ziel3b-$LAUF.txt" "$SPIEL/alt.txt" "$SPIEL/neu.txt" 2>&1)"
    if printf '%s' "$AUS3B" | grep -q '^KORRUPT_GESEHEN=False'; then
        ok "3b Lauf $LAUF: nie eine weder-alt-noch-neue Fassung sichtbar ($(printf '%s' "$AUS3B" | sed -n 's/^ABTASTUNGEN=//p') Abtastungen)"
    else
        bad "3b Lauf $LAUF: eine korrupte Zwischenfassung war sichtbar: $AUS3B"
    fi
    printf '%s' "$AUS3B" | grep -q '^ENDINHALT_GLEICH_NEU=True' \
        && ok "3b Lauf $LAUF: am Ende steht wirklich die neue Fassung" \
        || bad "3b Lauf $LAUF: Endinhalt weicht ab: $AUS3B"
done

echo
echo "=== 4. Selbstpruefung + echte Maschine unberuehrt =============================="
# Jeder 'ziel*'-Pfad in diesem Lauf liegt unter $SPIEL (siehe die Aufrufe
# oben) -- diese Zusage steht schon in der Konstruktion, hier nur ausdruecklich
# nachgesehen. $HOME meint ab hier wieder das ECHTE Zuhause dieser Shell: die
# einzelnen Wettlauf-Aufrufe oben haben HOME nur fuer sich selbst (per
# Praefix) auf $SPIEL umgelenkt, dieser Prozess hier nie.
if find "$SPIEL" -maxdepth 1 -name 'ziel*' | grep -q .; then
    ok "4: die Zieldateien dieses Laufs liegen tatsaechlich unter dem eigenen Testverzeichnis"
else
    bad "4: keine Zieldateien unter dem Testverzeichnis gefunden -- die Konstruktion selbst ist kaputt"
fi
if find "$HOME" -maxdepth 1 -name '*.atomar-tmp-*' 2>/dev/null | grep -q .; then
    bad "4: eine Nebendatei liegt unter dem echten \$HOME"
else
    ok "4: keine Nebendatei unter dem echten \$HOME entstanden"
fi
if find "$HOME/.local/trash-snapshots" -maxdepth 1 -newer "$SPIEL" 2>/dev/null | grep -q .; then
    bad "4: ein Schnappschuss dieses Laufs liegt unter dem echten trash-snapshots"
else
    ok "4: kein neuer Schnappschuss unter dem echten ~/.local/trash-snapshots"
fi
if [ ! -f "$HOME/.claude.json" ] || [ "$(find "$HOME/.claude.json" -newer "$SPIEL" 2>/dev/null)" = "" ]; then
    ok "4: das echte ~/.claude.json wurde nicht veraendert"
else
    bad "4: das echte ~/.claude.json wurde waehrend dieses Laufs veraendert"
fi

echo
echo "================================================================"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
