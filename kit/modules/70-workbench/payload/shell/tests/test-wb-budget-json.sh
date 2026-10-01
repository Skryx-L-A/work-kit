#!/bin/bash
# test-wb-budget-json.sh — `wb-budget --json`: der Limitstand als EIN JSON-Objekt mit
# Ausgangscode je Lage, und `--json --alle-maschinen` ueber einen ssh-Schirm.
#
# Anlass (2026-09-10, docs/AGENTS-PLAN.md, Anhang "Traeger"): Spawn-Werkzeuge und der
# Traeger brauchen den Limitstand maschinenlesbar. Bis dahin lieferte nur --limit Text
# mit Exit 0, und in einer nicht-interaktiven ssh-Sitzung fehlt ~/.local/bin im PATH --
# deshalb muss der Fernaufruf den PATH selbst setzen, und genau das prueft diese Suite
# am Wortlaut des abgeschickten Befehls.
#
# Die althergebrachte doppelte Bedeutung von --json bleibt bestehen: MIT Berichtsfilter
# (--tage, --von, ...) gilt weiterhin der volle Verbrauchsbericht (Suiten
# test-wb-budget-quellen/-echte-quellen/-inkrementell und die App rufen ihn so auf),
# OHNE Filter ist --json der Limitstand. Beide Wege werden hier gegeneinander geprueft.
#
# ISOLATION: eigenes HOME unter mktemp, eigene limits-latest.json und settings.json,
# ssh als Schirm ueber WB_BUDGET_SSH, kein Netz, kein tmux, kein Prozess ausser python3
# und dem Schirm. Der Testhaken WB_LIMIT_JETZT (erklaert in wb-budget, bei --limit)
# steuert das "jetzt" der Tageslinien-Rechnung; im Betrieb ist er nie gesetzt. Das
# Fenster entspricht dem von test-limit-tagesbudget.sh: Reset Montag 2026-08-24 14:00
# lokal, Start also Montag 2026-08-17 14:00; der Pruefzeitpunkt ist Samstag, Tag 6,
# erlaubt also 600/7 = 85,7143.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WB="$REPO_ROOT/shell/wb-budget"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
zusage() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKEHOME="$TMP/home"
QUELLE="$FAKEHOME/.claude/workbench/limits-latest.json"
SETTINGS="$FAKEHOME/.claude/workbench/settings.json"
mkdir -p "$(dirname "$QUELLE")"

RESET="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,8,24,14,0).timestamp()))')"
JETZT="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,8,22,20,0).timestamp()))')"
TS_LOKAL="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,8,21,23,53,2,tzinfo=datetime.timezone.utc).timestamp()))')"
TS_JUNG="$(python3 -c 'import datetime; print(int(datetime.datetime(2026,8,22,12,0,tzinfo=datetime.timezone.utc).timestamp()))')"
ERLAUBT="$(python3 -c 'print(round(min(100.0, 6*100/7), 4))')"   # Tag 6: 85.7143
HOSTNAME="$(python3 -c 'import socket; print(socket.gethostname())')"

# schreibe_quelle <seven_day_pct> <five_hour_pct> [reset_form: epoch|iso] [ts_epoch]
schreibe_quelle() {
  python3 - "$QUELLE" "$1" "$2" "${3:-epoch}" "${4:-$TS_LOKAL}" "$RESET" <<'PY'
import datetime, json, sys
pfad, sd, fh, form, ts, reset = (sys.argv[1], float(sys.argv[2]), float(sys.argv[3]),
                                 sys.argv[4], int(sys.argv[5]), int(sys.argv[6]))
if form == "iso":
    reset_wert = datetime.datetime.fromtimestamp(reset, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
else:
    reset_wert = str(reset)
d = {
    "ts": datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "session": "x",
    "five_hour_pct": fh,
    "seven_day_pct": sd,
    "five_hour_resets_at": reset_wert,
    "seven_day_resets_at": reset_wert,
}
json.dump(d, open(pfad, "w"))
PY
}

lauf() { # lauf [argumente...] -- stdout in $AUS, stderr in $TMP/laeufer-stderr
  HOME="$FAKEHOME" WB_LIMIT_JETZT="$JETZT" bash "$WB" --json "$@" 2>"$TMP/laeufer-stderr"
}

feld() { # feld <json> <ausdruck-ueber-d> -> Wert des Ausdrucks
  printf '%s' "$1" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1]))' "$2"
}

