#!/usr/bin/env bash
# test-context-guard-selbstkompaktierung.sh -- der Anschluss kommt auch dann, wenn
# sich der Worker SELBST kompaktiert hat und die Wache nie einen Kompaktierbefehl
# getippt hat.
#
# ANLASS (2026-09-18, Session wb-AI-b310aa-1d39e0, Worker 'mobil-spec', Harness codex,
# Modell gpt-5.6-sol:xhigh): 17:40 mahnte die Wache bei 90 % die Uebergabe an
# (Schritt 1). Danach kompaktierte codex sich SELBST (Eintrag "type":"compacted" im
# Rollout, Auslastung danach 19 %). Der Worker schrieb um 17:45 seine Uebergabe und
# blieb wie angewiesen stehen. Die Wache sah nur noch eine niedrige Auslastung, lief
# in den Rearm-Zweig (warned/compacted geloescht, continue) und tippte nie einen
# Anschluss: den Merker dafuer (ANSCHLUSS_DIR) schrieb bis dahin nur, wer selbst
# kompaktiert hatte. Der Worker stand mit fertiger Uebergabe still, bis der Nutzer es
# bemerkte.
#
# GEPRUEFT WIRD, mit einer echten Claude-Code-Statuszeile ('820k/1.0M', Quelle 1 aus
# read_load()) und ohne eigene Registry -- vier Faelle, vier Worker:
#
#   A "wselbst"  Gemahnt, Selbstkompaktierung, Uebergabe NACH der Mahnung, Pane
#                wartet leer: GENAU EIN Anschluss wird getippt.
#   B "wbusy"    Gemahnt, Selbstkompaktierung, aber der Pane arbeitet weiter: es
#                wird NICHTS getippt, eine Logzeile sagt das.
#   C "wohne"    Gemahnt, Selbstkompaktierung, KEINE Uebergabe: nichts getippt,
#                eine Logzeile.
#   C2 "walt"    Wie C, aber mit einer ALTEN Uebergabe (Zeitstempel vor der
#                Mahnung): sie beschreibt einen ueberholten Stand und zaehlt nicht.
#   D            Nach einem Neustart der Wache kein ZWEITER Anschluss fuer A.
#   E            Ist die Mahnung aelter als MAHNUNG_MAX_ALTER_S, wird nicht mehr
#                angeschlossen (sonst koennte ein laengst fertiger Worker Stunden
#                spaeter erneut angestossen werden).
#
# ISOLATION: eigener Socket, eigenes HOME -- wie die Schwestertests.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-claude-selbstkompakt.py"

SOCKET="wbtest-cgselbst-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
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

PROJECT_DIR="$TESTHOME/project"
mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.pi-workers/results" "$PROJECT_DIR"
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

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-selbstkompaktierung: Anschluss nach der Selbstkompaktierung eines Workers =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgs -c "$PROJECT_DIR" -x 140 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"

STEUER="$(tm new-window -d -t "=wb-Cgs:" -P -F '#{pane_id}')"
# Eigener, inerter Anker-Pane fuer die Orchestrator-Rolle (wie im Schwestertest):
# hier wird nur der WORKER-Zweig geprueft.
ORCH_ANKER="$(tm new-window -d -t "=wb-Cgs:" -P -F '#{pane_id}')"

LOG_SELBST="$TESTHOME/submit-selbst.log"; : > "$LOG_SELBST"
LOG_BUSY="$TESTHOME/submit-busy.log";     : > "$LOG_BUSY"
LOG_OHNE="$TESTHOME/submit-ohne.log";     : > "$LOG_OHNE"
LOG_ALT="$TESTHOME/submit-alt.log";       : > "$LOG_ALT"

