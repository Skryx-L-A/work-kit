#!/usr/bin/env bash
# test-context-guard-worktree-handoff.sh -- die Handoff-Suche findet die Uebergabe im
# WORKTREE des Workers, nicht nur in PROJECT.
#
# ANLASS (Befund des Nutzers, 2026-08-19, Worker mlxsrv): eine Kontextwarnung ging raus
# ("19:30 mlxsrv (%1) at 83% -> handoff requested"), danach passierte nie wieder etwas.
# Ursache (context-guard:1932 vor diesem Fix): der Schritt-2-Check wartete NUR auf
# "$PROJECT/HANDOFF-<name>.md". Seit dem 04.08. arbeitet jeder Worker aber in seinem
# eigenen Git-Worktree (~/.pi-workers/worktrees/<name>) statt in PROJECT und schreibt
# seine Uebergabe dorthin. Belegt: ~/.pi-workers/worktrees/mlxsrv/HANDOFF-mlxsrv.md
# stand mit 28723 Byte da, ~/AI/claude-workbench/HANDOFF-mlxsrv.md (PROJECT) gab es nie.
# Der Guard wartete also auf eine Datei, die an dieser Stelle nie erscheint, und
# kompaktierte nie. Der Aufforderungstext (context-guard:1915) sagte zusaetzlich
# "im Projektverzeichnis" -- fuer einen Worker im Worktree ebenfalls falsch.
#
# GEPRUEFT WIRD:
#   A1  Die Kontextwarnung nennt dem Worker den VOLLSTAENDIGEN Pfad seines eigenen
#       Worktrees, nicht "im Projektverzeichnis" -- und dieser Pfad kommt bei der
#       TUI auch wirklich an (TYPED-Protokoll).
#   A2  Die Uebergabe wird NUR im Worktree geschrieben (PROJECT bekommt nie eine
#       HANDOFF-Datei). Der Guard erkennt sie trotzdem und tippt den Kompaktierbefehl
#       -- das ist die eigentliche Regression: ohne den Fix waere dieser Schritt nie
#       gekommen.
#   A3  Danach kommt WEITERARBEITEN an und nennt ebenfalls den Worktree-Pfad, nicht
#       nur den nackten Dateinamen.
#   B    Zur Probe auf Exempel: ein zweiter Worker OHNE eigenes pane_current_path
#       (Pane im selben Verzeichnis wie PROJECT) findet seine im PROJEKT liegende
#       Uebergabe weiterhin -- der PROJECT-Fallback aus handoff_candidates() bleibt
#       also erhalten, das ist keine Verengung auf den Worktree-Fall.
#
# ISOLATION: eigener Socket, eigenes HOME, eigene Registry -- wie die Schwester-Tests
# test-context-guard-registry.sh und test-context-guard-absende-verschluckt.sh (gleiche
# Grundstruktur: Harness-Id 'pi' mit erfundenem Kontextformat 'KTX <n> %' und
# Kompaktierbefehl '/verdichte', damit ein Treffer nur aus DIESER Registry stammen kann).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-cgwt-$$"
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

PROJECT_DIR="$TESTHOME/project"
WORKTREE_DIR="$TESTHOME/pi-workers/worktrees/wtworker"
mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench" \
         "$TESTHOME/.pi-workers/results" "$PROJECT_DIR" "$WORKTREE_DIR"
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
      "id": "pi", "label": "Pruef-pi", "command": "pi", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "KTX", "promptPattern": "^KTX",
      "contextPattern": "KTX[[:space:]]*([0-9]{1,3})[[:space:]]*%",
      "compactCommand": "/verdichte"
    }
  ],
  "models": []
}
REGEOF

