#!/usr/bin/env bash
# Tests fuer wb-session-close: eine geschlossene Sitzung gibt ihren
# Modellserver frei — aber nur, wenn ihn sonst niemand mehr benutzt.
#
# Anlass (2026-08-21, der Nutzer woertlich): „Ich habe die Sitzung mit Pi und
# Qwen 3.8 geschlossen ... aber das Modell belegt noch den Speicherplatz, also
# es wird nicht entladen, wenn ich die Sitzung schliesse." Er musste den Server
# von Hand beenden. Die Belegung erkannte den Prozess danach von selbst als tot
# und nahm ihn aus der Vergabe — diese Haelfte lief bereits; was fehlte, war das
# Beenden.
#
# GEPRUEFT WIRD MIT EINEM STELLVERTRETER, NICHT MIT EINEM MODELL. Der „Server"
# ist ein `python3 -m http.server` auf einem freien Port: ein echter Prozess mit
# einem echten LISTEN-Socket und einer echten wb-nohup-Registrierung, aber ohne
# 28 GiB Gewichte. Das Werkzeug, das ihn beenden soll (`kit-llm`), ist
# ebenfalls ein Stellvertreter unter einem eigenen $HOME — es findet seinen
# Prozess wie das echte ueber den Port und beendet ihn.
#
# ROT VOR GRUEN: Test 2 belegt, dass der Server VOR dem Schliessen laeuft, und
# Test 5, dass er danach weg ist. Dazwischen steht der Fall, der beim blinden
# Beenden Schaden anrichten wuerde: eine ZWEITE Sitzung ist als Benutzer
# eingetragen, und dann muss der Server das Schliessen der ersten ueberleben.
# Gegengeprueft wurde ausserdem gegen die Fassung VOR der Reparatur
# (WB_SESSION_CLOSE=<alte Kopie>): dort bleibt der Server stehen, Test 5 faellt.
#
# Alles laeuft auf einem EIGENEN tmux-Socket und unter einem EIGENEN $HOME
# (Regel: Tests fassen die Live-Umgebung nie an) — die echte wb-nohup-
# Registrierung unter ~/.local/state bleibt unberuehrt.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-session-close-modell-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
TOOL="${WB_SESSION_CLOSE:-$REPO/wb-session-close}"
NOHUP_TOOL="$REPO/wb-nohup"
WORK="$(mktemp -d)"
TESTHOME="$WORK/home"
mkdir -p "$TESTHOME/.local/bin"
pass=0; fail=0
echo "Geprueft: $TOOL"

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  # Der Stellvertreter-Server haengt an keinem Pane (das ist ja der Punkt) —
  # er muss hier von Hand weg, sonst bleibt er als Waise stehen.
  [ -n "${SRVPID:-}" ] && kill "$SRVPID" 2>/dev/null
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$WORK"
}
trap cleanup EXIT

ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Kommando in einem Pane des TESTSERVERS ausfuehren, mit dem Test-$HOME.
pane_run() { # pane_run <session> <kommando> -> setzt OUT und RC
  local sess="$1" cmd="$2" f="$WORK/out.$RANDOM"
  tm send-keys -t "$sess:$WIN.$PANE" \
     "{ HOME=$TESTHOME $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 25 "pane_run: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

echo "== wb-session-close: Modellserver freigeben =="

# --- Der Stellvertreter fuer 'kit-llm' ---------------------------------
# Er tut genau das, was das echte Werkzeug bei `stop` tut: seinen Prozess ueber
# den Port suchen und beenden. Er notiert jeden Aufruf, damit der Test auch
# belegen kann, DASS er gerufen wurde — und nicht etwa ein roher kill daneben.
cat > "$TESTHOME/.local/bin/kit-llm" <<'STUB'
#!/bin/bash
set -uo pipefail
echo "kit-llm $*" >> "$HOME/stub-aufrufe.log"
[ "${1:-}" = "stop" ] || { echo "Stellvertreter kennt nur 'stop'." >&2; exit 2; }
port="$(cat "$HOME/stub-port" 2>/dev/null)"
pid="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)"
[ -n "$pid" ] || { echo "kit-llm: nicht aktiv — nichts zu beenden."; exit 0; }
kill "$pid" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  ps -o pid= -p "$pid" >/dev/null 2>&1 || break
  sleep 0.3
done
echo "kit-llm: beendet (PID $pid)."
STUB
chmod +x "$TESTHOME/.local/bin/kit-llm"

PORT=""
for p in $(seq 18131 18160); do
  lsof -nP -iTCP:"$p" -sTCP:LISTEN -t >/dev/null 2>&1 || { PORT="$p"; break; }
done
if [ -z "$PORT" ]; then
  echo "  FAIL  kein freier Port im Bereich 18131-18160 gefunden"
  exit 1
fi
printf '%s\n' "$PORT" > "$TESTHOME/stub-port"

tm kill-server 2>/dev/null
tm new-session -d -s erste  -c /tmp
tm new-session -d -s zweite -c /tmp
tm new-session -d -s steuer -c /tmp            # von hier wird "von aussen" geschlossen
WIN="$(tm show-options -gv base-index 2>/dev/null || echo 0)"
PANE="$(tm show-window-options -gv pane-base-index 2>/dev/null || echo 0)"
SOCKPFAD="$(tm display -p -t '=erste' '#{socket_path}')"
PANE_ERSTE="$(tm list-panes -t '=erste'  -F '#{pane_id}' | head -1)"
PANE_ZWEITE="$(tm list-panes -t '=zweite' -F '#{pane_id}' | head -1)"

echo "-- 1. der Stellvertreter-Server laeuft, registriert auf die erste Sitzung --"
# Gestartet wird er mit dem ECHTEN wb-nohup aus einem Pane der ersten Sitzung:
# nur so entsteht dieselbe Registrierung, die es im Betrieb auch gibt.
pane_run erste "$NOHUP_TOOL kit-llm -- /usr/bin/python3 -m http.server $PORT --bind 127.0.0.1"
SRVPID="$(printf '%s\n' "$OUT" | grep -E '^[0-9]+$' | tail -1)"
if [ -n "$SRVPID" ] && ps -o pid= -p "$SRVPID" >/dev/null 2>&1; then
  ok "Stellvertreter-Server laeuft (PID $SRVPID, Port $PORT)"
else
  bad "Stellvertreter-Server nicht gestartet: $OUT"
  echo; echo "wb-session-close/Modellserver: $pass ok, $((fail+1)) fehlgeschlagen"; exit 1
fi
REG="$TESTHOME/.local/state/wb-nohup/eigentuemer/$SRVPID.json"
[ -f "$REG" ] && ok "wb-nohup hat ihn registriert" || bad "keine Registrierung unter $REG"
grep -q "\"pane\": \"$PANE_ERSTE\"" "$REG" 2>/dev/null \
  && ok "die erste Sitzung steht als Benutzer drin" \
  || bad "der Pane der ersten Sitzung steht nicht in der Registrierung"

echo "-- 2. zweite Sitzung traegt sich als Benutzer dazu (der geteilte Server) --"
pane_run zweite "$NOHUP_TOOL benutzer $SRVPID --pane $PANE_ZWEITE --socket $SOCKPFAD"
[ "$RC" = 0 ] && ok "Eintrag als zweiter Benutzer angenommen" \
              || bad "wb-nohup benutzer schlug fehl (rc=$RC): $OUT"
grep -q "\"pane\": \"$PANE_ZWEITE\"" "$REG" 2>/dev/null \
  && ok "beide Sitzungen stehen als Benutzer in der Registrierung" \
  || bad "die zweite Sitzung steht nicht in der Registrierung"

echo "-- 3. die erste Sitzung schliessen: der geteilte Server MUSS weiterlaufen --"
pane_run steuer "$TOOL erste"
[ "$RC" = 0 ] && ok "'erste' geschlossen (rc=0)" || bad "Schliessen schlug fehl (rc=$RC): $OUT"
tm has-session -t '=erste' 2>/dev/null && bad "'erste' lebt noch" || ok "'erste' ist geschlossen"
if ps -o pid= -p "$SRVPID" >/dev/null 2>&1; then
  ok "der Server laeuft weiter — die zweite Sitzung benutzt ihn noch"
else
  bad "der Server wurde beendet, obwohl eine zweite Sitzung ihn benutzt"
fi
case "$OUT" in *"bleibt"*"benutzt ihn noch"*) ok "die Meldung nennt den lebenden Benutzer" ;;
               *) bad "die Meldung sagt nicht, warum der Server bleibt: $OUT" ;; esac
