#!/usr/bin/env bash
# test-pi-worker-fenster-verschwunden.sh -- pi-worker darf nie in eine fremde
# Session spawnen, wenn ihm unter den Haenden ein Fenster oder die ganze Session
# wegbricht.
#
# ANLASS (Bugjagd 2026-08-15, shell/pi-worker:719-721): bei workerLayout=window
# fragte pi-worker erst das Fenster 'workers' per Name ($wwin), dann dessen
# aktiven Pane ($wtgt), und splittete in diesen Pane hinein. Verschwand das
# Fenster zwischen den beiden Abfragen (eine andere Session raeumt gleichzeitig
# auf, ein Mensch schliesst es), war $wtgt leer -- und `tmux split-window -d -t
# ""` schlaegt NICHT fehl, sondern trifft das AKTUELLE Pane irgendeiner Session
# auf dem Server. Der Auftragstext landete dann in einer FREMDEN Workbench, und
# pi-worker meldete trotzdem Erfolg.
#
# UMGESCHRIEBEN AM 03.09.2026 (Stufe A), und der Grund ist der beste, den ein
# Test haben kann: die Race GIBT ES NICHT MEHR. Seit jeder Worker sein eigenes
# Fenster bekommt, sucht pi-worker keinen Ziel-Pane mehr, sondern legt mit
# `new-window -t "=<session>:"` ein neues Fenster an. Das Ziel ist damit die
# SESSION und kein Pane, `=` verlangt den exakten Namen, und ein fehlendes Ziel
# ist ein Fehler statt eines Zufallstreffers. Die alte Zusage -- „nie in eine
# fremde Session" -- steht deshalb unveraendert; nur die Faelle, an denen sie
# gemessen wird, sind die von heute:
#
#   A  Das Fenster 'workers' verschwindet mitten im Spawn. Der Worker muss
#      trotzdem in SEINER Session landen, in einem eigenen Fenster, und der
#      Lauf muss gelingen -- es gibt nichts mehr, worauf er angewiesen waere.
#   B  Die ganze Zielsession verschwindet mitten im Spawn. Dann muss pi-worker
#      laut scheitern: kein Pane irgendwo, kein Auftragstext, rc != 0.
#
# NACHGESTELLT, NICHT NUR BEHAUPTET: ein tmux-Schirm im PATH raeumt GENAU bei
# der Fensterabfrage weg, die pi-worker selbst schickt (`list-windows` auf die
# Zielsession) -- das macht die sonst seltene Race deterministisch, statt auf
# Zufallstiming zu hoffen.
#
# ISOLATION: eigener tmux-Socket, eigenes HOME (Registry, Ergebnisse, Zustand
# alle darunter), eigene Modell-Registry, eigenes Fixture-Arbeitsverzeichnis.
# Niemals die Live-Session oder ~/.pi-workers des Menschen. `trap` raeumt auf,
# auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_PI_WORKER:-$REPO/pi-worker}"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-wtgt-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="w$(date +%s)$$$RANDOM"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS + 5))
  while [ $SECONDS -lt $d ] && tm list-sessions >/dev/null 2>&1; do
    tm kill-server 2>/dev/null; sleep 0.3
  done
  tm list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== pi-worker: verschwundenes 'workers'-Fenster spawnt nie fremd (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$TOOL" ] || ueberspringen "shell/pi-worker fehlt ($TOOL)"

mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

cat > "$SHIM/tmux_real_call" <<EOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux_real_call"

# Falscher Agent: zeigt das Bereitschaftszeichen des claude-Harness, schreibt
# alles Weitere in eine Marke-Datei -- das belegt, WOHIN der Auftragstext
# wirklich ging -- und gibt es zugleich auf dem Schirm aus. Die Ausgabe ist
# noetig, seit der Spawn im gesunden Fall bis zur Absendepruefung von pi-worker
# durchlaeuft: die sucht den Auftragstext im Pane, und ein Agent, der alles
# stumm verschluckt, laesst sie zu Recht scheitern (gemessen 03.09.2026, rc=1
# mit „Eingabezeile ist leer, aber der Auftragstext ist nicht wiederzufinden").
cat > "$TESTHOME/.local/bin/claude" <<'SHIMEOF'
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec tee -a "$HOME/capture.log"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"
for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
cp "$REPO/wb-rolle" "$TESTHOME/.local/bin/wb-rolle"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-pane-write" \
         "$TESTHOME/.local/bin/wb-mensch" "$TESTHOME/.local/bin/wb-rolle"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

tm kill-server 2>/dev/null
tm -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40 -c /tmp
tm set-option -p -t "wb-$MARKE" @wb_role orchestrator
# 'workers'-Fenster von Hand vorbereiten, wie es ein frueherer Spawn getan haette.
WWIN_PANE=$(tm new-window -d -t "=wb-$MARKE:" -n workers -P -F '#{pane_id}' "sleep 300")
WWIN_ID=$(tm display -p -t "$WWIN_PANE" '#{window_id}')

# Fremde Session -- simuliert einen ANDEREN Orchestrator auf derselben Maschine.
tm -f /dev/null new-session -d -s "wb-fremd-$MARKE" -x 200 -y 40 -c /tmp
FREMD_PANE=$(tm list-panes -t "wb-fremd-$MARKE" -F '#{pane_id}')
tm set-option -p -t "$FREMD_PANE" @wb_role orchestrator

# Der Schirm: pi-workers EIGENE `list-windows`-Abfrage auf die Zielsession
# raeumt zuerst weg und reicht dann an das echte tmux weiter -- deterministisch
# statt auf Zufallstiming zu hoffen. Was weggeraeumt wird, steht in der Datei
# $SHIM/opfer: 'fenster' killt das 'workers'-Fenster (Fall A), 'session' die
# ganze Zielsession (Fall B), leer heisst nichts tun.
cat > "$SHIM/tmux" <<EOF
#!/bin/bash
if [ "\$1" = "list-windows" ]; then
  opfer="\$(cat "$SHIM/opfer" 2>/dev/null)"
  case "\$opfer" in
    fenster) "$SHIM/tmux_real_call" kill-window -t "$WWIN_ID" >/dev/null 2>&1 ;;
    session) "$SHIM/tmux_real_call" kill-session -t "=wb-$MARKE" >/dev/null 2>&1 ;;
  esac
  : > "$SHIM/opfer"
