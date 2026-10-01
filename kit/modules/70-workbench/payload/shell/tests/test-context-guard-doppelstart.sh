#!/usr/bin/env bash
# test-context-guard-doppelstart.sh -- der Befund vom 2026-08-08: zwei Wachen fuer denselben Pane.
#
# Seit 2026-08-07 erkennt `--ensure` einen laufenden Guard ueber eine Merkdatei je Instanz
# (Socket + Session) und startet keinen zweiten. Trotzdem liefen heute zwei Guards fuer Pane %10
# von Gardener-Sitzung des Nutzers (PIDs 14604 und 81969); die Merkdatei trug am Ende nur noch die
# juengere PID. Ursache: der Guard selbst trug sich beim Start BEDINGUNGSLOS ein, ohne
# nachzusehen, ob dort schon ein lebender steht -- der Schutz lag allein in `--ensure`, und
# `wb-code` startete den Guard direkt (`--auto <pane>` per nohup), also daran vorbei. Ein zweiter
# Guard tippt jedes `/compact` doppelt; das zweite trifft eine Sitzung, die gerade erst wieder
# anlaeuft.
#
# Geprueft wird deshalb der Startweg SELBST, nicht `--ensure`:
#   Punkt 1  ohne Merkdatei startet ein Guard normal (die Richtung "im Zweifel STARTEN" bleibt).
#   Punkt 2  ein zweiter Start auf demselben Weg, den wb-code benutzt, startet NICHT -- er meldet,
#            endet mit 0, laesst die Merkdatei des Vorgaengers unberuehrt, und der Vorgaenger
#            laeuft weiter. Genau EINER bleibt uebrig.
#   Punkt 3  die Gegenrichtung: eine Merkdatei mit einer TOTEN PID (SIGKILL laesst keine Falle zu)
#            darf einen Start nicht verhindern -- sonst waere ein voller Kontext der Preis.
#   Punkt 4  wb-code ruft den geprueften Weg auf, nicht mehr den direkten.
#   Punkt 5  `--ensure` hinterlaesst die Merkdatei, BEVOR es zurueckkehrt (Befund
#            2026-08-25/28: bis dahin trug sich erst das Kind ein, und zwischen der
#            Freigabe der Sperre und diesem Eintrag lagen gemessene 51 ms -- genau das
#            Fenster, in dem ein zweites `--ensure` einen zweiten Guard startet).
#
# SICHERHEIT (regeln/tests-und-eingriffe.md): eigener tmux-Socket mit PID im Namen, eigenes HOME,
# eigene Sessionnamen ('wb-DS-…'). Der PRUEFLING wird an den Testsocket GEBUNDEN, nicht nur der
# Test selbst -- context-guard ruft `tmux` intern an vielen Stellen auf, und eine Shell-Funktion
# gilt im Kindprozess nicht. Der Weg ist derselbe wie in test-context-guard-waise.sh: ein
# `tmux`-Schirm ganz vorn im PATH und context-guard immer ueber den ABSOLUTEN Pfad. `trap` raeumt
# Server, Guards und Verzeichnis auf, auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_GUARD_SRC="${CONTEXT_GUARD:-$REPO/context-guard}"
WB_CODE_SRC="${WB_CODE:-$REPO/wb-code}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-doppel-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" wb-pane-write wb-mensch \
  || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"

pass=0; fail=0
GUARD_PIDS=()   # jede von diesem Test gestartete Guard-PID -- verifiziert beendet, nicht angenommen

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  local p noch_da="" deadline
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null && kill "$p" 2>/dev/null
  done
  tmux_socket_beenden_ohne_reste "$SOCKET"
  deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  sleep 0.5
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null && noch_da="$noch_da $p"
  done
  [ -n "$noch_da" ] && echo "WARNUNG: Guard-PID(s)$noch_da laufen nach dem Aufraeumen noch" >&2
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

guard_gemerkt() {   # <pid> -> merkt eine Guard-PID genau einmal
  local neu="$1" p
  [ -n "$neu" ] || return 0
  for p in "${GUARD_PIDS[@]:-}"; do [ "$p" = "$neu" ] && return 0; done
  GUARD_PIDS+=("$neu")
}

[ -x "$CONTEXT_GUARD_SRC" ] || { echo "FAIL  context-guard nicht gefunden/ausfuehrbar: $CONTEXT_GUARD_SRC"; exit 1; }

