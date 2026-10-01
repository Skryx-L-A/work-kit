#!/usr/bin/env bash
# Tests fuer wb-worker-tab und wb-workers-window — die Strukturfehler der Nacht
# vom 03./04.08.2026, jeder einzeln nachgestellt.
#
# Alles laeuft auf einem EIGENEN Socket (Regel: Tests fassen die Live-Umgebung nie
# an), und jeder Aufruf der Werkzeuge geschieht aus einem Pane dieses Servers — nie
# aus der Test-Shell, die am Live-Server haengt. Muster: test-session-close.sh.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-worker-tab-$$"
# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override bleibt moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
TOOL="${WB_WORKER_TAB:-$REPO/wb-worker-tab}"
WORKERS_WINDOW="${WB_WORKERS_WINDOW:-$REPO/wb-workers-window}"
WORK="$(mktemp -d)"
pass=0; fail=0
echo "Geprueft: $TOOL, $WORKERS_WINDOW"

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
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

# Kommando in einem Pane des TESTSERVERS ausfuehren. Innerhalb des Panes zeigt
# $TMUX auf den Testsocket, das Werkzeug redet also mit dem Testserver.
pane_run() { # pane_run <session> <kommando> -> setzt OUT und RC
  local sess="$1" cmd="$2" f="$WORK/out.$RANDOM"
  tm send-keys -t "$sess:$WIN.$PANE" "{ $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 40 "pane_run: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

# Gibt es eine Session dieses Namens auf dem Testserver?
lives() { tm has-session -t "=$1" 2>/dev/null; }

echo "== wb-worker-tab =="
[ -x "$TOOL" ] || { echo "  FAIL  $TOOL fehlt oder ist nicht ausfuehrbar"; exit 1; }
tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp      # von hier werden die Werkzeuge aufgerufen
WIN="$(tm show-options -gv base-index 2>/dev/null || echo 0)"
PANE="$(tm show-window-options -gv pane-base-index 2>/dev/null || echo 0)"

# ── Fehler 1: `new-session -t <fehlende Basis>` legt eine Streu-Session an ─────
echo "-- Fehler 1: Sicht auf eine nicht existierende Basis --"
# Erst der BELEG, dass tmux hier wirklich nicht scheitert. Das ist die Annahme,
# auf der alle drei Reparaturen beruhen; wenn tmux sie eines Tages aendert, soll
# dieser Test es sagen und nicht die Werkzeuge stillschweigend uebergenau bleiben.
tm new-session -d -t '=wb-gibtsnicht-000000' -s 'wb-gibtsnicht-000000-view' 2>/dev/null
if lives 'wb-gibtsnicht-000000-view'; then
  belegte_gruppe="$(tm list-sessions -F '#{session_name}|#{session_group}' \
                    | awk -F'|' '$1=="wb-gibtsnicht-000000-view"{print $2}')"
  case "$belegte_gruppe" in
    =*) ok "Beleg: tmux legt eine Streu-Session an, Gruppe='$belegte_gruppe' (statt zu scheitern)" ;;
    *)  ok "Beleg: tmux legte eine Session an, Gruppe='$belegte_gruppe'" ;;
  esac
  tm kill-session -t '=wb-gibtsnicht-000000-view' 2>/dev/null
else
  ok "Beleg: dieses tmux scheitert bereits selbst (Reparatur bleibt trotzdem noetig)"
fi

# Das Werkzeug darf denselben Aufruf NICHT bauen: keine Basis, keine Sicht.
pane_run steuer "WB_WORKER_TAB_WAIT=1 $TOOL wb-tot-abc123 --no-attach"
lives 'wb-tot-abc123-view' \
  && bad "'wb-tot-abc123-view' wurde angelegt, obwohl es die Basis nicht gibt" \
  || ok "keine Sicht auf eine fehlende Basis angelegt"
case "$OUT" in
  *"keine laufende tmux-Session"*) ok "sagt verstaendlich, dass es keine Session gibt" ;;
  *) bad "keine verstaendliche Meldung (rc=$RC): $OUT" ;;
