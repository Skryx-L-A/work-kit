#!/usr/bin/env bash
# test-kontext-messungen.sh -- wb-kontext gegen dokumentierte Messungen, nicht
# gegen eine geratene Konstante.
#
# ANLASS (19.08.2026 abends, eigene des Nutzers Worte: "das darf nicht
# passieren"): der bisherige dichte Boden (KV_DICHTE_BODEN = 1,05 MiB/Token,
# pauschal fuer JEDES unbekannte dichte Modell) und eine falsch platzierte
# Denk-Faktor-Multiplikation liessen `wb-kontext stufen lmalpha-9b` fuer 32k
# einen Bedarf von 82,5 GiB ausweisen -- obwohl lmalpha:9b-256k auf dieser
# Maschine nachweislich mit 262144 Token bei 100% GPU, kein Spill lief
# (gemessen 2026-08-15, regeln/lokale-modelle.md). Der Fehler war nicht "die
# Zahl war falsch", sondern "eine Zahl, die einer bekannten Messung
# widerspricht, ist unbemerkt in den Betrieb gegangen". Dieser Test haelt die
# dokumentierten Messungen als Pruefpunkte fest, damit ein kuenftiger
# Regressionsfehler dieser Klasse SOFORT auffaellt.
#
# NICHT HERMETISCH, ABSICHTLICH: die Pruefpunkte sind die real auf DIESER
# Maschine installierten Modelle, ueber die tatsaechlich gemessen wurde
# (lmalpha:9b, lmalpha:35b -- Ollama; lmgamma-27b-mlx-4bit -- MLX-Verzeichnis
# unter ~/AI/mlx-models). Ein Fixture mit erfundenen Architekturwerten wuerde
# nur wb-kontexts eigene Rechnung gegen sich selbst pruefen, nicht gegen die
# Wirklichkeit, um die es hier geht. Fehlt eines der Modelle (andere
# Maschine, aufgeraeumt), wird der jeweilige Block uebersprungen (SKIP), statt
# falsch-rot zu werden -- dieselbe Haltung wie test-check-resources-ollama.sh.
#
# Geprueft wird bewusst NICHT das "passt"-Feld (das haengt am gerade freien
# Speicher dieses Moments und ist damit von Lauf zu Lauf verschieden), sondern
# "bedarfGib" bzw. der KV-Anteil daraus -- beides eine reine Funktion aus
# Architektur und Gewichten, unabhaengig von der Systemlast beim Testlauf.
set -uo pipefail

WK="${WB_KONTEXT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wb-kontext}"
WBB="${WB_BELEGUNG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wb-belegung}"
echo "Geprueft: $WK"

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
uebersprungen() { skip=$((skip+1)); printf '  SKIP  %s\n' "$1"; }

# Der GPU-adressierbare Rechner, auf dem gemessen wurde (regeln/lokale-modelle.md:
# "HARD ceiling: GPU-addressable ~43 GB of 48"). 48, nicht 43: die 43-GB-Grenze
# gilt fuer die Quant-WAHL (Modell passt komplett auf die GPU), nicht als
# rechnerischer Speicherdeckel dieses Tests -- "in 48 GB passt" ist des Nutzers
# eigene Formulierung im Auftrag.
DECKE_GIB=48

stufe_wert() {   # <json> <stufe-token> <feld>  -> Wert oder "FEHLT"
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
s = next((x for x in d['stufen'] if x['tokens'] == int(sys.argv[2])), None)
print(s[sys.argv[3]] if s is not None else 'FEHLT')
" "$1" "$2" "$3" 2>/dev/null || echo FEHLT
}

unter_decke() { awk -v w="$1" -v d="$2" 'BEGIN{exit !(w+0 < d+0)}'; }
in_band()     { awk -v w="$1" -v lo="$2" -v hi="$3" 'BEGIN{exit !(w+0 >= lo+0 && w+0 <= hi+0)}'; }

# Stdout (das JSON) und Stderr (HINWEIS-Zeilen wie "keine Stufe passt...")
# GETRENNT einfangen -- ein simples '2>&1' haette die HINWEIS-Zeile vor das
# JSON gemischt und jedes json.loads() zuverlaessig zum Scheitern gebracht
# (genau so wurde dieser Fehler beim ersten Lauf dieses Tests selbst
# gefunden: "Stufe steht nicht in der Liste", obwohl sie klar sichtbar in der
# Ausgabe stand).
wk_stufen() {   # <modell> -> setzt WK_JSON, WK_STDERR, WK_RC
  local errdatei
  errdatei="$(mktemp)"
  WK_JSON="$("$WK" stufen "$1" --parallel 1 --denken low --json 2>"$errdatei")"
  WK_RC=$?
  WK_STDERR="$(cat "$errdatei")"; rm -f "$errdatei"
}