neuer_worker() {   # <log> <busy 0|1> -> setzt PANE_ID
  local log="$1" busy="$2"
  PANE_ID="$(tm new-window -d -t "=wb-Cgs:" -c "$PROJECT_DIR" -P -F '#{pane_id}' \
      "PATH='$PANE_PATH' FAKE_LOG='$log' FAKE_PCT=82 FAKE_PCT_NACH=5 FAKE_SELBST_NACH=1 FAKE_BUSY=$busy python3 '$FAKE'" 2>/dev/null)"
}
neuer_worker "$LOG_SELBST" 0; W_SELBST="$PANE_ID"
neuer_worker "$LOG_BUSY"   1; W_BUSY="$PANE_ID"
neuer_worker "$LOG_OHNE"   0; W_OHNE="$PANE_ID"
neuer_worker "$LOG_ALT"    0; W_ALT="$PANE_ID"
sleep 2

# C2: die ALTE Uebergabe liegt schon VOR der Mahnung da, mit altem Zeitstempel.
printf 'Uebergabe aus einer frueheren Runde\n' > "$PROJECT_DIR/HANDOFF-walt.md"
touch -t 202001010101 "$PROJECT_DIR/HANDOFF-walt.md"

GLOG="$TESTHOME/guard.log"
start_guard() {   # [zusaetzliche env-zuweisungen]
  local extra="${1:-}"
  tm send-keys -t "$STEUER" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 ORCH_PCT=95 WARN_PCT=50 \
       ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$PROJECT_DIR' $extra \
       context-guard '$ORCH_ANKER' '$W_SELBST:wselbst' '$W_BUSY:wbusy' '$W_OHNE:wohne' '$W_ALT:walt'; } >> $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
  sleep 2
  GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"
}
stop_guard() {
  [ -n "$GUARDPID" ] || return 0
  kill "$GUARDPID" 2>/dev/null
  local deadline=$((SECONDS + 10))
  while [ $SECONDS -lt $deadline ] && kill -0 "$GUARDPID" 2>/dev/null; do sleep 0.3; done
  kill -0 "$GUARDPID" 2>/dev/null && { kill -9 "$GUARDPID" 2>/dev/null; sleep 1; }
  GUARDPID=""
}
: > "$GLOG"
start_guard

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.3
  done
  return 0
}

echo "-- Vorbereitung: alle vier Worker werden gemahnt, danach kompaktieren sie sich selbst --"
for pair in "wselbst:$W_SELBST" "wbusy:$W_BUSY" "wohne:$W_OHNE" "walt:$W_ALT"; do
  name="${pair%%:*}"; pane="${pair##*:}"
  if warte_auf "$GLOG" "$name \($pane\) at 82% -> handoff requested" 25; then
    ok "Vorbereitung: Mahnung fuer $name kam an"
  else
    bad "Vorbereitung: keine Mahnung fuer $name: $(tail -15 "$GLOG" 2>/dev/null)"
  fi
done
# Nur A und B bekommen eine frische Uebergabe -- NACH der Mahnung geschrieben.
printf 'Uebergabe (Test) fuer wselbst\n' > "$PROJECT_DIR/HANDOFF-wselbst.md"
printf 'Uebergabe (Test) fuer wbusy\n'   > "$PROJECT_DIR/HANDOFF-wbusy.md"

echo
echo "-- A: 'wselbst' -- Selbstkompaktierung, frische Uebergabe, leerer Pane: Anschluss --"
if warte_auf "$GLOG" "wselbst \($W_SELBST\) -> resumed \(Anschluss nach Selbstkompaktierung" 40; then
  ok "A1: der Anschluss kam, obwohl die Wache selbst nie kompaktiert hat"
else
  bad "A1: kein Anschluss fuer wselbst -- der Vorfall vom 2026-09-18 waere hier reproduziert: $(tail -30 "$GLOG" 2>/dev/null)"
fi
if grep -qF "Continue after the compaction" "$LOG_SELBST" 2>/dev/null; then
  ok "A2: der Anschluss-Prompt steht wirklich im Pane, nicht nur im Protokoll"
else
  bad "A2: der Pane hat keinen Anschluss-Prompt empfangen: $(cat "$LOG_SELBST" 2>/dev/null)"
fi
if grep -qF "HANDOFF-wselbst.md" "$LOG_SELBST" 2>/dev/null; then
  ok "A3: der Prompt nennt die Uebergabedatei"
else
  bad "A3: der Prompt nennt die Uebergabedatei nicht"
