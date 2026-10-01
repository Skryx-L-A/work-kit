#!/usr/bin/env bash
# Tests fuer wb-grid's Kapazitaetsgrenze pro Worker-Tab (2026-08-04, des Nutzers
# Anforderung nach dem Layout-Fix vom selben Tag): "wenn ein Terminal-Tab zu
# klein wird fuer so viele Worker, dann darf der Orchestrator ein neues
# Terminal-Tab spawnen" -- workers, workers-2, workers-3, ..., ueber
# maxWorkerPanesPerTab (0 = unbegrenzt, alles in einen Tab).
#
# Punkt 1 (siehe Result-Datei dieser Aufgabe fuer die volle Messreihe): ein
# echter, wegwerfbarer `claude`-Prozess (nie ein Prompt gesendet, keine
# Tokenkosten) zeigte minWorkerPaneWidth=60 als zu niedrig -- bei einem
# realistischen Projektpfad braucht die EXAKTE Kontextanzeige mindestens 80
# Spalten, darunter degradiert sie zum reinen Balken (10%-Schritte) und unter
# ~52 verschwindet sie ganz. Default jetzt 80, gemessen, nicht geraten.
#
# Punkt 2/3 hier: ab maxWorkerPanesPerTab wird ein zweites Fenster angelegt,
# kein Pane faellt unter minWorkerPaneWidth, kein Pane geht verloren.
# Punkt 4: ein Pane im zweiten Fenster wird von context-guard --auto WIRKLICH
# ueberwacht -- der ECHTE context-guard laeuft einen Poll lang, keine
# Nachbildung seiner Logik.
#
# Alles auf EIGENEM Socket + eigenem HOME (Regel: Tests fassen die
# Live-Umgebung nie an). Muster: test-worker-grid-layout.sh (selbe Aufgabe,
# voriger Schritt).
unset TMUX TMUX_PANE
set -uo pipefail

# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override je Werkzeug bleibt
# moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WBGRID="${WB_GRID:-$REPO/wb-grid}"
WBSTATE="${WB_STATE:-$REPO/wb-state}"
WBWW="${WB_WORKERS_WINDOW:-$REPO/wb-workers-window}"
GUARD="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
for f in "$WBGRID" "$WBSTATE" "$WBWW" "$GUARD"; do
  [ -x "$f" ] || { echo "FAIL  $f fehlt oder ist nicht ausfuehrbar"; exit 1; }
done
echo "Geprueft: wb-grid=$WBGRID wb-state=$WBSTATE wb-workers-window=$WBWW context-guard=$GUARD"

# Kennzeichen dieses Laufs (siehe test-context-guard-live-socket-unberuehrt.sh):
# haengt an Socket-, TESTHOME- und Worker-Namen, wenn LIVE_MARKER gesetzt ist --
# leer und ohne Wirkung, wenn diese Suite einzeln laeuft. Das TESTHOME-Kennzeichen
# ist noetig, weil diese Suite context-guard in einen mktemp-Pfad KOPIERT (Zeile
# unten) -- ein geleaktes context-guard traegt dann keinen Repo-Pfad.
MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-tabcap$MARK-$$"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-tabcap${MARK}.XXXXXX")"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
WFIRST="w-first$MARK"; WSECOND="w-second$MARK"
pass=0; fail=0

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
    tm kill-server 2>/dev/null
    sleep 0.3
  done
  tm list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench"
cp "$WBGRID" "$TESTHOME/.local/bin/wb-grid"
cp "$WBSTATE" "$TESTHOME/.local/bin/wb-state"
cp "$WBWW" "$TESTHOME/.local/bin/wb-workers-window"
cp "$GUARD" "$TESTHOME/.local/bin/context-guard"
chmod +x "$TESTHOME/.local/bin/"*
export HOME="$TESTHOME"

# Anker-Session, die den ganzen Lauf ueber lebt: jeder Testblock unten legt
# seine eigene SESS/SESS2/SESS3 an und killt sie am Blockende wieder -- ohne
# diesen Anker waere sie dabei zeitweise die EINZIGE Session auf $SOCKET, und
# ohne geladene ~/.tmux.conf steht `exit-empty` auf seinem Default (on). Die
# letzte Session zu killen wuerde dann den Server gleich mitbeenden, mit
# demselben SIGHUP-Race wie bei `kill-server` (siehe tmux_socket_beenden_ohne_reste).
tm new-session -d -s anker -c /tmp >/dev/null 2>&1

