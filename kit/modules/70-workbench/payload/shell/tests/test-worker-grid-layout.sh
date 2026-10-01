#!/usr/bin/env bash
# Tests fuer wb-grid's Flaechen-/Lesbarkeits-Garantie im Fenster 'workers'
# (workerLayout: window) -- Befund des Nutzers vom 2026-08-04: "es sind drei
# Worker da, aber nur drei Viertel des Bildschirms ausgefuellt". Gemessen
# (scratchpad, siehe Result-Datei dieser Aufgabe): tmux' eigenes
# `select-layout tiled` stapelt 2 Panes volle Breite/halbe Hoehe statt sie
# nebeneinanderzusetzen, obwohl beide nebeneinander bequem ueber
# minWorkerPaneWidth UND auf voller Fensterhoehe blieben -- reproduzierbar mit
# purem tmux, ohne wb-grid. Und: die Lesbarkeits-Pruefung filterte nach
# @wb_role=="worker", also blind fuer jeden Pane mit falscher oder fehlender
# Rolle (host2's orch-launch markiert JEDEN gestarteten Pane @wb_role
# orchestrator, auch reine Worker, siehe regeln/maschinen.md).
#
# Alles laeuft auf einem EIGENEN Socket + eigenem HOME (Regel: Tests fassen
# die Live-Umgebung nie an -- wb-grid liest workerLayout/minWorkerPaneWidth
# aus $HOME/.claude/workbench/settings.json). Muster: test-worker-tab.sh.
unset TMUX TMUX_PANE
set -uo pipefail

# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override je Werkzeug bleibt
# moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
WBGRID_SRC="${WB_GRID:-$REPO/wb-grid}"
WBSTATE_SRC="${WB_STATE:-$REPO/wb-state}"
WBWW_SRC="${WB_WORKERS_WINDOW:-$REPO/wb-workers-window}"
for f in "$WBGRID_SRC" "$WBSTATE_SRC" "$WBWW_SRC"; do
  [ -x "$f" ] || { echo "FAIL  $f fehlt oder ist nicht ausfuehrbar"; exit 1; }
done
echo "Geprueft: wb-grid=$WBGRID_SRC wb-state=$WBSTATE_SRC wb-workers-window=$WBWW_SRC"

SOCKET="wbtest-gridlayout-$$"
TESTHOME="$(mktemp -d)"
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
cp "$WBGRID_SRC" "$TESTHOME/.local/bin/wb-grid"
cp "$WBSTATE_SRC" "$TESTHOME/.local/bin/wb-state"
cp "$WBWW_SRC" "$TESTHOME/.local/bin/wb-workers-window"
chmod +x "$TESTHOME/.local/bin/"*
export HOME="$TESTHOME"

# Anker-Session, die den ganzen Lauf ueber lebt: jeder Testblock unten legt
# seine eigene $SESS an und killt sie am Blockende wieder -- ohne diesen Anker
# waere $SESS dabei zeitweise die EINZIGE Session auf $SOCKET, und ohne
# geladene ~/.tmux.conf steht `exit-empty` auf seinem Default (on). Die letzte
# Session zu killen wuerde dann den Server gleich mitbeenden, mit demselben
# SIGHUP-Race wie bei `kill-server` (siehe tmux_socket_beenden_ohne_reste).
tm new-session -d -s anker -c /tmp >/dev/null 2>&1

READABLE_MIN=52   # gemessene Statuszeilen-Abschneidegrenze, regeln/kontext-guard.md

run_grid_in_pane() { # run_grid_in_pane <orch-pane> -> blocks until done
  local orch="$1" out="$2" err="$3"
  local done_flag="$TESTHOME/done-$RANDOM"
  tm send-keys -t "$orch" "$TESTHOME/.local/bin/wb-grid $orch >>'$out' 2>>'$err'; touch '$done_flag'" Enter
  warte_auf_datei "$done_flag" 15 "wb-grid $orch" "$out"
}