[ -f "$TESTHOME/stub-aufrufe.log" ] \
  && bad "'kit-llm stop' wurde gerufen, obwohl der Server benutzt wird" \
  || ok "'kit-llm stop' wurde gar nicht erst gerufen"

echo "-- 4. der Server laeuft unmittelbar VOR dem letzten Schliessen noch --"
if ps -o pid= -p "$SRVPID" >/dev/null 2>&1 \
   && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  ok "PID $SRVPID lauscht auf Port $PORT"
else
  bad "der Stellvertreter-Server ist schon vor dem Schliessen weg"
fi

echo "-- 5. die letzte Sitzung schliessen: der Server wird beendet --"
pane_run steuer "$TOOL zweite"
[ "$RC" = 0 ] && ok "'zweite' geschlossen (rc=0)" || bad "Schliessen schlug fehl (rc=$RC): $OUT"
tm has-session -t '=zweite' 2>/dev/null && bad "'zweite' lebt noch" || ok "'zweite' ist geschlossen"
if ps -o pid= -p "$SRVPID" >/dev/null 2>&1; then
  bad "der Server laeuft weiter, obwohl keine Sitzung ihn mehr benutzt — genau Befund des Nutzers"
else
  ok "der Server ist beendet — der Speicher ist frei"
  SRVPID=""