READABLE_MIN=52
WIDTH=197; HEIGHT=54

run_grid_in_pane() {
  local orch="$1"
  local done_flag="$TESTHOME/done-$RANDOM"
  tm send-keys -t "$orch" "$TESTHOME/.local/bin/wb-grid $orch >>'$TESTHOME/grid.out' 2>>'$TESTHOME/grid.err'; touch '$done_flag'" Enter
  warte_auf_datei "$done_flag" 15 "wb-grid $orch" "$TESTHOME/grid.out"
}

echo "== Punkt 2/3: ein Fenster je Worker, keiner geht verloren, keiner wird zu schmal =="
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
MAXPT="$("$TESTHOME/.local/bin/wb-state" settings get maxWorkerPanesPerTab)"
MINW="$("$TESTHOME/.local/bin/wb-state" settings get minWorkerPaneWidth)"
echo "  (maxWorkerPanesPerTab=$MAXPT minWorkerPaneWidth=$MINW, aus den Defaults gelesen)"

N=10
SESS="wb-tabcap-$$"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
tmux_live_hooks_kappen "$SOCKET"   # sonst konkurriert das echte wb-grid mit dem hier geprueften
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator

i=1
while [ "$i" -le "$N" ]; do
  WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}' 2>>"$TESTHOME/grid.err")
  [ -n "$WP" ] || { i=$((i+1)); continue; }
  tm set -p -t "$WP" @wb_role worker
  tm set -p -t "$WP" @wb_worker "w$i"
  run_grid_in_pane "$ORCH"
  i=$((i+1))
done

# EIN FENSTER JE WORKER (umgestellt 03.09.2026, Stufe A). Bis dahin war die
# erwartete Fensterzahl `ceil(N / maxWorkerPanesPerTab)` -- die Einstellung
# entschied, wieviele Panes sich ein tmux-Fenster teilen. Sie entscheidet das
# nicht mehr: seither zaehlt sie Kacheln je Tab der ANWENDUNG (dort weiter
# geprueft, app/src/main/capacity.ts), und tmux bekommt genau einen Pane je
# Fenster. Der Grund steht im Kopf von shell/wb-grid; die Zusagen darunter --
# kein Worker verloren, keiner unter der lesbaren Breite -- sind unveraendert
# und pruefen jetzt erst recht, weil jeder Pane die volle Fensterbreite hat.
expected_windows=$N
tabwindows=$(tm list-windows -t "=$SESS" -F '#{window_name}' 2>/dev/null | grep -E '^workers(-[0-9]+)?$' | wc -l | tr -d ' ')
if [ "$tabwindows" -eq "$expected_windows" ]; then
  ok "N=$N Worker ergeben $tabwindows Fenster -- eines je Worker"
else
  bad "N=$N Worker ergeben $tabwindows Fenster, erwartet $expected_windows (eines je Worker)"
fi
mehrfach=""
while IFS='|' read -r wid wname; do
  case "$wname" in workers|workers-[0-9]*) ;; *) continue ;; esac
  c=$(tm list-panes -t "$wid" -F '#{@wb_role}' 2>/dev/null | awk '$1!="placeholder"' | grep -c . || true)
  [ "$c" -gt 1 ] && mehrfach="$mehrfach $wname($c)"
done < <(tm list-windows -t "=$SESS" -F '#{window_id}|#{window_name}' 2>/dev/null)
if [ -z "$mehrfach" ]; then
  ok "kein Fenster traegt mehr als einen Worker"
else
  bad "mehr als ein Worker je Fenster:$mehrfach"
fi