echo "== Form: genau ein JSON-Objekt, sonst nichts =="
schreibe_quelle 60 3
AUS="$(lauf)"; RC=$?
[ "$RC" = 0 ]; zusage $? "unter der Tageslinie endet --json mit Exit 0"
[ "$(printf '%s\n' "$AUS" | grep -c .)" = 1 ]; zusage $? "die Ausgabe ist GENAU eine Zeile (Objekt), sonst nichts"
[ ! -s "$TMP/laeufer-stderr" ]; zusage $? "auf stderr steht nichts"
python3 -c 'import json, sys; json.loads(sys.argv[1])' "$AUS" >/dev/null 2>&1
zusage $? "die Ausgabe ist gueltiges JSON"

echo "== Die Felder =="
[ "$(feld "$AUS" 'd["tageslimit_erreicht"]')" = "False" ]; zusage $? "60 % am Tag 6 ist NICHT am Tageslimit"
[ "$(feld "$AUS" 'd["fuenf_stunden_erreicht"]')" = "False" ]; zusage $? "3 % ist nicht am Fuenf-Stunden-Fenster"
[ "$(feld "$AUS" 'd["erlaubt_pct"]')" = "$ERLAUBT" ]; zusage $? "erlaubt_pct ist die Tageslinie ($ERLAUBT, Tag 6 wie bei --limit)"
[ "$(feld "$AUS" 'abs(d["luft"] - (d["erlaubt_pct"] - 60)) < 0.001')" = "True" ]; zusage $? "luft ist erlaubt minus verbraucht (25.7143)"
[ "$(feld "$AUS" 'abs(d["seven_day_resets_at_epoch"] - '"$RESET"') < 0.5')" = "True" ]; zusage $? "seven_day_resets_at_epoch ist die Epochensekunde des Resets"
[ "$(feld "$AUS" 'abs(d["five_hour_resets_at_epoch"] - '"$RESET"') < 0.5')" = "True" ]; zusage $? "five_hour_resets_at_epoch kommt daneben als Paar"
[ "$(feld "$AUS" 'd["quelle"]')" = "$QUELLE" ]; zusage $? "quelle nennt den Pfad der gelesenen Datei"
[ "$(feld "$AUS" 'd["maschine"]')" = "$HOSTNAME" ]; zusage $? "maschine ist der Hostname ($HOSTNAME)"
[ "$(feld "$AUS" 'd["ts"]')" = "2026-08-21T23:53:02Z" ]; zusage $? "ts ist der ISO-Zeitpunkt des Messwerts"
ERW_ALTER="$((JETZT - TS_LOKAL))"
[ "$(feld "$AUS" 'abs(d["alter_s"] - '"$ERW_ALTER"') < 0.5')" = "True" ]; zusage $? "alter_s sind die Sekunden seit ts ($ERW_ALTER s)"

echo "== ISO-Zeichenkette in der Quelle bleibt Wortlaut und bekommt ihr _epoch =="
schreibe_quelle 60 3 iso
AUS="$(lauf)"
[ "$(feld "$AUS" 'd["seven_day_resets_at"]')" = "2026-08-24T12:00:00Z" ] \
  && [ "$(feld "$AUS" 'abs(d["seven_day_resets_at_epoch"] - '"$RESET"') < 0.5')" = "True" ] \
  && zusage 0 "ISO bleibt Wortlaut, _epoch kommt daneben" \
  || bad "ISO-Normalisierung: $AUS"