echo "== Punkt 3: Flaeche/Lesbarkeit/Vorhersagbarkeit, N=1..8, workerLayout=window =="
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
# This test is about single-window tiling/coverage/shape (Punkt 1-3 of the
# 20260804-030841 task), not the tab-capacity feature added later the same
# day (20260804-033646, shell/tests/test-worker-tab-capacity.sh) -- pin
# capacity to unlimited so a real default change there can never silently
# make N workers split across workers/workers-2 look like "lost" panes here.
"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 0 >/dev/null 2>&1

WIDTH=197; HEIGHT=54; MINW=80   # matches wb-grid's actual default (2026-08-04, report 20260804-033646.md)
for N in 1 2 3 4 5 6 7 8; do
  SESS="wb-gridtest-$$-n$N"
  tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
  tmux_live_hooks_kappen "$SOCKET"   # sonst konkurriert das echte wb-grid mit dem hier geprueften
  ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
  tm set -p -t "$ORCH" @wb_role orchestrator
  SIDE=$(tm split-window -t "$ORCH" -h -b -l 28 -P -F '#{pane_id}' 2>/dev/null)
  [ -n "$SIDE" ] && tm set -p -t "$SIDE" @wb_role sidebar
  ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id} #{@wb_role}' | awk '$2=="orchestrator"{print $1; exit}')

  OUT="$TESTHOME/out-n$N.log"; ERR="$TESTHOME/err-n$N.log"; : >"$OUT"; : >"$ERR"
  # Realer Spawn: split-window trifft die Orchestrator-Pane, danach feuert der
  # after-split-window-Hook wb-grid EINMAL PRO Split -- nicht erst am Ende.
  i=1
  while [ "$i" -le "$N" ]; do
    WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}' 2>>"$ERR")
    [ -n "$WP" ] || { i=$((i+1)); continue; }
    tm set -p -t "$WP" @wb_role worker
    run_grid_in_pane "$ORCH" "$OUT" "$ERR" || echo "TIMEOUT n=$N i=$i" >>"$ERR"
    i=$((i+1))
  done

  wwin=$(tm list-windows -t "=$SESS" -F '#{window_id} #{window_name}' 2>/dev/null | awk '$2=="workers"{print $1; exit}')
  if [ -z "$wwin" ]; then
    bad "N=$N: kein Fenster 'workers' entstanden"
    tm kill-session -t "=$SESS" >/dev/null 2>&1
    continue
  fi

  # GEZAEHLT WIRD UEBER ALLE workers*-FENSTER, nicht mehr im einen Fenster
  # 'workers' (umgestellt 03.09.2026, Stufe A). Seither bekommt jeder Worker
  # sein eigenes Fenster; ein Pane in 'workers-3' ist kein verschollener Pane
  # mehr, sondern der Normalfall. Die Zusage dahinter ist unveraendert: KEIN
  # Worker geht verloren, KEINER faellt unter die lesbare Breite, und die
  # Flaeche ist gefuellt.
  minw=""; minh=""; sumarea=0; cnt=0; winarea=0; mehrfach=""
  while IFS='|' read -r wid wname; do
    case "$wname" in workers|workers-[0-9]*) ;; *) continue ;; esac
    read -r ww wh < <(tm display -p -t "$wid" '#{window_width} #{window_height}' 2>/dev/null)
    imfenster=0
    while IFS='|' read -r pid role pw ph; do
      [ -z "$pid" ] && continue
      [ "$role" = "placeholder" ] && continue
      cnt=$((cnt+1)); imfenster=$((imfenster+1)); sumarea=$((sumarea + pw*ph))
      if [ -z "$minw" ] || [ "$pw" -lt "$minw" ]; then minw=$pw; fi
      if [ -z "$minh" ] || [ "$ph" -lt "$minh" ]; then minh=$ph; fi
    done < <(tm list-panes -t "$wid" -F '#{pane_id}|#{@wb_role}|#{pane_width}|#{pane_height}' 2>/dev/null)
    [ "$imfenster" -gt 0 ] && winarea=$((winarea + ww*wh))
    [ "$imfenster" -gt 1 ] && mehrfach="$mehrfach $wname($imfenster)"
  done < <(tm list-windows -t "=$SESS" -F '#{window_id}|#{window_name}' 2>/dev/null)

  coverage_pct=$(( sumarea * 1000 / (winarea>0?winarea:1) ))   # 1 Dezimale, *10

  # 1) alle N Worker sind in einem Worker-Fenster gelandet, und zwar jeder in
  #    seinem eigenen
  if [ "$cnt" -eq "$N" ]; then ok "N=$N: $cnt/$N Worker in einem workers*-Fenster"; else bad "N=$N: nur $cnt/$N Worker in einem workers*-Fenster -- Rest verschollen"; fi
  if [ -z "$mehrfach" ]; then ok "N=$N: jedes Fenster traegt genau einen Worker"; else bad "N=$N: mehr als ein Worker je Fenster:$mehrfach"; fi

  # 2) Flaeche praktisch vollstaendig gefuellt (Panes + Border-Zeilen/-Spalten
  #    erklaeren den Rest; unter 90% ist ein echtes Loch, kein Rundungsfehler)
  if [ "$coverage_pct" -ge 900 ]; then
    ok "N=$N: Deckungsgrad $(( coverage_pct/10 )).$(( coverage_pct%10 ))% (>=90%)"
  else
    bad "N=$N: Deckungsgrad nur $(( coverage_pct/10 )).$(( coverage_pct%10 ))% -- Flaeche NICHT vollstaendig gefuellt"
  fi

  # 3) kein Pane unter der lesbaren Breite (Statuszeile schneidet ab ~52 Spalten)
  if [ -n "$minw" ] && [ "$minw" -ge "$READABLE_MIN" ]; then
    ok "N=$N: schmalste Pane-Breite ${minw} Spalten (>= ${READABLE_MIN}, lesbar)"
  else
    bad "N=$N: schmalste Pane-Breite ${minw:-?} Spalten -- unter ${READABLE_MIN}, Statuszeile schneidet ab"
  fi

  # 4) Vorhersagbarkeit: passen alle N Worker bei minWorkerPaneWidth NEBENEINANDER
  #    in die Fensterbreite (cols_moeglich >= N), dann darf wb-grid sie NICHT
  #    unnoetig UEBEREINANDER stapeln (halbe Fensterhoehe) -- das ist exakt
  #    des Nutzers "mehrere sind sehr duenn uebereinander", reproduziert mit
  #    purem tmux `select-layout tiled` auf dieser Fenstergeometrie.
  # 4) Vorhersagbarkeit. Sie hat mit Stufe A ihren Ort gewechselt: die FORM
  #    liegt nicht mehr bei tmux, sondern bei der Werkbank (geprueft in
  #    shell/tests/test-app-worker-fenster.sh, dort an der wirklich gezeichneten
  #    Buehne). Was hier bleibt, ist die Zusage an tmux: ein Fenster mit einem
  #    Pane gibt ihm seine ganze Flaeche -- keine Trennlinie, kein Stapeln, kein
  #    halbes Fenster. Genau das war Befund des Nutzers vom 04.08. ("mehrere sind
  #    sehr duenn uebereinander"), und hier faellt er strukturell weg.
  if [ -n "$minh" ] && [ "$minh" -ge $((HEIGHT-3)) ]; then
    ok "N=$N: jeder Pane nutzt die volle Hoehe seines Fensters (${minh}/${HEIGHT})"
  else
    bad "N=$N: ein Pane steht auf ${minh:-?}/${HEIGHT} Zeilen, obwohl er allein in seinem Fenster liegt"
  fi

  tm kill-session -t "=$SESS" >/dev/null 2>&1
