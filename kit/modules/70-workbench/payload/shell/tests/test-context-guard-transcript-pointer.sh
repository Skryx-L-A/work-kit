#!/usr/bin/env bash
# test-context-guard-transcript-pointer.sh -- ein Worker mit unlesbarer Statuszeile gilt
# NICHT mehr blind, wenn wb-state seinen Transkriptpfad kennt.
#
# ANLASS (Befund des Nutzers, 2026-08-19): die Wache meldete woertlich
#   'komm (%25): BLIND — weder Transcript noch Statuszeile lesbar; ... Transkript: <Pfad>'
# -- sie NANNTE den Transkriptpfad in derselben Zeile, weil announce_blind() ihn ueber
# `wb-state worker-transcript <name>` schon kannte, LAS ihn aber nie. Ursache
# (context-guard: transcript_load() vor diesem Fix): die einzige Pfadquelle war die
# EIGENE PID/CWD-Vermutung -- und die gibt bewusst auf, sobald der Projektordner MEHR
# als eine .jsonl enthaelt (mehrdeutig, z. B. nach mehreren Compact-Resumes desselben
# Workers). `wb-state worker-transcript` umgeht genau diese Mehrdeutigkeit (es kennt die
# claudeSessionId direkt aus pi-workers eigener Buchfuehrung), wurde aber nur fuer die
# BLIND-Meldung aufgerufen, nie um wirklich zu lesen.
#
# GEPRUEFT WIRD:
#   A  Ein Pane ohne jede lesbare Statuszeile (blosses `cat`, kein Harness erkennbar)
#      UND mit zwei .jsonl-Dateien im selben Projektordner (die eigene Vermutung MUSS
#      hier scheitern) gilt trotzdem NICHT als BLIND, sobald wb-state seinen
#      Transkriptpfad kennt -- und die Wache liest den RICHTIGEN der beiden Werte
#      (60 %, nicht die 1 % der Distraktor-Datei), Quelle 'registry' bzw. Warnschwelle
#      wird bei 60 % ausgeloest.
#   B  Gegenprobe: derselbe Aufbau, aber OHNE wb-state-Eintrag fuer den Worker (wie vor
#      diesem Fix) -- die eigene Vermutung bleibt mehrdeutig, der Pane gilt weiter BLIND.
#      Das zeigt, dass A wirklich am neuen Pfad haengt und nicht an einem Testartefakt.
#
# ISOLATION: eigener Socket, eigenes HOME, kein `--auto` (Panes werden wie bei den
# Schwester-Tests per Name direkt an context-guard uebergeben).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-cgtp-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
STATEDIR="$TESTHOME/.claude/workbench/sessions"
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
         "$TESTHOME/.pi-workers/results" "$STATEDIR"
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

# Minimale Registry -- fuer diesen Test inhaltlich irrelevant (der Pane laeuft 'cat',
# pane_harness() erkennt keinen Harness), aber die Wache erwartet eine lesbare Datei.
cat > "$REG" <<'REGEOF'
{ "version": 1, "providers": [], "harnesses": [], "models": [] }
REGEOF

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-transcript-pointer: wb-state-Transkriptpfad als echte Quelle =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

# ── Projektordner mit ZWEI .jsonl -- die eigene PID/CWD-Vermutung muss hieran scheitern ──
run_projekt() {   # run_projekt <cwd> <richtige-sid> <richtige-pct-tokens> <deko-sid> <deko-tokens>
  local cwd="$1" real_sid="$2" real_tok="$3" deko_sid="$4" deko_tok="$5" slug proj
  slug="$(printf '%s' "$cwd" | sed -E 's/[^A-Za-z0-9-]/-/g')"
  proj="$TESTHOME/.claude/projects/$slug"
  mkdir -p "$proj"
  printf '{"message":{"usage":{"input_tokens":%s}}}\n' "$real_tok" > "$proj/$real_sid.jsonl"
  printf '{"message":{"usage":{"input_tokens":%s}}}\n' "$deko_tok" > "$proj/$deko_sid.jsonl"
}

WORKER_A_DIR="$TESTHOME/worker-a-cwd"; mkdir -p "$WORKER_A_DIR"
WORKER_B_DIR="$TESTHOME/worker-b-cwd"; mkdir -p "$WORKER_B_DIR"
# 600000/1000000 = 60 % (richtig), 10000/1000000 = 1 % (Distraktor -- muss ignoriert werden)
run_projekt "$WORKER_A_DIR" "sess-real-a" 600000 "sess-deko-a" 10000
run_projekt "$WORKER_B_DIR" "sess-real-b" 600000 "sess-deko-b" 10000