echo "== Exit-Codes 1 und 2, Vorrang von 2 =="
schreibe_quelle 90 3
AUS="$(lauf)"; RC=$?
[ "$RC" = 1 ] && [ "$(feld "$AUS" 'd["tageslimit_erreicht"]')" = "True" ] \
  && zusage 0 "90 % verbraucht am Tag 6 (erlaubt 85.7143) endet mit Exit 1" \
  || bad "Tageslimit nicht Exit 1: rc=$RC, $AUS"
[ "$(feld "$AUS" 'd["luft"] < 0')" = "True" ]; zusage $? "am Tageslimit ist die Luft negativ"
schreibe_quelle 90 100
lauf >/dev/null; RC=$?
[ "$RC" = 2 ] && zusage $? "Fuenf-Stunden-Fenster hat Vorrang vor dem Tageslimit (Exit 2)" \
  || bad "Vorrang von 2 vor 1 verletzt"
schreibe_quelle 10 100
lauf >/dev/null; RC=$?
[ "$RC" = 2 ]; zusage $? "Fuenf-Stunden-Fenster allein reicht fuer Exit 2"

echo "== Exit 3: keine Quelle =="
rm -f "$QUELLE"
AUS="$(lauf)"; RC=$?
[ "$RC" = 3 ]; zusage $? "ohne Quelle endet --json mit Exit 3"
[ "$(feld "$AUS" 'sorted(d.keys())')" = "['fehler', 'quelle']" ]; zusage $? "das Fehlerobjekt traegt fehler und quelle"
printf 'muell {' > "$QUELLE"
lauf >/dev/null; RC=$?
[ "$RC" = 3 ]; zusage $? "eine unlesbare Quelle endet mit Exit 3"
printf '{"ts": "2026-08-21T23:53:02Z", "seven_day_pct": 60}\n' > "$QUELLE"
lauf >/dev/null; RC=$?
[ "$RC" = 3 ]; zusage $? "ein Stand ohne seven_day_resets_at ist unbrauchbar, keine Erfindung"

echo "== --alle-maschinen: Juengster Messwert gewinnt, Ausfaelle werden gemeldet =="
SSH_STUB="$TMP/ssh-schirm"
SSH_LOG="$TMP/ssh-aufrufe.log"
FERN_EINS="$TMP/maschine-eins.json"
: > "$SSH_LOG"
cat > "$SSH_STUB" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$SSH_LOG"
ziel="\$5"
case "\$ziel" in
  eins) cat "$FERN_EINS" ;;
  zwei) printf 'das ist kein json\n'; exit 7 ;;
  *) exit 9 ;;
esac
STUB
chmod +x "$SSH_STUB"
python3 - "$FERN_EINS" "$RESET" <<'PY'
import json, sys
d = {"ts": "2026-08-22T10:00:00Z", "session": "eins", "five_hour_pct": 0, "seven_day_pct": 5,
     "five_hour_resets_at": sys.argv[2], "seven_day_resets_at": sys.argv[2],
     "maschine": "eins-host", "quelle": "/fremd/limits-latest.json"}
json.dump(d, open(sys.argv[1], "w"))
PY
printf '%s\n' '{"agents": {"maschinen": [{"name": "eins", "ssh": "eins"}, {"name": "zwei", "ssh": "zwei"}]}}' > "$SETTINGS"

