#!/usr/bin/env bash
# test-context-guard-sentinel-fremd.sh -- ein Sentinel ohne die eigene Warnung
# DIESES Guards darf nie kompaktieren, egal unter welchem Namen er liegt.
#
# ANLASS (2026-09-10, Befund "context-guard kompaktiert die FALSCHE Orchestrator-
# Sitzung", zwei Guard-Logs unter ~/.local/state/): zwei Orchestrator-Sitzungen mit
# gleichem cwd teilten sich denselben $PROJECT/.wb-knowledge-saved. Guard A schrieb
# ihn nach seiner eigenen Warnung, Guard B sah dieselbe Datei mit einer mtime nach
# seinem eigenen GUARD_START und kompaktierte SEINEN Orchestrator -- unter 40% Last,
# ohne je gewarnt zu haben. Reines Wettrennen ueber einen gemeinsamen Pfad, nicht ein
# defektes mtime-Urteil.
#
# GEGENMASSNAHME (siehe shell/context-guard, SENTINEL/SENTINEL_OLD um Zeile 1266
# sowie die Sentinel-Pruefung kurz vor der Warn/Notbremse-Kette): der Sentinel ist
# jetzt session-eindeutig (Dateiname traegt den tmux-Sessionnamen des bewachten
# Orchestrator-Panes), UND er zaehlt nur noch, wenn DIESER Guard $ORCH in diesem
# Zyklus selbst gewarnt hat ($warned) -- nicht schon deshalb, weil eine Datei mit
# passendem Namen oder passender mtime dort liegt. Der alte, geteilte Name
# ($PROJECT/.wb-knowledge-saved) bleibt als Fallback erkennbar, wird aber ohne
# eigene Warnung NIE geloescht -- er koennte dem ANDEREN Guard gehoeren.
#
# GEPRUEFT WIRD, mit einem Guard und einem FREMDEN `touch` (statt zwei echten
# Guard-Prozessen -- der zweite Guard steckt hier im simulierten Fremdzugriff auf
# den geteilten Alt-Pfad, den dieser Guard nie selbst geschrieben hat):
#   A  Lauf "fremd": der ALTE, geteilte Sentinelname wird von aussen angelegt,
#      OHNE dass dieser Guard je gewarnt hat (Warn-Schwelle bleibt unerreicht).
#      Erwartet: eine sichtbare "ohne eigene Warnung ... ignoriert, NICHT
#      geloescht"-Zeile, die Datei bleibt liegen, und KEIN "-> ... typed" im
#      gesamten Protokoll -- der fremde Sentinel loest nichts aus.
#   B  Lauf "eigen": die Last erreicht die Warn-Schwelle, die Warnzeile nennt den
#      NEUEN, session-eindeutigen Pfad; erst NACHDEM er unter diesem Pfad
#      angelegt wird, kompaktiert die Wache -- und zwar GENAU EINMAL.
#
# ISOLATION: eigener Socket, eigenes HOME, eigene Registry -- wie die
# Schwestersuiten test-context-guard-kompakt-einmal.sh und
# test-context-guard-kompakt-wirkungslos.sh (Harness-Id "pi", erfundenes
# Kontextformat "KTX <n> %", Kompaktierbefehl "/verdichte").
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-worker-swallow.py"

SOCKET="wbtest-cgsentfremd-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
GUARDPID=""

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench" \
         "$TESTHOME/.pi-workers/results"
