#!/bin/bash
# Prueft wb-workers-window auf EIGENEM Socket: legt es die fehlende View-Session an
# und zeigt sie danach auf das workers-Fenster?
unset TMUX TMUX_PANE
set -uo pipefail
# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override bleibt moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
TOOL="${WB_WORKERS_WINDOW:-$REPO/wb-workers-window}"
WORK="$(mktemp -d)"
pass=0; fail=0
echo "Geprueft: $TOOL"
ok()  { pass=$((pass+1)); echo "  ok    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "wbtest-ww"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L wbtest-ww list-sessions >/dev/null 2>&1; do
    tmux -L wbtest-ww kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L wbtest-ww list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket 'wbtest-ww' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/wbtest-ww" "/tmp/tmux-$(id -u)/wbtest-ww"
  rm -rf "$WORK"
}
trap cleanup EXIT

tmux -L wbtest-ww kill-server 2>/dev/null
tmux -L wbtest-ww new-session -d -s wb-probe -c /tmp
export TMUX_TMPDIR=""   # nur zur Sicherheit; das Werkzeug redet ueber $TMUX/Default-Socket
# Den Pane ABFRAGEN statt 'wb-probe:1.1' zu raten: der Index haengt an
# base-index/pane-base-index aus der geerbten ~/.tmux.conf. Auf dem Mac steht dort
# 1, auf host2 nicht — dort hiess der einzige Pane 0.0 und jedes send-keys endete
# mit "can't find window: 1", also ohne einen einzigen Aufruf des Prueflings.
PROBE_PANE="$(tmux -L wbtest-ww list-panes -t '=wb-probe' -F '#{pane_id}' | head -1)"

# Das Werkzeug spricht den DEFAULT-Socket an — deshalb wird es hier ueber einen
# Pane des Testservers aufgerufen, dort zeigt $TMUX auf den Testsocket.
run() {
  local f="$WORK/ww.$RANDOM"
  tmux -L wbtest-ww send-keys -t "$PROBE_PANE" "$TOOL wb-probe > $f 2>&1; touch $f.done" Enter
  warte_auf_datei "$f.done" 15 "wb-workers-window wb-probe" "$f"
  cat "$f" 2>/dev/null; rm -f "$f" "$f.done"
}

# Wie run(), aber mit weiteren Argumenten und mit dem Rueckgabewert -- den
# braucht die Regression weiter unten, die auf eine ABLEHNUNG prueft.
run_args() {   # <weitere argumente...> -> setzt OUT und RC
  local f="$WORK/ww.$RANDOM"
  tmux -L wbtest-ww send-keys -t "$PROBE_PANE" \
    "$TOOL wb-probe $* > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  warte_auf_datei "$f.done" 15 "wb-workers-window wb-probe $*" "$f"
  OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
  RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  rm -f "$f" "$f.done"
}

run >/dev/null
sleep 1
tmux -L wbtest-ww list-windows -t '=wb-probe' -F '#{window_name}' | grep -qx workers \
  && ok "workers-Fenster angelegt" || bad "kein workers-Fenster"
tmux -L wbtest-ww has-session -t '=wb-probe-view' 2>/dev/null \
  && ok "View-Session angelegt" || bad "View-Session fehlt (genau der Fall vom 04.08.)"
act=$(tmux -L wbtest-ww list-windows -t '=wb-probe-view' -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1}')
[ "$act" = workers ] && ok "View zeigt auf das workers-Fenster" || bad "View zeigt auf '$act'"

# Zweiter Lauf: idempotent, nichts kaputt
run >/dev/null
tmux -L wbtest-ww has-session -t '=wb-probe-view' 2>/dev/null \
  && ok "zweiter Lauf laesst alles stehen" || bad "zweiter Lauf hat etwas zerstoert"

# --- Regression 05.09.2026: ein Fenstername, der mit '-' anfaengt --------------
# Gemessener Vorfall: `wb-workers-window wb-companion-299862 --no-attach` (eine
# Verwechslung mit wb-worker-tab) hat das neue Fenster zwar richtig benannt, aber
# jedes spaetere `-t "=<session>:--no-attach"` loeste tmux als VERSATZ zum
# aktuellen Fenster auf -- und 0 Fenster weiter ist das aktuelle. Rolle
# 'placeholder', Pane-Titel 'noch keine Worker' und `automatic-rename off` landeten
# damit auf dem Claude-Pane des Orchestrators, und die Werkbank fand danach kein
# Orchestrator-Pane mehr.
fenster_vorher="$(tmux -L wbtest-ww list-windows -t '=wb-probe' -F '#{window_id}' | wc -l | tr -d ' ')"
auto_vorher="$(tmux -L wbtest-ww display -p -t "$PROBE_PANE" '#{automatic-rename}')"

run_args --no-attach
[ "$RC" = 2 ] && ok "'--no-attach' als Fenstername wird abgelehnt (RC=2)" \
              || bad "'--no-attach' als Fenstername ergab RC=$RC statt 2 -- Ausgabe: $OUT"

fenster_nachher="$(tmux -L wbtest-ww list-windows -t '=wb-probe' -F '#{window_id}' | wc -l | tr -d ' ')"
[ "$fenster_nachher" = "$fenster_vorher" ] \
  && ok "kein Fenster '--no-attach' angelegt" \
  || bad "es sind Fenster entstanden ($fenster_vorher -> $fenster_nachher)"

rolle="$(tmux -L wbtest-ww display -p -t "$PROBE_PANE" '#{@wb_role}')"
[ -z "$rolle" ] && ok "das erste Pane behaelt seine Rolle (leer)" \
                || bad "das erste Pane traegt jetzt '$rolle' -- genau der Vorfall vom 05.09."

titel="$(tmux -L wbtest-ww display -p -t "$PROBE_PANE" '#{pane_title}')"
[ "$titel" != 'noch keine Worker' ] && ok "das erste Pane behaelt seinen Titel" \
                                    || bad "das erste Pane heisst jetzt 'noch keine Worker'"

auto_nachher="$(tmux -L wbtest-ww display -p -t "$PROBE_PANE" '#{automatic-rename}')"
[ "$auto_nachher" = "$auto_vorher" ] \
  && ok "automatic-rename des ersten Fensters unveraendert" \
  || bad "automatic-rename des ersten Fensters ging von $auto_vorher auf $auto_nachher"

# Gegenprobe: der Vertrag selbst bleibt benutzbar -- ein Ueberlauf-Fenster
# entsteht weiterhin, und sein Platzhalter traegt die Rolle.
run_args workers-2
[ "$RC" = 0 ] && ok "'workers-2' wird weiterhin angelegt (RC=0)" \
              || bad "'workers-2' ergab RC=$RC -- Ausgabe: $OUT"
ph="$(tmux -L wbtest-ww list-panes -t '=wb-probe' -s \
      -F '#{window_name}|#{pane_id}|#{@wb_role}' 2>/dev/null | awk -F'|' '$1=="workers-2"{print $3}')"
[ "$ph" = placeholder ] && ok "der Platzhalter in 'workers-2' traegt seine Rolle" \
                        || bad "der Platzhalter in 'workers-2' traegt '$ph' statt 'placeholder'"

echo "wb-workers-window: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