done

echo "== Punkt 4: Pane mit falscher/fehlender @wb_role wird bei der Lesbarkeits-Warnung mitgezaehlt =="
# host2's orch-launch markiert laut regeln/maschinen.md JEDEN gestarteten Pane
# @wb_role orchestrator, auch reine Worker. minWorkerPaneWidth extrem hoch
# gesetzt (200) macht den Trigger unabhaengig von der tatsaechlichen
# Geometrie: JEDER echte Pane ist garantiert schmaler als 200, die Warnung
# feuert so oder so -- die Frage ist NUR, ob sie den mistagged Pane mitzaehlt.
"$TESTHOME/.local/bin/wb-state" settings set minWorkerPaneWidth 200 >/dev/null 2>&1
SESS="wb-gridtest-$$-role"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}')
tm set -p -t "$ORCH" @wb_role orchestrator
OUT="$TESTHOME/out-role.log"; ERR="$TESTHOME/err-role.log"; : >"$OUT"; : >"$ERR"

W1=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
tm set -p -t "$W1" @wb_role worker
run_grid_in_pane "$ORCH" "$OUT" "$ERR"
W2=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
tm set -p -t "$W2" @wb_role worker
run_grid_in_pane "$ORCH" "$OUT" "$ERR"
W3=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
tm set -p -t "$W3" @wb_role orchestrator   # der host2-orch-launch-Fehltag
run_grid_in_pane "$ORCH" "$OUT" "$ERR"