# Dieselbe Fake-CLI wie test-context-guard-registry.sh, EIN Programmname 'pi' fuer alle
# drei Panes (pane_harness() erkennt den Harness ueber eine WORTGRENZE -- "pi-wt" waere
# kein Treffer fuer "pi" und liesse den Pane BLIND, gemessen beim ersten Testlauf dieser
# Datei). Welche Log-Datei eine Instanz fuehrt, kommt ueber TYPED_LOG aus der Umgebung,
# wie FAKE_LOG bei test-context-guard-absende-verschluckt.sh.
TYPED_ORCH="$TESTHOME/getippt-orch.log";  : > "$TYPED_ORCH"
TYPED_WT="$TESTHOME/getippt-wt.log";      : > "$TYPED_WT"
TYPED_PROJ="$TESTHOME/getippt-proj.log";  : > "$TYPED_PROJ"
cat > "$SHIM/pi" <<'PIEOF'
#!/bin/sh
pct=90
schirm() { printf '\n\n\nPruef-Harness laeuft\nKTX %s %%\n' "$pct"; }
schirm
while IFS= read -r zeile; do
  echo "$zeile" >> "$TYPED_LOG"
  case "$zeile" in
    */verdichte*) pct=5 ;;
  esac
  schirm
done
sleep 600
PIEOF
chmod +x "$SHIM/pi"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-worktree-handoff: Handoff-Suche im Worktree, nicht nur PROJECT =="
echo "   Socket: $SOCKET   HOME: $TESTHOME   PROJECT: $PROJECT_DIR   Worktree: $WORKTREE_DIR"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgwt -c "$PROJECT_DIR" -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

STEUER="$(tm new-window -d -t "=wb-Cgwt:" -P -F '#{pane_id}')"
ORCH="$(tm new-window -d -t "=wb-Cgwt:" -c "$PROJECT_DIR" -P -F '#{pane_id}' "PATH='$PANE_PATH' TYPED_LOG='$TYPED_ORCH' pi" 2>/dev/null)"
tm set -p -t "$ORCH" @wb_cmd "exec pi"

# Worker A: Pane sitzt im WORKTREE (-c), wie jeder echte Worker seit dem 04.08.
WORKER_WT="$(tm new-window -d -t "=wb-Cgwt:" -c "$WORKTREE_DIR" -P -F '#{pane_id}' "PATH='$PANE_PATH' TYPED_LOG='$TYPED_WT' pi" 2>/dev/null)"
tm set -p -t "$WORKER_WT" @wb_cmd "exec pi"
tm set -p -t "$WORKER_WT" @wb_worker wtworker

# Worker B: Pane OHNE eigenes Arbeitsverzeichnis -- sitzt (wie frueher jeder Worker)
# direkt in PROJECT. Gegenprobe: der PROJECT-Fallback muss weiter funktionieren.
WORKER_PROJ="$(tm new-window -d -t "=wb-Cgwt:" -c "$PROJECT_DIR" -P -F '#{pane_id}' "PATH='$PANE_PATH' TYPED_LOG='$TYPED_PROJ' pi" 2>/dev/null)"
tm set -p -t "$WORKER_PROJ" @wb_cmd "exec pi"
tm set -p -t "$WORKER_PROJ" @wb_worker projworker
sleep 2

GLOG="$TESTHOME/guard.log"
tm send-keys -t "$STEUER" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=2 ORCH_PCT=95 WARN_PCT=50 \
     ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$PROJECT_DIR' \
     context-guard '$ORCH' '$WORKER_WT:wtworker' '$WORKER_PROJ:projworker'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
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

echo "-- A: Worker im Worktree -- Warnung nennt den vollen Worktree-Pfad --"
WT_HANDOFF="$WORKTREE_DIR/HANDOFF-wtworker.md"
if warte_auf "$GLOG" "wtworker \($WORKER_WT\) at 90% -> handoff requested" 30; then
  ok "A1: die Kontextwarnung ging fuer den Worktree-Worker raus"
else
  bad "A1: keine 'handoff requested' fuer wtworker: $(tail -10 "$GLOG" 2>/dev/null)"
fi
if grep -qF "$WT_HANDOFF" "$GLOG" 2>/dev/null; then
  ok "A1: das Guard-Protokoll nennt den vollen Worktree-Pfad ($WT_HANDOFF)"
else
  bad "A1: der Worktree-Pfad fehlt im Guard-Protokoll: $(grep 'handoff requested' "$GLOG" 2>/dev/null)"
fi
if grep -qF "$WT_HANDOFF" "$TYPED_WT" 2>/dev/null; then
  ok "A1: der Worker selbst hat den vollen Worktree-Pfad in der Nachricht gesehen"