# Nur Worker A bekommt einen wb-state-Eintrag -- das ist der einzige Unterschied zu B.
cat > "$STATEDIR/testsession.json" <<EOF
{
  "workers": [
    {"name": "blindworker", "kind": "claude", "model": "sonnet", "dir": "$WORKER_A_DIR",
     "spawnedAt": "2026-08-19T00:00:00Z", "claudeSessionId": "sess-real-a"}
  ]
}
EOF

# Gegenprobe (0.): wb-state findet den Pfad wirklich, unabhaengig von der Wache selbst.
FOUND="$("$BIN/wb-state" worker-transcript blindworker)"
[ "$FOUND" = "$TESTHOME/.claude/projects/$(printf '%s' "$WORKER_A_DIR" | sed -E 's/[^A-Za-z0-9-]/-/g')/sess-real-a.jsonl" ] \
  && ok "0: wb-state worker-transcript loest den erwarteten Pfad auf" \
  || bad "0: wb-state worker-transcript liefert '$FOUND', nicht den erwarteten Pfad"

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgtp -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

STEUER="$(tm new-window -d -t "=wb-Cgtp:" -P -F '#{pane_id}')"
ORCH="$(tm new-window -d -t "=wb-Cgtp:" -P -F '#{pane_id}' "PATH='$PANE_PATH' cat")"
# Beide Worker-Panes zeigen NICHTS an (blosses 'cat') -- weder exakte Zahlen noch ein
# Balken, kein erkennbarer Harness. Die einzig moegliche Quelle ist das Transkript.
WORKER_A="$(tm new-window -d -t "=wb-Cgtp:" -c "$WORKER_A_DIR" -P -F '#{pane_id}' "PATH='$PANE_PATH' cat" 2>/dev/null)"
WORKER_B="$(tm new-window -d -t "=wb-Cgtp:" -c "$WORKER_B_DIR" -P -F '#{pane_id}' "PATH='$PANE_PATH' cat" 2>/dev/null)"
sleep 2

GLOG="$TESTHOME/guard.log"
tm send-keys -t "$STEUER" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 ORCH_PCT=95 WARN_PCT=50 \
     ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$TESTHOME' \
     context-guard '$ORCH' '$WORKER_A:blindworker' '$WORKER_B:blindworkerB'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
sleep 2
GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.5
  done
  return 0
}

echo "-- A: wb-state kennt den Worker -- kein BLIND, richtiger Prozentsatz (60 %) --"
if warte_auf "$GLOG" "blindworker \($WORKER_A\) at 60% -> handoff requested" 30; then
  ok "A1: die Wache hat 60 % ueber das Transkript gelesen -- den RICHTIGEN der beiden Werte"
else
  bad "A1: keine 'at 60%' fuer blindworker: $(tail -15 "$GLOG" 2>/dev/null)"
fi
if grep -qE "blindworker \($WORKER_A\).*BLIND" "$GLOG" 2>/dev/null; then
  bad "A1: blindworker steht trotzdem als BLIND im Protokoll"
else
  ok "A1: keine BLIND-Zeile fuer blindworker -- DAS ist die behobene Regression"
fi

echo
echo "-- B: Gegenprobe -- ohne wb-state-Eintrag bleibt derselbe Aufbau BLIND --"
if warte_auf "$GLOG" "blindworkerB \($WORKER_B\).*BLIND" 30; then
  ok "B1: ohne wb-state-Eintrag bleibt der Pane BLIND -- A haengt wirklich am neuen Pfad"
else
  bad "B1: blindworkerB wurde NICHT als BLIND gemeldet -- der Testaufbau selbst waere schon falsch: $(tail -15 "$GLOG" 2>/dev/null)"
fi
if grep -qE "blindworkerB \($WORKER_B\) at [0-9]+% -> handoff requested" "$GLOG" 2>/dev/null; then
  bad "B1: blindworkerB bekam trotzdem eine Prozentzahl -- Testaufbau fehlerhaft"
else
  ok "B1: blindworkerB bekam ohne wb-state-Eintrag konsequent keine Prozentzahl"
fi

kill "$GUARDPID" 2>/dev/null
sleep 1
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "Aufraeumen: Guard $GUARDPID laeuft noch"
fi
GUARDPID=""

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