# GEZAEHLT WIRD JETZT UEBER DIE FENSTER (03.09.2026, Stufe A). Vorher sassen
# alle drei Panes in EINEM Fenster, und die Warnung nannte die Zahl 3; seit jeder
# Worker sein eigenes Fenster hat, nennt sie dreimal die Zahl 1 -- einmal je
# Fenster. Die Zusage ist dieselbe geblieben: der Pane mit dem falschen
# @wb_role (host2's orch-launch markiert JEDEN gestarteten Pane als
# orchestrator, siehe regeln/maschinen.md) wird mitgeprueft und nicht
# weggefiltert. Sie wird jetzt daran gemessen, dass DREI Fenster gewarnt werden.
gewarnte=$(grep -o "^wb-grid: WARNUNG — [0-9]* Worker im Fenster '[^']*'" "$ERR" \
             | sed "s/.*im Fenster '\([^']*\)'/\1/" | sort -u | grep -c . | tr -d ' ')
if [ "$gewarnte" = "3" ]; then
  ok "die Warnung feuert fuer alle drei Fenster (inkl. des mistagged Panes) -- population = alle Nicht-Placeholder"
elif [ "$gewarnte" = "0" ]; then
  bad "keine Warnung ausgeloest -- erwartet, da minWorkerPaneWidth=200 garantiert ueber jeder echten Pane-Breite liegt"
else
  bad "die Warnung nennt nur $gewarnte Fenster (erwartet 3) -- der Pane mit @wb_role=orchestrator bekommt keins oder wird uebergangen"
fi
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Punkt 5: der Rueckweg window -> split holt die Worker wirklich zurueck =="
# Befund B2 des Betriebslaufs (2026-08-04): der split-Zweig bildete seine
# Arbeitsliste nur aus Panes des Orchestrator-Fensters, die Panes in
# 'workers'/'workers-2' sah er nie -- null von drei Workern kamen zurueck,
# waehrend Kopf und Kommentar von wb-grid das Gegenteil versprachen. Regression
# aus Commit 6568a03 vom selben Tag; bis dahin stand die Bedingung
# '($3==ow || ($3==ww && ww!=""))' in `rest` (Commit 0cfe9da, 2026-07-25).
#
# minWorkerPaneWidth steht in diesen Faellen auf 60: bei 197 Spalten Breite
# passen damit drei Worker NEBENEINANDER in die Reihe (197/60 = 3). Mit dem
# Default 80 waere einer davon regulaerer Ueberlauf und bliebe absichtlich im
# Fenster 'workers' stehen -- dieser Fall wird in Punkt 6 eigens geprueft.
"$TESTHOME/.local/bin/wb-state" settings set minWorkerPaneWidth 60 >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 0 >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1