fi
grep -q '^kit-llm stop$' "$TESTHOME/stub-aufrufe.log" 2>/dev/null \
  && ok "beendet wurde ueber 'kit-llm stop', nicht mit einem rohen kill" \
  || bad "'kit-llm stop' steht nicht im Protokoll des Stellvertreters"
case "$OUT" in *"Modellserver"*"beendet"*) ok "die Meldung sagt, dass der Modellserver beendet wurde" ;;
               *) bad "die Meldung nennt das Beenden nicht: $OUT" ;; esac
case "$OUT" in *"neu geladen"*) ok "die Meldung nennt den Preis: beim Fortsetzen wird neu geladen" ;;
               *) bad "die Meldung verschweigt, dass das Modell neu geladen werden muss: $OUT" ;; esac

echo "-- 6. eine Sitzung ohne Modellserver schliesst wie bisher --"
tm new-session -d -s ohne -c /tmp
pane_run steuer "$TOOL ohne"
[ "$RC" = 0 ] && ok "'ohne' geschlossen (rc=0)" || bad "Schliessen schlug fehl (rc=$RC): $OUT"
case "$OUT" in *Modellserver*) bad "es wird ein Modellserver gemeldet, den es nicht gibt: $OUT" ;;
               *) ok "keine Modellserver-Meldung, wo es keinen gibt" ;; esac