mkdir -p "$BIN" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.local/state"
# ERST den Symlink aus werkzeuge_installieren entfernen, DANN kopieren (siehe waise-Test): ein
# `cp` auf einen Symlink schreibt durch ihn hindurch und wuerde bei CONTEXT_GUARD=<andere
# Fassung> die Datei im Arbeitsbaum ueberschreiben.
rm -f "$BIN/context-guard"
cp "$CONTEXT_GUARD_SRC" "$BIN/context-guard"
chmod +x "$BIN/context-guard"
cp "$HOME/.local/bin/wb-state" "$BIN/wb-state" 2>/dev/null && chmod +x "$BIN/wb-state"

GUARD="$BIN/context-guard"   # IMMER absolut aufrufen, siehe Kopfkommentar
STATE="$TESTHOME/.local/state/wb-context-guard"

SHIM="$TESTHOME/.shim"
mkdir -p "$SHIM"
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

export HOME="$TESTHOME"
TPATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

tm() { tmux -L "$SOCKET" "$@"; }

# Kommando in der STEUER-Pane des Testservers ausfuehren (nie aus dieser Shell heraus): nur dort
# zeigt $TMUX auf den Testsocket, und context-guards eigene tmux-Aufrufe laufen ueber den Schirm.
lauf() {   # lauf <kommando> [<frist-s>] -> setzt OUT und RC
  local cmd="$1" frist="${2:-30}" f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t ctrl \
    "{ export PATH='$TPATH' HOME='$TESTHOME'; $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" "$frist" "lauf: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

pidfile_inhalt() {   # -> PID aus der Merkdatei dieser Instanz, leer wenn keine da ist
  local f
  f="$(ls "$STATE"/*wb-DS-eins.pid 2>/dev/null | head -1)"
  [ -n "$f" ] || return 0
  head -1 "$f" 2>/dev/null | tr -dc '0-9'
}

warte_auf_pidfile() {   # <frist-s> -> 0, sobald die Merkdatei eine PID traegt
  local deadline=$((SECONDS + $1))
  while [ $SECONDS -lt $deadline ]; do
    [ -n "$(pidfile_inhalt)" ] && return 0
    sleep 0.2
  done
  return 1
}

echo "== context-guard: kein zweiter Guard fuer dieselbe Instanz, auch ohne --ensure =="

tm kill-server 2>/dev/null
tm new-session -d -s ctrl -c /tmp
tm new-session -d -s wb-DS-eins -c /tmp
PANE="$(tm list-panes -t '=wb-DS-eins' -F '#{pane_id}' | head -1)"
tm set -p -t "$PANE" @wb_role orchestrator

echo "-- Punkt 1: ohne Merkdatei startet ein Guard --"
[ -z "$(pidfile_inhalt)" ] \
  && ok "vor dem ersten Start liegt keine Merkdatei -- die Ausgangslage stimmt" \
  || bad "es liegt schon eine Merkdatei ($(pidfile_inhalt)) -- der Test misst dann etwas anderes"

# GENAU die Zeile, mit der wb-code den Guard bis heute gestartet hat: --auto, kein --ensure,
# nohup, beide Stroeme in ein Log.
lauf "POLL=3 nohup '$GUARD' --auto '$PANE' >'$TESTHOME/eins.log' 2>&1 & echo \$! > '$TESTHOME/pid1'; echo PID=\$!"
PID1="$(cat "$TESTHOME/pid1" 2>/dev/null | tr -dc '0-9')"
guard_gemerkt "$PID1"
if [ -n "$PID1" ] && kill -0 "$PID1" 2>/dev/null; then
  ok "erster Guard laeuft (PID $PID1, gestartet wie wb-code es tat: --auto, ohne --ensure)"
else
  bad "erster Guard laeuft nicht ($OUT) -- ohne ihn prueft Punkt 2 nichts"
fi
if warte_auf_pidfile 10; then
  [ "$(pidfile_inhalt)" = "$PID1" ] \
    && ok "die Merkdatei traegt seine PID ($PID1)" \
    || bad "die Merkdatei traegt '$(pidfile_inhalt)', erwartet war $PID1"
else
  bad "nach 10s traegt keine Merkdatei eine PID -- der Guard hat sich nicht eingetragen"
fi

echo "-- Punkt 2: ein zweiter Start auf demselben Weg startet NICHT --"
# `wait` auf den Hintergrundprozess: beendet er sich wie gefordert, kommt `lauf` sofort zurueck.
# Laeuft er weiter (der Fehler von heute), schlaegt die Frist zu und der Test meldet das, statt
# haengen zu bleiben. Die PID liegt in einer Datei, damit sie auch nach einer Fristueberschreitung
# fuer das Aufraeumen bekannt ist.
lauf "POLL=3 nohup '$GUARD' --auto '$PANE' >'$TESTHOME/zwei.log' 2>&1 & echo \$! > '$TESTHOME/pid2'; wait \$!" 20
PID2="$(cat "$TESTHOME/pid2" 2>/dev/null | tr -dc '0-9')"
guard_gemerkt "$PID2"
if [ "$RC" = "124" ]; then
  bad "der zweite Guard (PID $PID2) lief nach 20s noch -- zwei Wachen fuer $PANE, genau der Befund"
else
  ok "der zweite Start hat sich selbst beendet, statt als zweite Wache weiterzulaufen"
fi
[ -n "$PID2" ] && ! kill -0 "$PID2" 2>/dev/null \
  && ok "sein Prozess ist weg (PID $PID2)" \
  || bad "PID $PID2 laeuft noch"
grep -qF "laeuft bereits ein Guard (PID $PID1)" "$TESTHOME/zwei.log" \
  && ok "er hat laut gemeldet, warum: $(grep -F 'laeuft bereits ein Guard' "$TESTHOME/zwei.log" | head -1 | cut -c1-120)…" \
  || bad "keine Meldung im Log des zweiten Starts: $(tail -3 "$TESTHOME/zwei.log" 2>/dev/null | tr '\n' ' ')"
# Der Kern des heutigen Fehlers: der juengere hatte die Merkdatei ueberschrieben, damit war der
# aeltere fuer jede spaetere Pruefung unsichtbar.
[ "$(pidfile_inhalt)" = "$PID1" ] \
  && ok "die Merkdatei traegt unveraendert die PID des Vorgaengers ($PID1)" \
  || bad "die Merkdatei traegt jetzt '$(pidfile_inhalt)' statt $PID1 -- der abgelehnte Start hat sie ueberschrieben"
kill -0 "$PID1" 2>/dev/null \
  && ok "der erste Guard laeuft unberuehrt weiter -- genau einer bewacht $PANE" \
  || bad "der erste Guard ist verschwunden -- die Absage hat den falschen getroffen"
DOPPELLOG="$(ls "$STATE"/*wb-DS-eins.doppelstart.log 2>/dev/null | head -1)"
[ -n "$DOPPELLOG" ] && grep -q "abgelehnt" "$DOPPELLOG" \
  && ok "die Absage steht zusaetzlich in einem von stdout unabhaengigen Protokoll" \
  || bad "keine Spur der Absage neben der Merkdatei -- bei umgeleiteten Stroemen bliebe sie unsichtbar"

echo "-- Punkt 3: eine TOTE PID in der Merkdatei darf den Start nicht verhindern --"
# SIGKILL laesst keine Falle zu, die Merkdatei bleibt also mit einer toten PID stehen -- der Fall,
# in dem ein zu strenger Schutz einen Kontext volllaufen liesse.
kill -9 "$PID1" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID1" 2>/dev/null || break; sleep 0.3; done
if kill -0 "$PID1" 2>/dev/null; then
  bad "PID $PID1 liess sich nicht mit SIGKILL beenden -- Punkt 3 nicht pruefbar"
else
  [ "$(pidfile_inhalt)" = "$PID1" ] \
    && ok "die Merkdatei steht noch und traegt die tote PID $PID1 -- der Befund ist hergestellt" \
    || bad "die Merkdatei ist weg oder traegt '$(pidfile_inhalt)' -- ohne die tote PID prueft Punkt 3 nichts"
  lauf "POLL=3 nohup '$GUARD' --auto '$PANE' >'$TESTHOME/drei.log' 2>&1 & echo \$! > '$TESTHOME/pid3'; echo PID=\$!"
  PID3="$(cat "$TESTHOME/pid3" 2>/dev/null | tr -dc '0-9')"
  guard_gemerkt "$PID3"
  sleep 2
  if [ -n "$PID3" ] && kill -0 "$PID3" 2>/dev/null; then
    ok "trotz stehender Merkdatei ist ein neuer Guard gestartet (PID $PID3)"
  else
    bad "kein Guard gestartet -- eine tote PID hat ihn blockiert, der Kontext bliebe unbewacht: $(tail -3 "$TESTHOME/drei.log" 2>/dev/null | tr '\n' ' ')"
  fi
  [ "$(pidfile_inhalt)" = "$PID3" ] \
    && ok "die Merkdatei traegt jetzt seine PID ($PID3)" \
    || bad "die Merkdatei traegt '$(pidfile_inhalt)' statt $PID3"
  kill "$PID3" 2>/dev/null
fi

echo "-- Punkt 4: wb-code startet den Guard ueber den geprueften Weg --"
if [ -r "$WB_CODE_SRC" ]; then
  grep -q -- "context-guard\" --ensure" "$WB_CODE_SRC" \
    && ok "wb-code ruft 'context-guard --ensure' auf" \
    || bad "wb-code ruft --ensure nicht auf -- der Startweg von heute frueh ist noch drin"
  grep -q -- 'context-guard" --auto' "$WB_CODE_SRC" \
    && bad "wb-code startet den Guard weiterhin direkt mit --auto" \
    || ok "kein direkter --auto-Start mehr in wb-code"
  grep -q 'pgrep -f "\[c\]ontext-guard' "$WB_CODE_SRC" \
    && bad "wb-code erkennt laufende Guards noch ueber pgrep -- maschinenweit, also nicht je tmux-Server" \
    || ok "die maschinenweite pgrep-Erkennung ist aus wb-code raus"
else
  bad "wb-code nicht lesbar: $WB_CODE_SRC"
fi


echo "-- Punkt 5: --ensure hinterlaesst die Merkdatei, BEVOR es zurueckkehrt --"
# Der Befund vom 2026-08-25 (Masterliste): mehrere Spawns meldeten brav "laeuft bereits",
# und trotzdem entstand ein zweiter Guard mit identischen Argumenten. Punkt 1 bis 4 pruefen
# den direkten Startweg; hier geht es um `--ensure` selbst.
#
# Gemessen am 2026-08-28: `--ensure` startete das Kind per nohup, gab die Sperre SOFORT
# wieder frei und ueberliess das Eintragen in die Merkdatei dem Kind -- das sich erst am
# Ende seines eigenen Anlaufs eintrug. Auf einer ruhigen Maschine lagen dazwischen 51 ms
# (Rueckkehr nach 346 ms, Merkdatei nach 396 ms). Ein zweites `--ensure` in diesem Fenster
# sieht "kein Guard da" und startet einen zweiten -- die Sperre schuetzt dort nicht mehr,
# sie ist ja schon offen. pi-worker ruft `--ensure` nach JEDEM Pane-Start auf, zwei Spawns
# kurz hintereinander sind also der Normalfall.
#
# Geprueft wird deshalb die Zusage selbst, ohne Stoppuhr: in dem Augenblick, in dem
# `--ensure` zurueckkehrt, MUSS die Merkdatei da sein und eine lebende PID tragen. Eine
# Zeitmessung waere hier die schlechtere Pruefung -- sie wuerde von der Tagesform der
# Maschine abhaengen, und ein Fenster von wenigen Millisekunden verschwindet im Rauschen
# von `date`. Diese Zusage dagegen gilt oder gilt nicht.
tm new-session -d -s wb-DS-zwei -c /tmp
PANE5="$(tm list-panes -t '=wb-DS-zwei' -F '#{pane_id}' | head -1)"
tm set -p -t "$PANE5" @wb_role orchestrator

pidfile5() {   # -> PID aus der Merkdatei DIESER zweiten Instanz
  local f
  f="$(ls "$STATE"/*wb-DS-zwei.pid 2>/dev/null | head -1)"
  [ -n "$f" ] || return 0
  head -1 "$f" 2>/dev/null | tr -dc '0-9'
}

[ -z "$(pidfile5)" ] \
  && ok "Punkt 5: vor dem Aufruf liegt keine Merkdatei fuer die zweite Instanz" \
  || bad "Punkt 5: es liegt schon eine Merkdatei ($(pidfile5)) -- der Punkt misst dann nichts"

# Der Aufruf und das Nachsehen liegen im SELBEN Kommando: nur so ist "direkt nach der
# Rueckkehr" wirklich direkt und nicht erst nach einer Runde durch die Testshell.
lauf "'$GUARD' --ensure '$PANE5'; ls $STATE/*wb-DS-zwei.pid 2>/dev/null | wc -l" 40
PID5="$(pidfile5)"
guard_gemerkt "$PID5"
if printf '%s' "$OUT" | tail -1 | grep -qE '^[[:space:]]*1[[:space:]]*$'; then
  ok "Punkt 5: die Merkdatei existiert im Augenblick der Rueckkehr -- kein Fenster fuer einen zweiten Start"
else
  bad "Punkt 5: nach der Rueckkehr von --ensure lag KEINE Merkdatei (Ausgabe: $OUT) -- genau das Fenster vom 25.08."
fi
if [ -n "$PID5" ] && kill -0 "$PID5" 2>/dev/null; then
  ok "Punkt 5: und sie traegt eine lebende PID ($PID5), nicht bloss irgendeinen Inhalt"
else
  bad "Punkt 5: die Merkdatei traegt keine lebende PID ('$PID5') -- eine Eintragung ohne Prozess waere schlimmer als keine"
fi

# Zweiter Aufruf unmittelbar danach: genau der Fall, den pi-worker beim naechsten Worker
# ausloest. Er darf melden, aber nichts starten.
lauf "'$GUARD' --ensure '$PANE5'" 40
printf '%s' "$OUT" | grep -q "laeuft bereits" \
  && ok "Punkt 5: ein sofort folgendes --ensure meldet 'laeuft bereits' und startet nichts" \
  || bad "Punkt 5: das zweite --ensure meldete nicht 'laeuft bereits': $OUT"
[ "$(pidfile5)" = "$PID5" ] \
  && ok "Punkt 5: die Merkdatei gehoert weiterhin dem ersten Guard ($PID5)" \
  || bad "Punkt 5: die Merkdatei traegt jetzt '$(pidfile5)' statt $PID5 -- der zweite Aufruf hat sie uebernommen"

echo "-- Punkt 6: --ensure findet auch einen Guard ohne eigene Merkdatei --"
# Produktionsbefund 18.09.: ein schon laufender --auto --exit-when-session-gone
# Guard fuer denselben Pane lag unter einem abweichenden (Basis/-view-)Slug.
# Die -view-Schwester ist Teil der Reproduktion: sie teilt den Pane der
# Basis-Session, aber nicht ihren zurueckgemeldeten Sessionnamen.
tm new-session -d -s wb-DS-basis -c /tmp
tm new-session -d -t '=wb-DS-basis' -s wb-DS-basis-view -c /tmp
PANE6="$(tm list-panes -t '=wb-DS-basis-view' -F '#{pane_id}' | head -1)"
tm set -p -t "$PANE6" @wb_role orchestrator
lauf "POLL=3 nohup '$GUARD' --auto --exit-when-session-gone '$PANE6' >'$TESTHOME/sechs.log' 2>&1 & echo \$! > '$TESTHOME/pid6'; echo PID=\$!"
PID6="$(cat "$TESTHOME/pid6" 2>/dev/null | tr -dc '0-9')"
guard_gemerkt "$PID6"
sleep 1
if [ -n "$PID6" ] && kill -0 "$PID6" 2>/dev/null; then
  ok "Punkt 6: der fremd registrierte Guard laeuft (PID $PID6, Pane $PANE6)"
else
  bad "Punkt 6: der vorbereitete Guard laeuft nicht: $(tail -3 "$TESTHOME/sechs.log" 2>/dev/null | tr '\n' ' ')"
fi
PID6_ALT="$(ls "$STATE"/*wb-DS-basis.pid 2>/dev/null | head -1)"
if [ -n "$PID6_ALT" ]; then
  mv "$PID6_ALT" "${PID6_ALT%.pid}-view.pid"
  ok "Punkt 6: die PID-Merkdatei liegt nur unter dem alten -view-Slug"
else
  bad "Punkt 6: keine Ausgangs-Merkdatei zum Verschieben gefunden"
fi
lauf "'$GUARD' --ensure '$PANE6'" 40
printf '%s' "$OUT" | grep -q "laeuft bereits" \
  && ok "Punkt 6: --ensure erkennt den laufenden Guard trotz altem -view-Slug" \
  || bad "Punkt 6: --ensure meldete keinen vorhandenen Guard: $OUT"
PID6_DATEI="$(grep -rl "^$PID6$" "$STATE"/*.pid 2>/dev/null | head -1)"
[ -n "$PID6_DATEI" ] && [ "$(head -1 "$PID6_DATEI" 2>/dev/null | tr -dc '0-9')" = "$PID6" ] \
  && ok "Punkt 6: --ensure hat die gefundene PID in seiner Instanz-Merkdatei verankert" \
  || bad "Punkt 6: die Merkdatei benennt nicht den gefundenen Guard ($PID6)"
kill -0 "$PID6" 2>/dev/null \
  && ok "Punkt 6: kein zweiter Guard gestartet, der vorhandene laeuft weiter" \
  || bad "Punkt 6: der vorhandene Guard verschwand beim Erkennen"

echo
echo "wb-context-guard-doppelstart: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
