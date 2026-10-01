#!/bin/bash
# test-wb-budget-inkrementell.sh -- der Zwischenspeicher des Standardberichts von `wb-budget`.
#
# WARUM (Auftrag 2026-08-16): der Bericht las bei JEDEM Aufruf alle Transkripte der letzten acht
# Tage neu -- auf dieser Maschine 233 Dateien und 1,8 GB, gemessen 11,22 / 11,34 / 11,50 s. Jetzt
# merkt er sich je Datei Byte-Versatz und Zwischensumme (~/.local/state/wb-budget/usage-cache.json)
# und liest nur das Neue nach (gemessen 1,51 s kalt, 0,25-0,28 s warm).
#
# EIN ZWISCHENSPEICHER IST NUR SO GUT WIE SEINE VERWERFUNG. Was diese Suite haelt, sind genau die
# Stellen, an denen so etwas leise falsch wird:
#
#   1  Kalt und warm ergeben DIESELBEN Zahlen -- sonst haengt die Auskunft davon ab, wie oft man
#      schon gefragt hat.
#   2  Angehaengte Nachrichten kommen dazu, und zwar genau einmal (kein doppeltes Zaehlen der
#      schon gelesenen Zeilen).
#   3  Eine GESCHRUMPFTE Datei (neu geschrieben, gedreht) wird von vorn gelesen, nicht ab einem
#      Versatz, der in eine andere Datei zeigt.
#   4  Bei gleicher Groesse UND gleicher mtime wird die Datei NICHT wieder geoeffnet -- das ist
#      der schnelle Fall, und er wird hier bewiesen, statt geglaubt: der Inhalt wird heimlich
#      ausgetauscht (gleiche Laenge, gleiche mtime), und der Bericht muss die ALTE Zahl zeigen.
#   5  Eine angefangene letzte Zeile ohne Zeilenumbruch zaehlt nicht mit und blockiert nicht --
#      beim naechsten Lauf, vollstaendig geschrieben, ist sie da.
#   6  Ein kaputter Zwischenspeicher ist ein kalter Start, kein Fehler.
#   7  Subagenten-Transkripte (<projekt>/<sitzung>/subagents/*.jsonl) zaehlen mit -- im Bericht
#      wie in `--json`, mit derselben Zahl.
#
# ISOLATION: eigenes HOME in einem mktemp-Verzeichnis, eigene Transkripte, kein Netz, keine echte
# Sitzung. Die Zeitstempel der Fixturen werden zur Laufzeit gesetzt (heute, UTC), damit die
# Fenster des Berichts sie sehen.
#
# Run: shell/tests/test-wb-budget-inkrementell.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
TOOL="$REPO/wb-budget"
echo "Geprueft: $TOOL (Standardbericht, inkrementell)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

[ -x "$TOOL" ] || ueberspringen "shell/wb-budget fehlt oder ist nicht ausfuehrbar"
command -v /usr/bin/python3 >/dev/null 2>&1 || ueberspringen "/usr/bin/python3 fehlt"

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-budget-inkrementell.XXXXXX")" && pwd)"
trap 'rm -rf "$TESTHOME"' EXIT
H="$TESTHOME/home"
PROJ="$H/.claude/projects/-Users-probe-arbeit"
CACHE="$H/.local/state/wb-budget/usage-cache.json"
mkdir -p "$PROJ"

# --- Fixturen ---------------------------------------------------------------------------------
# Eine Zeile = eine assistant-Nachricht mit usage. Der Zeitstempel liegt bewusst 30 Minuten
# zurueck: damit faellt sie in ALLE vier Sichten des Berichts (5h, 7d, Trend, heute) -- AUCH
# kurz nach Mitternacht UTC (gemessen 2026-08-22, 00:18 UTC): ein fester Versatz von 1800 s
# springt dort ueber die Tagesgrenze zurueck in den VORTAG, "bisher heute" zaehlt die Zeile
# dann nicht mit. Der Versatz wird deshalb auf die seit Mitternacht vergangene Zeit gedeckelt.
zeile() { # zeile <input> <output> <cache_write> <cache_read>
  /usr/bin/python3 -c '
import json, sys, time
sekunden_seit_mitternacht = time.time() % 86400
versatz = min(1800, max(1, sekunden_seit_mitternacht - 1))
ts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - versatz))
i, o, cw, cr = (int(x) for x in sys.argv[1:5])
print(json.dumps({"type": "assistant", "timestamp": ts,
                  "message": {"model": "claude-opus-5",
                              "usage": {"input_tokens": i, "output_tokens": o,
                                        "cache_creation_input_tokens": cw,
                                        "cache_read_input_tokens": cr}}}))