# Wo liegt ein Pane? -> Fenstername, leer wenn es ihn nicht mehr gibt.
fenster_von() { tm display -p -t "$1" '#{window_name}' 2>/dev/null; }
# Wie viele Worker-Panes stecken in einem Fenster dieser Session?
worker_in() { # worker_in <session> <fenstername>
  tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
    | awk -F'|' -v s="$1" -v w="$2" '$1==s && $2==w && $3=="worker"' | grep -c . | tr -d ' '
}
# Wie viele Worker-Panes stecken in IRGENDEINEM Worker-Fenster dieser Session?
# Seit Stufe A (03.09.2026) hat jeder Worker sein eigenes: 'workers',
# 'workers-2', ... -- die Frage "sind sie drueben?" laesst sich deshalb nicht
# mehr an einem einzelnen Fensternamen stellen.
worker_in_tabs() { # worker_in_tabs <session>
  tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="worker"' | grep -c . | tr -d ' '
}
# wb-grid in einem Pane laufen lassen und den Rueckgabewert einsammeln.
grid_rc() { # grid_rc <pane> [PATH-Praefix] -> setzt RC
  local orch="$1" pfad="${2:-}" flag="$TESTHOME/rc-$RANDOM"
  tm send-keys -t "$orch" \
    "${pfad:+PATH='$pfad':\$PATH }$TESTHOME/.local/bin/wb-grid $orch >>'$TESTHOME/grid5.out' 2>>'$TESTHOME/grid5.err'; echo \$? > '$flag'" Enter
  if warte_auf_bedingung 20 "grid_rc: wb-grid $orch" "[ -s '$flag' ]" "$TESTHOME/grid5.out"; then
    RC="$(cat "$flag" 2>/dev/null)"; RC="${RC:-99}"
  else
    RC=124
  fi
  rm -f "$flag"
}

SESS="wb-gridtest-$$-split"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator
: >"$TESTHOME/grid5.out"; : >"$TESTHOME/grid5.err"
SW=""
for i in 1 2 3; do
  WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
  tm set -p -t "$WP" @wb_role worker; tm set -p -t "$WP" @wb_worker "s$i"
  SW="$SW $WP"
  grid_rc "$ORCH"
done
[ "$(worker_in_tabs "$SESS")" = 3 ] && ok "Ausgangslage: drei Worker in je einem eigenen Worker-Fenster" \
                                    || bad "Ausgangslage misslungen: $(worker_in_tabs "$SESS") von 3 in einem workers*-Fenster"

"$TESTHOME/.local/bin/wb-state" settings set workerLayout split >/dev/null 2>&1
grid_rc "$ORCH"
[ "$RC" = 0 ] && ok "der Wechsel auf 'split' endet mit rc=0" \
              || bad "der Wechsel auf 'split' endet mit rc=$RC: $(tail -3 "$TESTHOME/grid5.err")"
im_main=$(worker_in "$SESS" main)
[ "$im_main" = 3 ] && ok "alle drei Worker liegen wieder im Orchestrator-Fenster" \
                   || bad "nur $im_main von 3 Workern im Orchestrator-Fenster"
[ "$(worker_in_tabs "$SESS")" = 0 ] && ok "in keinem workers*-Fenster steht noch ein Worker" \
                                    || bad "$(worker_in_tabs "$SESS") Worker blieben in einem workers*-Fenster liegen"
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qE '^workers(-[0-9]+)?$' \
  && bad "ein leeres workers*-Fenster steht noch" || ok "die leeren workers*-Fenster sind verschwunden"
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -q '_wbhold' \
  && bad "ein Pane haengt im Haltefenster _wbhold" || ok "kein Pane im Haltefenster _wbhold"

echo
echo "== Punkt 5b: derselbe Weg zurueck (split -> window) =="
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
grid_rc "$ORCH"
[ "$RC" = 0 ] && ok "der Wechsel auf 'window' endet mit rc=0" \
              || bad "der Wechsel auf 'window' endet mit rc=$RC: $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in_tabs "$SESS")" = 3 ] && ok "alle drei Worker sind wieder in je einem eigenen Worker-Fenster" \
                                    || bad "nur $(worker_in_tabs "$SESS") von 3 in einem workers*-Fenster"