for w in context-guard wb-state; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/*

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi (Sentinel-fremd)", "command": "pi",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "KTX",
      "contextPattern": "KTX[[:space:]]*([0-9]{1,3})[[:space:]]*%",
      "compactCommand": "/verdichte"
    }
  ],
  "models": []
}
REGEOF

cat > "$SHIM/pi" <<PIEOF
#!/bin/sh
exec /usr/bin/python3 "$FAKE"
PIEOF
chmod +x "$SHIM/pi"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-sentinel-fremd: ein Sentinel ohne eigene Warnung kompaktiert nie =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.3
  done
  return 0
}

# --- Lauf A: der fremde, alte Sentinelname ohne eigene Warnung ---------------
echo "-- A: alter geteilter Sentinel, OHNE dass dieser Guard je gewarnt hat --"
tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgsf -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"

LOG_A="$TESTHOME/orch-enter-fremd.log"; : > "$LOG_A"
# FAKE_PCT bleibt UNTER der Warn-Schwelle (ORCH_PCT=90) -- dieser Guard warnt in
# diesem Lauf zu keinem Zeitpunkt, exakt der Zustand, den der alte, geteilte
# Sentinelname ueberleben muesste, wenn er noch zaehlen wuerde.
ORCH_A="$(tm new-window -d -t "=wb-Cgsf:" -P -F '#{pane_id}' \
    "PATH='$PANE_PATH' FAKE_KIND=hart FAKE_LOG='$LOG_A' FAKE_PCT=50 FAKE_PCT_NACH=10 FAKE_COMPACT_TRIGGER='/verdichte' pi" 2>/dev/null)"
tm set -p -t "$ORCH_A" @wb_cmd "exec pi"
sleep 2

GLOG_A="$TESTHOME/guard-fremd.log"
STEUER_A="$(tm new-window -d -t "=wb-Cgsf:" -P -F '#{pane_id}')"
tm send-keys -t "$STEUER_A" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=1 ORCH_PCT=90 WARN_PCT=95 \
     ORCH_REARM_GAP=10 PROJECT='$TESTHOME' \
     context-guard '$ORCH_A'; } > $GLOG_A 2>&1 & echo \$! > $TESTHOME/guard-fremd.pid" Enter

if warte_auf "$GLOG_A" "^context-guard: orchestrator=" 60; then
  ok "A: die Wache ist angelaufen (Startmeldung im Protokoll)"
else
  bad "A: die Wache hat nach 60 s keine Startmeldung geschrieben: $(tail -5 "$GLOG_A" 2>/dev/null)"
fi
GUARDPID="$(cat "$TESTHOME/guard-fremd.pid" 2>/dev/null || true)"

# Der ALTE, geteilte Name -- so, wie ihn ein Orchestrator noch mit der alten
# Nudge-Formulierung im Kontext von sich aus anlegen wuerde, oder wie er hier
# einen FREMDEN Guard auf demselben PROJECT vertritt.
FREMD_SENTINEL="$TESTHOME/.wb-knowledge-saved"
touch "$FREMD_SENTINEL"

# Mehrere Poll-Zyklen abwarten (POLL=2s): ohne den Fix waere das laengst kompaktiert.
sleep 8

kill "$GUARDPID" 2>/dev/null
sleep 1
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "A: Aufraeumen -- Guard $GUARDPID laeuft noch"
  kill -9 "$GUARDPID" 2>/dev/null
fi
GUARDPID=""

if grep -qE "ohne eigene Warnung dieses Guards.*ignoriert, NICHT geloescht" "$GLOG_A" 2>/dev/null; then
  ok "A: die Wache meldet den fremden Sentinel sichtbar als ignoriert, nicht geloescht"
else
  bad "A: keine 'ohne eigene Warnung ... ignoriert'-Zeile im Protokoll: $(tail -10 "$GLOG_A" 2>/dev/null)"
fi
if [ -f "$FREMD_SENTINEL" ]; then
  ok "A: der fremde Sentinel liegt noch da -- die Wache hat ihn NICHT geloescht"
else
  bad "A: der fremde Sentinel wurde geloescht -- er koennte dem anderen Guard gehoert haben"
fi
if grep -qE -- "-> /verdichte typed" "$GLOG_A" 2>/dev/null; then
  bad "A: '-> /verdichte typed' steht im Protokoll -- der fremde Sentinel hat trotzdem kompaktiert: $(tail -10 "$GLOG_A" 2>/dev/null)"
else
  ok "A: kein '-> /verdichte typed' im Protokoll -- der fremde Sentinel loest nichts aus"
fi

echo
# --- Lauf B: der eigene, session-eindeutige Sentinel NACH eigener Warnung ----
echo "-- B: session-eindeutiger Sentinel NACH der eigenen Warnung dieses Guards --"
tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgsf -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"

LOG_B="$TESTHOME/orch-enter-eigen.log"; : > "$LOG_B"
# FAKE_PCT liegt zwischen der Warn-Schwelle (ORCH_PCT=70) und der Notbremse-Vorgabe
# (80, hier unveraendert) -- die Warnung muss wirklich ausgeloest werden, die Last
# selbst bleibt unter der Notbremse. FAKE_KIND=sofort, damit der Kompaktierbefehl
# tatsaechlich ankommt und sich zaehlen laesst.
ORCH_B="$(tm new-window -d -t "=wb-Cgsf:" -P -F '#{pane_id}' \
    "PATH='$PANE_PATH' FAKE_KIND=sofort FAKE_LOG='$LOG_B' FAKE_PCT=75 FAKE_PCT_NACH=10 FAKE_COMPACT_TRIGGER='/verdichte' pi" 2>/dev/null)"
tm set -p -t "$ORCH_B" @wb_cmd "exec pi"
sleep 2

GLOG_B="$TESTHOME/guard-eigen.log"
STEUER_B="$(tm new-window -d -t "=wb-Cgsf:" -P -F '#{pane_id}')"
tm send-keys -t "$STEUER_B" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=1 ORCH_PCT=70 WARN_PCT=95 \
     ORCH_REARM_GAP=10 PROJECT='$TESTHOME' \
     context-guard '$ORCH_B'; } > $GLOG_B 2>&1 & echo \$! > $TESTHOME/guard-eigen.pid" Enter

if warte_auf "$GLOG_B" "brain\+state update requested, warte auf " 30; then
  ok "B: die Warnzeile mit dem Sentinelpfad steht im Protokoll"
else
  bad "B: keine Warnzeile im Protokoll: $(tail -10 "$GLOG_B" 2>/dev/null)"
fi
GUARDPID="$(cat "$TESTHOME/guard-eigen.pid" 2>/dev/null || true)"

EIGEN_SENTINEL="$(grep -oE 'warte auf .*$' "$GLOG_B" | tail -1 | sed 's/^warte auf //')"
if [ -n "$EIGEN_SENTINEL" ] && [ "$EIGEN_SENTINEL" != "$FREMD_SENTINEL" ]; then
  ok "B: der genannte Pfad ist der NEUE, session-eindeutige Sentinel, nicht der alte geteilte Name ($EIGEN_SENTINEL)"
else
  bad "B: kein eindeutiger Sentinelpfad aus der Warnzeile extrahiert (bekommen: '$EIGEN_SENTINEL')"
fi

touch "$EIGEN_SENTINEL"

if warte_auf "$GLOG_B" "\-> /verdichte typed" 30; then
  ok "B: die Wache hat nach dem eigenen Sentinel kompaktiert"
else
  bad "B: kein '-> /verdichte typed' im Protokoll: $(tail -10 "$GLOG_B" 2>/dev/null)"
fi

# Ein paar weitere Poll-Zyklen abwarten, damit ein etwaiger zweiter Versuch sichtbar wuerde.
sleep 6

kill "$GUARDPID" 2>/dev/null
sleep 1
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "B: Aufraeumen -- Guard $GUARDPID laeuft noch"
  kill -9 "$GUARDPID" 2>/dev/null
fi
GUARDPID=""

N_TYPED=$(grep -cE -- "-> /verdichte typed" "$GLOG_B" 2>/dev/null | tr -d ' ')
if [ "$N_TYPED" = "1" ]; then
  ok "B: genau EIN '-> /verdichte typed' im Protokoll"
else
  bad "B: ${N_TYPED}x '-> /verdichte typed' im Protokoll (erwartet: 1): $(grep -E -- "-> /verdichte typed" "$GLOG_B" 2>/dev/null)"
fi
if grep -qF "Sentinel $EIGEN_SENTINEL" "$GLOG_B" 2>/dev/null; then
  ok "B: die Kompaktierung nennt den eigenen Sentinelpfad als Grund"
else
  bad "B: die Kompaktierung nennt nicht den erwarteten Sentinelpfad: $(grep -E 'typed' "$GLOG_B" 2>/dev/null)"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