' "$1" "$2" "$3" "$4"
}

heute() { # heute <bericht> -- die Tokenzahl des laufenden UTC-Tages
  printf '%s' "$1" | sed -n 's/^  bisher heute: \([0-9]*\) Tokens.*/\1/p'
}

bericht() { HOME="$H" "$TOOL" 2>/dev/null; }

zeile 100 200 300 9000 >  "$PROJ/sitzung-a.jsonl"
zeile 1 2 3 4          >> "$PROJ/sitzung-a.jsonl"

# --- 1. Kalt und warm sind dieselbe Auskunft ---------------------------------------------------
B1="$(bericht)"
H1="$(heute "$B1")"
[ -s "$CACHE" ] && ok "1: der Zwischenspeicher entsteht beim ersten Lauf ($CACHE)" \
                || bad "1: keine Cache-Datei nach dem ersten Lauf"
B2="$(bericht)"
H2="$(heute "$B2")"
[ "$H1" = "606" ] && ok "1: kalt gerechnet: 100+200+300 + 1+2+3 = 606 Tokens ohne cache_read" \
                  || bad "1: erwartet 606, bekommen '$H1'"
[ "$H1" = "$H2" ] && ok "1: warm dieselbe Zahl ($H2) -- der Zwischenspeicher aendert die Auskunft nicht" \
                  || bad "1: kalt $H1, warm $H2"

# --- 2. Angehaengt wird genau einmal gezaehlt --------------------------------------------------
zeile 10 20 30 40 >> "$PROJ/sitzung-a.jsonl"
H3="$(heute "$(bericht)")"
[ "$H3" = "666" ] && ok "2: eine angehaengte Nachricht kommt dazu (606 + 60 = 666), nichts doppelt" \
                  || bad "2: erwartet 666, bekommen '$H3'"

# --- 3. Geschrumpfte Datei wird von vorn gelesen -----------------------------------------------
# Neu geschrieben mit EINER Zeile, kuerzer als der gemerkte Versatz.
zeile 7 7 7 7 > "$PROJ/sitzung-a.jsonl"
H4="$(heute "$(bericht)")"
[ "$H4" = "21" ] && ok "3: eine geschrumpfte Datei wird von vorn gelesen (21), nicht ab dem alten Versatz" \
                 || bad "3: erwartet 21, bekommen '$H4'"

# --- 4. Gleiche Groesse UND gleiche mtime heisst: gar nicht erst oeffnen -----------------------
# Der Inhalt wird heimlich ausgetauscht -- gleiche Laenge, danach die alte mtime zurueckgesetzt.
# Zeigte der Bericht jetzt die NEUE Zahl, haette er die Datei entgegen der Zusage neu gelesen.
ALT_MTIME="$(/usr/bin/python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime)' "$PROJ/sitzung-a.jsonl")"
LAENGE="$(wc -c < "$PROJ/sitzung-a.jsonl" | tr -d ' ')"
zeile 8 8 8 8 > "$TESTHOME/anders.jsonl"
NEU_LAENGE="$(wc -c < "$TESTHOME/anders.jsonl" | tr -d ' ')"
if [ "$LAENGE" = "$NEU_LAENGE" ]; then
  cp "$TESTHOME/anders.jsonl" "$PROJ/sitzung-a.jsonl"
  /usr/bin/python3 -c 'import os,sys; os.utime(sys.argv[1], (float(sys.argv[2]), float(sys.argv[2])))' \
    "$PROJ/sitzung-a.jsonl" "$ALT_MTIME"
  H5="$(heute "$(bericht)")"
  [ "$H5" = "21" ] && ok "4: gleiche Groesse und gleiche mtime -> nicht neu gelesen (weiter 21)" \
                   || bad "4: erwartet 21 (aus dem Zwischenspeicher), bekommen '$H5'"