echo "-- 7. eine Leiche in der Registrierung beendet nichts (PID-Wiederverwendung) --"
# Ein Eintrag, dessen `lstart_pruefwert` nicht mehr zur PID passt, beschreibt
# einen laengst ersetzten Prozess. Er darf keinen Stop ausloesen — sonst
# beendete eine alte Registrierung irgendeinen neuen Prozess mit derselben
# Nummer. Nachgestellt am eigenen Pane-Prozess dieser Testsitzung.
tm new-session -d -s leiche -c /tmp
# Die PID gehoert bewusst zu einer ANDEREN, weiterlaufenden Session: sie steht
# fuer den fremden Prozess, der die Nummer inzwischen bekommen hat. Der
# eingetragene Pane dagegen gehoert zu 'leiche' — nur so wird der Eintrag
# ueberhaupt als Kandidat dieser Sitzung erkannt, und genau dann muss der
# lstart-Vergleich ihn aussortieren.
FREMDPID="$(tm list-panes -t '=steuer' -F '#{pane_pid}' | head -1)"
PANE_LEICHE="$(tm list-panes -t '=leiche' -F '#{pane_id}' | head -1)"
mkdir -p "$TESTHOME/.local/state/wb-nohup/eigentuemer"
cat > "$TESTHOME/.local/state/wb-nohup/eigentuemer/$FREMDPID.json" <<JSON
{
  "pid": $FREMDPID,
  "name": "kit-llm",
  "befehl": ["python3"],
  "worker": "test",
  "pane": "$PANE_LEICHE",
  "socket_path": "$SOCKPFAD",
  "benutzer": [{"pane": "$PANE_LEICHE", "socket_path": "$SOCKPFAD"}],
  "lstart_pruefwert": "Thu Jan  1 00:00:00 1970"
}
JSON
: > "$TESTHOME/stub-aufrufe.log"
pane_run steuer "$TOOL leiche"
[ "$RC" = 0 ] && ok "'leiche' geschlossen (rc=0)" || bad "Schliessen schlug fehl (rc=$RC): $OUT"
grep -q '^kit-llm stop$' "$TESTHOME/stub-aufrufe.log" 2>/dev/null \
  && bad "ein Eintrag mit falschem lstart-Pruefwert hat 'stop' ausgeloest" \
  || ok "der veraltete Eintrag loest nichts aus"
ps -o pid= -p "$FREMDPID" >/dev/null 2>&1 \
  && ok "der fremde Prozess mit derselben PID lebt noch" \
  || bad "der fremde Prozess wurde beendet"

echo "-- 8. derselbe Griff ueber --self (der Tastendruck Prefix + S) --"
# `--self` muss VOR dem Schliessen entscheiden: der Kill trifft den Pane, in dem
# das Werkzeug selbst laeuft, und was danach steht, laeuft nicht mehr. Deshalb
# hier eigens geprueft — der Port ist nach Test 5 wieder frei.
: > "$TESTHOME/stub-aufrufe.log"
tm new-session -d -s selbst -c /tmp
tm new-session -d -t selbst -s selbst-view
pane_run selbst "$NOHUP_TOOL kit-llm -- /usr/bin/python3 -m http.server $PORT --bind 127.0.0.1"
SRVPID="$(printf '%s\n' "$OUT" | grep -E '^[0-9]+$' | tail -1)"
if [ -n "$SRVPID" ] && ps -o pid= -p "$SRVPID" >/dev/null 2>&1; then
  ok "zweiter Stellvertreter-Server laeuft (PID $SRVPID)"
else
  bad "zweiter Stellvertreter-Server nicht gestartet: $OUT"
fi
tm run-shell "HOME=$TESTHOME WB_SESSION_CLOSE_CONFIRM=selbst $TOOL --self"
if warte_auf_bedingung 20 "--self schliesst 'selbst'" \
     '! tmux -L "$SOCKET" has-session -t "=selbst" 2>/dev/null'; then
  ok "--self hat die eigene Basis-Session geschlossen"
fi
tm has-session -t '=selbst-view' 2>/dev/null && bad "'selbst-view' lebt noch" \
                                             || ok "die gruppierte Sicht ist mitgeschlossen"
if warte_auf_bedingung 10 "--self beendet den Modellserver" \
     '! ps -o pid= -p "$SRVPID" >/dev/null 2>&1'; then
  ok "--self hat den Modellserver mit beendet"
  SRVPID=""
fi
grep -q '^kit-llm stop$' "$TESTHOME/stub-aufrufe.log" 2>/dev/null \
  && ok "auch hier ueber 'kit-llm stop'" \
  || bad "'kit-llm stop' steht nicht im Protokoll des Stellvertreters"

echo
echo "wb-session-close/Modellserver: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