fi
exec "$SHIM/tmux_real_call" "\$@"
EOF
chmod +x "$SHIM/tmux"
: > "$SHIM/opfer"

HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
  "$TESTHOME/.local/bin/wb-state" settings set workerLayout window >/dev/null 2>&1

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= WB_SESSION="wb-$MARKE" \
      bash "$TOOL" "$@" 2>&1
}

spawn() { # spawn <name> -> setzt RC, AUS, NEUER_PANE
  local name="$1"
  VOR_PANES="$(tm list-panes -a -F '#{pane_id}' | sort)"
  AUS="$(pi "$name" claude-opus5 "$TESTHOME/arbeit" "Testauftrag $MARKE")"
  RC=$?
  sleep 0.5
  NACH_PANES="$(tm list-panes -a -F '#{pane_id}' | sort)"
  NEUER_PANE="$(comm -13 <(echo "$VOR_PANES") <(echo "$NACH_PANES"))"
}
fremde_treffer() { # fremde_treffer -> Panes, die in der FREMDEN Session gelandet sind
  local p treffer=""
  for p in $NEUER_PANE; do
    [ "$(tm display -p -t "$p" '#{session_name}' 2>/dev/null)" = "wb-fremd-$MARKE" ] && treffer="$treffer $p"
  done
  printf '%s' "$treffer"
}

echo "-- Fall A: das Fenster 'workers' verschwindet mitten im Spawn"
echo fenster > "$SHIM/opfer"
spawn "worker-a-$MARKE"
[ "$RC" -eq 0 ] && ok "A: pi-worker gelingt (rc=0) -- ein eigenes Fenster braucht kein bestehendes" \
                || bad "A: pi-worker scheiterte mit rc=$RC: $(printf '%s' "$AUS" | tail -3 | tr '\n' ' ')"
[ -n "$NEUER_PANE" ] && ok "A: ein neuer Pane ist entstanden" \
                     || bad "A: kein neuer Pane entstanden"
FREMD="$(fremde_treffer)"
[ -z "$FREMD" ] && ok "A: kein Pane in der fremden Session" \
                || bad "A: der Pane$FREMD landete in der FREMDEN Session -- genau der Fehler"
EIGEN=0
for p in $NEUER_PANE; do
  [ "$(tm display -p -t "$p" '#{session_name}' 2>/dev/null)" = "wb-$MARKE" ] && EIGEN=$((EIGEN+1))
done
[ "$EIGEN" -ge 1 ] && ok "A: der Worker liegt in seiner eigenen Session" \
                   || bad "A: kein neuer Pane in der eigenen Session 'wb-$MARKE'"
ALLEIN=1
for p in $NEUER_PANE; do
  W="$(tm display -p -t "$p" '#{window_id}' 2>/dev/null)"
  [ "$(tm list-panes -t "$W" -F '#{pane_id}' 2>/dev/null | grep -c .)" = 1 ] || ALLEIN=0
done
[ "$ALLEIN" = 1 ] && ok "A: der Worker liegt allein in seinem Fenster" \
                  || bad "A: der Worker teilt sich sein Fenster mit einem anderen Pane"

echo
echo "-- Fall B: die ganze Zielsession verschwindet mitten im Spawn"
: > "$TESTHOME/capture.log"
echo session > "$SHIM/opfer"
spawn "worker-b-$MARKE"
[ "$RC" -ne 0 ] && ok "B: pi-worker meldet Fehlschlag (rc=$RC), nicht Erfolg" \
                || bad "B: pi-worker meldet Erfolg (rc=0), obwohl die Zielsession weg war"
[ -z "$NEUER_PANE" ] && ok "B: kein neuer Pane entstanden -- kein Spawn ins Blaue" \
                     || bad "B: neuer Pane entstanden: $NEUER_PANE (haette es nicht duerfen)"
FREMD="$(fremde_treffer)"
[ -z "$FREMD" ] && ok "B: kein Pane in der fremden Session" \
                || bad "B: der Pane$FREMD landete in der FREMDEN Session -- genau der Fehler"
[ ! -s "$TESTHOME/capture.log" ] && ok "B: kein Auftragstext irgendwo eingefuegt" \
                                  || bad "B: Auftragstext wurde trotzdem eingefuegt: $(head -1 "$TESTHOME/capture.log")"

echo
echo "wb-pi-worker/fenster-verschwunden: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