echo "== 1  lmalpha:9b bei 256k Token -- lief nachweislich, Bedarf muss unter ${DECKE_GIB} GiB bleiben =="
if ! command -v ollama >/dev/null 2>&1 || ! ollama show lmalpha:9b >/dev/null 2>&1; then
  uebersprungen "lmalpha:9b @ 256k (ollama oder das Modell fehlt auf dieser Maschine)"
else
  wk_stufen lmalpha:9b
  if [ "$WK_RC" -ne 0 ]; then
    bad "lmalpha:9b @ 256k: wb-kontext brach ab" "$WK_STDERR"
  else
    bedarf="$(stufe_wert "$WK_JSON" 262144 bedarfGib)"
    if [ "$bedarf" = FEHLT ]; then
      bad "lmalpha:9b @ 256k: Stufe 262144 steht nicht in der Liste" "$WK_JSON"
    elif unter_decke "$bedarf" "$DECKE_GIB"; then
      ok "lmalpha:9b @ 262144 Token: Bedarf ${bedarf} GiB, passt unter ${DECKE_GIB} GiB -- deckt sich mit der echten Messung"
    else
      bad "lmalpha:9b @ 262144 Token: Bedarf ${bedarf} GiB -- ueberschreitet ${DECKE_GIB} GiB, widerspricht der echten Messung (lief dort wirklich)"
    fi
  fi
fi

echo "== 2  lmalpha:35b bei 256k Token -- dieselbe Messreihe, Bedarf muss unter ${DECKE_GIB} GiB bleiben =="
if ! command -v ollama >/dev/null 2>&1 || ! ollama show lmalpha:35b >/dev/null 2>&1; then
  uebersprungen "lmalpha:35b @ 256k (ollama oder das Modell fehlt auf dieser Maschine)"
else
  wk_stufen lmalpha:35b
  if [ "$WK_RC" -ne 0 ]; then
    bad "lmalpha:35b @ 256k: wb-kontext brach ab" "$WK_STDERR"
  else
    bedarf="$(stufe_wert "$WK_JSON" 262144 bedarfGib)"
    if [ "$bedarf" = FEHLT ]; then
      bad "lmalpha:35b @ 256k: Stufe 262144 steht nicht in der Liste" "$WK_JSON"
    elif unter_decke "$bedarf" "$DECKE_GIB"; then
      ok "lmalpha:35b @ 262144 Token: Bedarf ${bedarf} GiB, passt unter ${DECKE_GIB} GiB -- deckt sich mit der echten Messung"
    else
      bad "lmalpha:35b @ 262144 Token: Bedarf ${bedarf} GiB -- ueberschreitet ${DECKE_GIB} GiB, widerspricht der echten Messung (lief dort wirklich)"
    fi
  fi
fi

echo "== 3  lmgamma-27b bei 128k, 1 Sequenz -- KV-Anteil muss rund 8 GiB sein, nicht das Vielfache =="
QDIR="$HOME/AI/mlx-models/lmgamma-27b-mlx-4bit"
if [ ! -d "$QDIR" ]; then
  uebersprungen "lmgamma-27b ('$QDIR' nicht vorhanden auf dieser Maschine)"
else
  wk_stufen "$QDIR"
  if [ "$WK_RC" -ne 0 ]; then
    bad "lmgamma-27b @ 128k: wb-kontext brach ab" "$WK_STDERR"
  else
    kv_je_token="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d['kvMibProToken'])
" "$WK_JSON" 2>/dev/null || echo FEHLT)"
    if [ "$kv_je_token" = FEHLT ]; then
      bad "lmgamma-27b @ 128k: kvMibProToken fehlt in der Ausgabe" "$WK_JSON"
    else
      kv_gib="$(awk -v k="$kv_je_token" 'BEGIN{printf "%.4f", k*131072/1024}')"
      if in_band "$kv_gib" 7 9; then
        ok "lmgamma-27b @ 131072 Token, 1 Sequenz: KV-Anteil ${kv_gib} GiB, rund 8 GiB wie gemessen (0,0625 MiB/Token aus kv-bedarf.json)"
      else
        bad "lmgamma-27b @ 131072 Token: KV-Anteil ${kv_gib} GiB -- weit weg von den gemessenen ~8 GiB (Denk-Faktor faelschlich in die KV-Rechnung multipliziert?)"
      fi
    fi
  fi