fi
if grep -qE "wselbst \($W_SELBST\).*/compact" "$GLOG" 2>/dev/null; then
  bad "A4: die Wache hat doch einen Kompaktierbefehl getippt -- hier war nichts zu kompaktieren"
else
  ok "A4: kein Kompaktierbefehl getippt -- der Harness hatte sich selbst kompaktiert"
fi

echo
echo "-- B: 'wbusy' -- der Worker arbeitet nach der Selbstkompaktierung weiter: nichts tippen --"
if warte_auf "$GLOG" "wbusy \($W_BUSY\): 5% ohne eigene Kompaktierung, aber der Pane arbeitet" 30; then
  ok "B1: die Wache sagt, dass sie wegen des laufenden Zugs nichts tippt"
else
  bad "B1: keine Logzeile zum arbeitenden Pane: $(tail -30 "$GLOG" 2>/dev/null)"
fi
if grep -qF "Continue after the compaction" "$LOG_BUSY" 2>/dev/null; then
  bad "B2: dem arbeitenden Worker wurde ein Anschluss getippt"
else
  ok "B2: dem arbeitenden Worker wurde nichts getippt"
fi

echo
echo "-- C/C2: 'wohne' (keine Uebergabe) und 'walt' (alte Uebergabe) --"
for pair in "wohne:$W_OHNE:$LOG_OHNE" "walt:$W_ALT:$LOG_ALT"; do
  name="${pair%%:*}"; rest="${pair#*:}"; pane="${rest%%:*}"; slog="${rest##*:}"
  if warte_auf "$GLOG" "$name \($pane\): 5% ohne eigene Kompaktierung, aber keine Uebergabe nach der Mahnung" 30; then
    ok "C1 ($name): die Wache meldet ehrlich, dass keine gueltige Uebergabe vorliegt"
  else
    bad "C1 ($name): keine passende Logzeile: $(tail -30 "$GLOG" 2>/dev/null)"
  fi
  if grep -qF "Continue after the compaction" "$slog" 2>/dev/null; then
    bad "C2 ($name): es wurde trotzdem ein Anschluss getippt"
  else
    ok "C2 ($name): nichts getippt"
  fi
done

echo
echo "-- D: Neustart der Wache -- kein zweiter Anschluss fuer wselbst --"
stop_guard
start_guard
sleep 12   # mehrere Poll-Zyklen (POLL=2s)
N=$(grep -cE "wselbst \($W_SELBST\) -> resumed \(Anschluss nach Selbstkompaktierung" "$GLOG" 2>/dev/null | tr -d ' ')
[ "$N" = "1" ] \
  && ok "D1: weiterhin genau EIN Anschluss im Protokoll" \
  || bad "D1: ${N}x Anschluss im Protokoll (erwartet: 1)"
N=$(grep -cF "Continue after the compaction" "$LOG_SELBST" 2>/dev/null | tr -d ' ')
[ "$N" = "1" ] \
  && ok "D2: weiterhin genau EIN Anschluss-Prompt im Pane" \
  || bad "D2: ${N}x Anschluss-Prompt im Pane (erwartet: 1)"

echo
echo "-- E: abgelaufene Mahnung -- kein Anschluss mehr, auch wenn die Uebergabe noch kommt --"
stop_guard
start_guard "MAHNUNG_MAX_ALTER_S=1"
printf 'Uebergabe (Test), viel zu spaet\n' > "$PROJECT_DIR/HANDOFF-wohne.md"
if warte_auf "$GLOG" "wohne \($W_OHNE\): .*die Mahnung ist aber [0-9]+s alt \(Frist 1s\) -- kein Anschluss getippt" 30; then
  ok "E1: die Wache laesst eine verfallene Mahnung verfallen und sagt es"
else
  bad "E1: keine Verfalls-Logzeile fuer wohne: $(tail -30 "$GLOG" 2>/dev/null)"
fi
if grep -qF "Continue after the compaction" "$LOG_OHNE" 2>/dev/null; then
  bad "E2: nach Ablauf der Frist wurde doch noch ein Anschluss getippt"
else
  ok "E2: nach Ablauf der Frist wurde nichts getippt"
fi

stop_guard

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