else
  bad "A1: der Worktree-Pfad kam nie bei der TUI des Workers an: $(cat "$TYPED_WT" 2>/dev/null)"
fi
if grep -q 'im Projektverzeichnis' "$TYPED_WT" 2>/dev/null; then
  bad "A1: die Nachricht sagt weiter 'im Projektverzeichnis' -- fuer den Worktree-Worker falsch"
else
  ok "A1: keine irrefuehrende 'im Projektverzeichnis'-Formulierung mehr in der Nachricht"
fi

echo
echo "-- A2: Uebergabe liegt NUR im Worktree -- Kompaktierung muss trotzdem ausgeloest werden --"
[ -f "$PROJECT_DIR/HANDOFF-wtworker.md" ] \
  && bad "A2: Testaufbau fehlerhaft -- HANDOFF-wtworker.md liegt bereits in PROJECT" \
  || ok "A2: PROJECT hat (wie im echten Vorfall) keine HANDOFF-Datei fuer wtworker"
printf 'Uebergabe (Test, geschrieben in den Worktree)\n' > "$WT_HANDOFF"

if warte_auf "$GLOG" "wtworker \($WORKER_WT\) -> /verdichte typed \(handoff persisted\)" 40; then
  ok "A2: die Wache hat die im Worktree liegende Uebergabe gefunden und kompaktiert -- DAS ist die behobene Regression"
else
  bad "A2: kein '/verdichte typed' fuer wtworker -- die Wache wartet weiter auf PROJECT: $(tail -15 "$GLOG" 2>/dev/null)"
fi
grep -q '/verdichte' "$TYPED_WT" && ok "A2: die TUI des Worktree-Workers hat '/verdichte' wirklich bekommen" \
                                  || bad "A2: '/verdichte' fehlt im Protokoll der TUI"
[ -f "$PROJECT_DIR/HANDOFF-wtworker.md" ] \
  && bad "A2: irgendetwas hat nachtraeglich doch eine HANDOFF-Datei in PROJECT angelegt" \
  || ok "A2: PROJECT blieb wtworker gegenueber die ganze Zeit ohne HANDOFF-Datei"

echo
echo "-- A3: WEITERARBEITEN nennt ebenfalls den Worktree-Pfad --"
if warte_auf "$GLOG" "wtworker \($WORKER_WT\) -> resumed" 150; then
  ok "A3: WEITERARBEITEN kam an -- die Kette handoff -> kompaktieren -> weiterarbeiten ist vollstaendig durchgelaufen"
else
  bad "A3: kein 'resumed' fuer wtworker: $(tail -15 "$GLOG" 2>/dev/null)"
fi
if grep -qF "$WT_HANDOFF" "$TYPED_WT" 2>/dev/null; then
  ok "A3: auch die WEITERARBEITEN-Nachricht nannte den vollen Worktree-Pfad"
else
  bad "A3: der Worktree-Pfad fehlt in der WEITERARBEITEN-Nachricht: $(cat "$TYPED_WT" 2>/dev/null)"
fi

echo
echo "-- B: Gegenprobe -- ein Worker ohne eigenes Arbeitsverzeichnis findet seine Uebergabe weiter in PROJECT --"
if warte_auf "$GLOG" "projworker \($WORKER_PROJ\) at 90% -> handoff requested" 30; then
  ok "B1: die Kontextwarnung ging auch fuer den PROJECT-Worker raus"
else
  bad "B1: keine 'handoff requested' fuer projworker: $(tail -15 "$GLOG" 2>/dev/null)"
fi
printf 'Uebergabe (Test, geschrieben in PROJECT)\n' > "$PROJECT_DIR/HANDOFF-projworker.md"
if warte_auf "$GLOG" "projworker \($WORKER_PROJ\) -> /verdichte typed \(handoff persisted\)" 40; then
  ok "B2: der PROJECT-Fallback aus handoff_candidates() funktioniert weiterhin"
else
  bad "B2: kein '/verdichte typed' fuer projworker -- der PROJECT-Fallback ist kaputtgegangen: $(tail -15 "$GLOG" 2>/dev/null)"
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