schreibe_quelle 60 3
AUS="$(WB_BUDGET_SSH="$SSH_STUB" lauf --alle-maschinen)"; RC=$?
[ "$RC" = 0 ]; zusage $? "--alle-maschinen endet mit dem Exit des juengsten Werts (0)"
[ "$(feld "$AUS" 'd["maschine"]')" = "eins-host" ]; zusage $? "der juengere Messwert der Fernmaschine gewinnt (ihr maschine-Feld)"
[ "$(feld "$AUS" 'd["seven_day_pct"]')" = "5.0" ]; zusage $? "der Siegerwert (5 %) ist im Objekt, nicht der lokale (60 %)"
[ "$(feld "$AUS" 'd["quelle"]')" = "/fremd/limits-latest.json" ]; zusage $? "die Quelle des Siegers steht im Objekt"
[ "$(feld "$AUS" 'd["maschinen_gelesen"]')" = "['eins']" ]; zusage $? "maschinen_gelesen nennt die erfolgreiche Maschine"
[ "$(feld "$AUS" '[f["name"] for f in d["maschinen_fehlgeschlagen"]]')" = "['zwei']" ]; zusage $? "die ausgefallene Maschine steht in maschinen_fehlgeschlagen"
[ "$(feld "$AUS" 'd["maschinen_fehlgeschlagen"][0]["grund"] != ""')" = "True" ]; zusage $? "der Ausfall traegt einen Grund"
[ "$(feld "$AUS" 'd["tageslimit_erreicht"]')" = "False" ]; zusage $? "die Tageslinien-Rechnung lief auf dem juengsten Wert"

grep -qF 'PATH=$HOME/.local/bin:$PATH wb-budget --json' "$SSH_LOG" \
  && ok "der Fernaufruf setzt den PATH, weil er in nicht-interaktiven Sitzungen fehlt" \
  || bad "ssh-Befehl ohne den gesetzten PATH: $(tail -1 "$SSH_LOG")"
grep -qF 'BatchMode=yes' "$SSH_LOG" && grep -qF 'ConnectTimeout=5' "$SSH_LOG" \
  && ok "der Fernaufruf kommt mit BatchMode=yes und ConnectTimeout=5" \
  || bad "ssh-Optionen fehlen: $(tail -1 "$SSH_LOG")"

echo "== --alle-maschinen: juengster Wert darf auch der lokale sein =="
schreibe_quelle 60 3 epoch "$TS_JUNG"   # lokal 12:00 UTC, fern 10:00 UTC
AUS="$(WB_BUDGET_SSH="$SSH_STUB" lauf --alle-maschinen)"; RC=$?
[ "$(feld "$AUS" 'd["maschine"]')" = "$HOSTNAME" ] && [ "$(feld "$AUS" 'd["seven_day_pct"]')" = "60.0" ] \
  && [ "$RC" = 0 ] && zusage $? "ist der lokale Wert juenger, gewinnt er (Exit des lokalen Stands)" \
  || bad "lokal-juenger-Fall: rc=$RC, $AUS"

echo "== --alle-maschinen: unlesbares LOCAL faellt nicht unter den Tisch =="
rm -f "$QUELLE"
AUS="$(WB_BUDGET_SSH="$SSH_STUB" lauf --alle-maschinen)"; RC=$?
[ "$RC" = 0 ] && [ "$(feld "$AUS" 'd["maschine"]')" = "eins-host" ] \
  && zusage $? "ohne lokalen Stand gewinnt trotzdem die erreichbare Maschine" \
  || bad "lokaler Ausfall verdrängt die Fernmaschinen: rc=$RC, $AUS"
case "$(feld "$AUS" '[f["name"] for f in d["maschinen_fehlgeschlagen"]]')" in
  *"$HOSTNAME"*) ok "der unlesbare lokale Stand steht mit Hostname und Grund in maschinen_fehlgeschlagen" ;;
  *) bad "lokaler Ausfall fehlt in der Liste: $AUS" ;;
esac

echo "== --alle-maschinen: alle Quellen weg -- Fehler mit den Listen, Exit 3 =="
rm -f "$QUELLE" "$FERN_EINS"
AUS="$(WB_BUDGET_SSH="$SSH_STUB" lauf --alle-maschinen)"; RC=$?
[ "$RC" = 3 ]; zusage $? "ohne jeden brauchbaren Stand endet --alle-maschinen mit Exit 3"
[ "$(feld "$AUS" 'sorted(d["maschinen_gelesen"])')" = "[]" ]; zusage $? "keine Maschine gelesen"
case "$(feld "$AUS" '[f["name"] for f in d["maschinen_fehlgeschlagen"]]')" in
  *"zwei"*|*"eins"*) ok "die Fehlgründe beider Maschinen stehen im Fehlerobjekt" ;;
  *) bad "Fehlerobjekt ohne Maschinenliste: $AUS" ;;