esac
# Und es bleibt ueberhaupt nichts Neues stehen.
tm list-sessions -F '#{session_name}' | grep -q '^wb-tot' \
  && bad "eine wb-tot-* Session ist entstanden" \
  || ok "keine Streu-Session hinterlassen"

# ── Fehler 4: gespeicherter Name tot, Ordner hat aber eine laufende Session ────
echo "-- Fehler 4: toter Sessionname, lebende Schwester desselben Ordners --"
tm new-session -d -s 'wb-AI-b310aa' -c /tmp
sleep 1
pane_run steuer "WB_WORKER_TAB_WAIT=1 $TOOL wb-AI-b310aa-e8d13f --no-attach"
# Exakte Zeile, nicht Teilzeichenkette: 'BASE=wb-AI-b310aa-e8d13f' enthaelt
# 'BASE=wb-AI-b310aa' und wuerde eine lockere Pruefung faelschlich bestehen.
printf '%s\n' "$OUT" | grep -qx 'BASE=wb-AI-b310aa' \
  && ok "faellt auf die neueste laufende Session des Ordners zurueck" \
  || bad "kein Rueckfall auf 'wb-AI-b310aa' (rc=$RC): $OUT"
lives 'wb-AI-b310aa-view' && ok "die Sicht haengt an der lebenden Basis" \
                          || bad "keine Sicht an der lebenden Basis"
lives 'wb-AI-b310aa-e8d13f-view' \
  && bad "trotzdem eine Sicht auf den toten Namen angelegt" \
  || ok "keine Sicht auf den toten Namen"

# ── Fehler 2: aus einer Sicht wird eine Sicht ─────────────────────────────────
echo "-- Fehler 2: Sicht auf eine Sicht ('-view-view') --"
pane_run steuer "WB_WORKER_TAB_WAIT=1 $TOOL wb-AI-b310aa-view --no-attach"
printf '%s\n' "$OUT" | grep -qx 'BASE=wb-AI-b310aa' \
  && ok "der Sichtname wurde auf die Basis normalisiert" \
  || bad "Sichtname nicht normalisiert (rc=$RC): $OUT"
lives 'wb-AI-b310aa-view-view' && bad "'-view-view' entstanden" \
                               || ok "kein '-view-view'"
# Auch dreifach geschachtelt, wie am 04.08. real vorgefunden.
pane_run steuer "WB_WORKER_TAB_WAIT=1 $TOOL wb-AI-b310aa-view-view --no-attach"
lives 'wb-AI-b310aa-view-view-view' && bad "'-view-view-view' entstanden" \
                                    || ok "auch eine dreifach geschachtelte Sicht wird normalisiert"

echo "-- wb-workers-window mit einem Sichtnamen --"
# Aufraeumen, damit dieser Fall unabhaengig davon urteilt, was die Faelle davor
# hinterlassen haben (bei der Gegenprobe gegen den alten Stand tun sie das).
tm kill-session -t '=wb-AI-b310aa-view-view-view' 2>/dev/null
tm kill-session -t '=wb-AI-b310aa-view-view' 2>/dev/null
pane_run steuer "$WORKERS_WINDOW wb-AI-b310aa-view"
lives 'wb-AI-b310aa-view-view' && bad "wb-workers-window hat '-view-view' gebaut" \
                               || ok "wb-workers-window arbeitet auf der Basis"
tm list-windows -t '=wb-AI-b310aa' -F '#{window_name}' | grep -qx workers \
  && ok "das workers-Fenster liegt in der Basis" || bad "kein workers-Fenster in der Basis"

# Sichtname, dessen Basis NICHT mehr existiert: nichts anlegen, nichts stapeln.
echo "-- wb-workers-window: Sicht ohne Basis --"
tm new-session -d -s 'wb-waise-111111' -c /tmp
tm new-session -d -t '=wb-waise-111111' -s 'wb-waise-111111-view'
tm kill-session -t '=wb-waise-111111'
pane_run steuer "$WORKERS_WINDOW wb-waise-111111-view"
lives 'wb-waise-111111-view-view' && bad "aus der verwaisten Sicht wurde eine weitere Sicht" \
                                  || ok "verwaiste Sicht erzeugt keine weitere Sicht"