[ "$(worker_in "$SESS" main)" = 0 ] && ok "im Orchestrator-Fenster steht kein Worker mehr" \
                                    || bad "$(worker_in "$SESS" main) Worker blieben im Orchestrator-Fenster"

echo
echo "== Punkt 5c: nichts zu tun heisst rc=0 und keine Bewegung =="
vorher="$(tm list-panes -a -F '#{session_name}|#{pane_id}|#{window_name}' | awk -F'|' -v s="$SESS" '$1==s')"
grid_rc "$ORCH"
nachher="$(tm list-panes -a -F '#{session_name}|#{pane_id}|#{window_name}' | awk -F'|' -v s="$SESS" '$1==s')"
[ "$RC" = 0 ] && ok "ein zweiter Lauf ohne Aenderung endet mit rc=0" || bad "ein Leerlauf endet mit rc=$RC"
[ "$vorher" = "$nachher" ] && ok "der Leerlauf hat keinen Pane bewegt" \
                           || bad "der Leerlauf hat Panes bewegt"
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Punkt 6: Rueckweg aus einem UEBERLAUF-Fenster ('workers-2') =="
# Zwei Worker heissen seit Stufe A zwei Fenster; der Rueckweg muss aus ALLEN
# workers*-Fenstern holen, nicht nur aus dem ersten. (Bis zum 03.09.2026 musste
# dafuer maxWorkerPanesPerTab=1 gesetzt werden -- die Einstellung zaehlt jetzt
# Kacheln je Tab der Anwendung und hat auf tmux keine Wirkung mehr.)
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
SESS="wb-gridtest-$$-ov"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator
ov_rc=0
for i in 1 2; do
  WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
  tm set -p -t "$WP" @wb_role worker; tm set -p -t "$WP" @wb_worker "o$i"
  grid_rc "$ORCH"
  [ "$RC" = 0 ] || ov_rc="$RC"
done
# Der Weg HIN (window, mit Ueberlauf) darf den neuen Rueckgabewert nicht
# faelschlich faerben: ein Pane, der in 'workers-2' landet, hat sein Fenster ja
# verlassen.
[ "$ov_rc" = 0 ] && ok "die Spawns mit Ueberlauf-Tab enden alle mit rc=0" \
                 || bad "ein Spawn mit Ueberlauf-Tab endete mit rc=$ov_rc: $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in "$SESS" workers-2)" = 1 ] && ok "Ausgangslage: ein Worker liegt im Ueberlauf-Fenster 'workers-2'" \
                                         || bad "Ausgangslage misslungen: kein Worker in 'workers-2'"

"$TESTHOME/.local/bin/wb-state" settings set workerLayout split >/dev/null 2>&1
grid_rc "$ORCH"
[ "$RC" = 0 ] && ok "der Wechsel auf 'split' endet mit rc=0" \
              || bad "der Wechsel auf 'split' endet mit rc=$RC: $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in "$SESS" main)" = 2 ] && ok "beide Worker liegen im Orchestrator-Fenster" \
                                    || bad "nur $(worker_in "$SESS" main) von 2 Workern im Orchestrator-Fenster"
uebrig=$(tm list-windows -t "=$SESS" -F '#{window_name}' | grep -cE '^workers(-[0-9]+)?$' | tr -d ' ')
[ "$uebrig" = 0 ] && ok "weder 'workers' noch 'workers-2' sind uebriggeblieben" \
                  || bad "$uebrig workers*-Fenster stehen noch"
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Punkt 7: ein Pane, der bewegt werden MUSS und nicht bewegt wird, faerbt den Rueckgabewert =="
# Das ist der Kern von Befund B3: wb-doctor --fix wertet den Rueckgabewert von
# wb-grid als Beleg fuer eine Reparatur. Solange wb-grid schweigend nichts tut
# und 0 meldet, meldet wb-doctor eine Reparatur, die nie stattgefunden hat.
# Der Fehlschlag wird hier absichtlich herbeigefuehrt: ein `tmux`-Schirm vorn im
# PATH verweigert genau `join-pane` und `break-pane` und reicht alles andere
# durch. Damit kann kein Pane sein Fenster verlassen -- die Frage ist nur, ob
# wb-grid das bemerkt.
mkdir -p "$TESTHOME/schirm"
cat > "$TESTHOME/schirm/tmux" <<SCHIRM
#!/bin/sh
case "\$1" in
  join-pane|break-pane) echo "schirm: \$1 verweigert" >&2; exit 1 ;;