esac

echo "== --alle-maschinen ohne Liste in settings.json: keine andere Maschine (kit: one machine) =="
printf '%s\n' '{}' > "$SETTINGS"
VORHER="$(cat "$SSH_LOG" 2>/dev/null | wc -l | tr -d ' ')"
AUS="$(WB_BUDGET_SSH="$SSH_STUB" lauf --alle-maschinen)"
if [ "$(cat "$SSH_LOG" 2>/dev/null | wc -l | tr -d ' ')" = "$VORHER" ]; then
  ok "ohne agents.maschinen wird keine andere Maschine gefragt"
else
  bad "ssh ohne Maschinenliste: $(tail -1 "$SSH_LOG")"
fi

echo "== --base ersetzt \$HOME =="
BASIS="$TMP/anderes-home"
mkdir -p "$BASIS/.claude/workbench"
python3 - "$BASIS/.claude/workbench/limits-latest.json" "$RESET" <<'PY'
import json, sys
d = {"ts": "2026-08-22T11:00:00Z", "session": "b", "five_hour_pct": 1, "seven_day_pct": 20,
     "five_hour_resets_at": sys.argv[2], "seven_day_resets_at": sys.argv[2]}
json.dump(d, open(sys.argv[1], "w"))
PY
AUS="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$JETZT" bash "$WB" --json --base "$BASIS" 2>"$TMP/laeufer-stderr")"; RC=$?
[ "$RC" = 0 ] && [ "$(feld "$AUS" 'd["seven_day_pct"]')" = "20.0" ] \
  && [ "$(feld "$AUS" 'd["quelle"]')" = "$BASIS/.claude/workbench/limits-latest.json" ] \
  && zusage $? "--base ersetzt \$HOME: der Stand kommt aus dem anderen workbench-Verzeichnis" \
  || bad "--base-Fall: rc=$RC, $AUS"

echo "== Mit Berichtsfilter gilt weiterhin der volle Verbrauchsbericht =="
schreibe_quelle 60 3
AUS="$(lauf --tage 1 --ohne-kontingent)"; RC=$?
[ "$RC" = 0 ]; zusage $? "der gefilterte --json-Aufruf endet weiter mit Exit 0"
case "$AUS" in
  *tageslimit_erreicht*) bad "der gefilterte Aufruf lieferte den neuen Limitstand statt des vollen Berichts" ;;
  *) ok "mit Filter gilt weiterhin der volle Verbrauchsbericht (ohne tageslimit_erreicht)" ;;
esac
lauf --alle-maschinen --tage 1 >/dev/null 2>&1
[ $? -ne 0 ]; zusage $? "Berichtsfilter neben --alle-maschinen sind ein Fehler, kein stilles Durchreichen"

echo "== --limit bleibt Text mit Exit 0 =="
printf '{"ts": "2026-08-21T23:53:02Z", "session": "x", "five_hour_pct": 3, "seven_day_pct": 60, "seven_day_resets_at": "%s"}\n' \
  "$RESET" > "$FAKEHOME/.claude/workbench/limits.jsonl"
AUS="$(HOME="$FAKEHOME" WB_LIMIT_JETZT="$JETZT" bash "$WB" --limit --knapp 2>&1)"; RC=$?
[ "$RC" = 0 ] && case "$AUS" in *Wochenlimit*) ok "--limit bleibt Text mit Exit 0" ;; *) bad "--limit ohne Wochenlimit-Text: $AUS" ;; esac

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
