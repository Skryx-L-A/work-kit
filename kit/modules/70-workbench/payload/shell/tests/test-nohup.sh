#!/usr/bin/env bash
# Tests fuer wb-nohup — der vorgeschriebene Weg, einen Hintergrundprozess
# abgeloest zu starten und dabei im selben Handgriff seinen Eigentuemer
# (PID, Startbefehl, Startzeit, Worker, Pane) zu hinterlegen. `wb-waisen`
# liest genau diese Registrierung (siehe test-waisen.sh).
#
# Isolation: eigener tmux-Socket, jede erzeugte PID wird im `trap` per PID
# beendet (nie per Muster). wb-nohup selbst wird IMMER aus einem Pane des
# Testservers heraus aufgerufen — es braucht `$TMUX`/`$TMUX_PANE`, und diese
# muessen auf den Testsocket zeigen, nie auf den Live-Server.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-nohup-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib-testwerkzeuge.sh"
TOOL="${WB_NOHUP:-$REPO_ROOT/shell/wb-nohup}"
WORK="$(mktemp -d)"
pass=0; fail=0
echo "Geprueft: $TOOL"

tm() { tmux -L "$SOCKET" "$@"; }

EIGENE_PIDS=()
cleanup() {
  local p
  for p in "${EIGENE_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    ps -o pid= -p "$p" >/dev/null 2>&1 && kill "$p" 2>/dev/null
  done
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

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "SKIP -- wb-nohup ist nur auf macOS unterstuetzt (siehe wb-waisens Kopfkommentar)"
  exit 0
fi

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp
tm set -p -t steuer @wb_worker nohup-testworker

# Aus einem Pane des Testservers heraus aufrufen (dasselbe Pane-Muster wie
# test-doctor-betriebs-befunde.sh) -- $TMUX/$TMUX_PANE zeigen dann auf den
# Testsocket, wb-nohup braucht keine weiteren Isolationsvorkehrungen.
pane_run() {  # pane_run <kommando> -> setzt OUT, RC
  local cmd="$1" f="$WORK/out.$RANDOM"
  tm send-keys -t steuer "{ $cmd ; } > '$f' 2>&1; echo \"RC=\$?\" >> '$f'; touch '$f.done'" Enter
  if warte_auf_datei "$f.done" 15 "pane_run: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

echo "== wb-nohup =="

# ---------------------------------------------------------------------------
# 1. Normaler Start: Registrierung entsteht mit den richtigen Feldern
# ---------------------------------------------------------------------------
echo "-- 1: Registrierung entsteht mit PID, Name, Worker, Pane, Socket, lstart --"
mkdir -p "$WORK/home1/bin"
cat > "$WORK/home1/bin/sleeper" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$WORK/home1/bin/sleeper"
pane_run "HOME='$WORK/home1' '$TOOL' probe1 -- '$WORK/home1/bin/sleeper'"
[ "$RC" -eq 0 ] && ok "wb-nohup endet mit 0" || bad "wb-nohup endet mit $RC: $OUT"
PID1="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
if [ -n "$PID1" ] && [ "$PID1" -gt 0 ] 2>/dev/null; then
  EIGENE_PIDS[${#EIGENE_PIDS[@]}]="$PID1"
  ok "eine PID wurde auf stdout ausgegeben ($PID1)"
  ps -o pid= -p "$PID1" >/dev/null 2>&1 \
    && ok "diese PID lebt wirklich" \
    || bad "PID $PID1 lebt nicht"
else
  bad "keine brauchbare PID auf stdout: $OUT"
fi
REGFILE="$WORK/home1/.local/state/wb-nohup/eigentuemer/$PID1.json"
if [ -f "$REGFILE" ]; then
  ok "Registrierungsdatei liegt an der erwarteten Stelle"
  # EINE pipe-getrennte Zeile statt mehrerer print()-Zeilen: `read` liest von
  # einem Here-String immer nur EINE Zeile, egal wie viele Variablennamen man
  # ihm gibt -- `IFS=$'\n' read -r a b c <<< "$mehrzeilig"` befuellt nur `a`
  # und laesst den Rest leer (gemessen). Das ist derselbe pipe-getrennte
  # Aufbau, den wb-waisens eigene lade_eigentuemer() benutzt.
  FELDER="$(/usr/bin/python3 -c "
import json
d = json.load(open('$REGFILE'))
befehl = ' '.join(d.get('befehl') or [])
print('%s|%s|%s|%s|%s|%s|%s' % (d.get('pid'), d.get('name'), d.get('worker'),
      d.get('pane'), befehl, bool(d.get('lstart_pruefwert')), bool(d.get('gestartet'))))
")"
  IFS='|' read -r F_PID F_NAME F_WORKER F_PANE F_BEFEHL F_LSTART F_GESTARTET <<< "$FELDER"
  [ "$F_PID" = "$PID1" ] && ok "pid im Eintrag stimmt" || bad "pid im Eintrag ist '$F_PID', erwartet $PID1"
  [ "$F_NAME" = "probe1" ] && ok "name im Eintrag stimmt" || bad "name im Eintrag ist '$F_NAME'"
  [ "$F_WORKER" = "nohup-testworker" ] && ok "worker wurde aus @wb_worker des Panes gelesen" || bad "worker ist '$F_WORKER', erwartet 'nohup-testworker'"
  [ -n "$F_PANE" ] && ok "pane ist gesetzt ($F_PANE)" || bad "pane fehlt im Eintrag"
  printf '%s\n' "$F_BEFEHL" | grep -qF "sleeper" && ok "befehl im Eintrag nennt den echten Befehl" || bad "befehl fehlt/falsch: '$F_BEFEHL'"
  [ "$F_LSTART" = "True" ] && ok "lstart_pruefwert ist gesetzt" || bad "lstart_pruefwert fehlt"
  [ "$F_GESTARTET" = "True" ] && ok "gestartet-Zeitstempel ist gesetzt" || bad "gestartet fehlt"
else
  bad "keine Registrierungsdatei unter $REGFILE"
fi
LOGFILE="$WORK/home1/.local/state/wb-nohup/logs/probe1.log"
[ -f "$LOGFILE" ] && ok "Protokolldatei wurde angelegt" || bad "keine Protokolldatei unter $LOGFILE"

# ---------------------------------------------------------------------------
# 2. --worker ueberschreibt die automatische Erkennung
# ---------------------------------------------------------------------------
echo "-- 2: --worker setzt den Worker-Namen explizit --"
mkdir -p "$WORK/home2/bin"
cp "$WORK/home1/bin/sleeper" "$WORK/home2/bin/sleeper"
pane_run "HOME='$WORK/home2' '$TOOL' probe2 --worker eigener-name -- '$WORK/home2/bin/sleeper'"
PID2="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
[ -n "$PID2" ] && [ "$PID2" -gt 0 ] 2>/dev/null && EIGENE_PIDS[${#EIGENE_PIDS[@]}]="$PID2"
REGFILE2="$WORK/home2/.local/state/wb-nohup/eigentuemer/$PID2.json"
if [ -f "$REGFILE2" ]; then
  W="$(/usr/bin/python3 -c "import json; print(json.load(open('$REGFILE2')).get('worker'))")"
  [ "$W" = "eigener-name" ] && ok "--worker ueberschreibt den Pane-Worker-Namen" || bad "worker ist '$W', erwartet 'eigener-name'"
else
  bad "keine Registrierungsdatei fuer Fall 2"
fi

# ---------------------------------------------------------------------------
# 3. Sofort fehlschlagender Befehl hinterlaesst KEINE Registrierung
# ---------------------------------------------------------------------------
echo "-- 3: ein sofort fehlschlagender Befehl registriert nichts --"
pane_run "HOME='$WORK/home3' '$TOOL' probe3 -- /nicht/vorhanden/programm-xyz"
[ "$RC" -ne 0 ] && ok "wb-nohup meldet den Fehlschlag ueber den Rueckgabewert ($RC)" || bad "wb-nohup meldete Erfolg trotz nicht existierendem Programm"
if [ -d "$WORK/home3/.local/state/wb-nohup/eigentuemer" ] && [ -n "$(ls -A "$WORK/home3/.local/state/wb-nohup/eigentuemer" 2>/dev/null)" ]; then
  bad "es wurde trotzdem eine Registrierung angelegt"
else
  ok "keine Registrierung fuer den fehlgeschlagenen Start"
fi

# ---------------------------------------------------------------------------
# 4. Ausserhalb eines tmux-Panes verweigert wb-nohup den Start
# ---------------------------------------------------------------------------
echo "-- 4: ausserhalb eines tmux-Panes wird verweigert --"
OHNE_TMUX_RC=0
env -u TMUX -u TMUX_PANE HOME="$WORK/home4" "$TOOL" probe4 -- /bin/sleep 5 >/dev/null 2>&1 || OHNE_TMUX_RC=$?
[ "$OHNE_TMUX_RC" -ne 0 ] && ok "wb-nohup verweigert ohne \$TMUX/\$TMUX_PANE (rc=$OHNE_TMUX_RC)" || bad "wb-nohup lief trotz fehlendem tmux-Kontext durch"
if [ -d "$WORK/home4" ]; then
  find "$WORK/home4" -name '*.json' 2>/dev/null | grep -q . \
    && bad "trotzdem eine Registrierung angelegt" \
    || ok "keine Registrierung ohne tmux-Kontext"
else
  ok "keine Registrierung ohne tmux-Kontext (Verzeichnis nie angelegt)"
fi

# ---------------------------------------------------------------------------
# 5. Zweite Eigentuemer-Art: ein launchd-Job statt eines Panes (2026-08-13),
#    mit den beiden Huerden aus dem Review (S6): Praefix agent-workbench. UND
#    Abstammung — die PID des Jobs muss ein Vorfahre des Aufrufs sein.
# ---------------------------------------------------------------------------
# Die lebende launchd-Domain wird hier NICHT mehr befragt. Frueher suchte
# dieser Fall sich ein beliebiges geladenes Label und schrieb damit genau das
# Verhalten als richtig fest, das der Review als Loch benannt hat. Stattdessen
# steht `launchctl` als Attrappe im PATH: geprueft wird die Logik von
# wb-nohup (Praefix, PID lesen, Abstammung), nicht der Zustand der Maschine.
STUBBIN="$WORK/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/launchctl" <<'EOF'
#!/bin/bash
# Attrappe: beantwortet nur `launchctl print gui/<uid>/<label>`.
# STUB_LABEL = das eine Label, das es "gibt"; STUB_PID = dessen PID
# (leer = geladen, laeuft aber nicht).
if [ "$1" = "print" ]; then
  case "$2" in
    */"${STUB_LABEL:-__keins__}")
      if [ -n "${STUB_PID:-}" ]; then
        printf '\tstate = running\n\tpid = %s\n' "$STUB_PID"
      else
        printf '\tstate = not running\n'
      fi
      exit 0 ;;
  esac
  echo "Could not find service \"$2\"" >&2
  exit 113
fi
exit 0
EOF
chmod +x "$STUBBIN/launchctl"

nohup_launchd() {   # nohup_launchd <home> <label> <stub-label> <stub-pid> <probe>
  OUT="$(env -u TMUX -u TMUX_PANE HOME="$1" PATH="$STUBBIN:$PATH" \
         STUB_LABEL="$3" STUB_PID="$4" \
         "$TOOL" "$5" --launchd "$2" -- "$WORK/home1/bin/sleeper" 2>&1)"
  RC=$?
}

echo "-- 5: ein eigener, laufender Job aus der eigenen Prozesskette wird Eigentuemer --"
mkdir -p "$WORK/home5"
nohup_launchd "$WORK/home5" agent-workbench.testjob agent-workbench.testjob "$$" probe5
PID5="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
[ -n "$PID5" ] && [ "$PID5" -gt 0 ] 2>/dev/null && EIGENE_PIDS[${#EIGENE_PIDS[@]}]="$PID5"
[ "$RC" -eq 0 ] && ok "wb-nohup laeuft ohne Pane durch, wenn der eigene launchd-Job Eigentuemer ist" \
                || bad "wb-nohup endete mit $RC: $OUT"
REGFILE5="$WORK/home5/.local/state/wb-nohup/eigentuemer/$PID5.json"
if [ -f "$REGFILE5" ]; then
  FELDER5="$(/usr/bin/python3 -c "
import json
d = json.load(open('$REGFILE5'))
print('%s|%s|%s' % (d.get('launchd_label'), d.get('pane'), d.get('worker')))
")"
  IFS='|' read -r F5_LABEL F5_PANE F5_WORKER <<< "$FELDER5"
  [ "$F5_LABEL" = "agent-workbench.testjob" ] && ok "launchd_label steht im Eintrag" || bad "launchd_label ist '$F5_LABEL'"
  [ -z "$F5_PANE" ] && ok "pane bleibt leer (es gibt keinen)" || bad "pane ist '$F5_PANE', muesste leer sein"
  [ "$F5_WORKER" = "launchd:agent-workbench.testjob" ] && ok "worker benennt den Job" || bad "worker ist '$F5_WORKER'"
else
  bad "keine Registrierungsdatei unter $REGFILE5"
fi

echo "-- 6: die vier Wege, auf denen ein Label abgelehnt wird --"
# 6a: fremdes Label (der gemessene Spoof aus dem Review)
nohup_launchd "$WORK/home6a" com.apple.Finder com.apple.Finder "$$" probe6a
[ "$RC" -ne 0 ] && ok "fremdes Label wird abgelehnt (rc=$RC)" || bad "com.apple.Finder wurde als Eigentuemer akzeptiert"
case "$OUT" in *"agent-workbench."*) ok "die Ablehnung nennt den Grund (nur eigene Jobs)" ;;
               *) bad "die Ablehnung nennt den Grund nicht: $OUT" ;; esac
# 6b: eigenes Label, aber launchd kennt es nicht
nohup_launchd "$WORK/home6b" agent-workbench.gibt-es-nicht agent-workbench.anderer "$$" probe6b
[ "$RC" -ne 0 ] && ok "unbekanntes Label wird abgelehnt (rc=$RC)" || bad "ein unbekanntes Label wurde akzeptiert"
# 6c: eigenes Label, geladen, laeuft aber nicht
nohup_launchd "$WORK/home6c" agent-workbench.testjob agent-workbench.testjob "" probe6c
[ "$RC" -ne 0 ] && ok "ein geladener, aber nicht laufender Job ist kein Eigentuemer (rc=$RC)" || bad "ein nicht laufender Job wurde akzeptiert"
# 6d: eigenes Label, laeuft — aber ausserhalb der eigenen Prozesskette
/bin/sleep 30 & FREMD_PID=$!
EIGENE_PIDS[${#EIGENE_PIDS[@]}]="$FREMD_PID"
nohup_launchd "$WORK/home6d" agent-workbench.testjob agent-workbench.testjob "$FREMD_PID" probe6d
[ "$RC" -ne 0 ] && ok "ein Job ausserhalb der eigenen Prozesskette wird abgelehnt (rc=$RC)" || bad "fremde Abstammung wurde akzeptiert"
case "$OUT" in *"Prozesskette"*) ok "die Ablehnung nennt die Abstammung" ;;
               *) bad "die Ablehnung nennt die Abstammung nicht: $OUT" ;; esac
kill "$FREMD_PID" 2>/dev/null; wait "$FREMD_PID" 2>/dev/null
for h in 6a 6b 6c 6d; do
  if find "$WORK/home$h" -name '*.json' 2>/dev/null | grep -q .; then
    bad "Fall $h hat trotz Ablehnung eine Registrierung angelegt"
  else
    ok "Fall $h hat keine Registrierung hinterlassen"
  fi
done

echo
echo "wb-nohup: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