fi

echo "== 4  lmgamma-27b bei 32k -- 'plaetze' darf dem Menschen nie mehr versprechen, als der echte Waechter (wb-belegung) durchlaesst =="
# Pruefer-Befund N7: "wb-kontext meldet plaetze 1, wb-belegung darf antwortet
# fuer dieselbe eine Sequenz NEIN" -- eine Zahl, die mehr Plaetze verspricht,
# als der Waechter durchlaesst, ist eine Falle. Geprueft wird direkt gegen
# den Waechter selbst (die Quelle der Wahrheit), nicht gegen eine zweite,
# eigene Formel -- "eine Quelle, nicht zwei".
if [ ! -d "$QDIR" ] || [ ! -x "$WBB" ]; then
  uebersprungen "lmgamma-27b plaetze-Gegenprobe ('$QDIR' oder wb-belegung fehlt)"
else
  wk_stufen "$QDIR"
  if [ "$WK_RC" -ne 0 ]; then
    bad "lmgamma-27b plaetze: wb-kontext brach ab" "$WK_STDERR"
  else
    lies_stufe32k="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
s = next((x for x in d['stufen'] if x['tokens'] == 32768), None)
# Nachtrag zweite Runde: die Entlastung 'schon geladen' steht seit dem
# Gegenleser-Befund Punkt 4 NUR NOCH in der bedarfQuelle DIESER Stufe, nicht
# mehr in der obersten gewichteQuelle (die zeigt jetzt immer den realen,
# stufenunabhaengigen Wert) -- hier also gegen s['bedarfQuelle'] pruefen.
schon_geladen = bool(s) and 'schon geladen' in (s.get('bedarfQuelle') or '')
print('%s %s %s' % (s['plaetze'], d['gewichteGb'], 'ja' if schon_geladen else 'nein') if s else 'FEHLT FEHLT FEHLT')
" "$WK_JSON" 2>/dev/null || echo "FEHLT FEHLT FEHLT")"
    plaetze="$(printf '%s' "$lies_stufe32k" | cut -d' ' -f1)"
    gewichte="$(printf '%s' "$lies_stufe32k" | cut -d' ' -f2)"
    schon_geladen="$(printf '%s' "$lies_stufe32k" | cut -d' ' -f3)"
    if [ "$plaetze" = FEHLT ]; then
      bad "lmgamma-27b plaetze: Stufe 32768 oder gewichteGb fehlt" "$WK_JSON"
    elif [ "$plaetze" -eq 0 ]; then
      ok "lmgamma-27b @ 32k: plaetze=0 -- nichts zu ueberpruefen, aber auch nichts versprochen"
    else
      # Laeuft der Server schon MIT diesem Modell (Nachtrag 2026-09-08, siehe
      # bereits_geladener_server() in wb-kontext), meldet wb-kontext gewichteGb
      # nahe 0 -- eine unabhaengige Gegenprobe muss dann genau wie wb-kontexts
      # eigenes plaetze_wirklich() rechnen (0,001 GiB Boden, --ohne-sockel: der
      # Sockel ist beim Serverstart schon bezahlt), sonst lehnt wb-belegung die
      # Anfrage schon an der Eingabepruefung ab ("--gewichte-gb muss groesser
      # als 0,0 sein") -- kein echtes Nein, nur eine falsch nachgebaute Anfrage.
      GEGENPROBE_ARGS=(--gewichte-gb "$gewichte")
      if [ "$schon_geladen" = ja ]; then
        GEGENPROBE_ARGS=(--gewichte-gb 0.001 --ohne-sockel)
      fi
      darf_json="$("$WBB" darf "${GEGENPROBE_ARGS[@]}" --modell lmgamma-27b-mlx-4bit \
                    --parallel "$plaetze" --kontext 32768 --abtastungen 1 --abstand 0 --json 2>/dev/null)"
      ja="$(printf '%s' "$darf_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ja'))" 2>/dev/null)"
      if [ "$ja" = True ]; then
        ok "lmgamma-27b @ 32k: plaetze=${plaetze} -- wb-belegung sagt fuer genau so viele Sequenzen JA"
      else
        bad "lmgamma-27b @ 32k: plaetze=${plaetze} verspricht mehr, als wb-belegung erlaubt (darf -> ${ja:-FEHLER})" "$darf_json"
      fi
    fi
  fi
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL, $skip SKIP"
[ "$fail" -eq 0 ]