total_real=$(tm list-panes -a -F '#{session_name} #{window_name} #{@wb_role}' 2>/dev/null \
  | awk -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="worker"' | wc -l | tr -d ' ')
if [ "$total_real" -eq "$N" ]; then
  ok "alle $N Worker stecken in einem workers*-Fenster (keiner verloren)"
else
  bad "nur $total_real von $N Workern in einem workers*-Fenster -- Rest verschollen"
fi

minw=""
while read -r w; do
  [ -z "$w" ] && continue
  if [ -z "$minw" ] || [ "$w" -lt "$minw" ]; then minw=$w; fi
done < <(tm list-panes -a -F '#{session_name} #{window_name} #{@wb_role} #{pane_width}' 2>/dev/null \
  | awk -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="worker"{print $4}')
if [ -n "$minw" ] && [ "$minw" -ge "$MINW" ]; then
  ok "schmalste Worker-Pane ${minw} Spalten (>= minWorkerPaneWidth=${MINW})"
else
  bad "schmalste Worker-Pane ${minw:-?} Spalten -- unter minWorkerPaneWidth=${MINW}"
fi
if [ -n "$minw" ] && [ "$minw" -ge "$READABLE_MIN" ]; then
  ok "schmalste Worker-Pane bleibt oberhalb der harten Lesbarkeitsgrenze (${READABLE_MIN})"
else
  bad "schmalste Worker-Pane ${minw:-?} unter der harten Lesbarkeitsgrenze ${READABLE_MIN}"
fi

if [ -s "$TESTHOME/grid.err" ] && grep -q "WARNUNG.*unter minWorkerPaneWidth" "$TESTHOME/grid.err"; then
  bad "wb-grid warnte ueber zu schmale Panes: $(grep -c WARNUNG "$TESTHOME/grid.err") mal"
else
  ok "keine Breiten-Warnung noetig -- ein Pane allein in seinem Fenster hat dessen volle Breite"
fi
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Punkt 2: maxWorkerPanesPerTab hat auf die tmux-Fenster keine Wirkung mehr =="
"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 0 >/dev/null 2>&1
SESS2="wb-tabcap0-$$"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS2" -n main >/dev/null 2>&1
ORCH2=$(tm list-panes -t "=$SESS2" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH2" @wb_role orchestrator
i=1
while [ "$i" -le 5 ]; do
  WP=$(tm split-window -t "$ORCH2" -P -F '#{pane_id}')
  tm set -p -t "$WP" @wb_role worker
  run_grid_in_pane "$ORCH2"
  i=$((i+1))
done
# GEDREHT (03.09.2026, Stufe A). Vorher stand hier die Zusage, dass
# `maxWorkerPanesPerTab=0` alle Worker in EIN Fenster legt -- des Nutzers
# ausdrueckliche Wahl fuer "ich nehme das Gedraenge in Kauf". Das Gedraenge gibt
# es nicht mehr zu waehlen: ein Fenster mit mehreren Panes ist genau der
# Zustand, den Stufe A aufloest (tmux gaebe dann wieder die Form vor und liesse
# 7,1 % der Buehne als Zellrand stehen). Wer die Worker zusammen in einem
# Fenster sehen will, hat dafuer weiterhin `workerLayout: split`. Geprueft wird
# deshalb das Gegenteil: die Einstellung aendert an den Fenstern NICHTS.
tabwindows2=$(tm list-windows -t "=$SESS2" -F '#{window_name}' 2>/dev/null | grep -cE '^workers(-[0-9]+)?$' || true)
if [ "$tabwindows2" = "5" ]; then
  ok "maxWorkerPanesPerTab=0 aendert nichts: fuenf Worker, fuenf Fenster"
else
  bad "fuenf Worker ergaben ${tabwindows2} workers*-Fenster (erwartet 5)"
fi
tm kill-session -t "=$SESS2" >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 1 >/dev/null 2>&1

echo
echo "== Punkt 4: ein Pane im zweiten Fenster wird bewacht und beschrieben =="
SESS3="wb-tabcap-guard$MARK-$$"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS3" -n main >/dev/null 2>&1
ORCH3=$(tm list-panes -t "=$SESS3" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH3" @wb_role orchestrator
W1=$(tm split-window -t "$ORCH3" -P -F '#{pane_id}')
tm set -p -t "$W1" @wb_role worker; tm set -p -t "$W1" @wb_worker "$WFIRST"
run_grid_in_pane "$ORCH3"
W2=$(tm split-window -t "$ORCH3" -P -F '#{pane_id}')
tm set -p -t "$W2" @wb_role worker; tm set -p -t "$W2" @wb_worker "$WSECOND"
run_grid_in_pane "$ORCH3"

w2win=$(tm list-panes -a -F '#{session_name} #{pane_id} #{window_name}' 2>/dev/null \
  | awk -v s="$SESS3" -v p="$W2" '$1==s && $2==p{print $3}')
if [ "$w2win" = "workers-2" ]; then
  ok "der zweite Worker landet in seinem eigenen Fenster 'workers-2'"
else
  bad "zweiter Worker landet in '${w2win:-?}', erwartet 'workers-2'"
fi

# Statuszeile ueber der Warnschwelle, damit der ECHTE context-guard sichtbar reagiert.
tm send-keys -t "$W2" "clear; printf 'conversation\\n Sonnet xhigh . proj main . ▓▓▓▓▓▓▓▓▓░ 990k/1.0M . 5h 1%%\\n ⏵⏵ bypass permissions on\\n'" Enter
sleep 1

GLOG="$TESTHOME/guard.log"
tm send-keys -t "$ORCH3" "PROJECT='$TESTHOME' WARN_PCT=80 timeout 20 $TESTHOME/.local/bin/context-guard --auto $ORCH3 > '$GLOG' 2>&1" Enter
warte_auf_bedingung 15 "'$WSECOND' erscheint im Guard-Log" "grep -qF '$WSECOND' '$GLOG' 2>/dev/null" "$GLOG"
tm send-keys -t "$ORCH3" C-c Enter

if grep -q "$WSECOND ($W2) at [0-9]*% -> handoff requested" "$GLOG" 2>/dev/null; then
  ok "context-guard --auto entdeckt UND liest den Pane in 'workers-2' korrekt (99% erkannt, Handoff angefragt)"
elif grep -q "$WSECOND ($W2).*BLIND" "$GLOG" 2>/dev/null; then
  bad "context-guard entdeckte den Pane in 'workers-2', konnte ihn aber nicht lesen (BLIND)"
else
  bad "context-guard --auto hat den Pane in 'workers-2' gar nicht entdeckt/erwaehnt -- Log: $(cat "$GLOG" 2>/dev/null | tr '\n' ' ')"
fi
# DER FREIGABE-RUECKKANAL (ergaenzt 03.09.2026, Stufe A). `wb-pane-write` ist
# die eine Stelle, die entscheidet, wer in einen Pane tippen darf -- ueber sie
# laufen die Freigaben und die Kontextwache. Sie loest den Pane ueber die
# Pane-Option @wb_role auf, nicht ueber sein Fenster; dass jeder Worker jetzt in
# einem eigenen Fenster sitzt, darf daran also nichts aendern. Gemessen statt
# angenommen, und zwar an dem Pane, der am weitesten vom Orchestrator entfernt
# liegt: dem in 'workers-2'.
if HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$TESTHOME/.local/bin/wb-pane-write" darf "$W2" >/dev/null 2>&1; then
  ok "wb-pane-write erlaubt das Schreiben in den Worker-Pane in 'workers-2'"
else
  bad "wb-pane-write verweigert den Worker-Pane in 'workers-2' -- der Freigabe-Rueckkanal ist unterbrochen"
fi
MARKE_SCHREIB="freigabe-$MARK-$$"
printf 'echo %s\n' "$MARKE_SCHREIB" \
  | HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$TESTHOME/.local/bin/wb-pane-write" tippen "$W2" >/dev/null 2>&1
warte_auf_bedingung 10 "die geschriebene Marke erscheint im Pane" \
  "tm capture-pane -p -t '$W2' 2>/dev/null | grep -qF '$MARKE_SCHREIB'" ""
if tm capture-pane -p -t "$W2" 2>/dev/null | grep -qF "$MARKE_SCHREIB"; then
  ok "der geschriebene Text steht wirklich im Pane in 'workers-2'"
else
  bad "der geschriebene Text kam im Pane in 'workers-2' nicht an"
fi
# Die Gegenprobe: der ORCHESTRATOR-Pane bleibt zu. Ohne sie belegte der Test nur,
# dass wb-pane-write ueberhaupt schreibt, nicht dass es noch unterscheidet.
if HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$TESTHOME/.local/bin/wb-pane-write" darf "$ORCH3" >/dev/null 2>&1; then
  bad "wb-pane-write laesst in den Orchestrator-Pane schreiben -- die Regel vom 06.08. haelt nicht mehr"
else
  ok "wb-pane-write verweigert den Orchestrator-Pane weiterhin (fail-closed)"
fi
tm kill-session -t "=$SESS3" >/dev/null 2>&1

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