# ── der Normalfall muss weiter funktionieren ─────────────────────────────────
echo "-- Normalfall --"
tm new-session -d -s 'wb-Normal-222222' -c /tmp
pane_run steuer "WB_WORKER_TAB_WAIT=5 $TOOL wb-Normal-222222 --no-attach"
lives 'wb-Normal-222222-view' && ok "Sicht fuer eine laufende Basis angelegt" \
                              || bad "keine Sicht fuer eine laufende Basis (rc=$RC): $OUT"
akt="$(tm list-windows -t '=wb-Normal-222222-view' -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1}')"
[ "$akt" = workers ] && ok "die Sicht steht auf dem workers-Fenster" \
                     || bad "die Sicht steht auf '$akt'"
grp="$(tm list-sessions -F '#{session_name}|#{session_group}' | awk -F'|' '$1=="wb-Normal-222222-view"{print $2}')"
case "$grp" in
  =*) bad "die Sicht haengt an der Zeichenkette '$grp'" ;;
  *)  ok "die Sicht haengt an der Session (Gruppe='$grp')" ;;
esac
# Zweiter Lauf: idempotent.
pane_run steuer "WB_WORKER_TAB_WAIT=5 $TOOL wb-Normal-222222 --no-attach"
lives 'wb-Normal-222222-view' && ok "zweiter Lauf laesst alles stehen" \
                              || bad "zweiter Lauf hat die Sicht zerstoert"

# ── --window: zweiter Worker-Tab (2026-08-04, diese Aufgabe) ──────────────────
echo "-- --window: ein existierendes Ueberlauf-Fenster wird wirklich angewaehlt --"
tm new-session -d -s 'wb-Zwei-333333' -c /tmp
tm new-window -t '=wb-Zwei-333333:' -n workers-2 'while :; do sleep 3600; done'
pane_run steuer "WB_WORKER_TAB_WAIT=5 $TOOL wb-Zwei-333333 --window workers-2 --no-attach"
akt="$(tm list-windows -t '=wb-Zwei-333333-view' -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1}')"
[ "$akt" = workers-2 ] && ok "die Sicht steht auf 'workers-2'" \
                       || bad "die Sicht steht auf '${akt:-?}', erwartet 'workers-2'"
tm list-windows -t '=wb-Zwei-333333' -F '#{window_name}' | grep -qx workers \
  && ok "das primaere 'workers'-Fenster existiert trotzdem (Gruppenschutz)" \
  || bad "'workers' fehlt — Gruppenschutz nicht gelaufen"

echo "-- --window: ein nicht existierendes Fenster wird sauber abgelehnt --"
pane_run steuer "WB_WORKER_TAB_WAIT=1 $TOOL wb-Zwei-333333 --window workers-9 --no-attach"
case "$OUT" in
  *"'workers-9' gibt es (noch) nicht"*) ok "sagt verstaendlich, dass 'workers-9' fehlt" ;;
  *) bad "keine verstaendliche Meldung (rc=$RC): $OUT" ;;
esac
akt="$(tm list-windows -t '=wb-Zwei-333333-view' -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1}')"
[ "$akt" = workers ] && ok "faellt auf 'workers' zurueck statt ins Leere zu zeigen" \
                      || bad "die Sicht steht auf '${akt:-?}', erwartet den Rueckfall auf 'workers'"
tm list-windows -t '=wb-Zwei-333333' -F '#{window_name}' | grep -qx workers-9 \
  && bad "'workers-9' wurde trotzdem angelegt" \
  || ok "'workers-9' wurde nicht angelegt — das ist wb-grids Job, nicht der des Tabs"

echo "-- --window: ein unerwarteter Fenstername wird abgelehnt --"
pane_run steuer "$TOOL wb-Zwei-333333 --window ../evil --no-attach"
[ "$RC" -ne 0 ] && ok "'--window ../evil' wird mit Fehler abgelehnt (rc=$RC)" \
                 || bad "'--window ../evil' lief ohne Fehler durch"

echo
echo "wb-worker-tab: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