esac
exec $(command -v tmux) "\$@"
SCHIRM
chmod +x "$TESTHOME/schirm/tmux"

"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 0 >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
SESS="wb-gridtest-$$-rc"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator
WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
tm set -p -t "$WP" @wb_role worker; tm set -p -t "$WP" @wb_worker r1
grid_rc "$ORCH"
[ "$(worker_in_tabs "$SESS")" = 1 ] && ok "Ausgangslage: ein Worker in seinem eigenen Fenster" \
                                    || bad "Ausgangslage misslungen"

"$TESTHOME/.local/bin/wb-state" settings set workerLayout split >/dev/null 2>&1
grid_rc "$ORCH" "$TESTHOME/schirm"
[ "$RC" != 0 ] && ok "wb-grid meldet den verhinderten Umzug mit rc=$RC" \
               || bad "wb-grid meldet Erfolg (rc=0), obwohl kein Pane bewegt wurde"
grep -q "haetten ihr Fenster verlassen muessen" "$TESTHOME/grid5.err" \
  && ok "die Fehlermeldung nennt die liegengebliebenen Panes" \
  || bad "keine Fehlermeldung ueber liegengebliebene Panes: $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in_tabs "$SESS")" = 1 ] && ok "der Worker laeuft unveraendert weiter (nichts wurde getoetet)" \
                                    || bad "der Worker ist beim Fehlschlag verlorengegangen"
# Ohne Schirm holt derselbe Aufruf den Pane dann wirklich zurueck.
grid_rc "$ORCH"
[ "$RC" = 0 ] && [ "$(worker_in "$SESS" main)" = 1 ] \
  && ok "derselbe Aufruf ohne Schirm holt den Pane zurueck und endet mit rc=0" \
  || bad "der Lauf ohne Schirm scheiterte (rc=$RC, im Orchestrator-Fenster: $(worker_in "$SESS" main))"
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Punkt 8: die Teilausfuehrung wird ausgesprochen und bekommt einen eigenen Rueckgabewert =="
# Entscheidung des Nutzers vom 2026-08-04: eine halbe Ausfuehrung, die Erfolg
# meldet, ist ein Fehler und kein Kompromiss. Passen bei minWorkerPaneWidth nicht
# alle Worker nebeneinander in die Orchestrator-Reihe, bleibt der Rest im Fenster
# 'workers' -- das darf so sein, aber es muss (a) mit Zahlen und Grund gesagt
# werden und (b) den Rueckgabewert 3 ergeben, damit ein Aufrufer wie
# `wb-doctor --fix` es nicht als erledigt verbucht.
#
# Der Fall wird ueber die Breite gestellt, nicht ueber die Zahl der Worker: bei
# 197 Spalten und minWorkerPaneWidth=100 passt genau EINER nebeneinander, drei
# Worker ergeben also 1 zurueck und 2 zurueckgehalten. Beide Zahlen sind aus der
# Einstellung ausgerechnet und nicht geraten.
"$TESTHOME/.local/bin/wb-state" settings set maxWorkerPanesPerTab 0 >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set minWorkerPaneWidth 100 >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1
SESS="wb-gridtest-$$-teil"
tm new-session -d -x "$WIDTH" -y "$HEIGHT" -s "$SESS" -n main >/dev/null 2>&1
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator
: >"$TESTHOME/grid5.err"
for i in 1 2 3; do
  WP=$(tm split-window -t "$ORCH" -P -F '#{pane_id}')
  tm set -p -t "$WP" @wb_role worker; tm set -p -t "$WP" @wb_worker "t$i"
  grid_rc "$ORCH"