else
  bad "4: die Ersatzzeile hat eine andere Laenge ($LAENGE gegen $NEU_LAENGE) -- Fall nicht pruefbar"
fi

# --- 5. Angefangene letzte Zeile ---------------------------------------------------------------
# Ohne Zeilenumbruch geschrieben: sie darf nicht mitzaehlen, und der Versatz darf nicht ueber sie
# hinweggehen -- sonst faellt genau die Nachricht heraus, die gerade entsteht.
#
# Der Zwischenspeicher wird hier weggeworfen, und damit gilt ab jetzt, was WIRKLICH in
# sitzung-a.jsonl steht: die heimlich untergeschobene Zeile aus Fall 4 mit 8+8+8 = 24 Tokens,
# nicht mehr die gemerkten 21. Genau dieser Sprung ist der Beweis von Fall 4 -- vorher stand die
# Zahl aus dem Gedaechtnis da, jetzt die aus der Datei.
rm -f "$CACHE"
zeile 100 100 100 100 > "$PROJ/sitzung-b.jsonl"
printf '%s' "$(zeile 5 5 5 5)" >> "$PROJ/sitzung-b.jsonl"   # ohne abschliessendes \n
H6="$(heute "$(bericht)")"
[ "$H6" = "324" ] && ok "5: die angefangene Zeile zaehlt nicht mit (24 + 300 = 324)" \
                  || bad "5: erwartet 324, bekommen '$H6'"
printf '\n' >> "$PROJ/sitzung-b.jsonl"                       # jetzt vollstaendig
H7="$(heute "$(bericht)")"
[ "$H7" = "339" ] && ok "5: vollstaendig geschrieben kommt sie im naechsten Lauf dazu (324 + 15 = 339)" \
                  || bad "5: erwartet 339, bekommen '$H7'"

# --- 6. Kaputter Zwischenspeicher = kalter Start ------------------------------------------------
printf 'kein json, sondern Muell\n' > "$CACHE"
H8="$(heute "$(bericht)")"
[ "$H8" = "339" ] && ok "6: ein kaputter Zwischenspeicher ist ein kalter Start, kein Fehler (339)" \
                  || bad "6: erwartet 339, bekommen '$H8'"

# --- 7. Subagenten-Transkripte zaehlen mit, im Bericht wie in --json ---------------------------
mkdir -p "$PROJ/2c297d5a-6b7c-4fd1-a6ea-cf18b16d5da9/subagents"
zeile 1000 2000 3000 4000 > "$PROJ/2c297d5a-6b7c-4fd1-a6ea-cf18b16d5da9/subagents/agent-abc.jsonl"
H9="$(heute "$(bericht)")"
[ "$H9" = "6339" ] && ok "7: eine Subagenten-Datei zaehlt im Bericht mit (339 + 6000 = 6339)" \
                   || bad "7: erwartet 6339, bekommen '$H9'"
JSON_HEUTE="$(HOME="$H" "$TOOL" --json --tage 1 --harness claude --ohne-kontingent 2>/dev/null \
  | /usr/bin/python3 -c '
import json, sys, time
d = json.load(sys.stdin)
tag = time.strftime("%Y-%m-%d", time.gmtime())
print(sum(z["ohne_cache_read"] for z in d["je_tag"] if z["tag"] == tag))
')"
[ "$JSON_HEUTE" = "$H9" ] \
  && ok "7: --json nennt dieselbe Tageszahl wie der Bericht ($JSON_HEUTE) -- eine Frage, eine Antwort" \
  || bad "7: Bericht $H9, --json $JSON_HEUTE"

echo
echo "  bestanden: $PASS, fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ]