done
[ "$(worker_in_tabs "$SESS")" = 3 ] && ok "Ausgangslage: drei Worker in je einem eigenen Worker-Fenster" \
                                    || bad "Ausgangslage misslungen: $(worker_in_tabs "$SESS") von 3 in einem workers*-Fenster"

: >"$TESTHOME/grid5.err"
"$TESTHOME/.local/bin/wb-state" settings set workerLayout split >/dev/null 2>&1
grid_rc "$ORCH"
[ "$RC" = 3 ] && ok "die Teilausfuehrung endet mit dem eigenen Rueckgabewert 3" \
              || bad "die Teilausfuehrung endet mit rc=$RC (erwartet 3): $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in "$SESS" main)" = 1 ] && ok "ein Worker passt in die Reihe und liegt beim Orchestrator" \
                                    || bad "$(worker_in "$SESS" main) Worker beim Orchestrator (erwartet 1)"
[ "$(worker_in_tabs "$SESS")" = 2 ] && ok "die anderen beiden bleiben in ihren Worker-Fenstern" \
                                    || bad "$(worker_in_tabs "$SESS") Worker in workers*-Fenstern (erwartet 2)"

MELDUNG="$(grep 'TEILWEISE' "$TESTHOME/grid5.err" | tail -1)"
[ -n "$MELDUNG" ] && ok "der Lauf sagt ausdruecklich, dass er nur teilweise ausgefuehrt hat" \
                  || bad "keine TEILWEISE-Meldung: $(tail -3 "$TESTHOME/grid5.err")"
case "$MELDUNG" in
  *"1 von 3"*) ok "die Meldung nennt die Zahlen (1 von 3 zurueck)" ;;
  *) bad "die Meldung nennt die Zahlen nicht: $MELDUNG" ;;
esac
case "$MELDUNG" in
  *"2 bleiben"*) ok "die Meldung nennt, wie viele liegenbleiben" ;;
  *) bad "die Meldung sagt nicht, wie viele liegenbleiben: $MELDUNG" ;;
esac
case "$MELDUNG" in
  *"minWorkerPaneWidth=100"*) ok "die Meldung nennt den Grund samt geltendem Wert" ;;
  *) bad "die Meldung nennt minWorkerPaneWidth=100 nicht: $MELDUNG" ;;
esac
case "$MELDUNG" in
  *"wb-close"*|*"verbreitern"*) ok "die Meldung sagt, was dagegen zu tun ist" ;;
  *) bad "die Meldung nennt keine Abhilfe: $MELDUNG" ;;
esac

echo "-- derselbe Fall, aber die Reihe ist breit genug: rc=0, keine Teilmeldung --"
: >"$TESTHOME/grid5.err"
"$TESTHOME/.local/bin/wb-state" settings set minWorkerPaneWidth 60 >/dev/null 2>&1
grid_rc "$ORCH"
[ "$RC" = 0 ] && ok "mit passender Grenze endet derselbe Wechsel mit rc=0" \
              || bad "mit passender Grenze endet der Wechsel mit rc=$RC: $(tail -3 "$TESTHOME/grid5.err")"
[ "$(worker_in "$SESS" main)" = 3 ] && ok "jetzt liegen alle drei beim Orchestrator" \
                                    || bad "nur $(worker_in "$SESS" main) von 3 beim Orchestrator"
grep -q 'TEILWEISE' "$TESTHOME/grid5.err" \
  && bad "es wird weiter eine Teilausfuehrung gemeldet, obwohl alle zurueckkamen" \
  || ok "keine Teilmeldung, wenn nichts liegenbleibt"

echo "-- und nichts zu tun bleibt nichts zu tun: rc=0 --"
: >"$TESTHOME/grid5.err"
grid_rc "$ORCH"
[ "$RC" = 0 ] && ok "der Leerlauf endet mit rc=0" || bad "der Leerlauf endet mit rc=$RC"
grep -q 'TEILWEISE' "$TESTHOME/grid5.err" \
  && bad "der Leerlauf meldet eine Teilausfuehrung" || ok "der Leerlauf meldet nichts"
tm kill-session -t "=$SESS" >/dev/null 2>&1

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
