#!/usr/bin/env bash
# test-context-guard-fremdharness.sh — die FUENFTE Quelle: die Sitzungsdatei, die ein
# fremder Harness selbst schreibt.
#
# Anlass (Messung 2026-08-08): codex, aider und agy zeigen ihre Kontextauslastung
# NIRGENDS an. Fuer sie gibt es deshalb auch kein contextPattern, das man eintragen
# koennte — die vierte Quelle laeuft ins Leere, und ein Worker auf einem dieser drei
# Harnesses lief unbewacht. Zwei von ihnen schreiben die Zahlen aber in eine Datei:
# codex in ~/.codex/sessions/**/rollout-*.jsonl (Verbrauch UND Fenster), aider in
# .aider.chat.history.md im Arbeitsverzeichnis (nur den Verbrauch).
#
# Geprueft wird, in zwei Laeufen:
#   A1  codex-rollout: die Auslastung kommt aus der Sitzungsdatei, die Quelle heisst
#       'session', und der Nenner stammt aus derselben Datei (model_context_window).
#   A2  Ein token_count-Satz mit "info": null wird uebersprungen statt als Null gelesen
#       — genau so steht er in der echten Sitzung, die am erschoepften Kontingent starb.
#   B1  aider-chat-history: die Zahl kommt aus '> Tokens: 6.1k sent', der Nenner aus
#       contextWindow des Modells, und die 'k'-Schreibweise wird richtig gelesen.
#   B2  Nur die LAUFENDE Sitzung zaehlt: in derselben Datei steht davor eine aeltere
#       Sitzung mit 9.5k (95 %). Waere der Abschnitt nach dem letzten
#       '# aider chat started at' nicht abgeschnitten, stuende 95 statt 61 im Protokoll.
#   B3  Zwei gleichzeitig lebende codex-Sitzungen im selben Verzeichnis -> BLIND, keine
#       Zahl. Welche zum Pane gehoert, ist nicht entscheidbar, und eine falsche NIEDRIGE
#       Zahl verschluckt die Warnung still.
#   B4  Eine Sitzungsdatei aelter als maxAgeSec -> BLIND statt einer fremden Zahl aus
#       einem frueheren Lauf im selben Verzeichnis.
#   B5  aider ohne contextWindow am Modell -> BLIND, und die Meldung nennt das fehlende
#       Feld. Der Nenner wird NICHT geraten.
#   B6  Ein Harness ohne beides (agy) -> BLIND, und die Meldung nennt contextPattern UND
#       die fehlende lesbare Sitzungsquelle (den session-Block).
#
# Alle Zahlen stammen aus FIXTUREN (aufgezeichnete Dateien im Testverzeichnis), nie aus
# einem laufenden codex oder aider. Die Formate der Fixturen sind an den echten Dateien
# abgelesen: an den vier Rollouts unter ~/.codex/sessions und an einer aider-Sitzung vom
# 2026-08-08 (aider 0.86.2 + ollama/qwen3:1.7b, eigener Socket, eigenes HOME).
#
# SICHERHEIT: eigener Socket, eigenes HOME, eigene Registry, tmux ohne ~/.tmux.conf.
# Der Guard laeuft in einem PANE des Testservers, damit seine eigenen tmux-Aufrufe
# dorthin gehen und nicht auf 'default' (Vorfall 2026-08-04). Er wird am Ende ueber
# seine gemerkte PID beendet, nicht durch Abraeumen seiner Umgebung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-cgfremd-$$"
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
for w in context-guard wb-state wb-session-load; do
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

# Registry dieses Laufs: drei fremde Harnesses, keiner mit contextPattern — genau die
# Lage, in der die vierte Quelle nichts hergibt.
cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "codex", "label": "Pruef-codex", "command": "codex", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "STILL", "promptPattern": "^STILL",
      "contextPattern": null, "compactCommand": null,
      "session": {
        "via": "sessionFile",
        "format": "codex-rollout",
        "ort": "~/codexsitzungen/*/rollout-*.jsonl",
        "maxAgeSec": 43200,
        "zuordnung": "cwd", "live": true, "eingabe": "pane",
        "probe": {"datum": "2026-08-08", "beleg": "Fixtur dieser Suite"}
      }
    },
    {
      "id": "aider", "label": "Pruef-aider", "command": "aider", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "STILL", "promptPattern": "^STILL",
      "contextPattern": null, "compactCommand": null,
      "session": {"via": "sessionFile", "format": "aider-chat-history",
                  "ort": ".aider.chat.history.md", "zuordnung": "cwd", "live": true,
                  "eingabe": "pane",
                  "probe": {"datum": "2026-08-08", "beleg": "Fixtur dieser Suite"}}
    },
    {
      "id": "agy", "label": "Pruef-agy", "command": "agy", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "STILL", "promptPattern": "^STILL",
      "contextPattern": null, "compactCommand": null,
      "session": {"via": "", "grund": "Fixtur: dieser Harness kann es nicht", "live": false,
                  "eingabe": "pane",
                  "probe": {"datum": "2026-08-08", "beleg": "Fixtur dieser Suite"}}
    }
  ],
  "models": [
    {"id": "pruef-codex", "label": "Pruef-codex", "harness": "codex", "provider": "pruefprovider",
     "modelRef": "pruef", "roles": ["worker", "orchestrator"]},
    {"id": "pruef-aider", "label": "Pruef-aider", "harness": "aider", "provider": "pruefprovider",
     "modelRef": "pruef", "roles": ["worker", "orchestrator"], "contextWindow": 10000},
    {"id": "pruef-aider-ohne-fenster", "label": "Pruef-aider ohne Fenster", "harness": "aider",
     "provider": "pruefprovider", "modelRef": "pruef", "roles": ["worker"]},
    {"id": "pruef-agy", "label": "Pruef-agy", "harness": "agy", "provider": "pruefprovider",
     "modelRef": "pruef", "roles": ["worker", "orchestrator"]}
  ]
}
REGEOF

# Die Fixturen ----------------------------------------------------------------
# 1) codex-Rollout. Aufbau wie in den echten Dateien: erste Zeile session_meta mit dem
#    Arbeitsverzeichnis, danach je Zug ein event_msg/token_count. Der LETZTE Satz traegt
#    "info": null (so steht er in der Sitzung, die am erschoepften Kontingent starb) und
#    muss uebersprungen werden; davor stehen 82 000 von 100 000 Token.
rollout_schreiben() {   # <datei> <cwd> <letzte-tokenzahl>
  cat > "$1" <<ROLLEOF
{"timestamp":"2026-08-08T10:00:00.000Z","type":"session_meta","payload":{"session_id":"pruef","cwd":"$2","originator":"codex-tui","cli_version":"0.146.0"}}
{"timestamp":"2026-08-08T10:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
{"timestamp":"2026-08-08T10:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"input_tokens":19000,"output_tokens":1000,"total_tokens":20000},"model_context_window":100000}}}
{"timestamp":"2026-08-08T10:03:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":980000},"last_token_usage":{"input_tokens":81000,"output_tokens":1000,"total_tokens":$3},"model_context_window":100000}}}
{"timestamp":"2026-08-08T10:04:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"premium"}}}
ROLLEOF
}

# 2) aider-Verlauf. Zwei Sitzungen in EINER Datei — so haengt aider an, wenn im selben
#    Arbeitsbaum ein zweites Mal gestartet wird. Gueltig ist nur die zweite.
aider_verlauf_schreiben() {   # <datei>
  cat > "$1" <<AIDEOF

# aider chat started at 2026-08-08 10:00:00

> Aider v0.86.2
> Model: pruef with whole edit format

#### alte Sitzung, fast voll

OK

> Tokens: 9.5k sent, 200 received.

# aider chat started at 2026-08-08 19:00:00

> Aider v0.86.2
> Model: pruef with whole edit format

#### neue Sitzung

OK

> Tokens: 6.1k sent, 300 received.
AIDEOF
}

# Die Fake-CLI: ein Bildschirm ohne jede Zahl. Damit kann KEINE der vier Quellen davor
# etwas lesen — ein Treffer kann nur aus der Sitzungsdatei stammen.
cat > "$SHIM/stumm" <<'STEOF'
#!/bin/sh
printf '\n\n\nSTILL: dieser Harness zeigt keine Auslastung\nkeine Zahlen hier\n'
while IFS= read -r zeile; do echo "GETIPPT: $zeile" >> "$GETIPPT"; done
sleep 600
STEOF
chmod +x "$SHIM/stumm"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
GETIPPT="$TESTHOME/getippt.log"; : > "$GETIPPT"

echo "== test-context-guard-fremdharness: die Sitzungsdatei als fuenfte Quelle =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgfremd -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

neuer_pane() {   # neuer_pane <arbeitsverzeichnis> <modell-id> -> Pane-Id
  local p
  p="$(tm new-window -d -t "=wb-Cgfremd:" -c "$1" -P -F '#{pane_id}' \
       "PATH='$PANE_PATH' GETIPPT='$GETIPPT' stumm" 2>/dev/null)"
  # Der Guard erkennt den Harness an dieser Zeile: die Registry-Form, in der der
  # Harness am Modell haengt (wie sie wb-harness-run wirklich startet).
  tm set -p -t "$p" @wb_cmd "$HOME/.local/bin/wb-harness-run --model $2 --role worker"
  printf '%s' "$p"
}

guard_starten() {   # guard_starten <orch> [<worker>:<name> ...]
  GLOG="$TESTHOME/guard.$RANDOM.log"
  local args="'$1'" a
  shift
  for a in "$@"; do args="$args '$a'"; done
  tm send-keys -t "$STEUER" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=2 ORCH_PCT=50 WARN_PCT=50 \
       ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$TESTHOME' \
       context-guard $args; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
  sleep 2
  GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"
}
warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.5
  done
  return 0
}
guard_stoppen() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
  sleep 1
  if [ -n "$GUARDPID" ] && kill -0 "$GUARDPID" 2>/dev/null; then
    bad "Aufraeumen: Guard $GUARDPID laeuft noch"
  fi
  GUARDPID=""
}

STEUER="$(tm new-window -d -t "=wb-Cgfremd:" -P -F '#{pane_id}')"

# ── Lauf A: codex liest seine eigene Sitzungsdatei ────────────────────────
WORK_CODEX="$TESTHOME/arbeit-codex"; mkdir -p "$WORK_CODEX"
mkdir -p "$TESTHOME/codexsitzungen/2026-08-08"
rollout_schreiben "$TESTHOME/codexsitzungen/2026-08-08/rollout-A.jsonl" "$WORK_CODEX" 82000

ORCH="$(neuer_pane "$WORK_CODEX" pruef-codex)"
sleep 2

echo "-- A: codex-rollout als Quelle --"
guard_starten "$ORCH"

if warte_auf "$GLOG" 'at 82% \(session\)' 25; then
  ok "A1: die Auslastung kommt aus der Sitzungsdatei (82 %, Quelle 'session', Nenner aus der Datei)"
else
  ok_zeile="$(tail -5 "$GLOG" 2>/dev/null)"
  bad "A1: keine Zeile 'at 82% (session)' im Guard-Log: $ok_zeile"
fi
grep -qE 'at (0|20)% \(session\)' "$GLOG" \
  && bad "A2: ein token_count mit 'info': null oder ein aelterer Satz wurde gelesen" \
  || ok "A2: der Satz mit \"info\": null wurde uebersprungen, gelesen wurde der letzte gueltige"
guard_stoppen

# ── Lauf B: aider, und die vier Faelle, in denen bewusst NICHTS gemeldet wird ──
echo
echo "-- B: aider-Verlauf, Mehrdeutigkeit, Alter, fehlender Nenner, fehlendes Feld --"
WORK_AIDER="$TESTHOME/arbeit-aider"; mkdir -p "$WORK_AIDER"
aider_verlauf_schreiben "$WORK_AIDER/.aider.chat.history.md"

WORK_AMBIG="$TESTHOME/arbeit-ambig"; mkdir -p "$WORK_AMBIG"
mkdir -p "$TESTHOME/codexsitzungen/ambig"
rollout_schreiben "$TESTHOME/codexsitzungen/ambig/rollout-B1.jsonl" "$WORK_AMBIG" 82000
rollout_schreiben "$TESTHOME/codexsitzungen/ambig/rollout-B2.jsonl" "$WORK_AMBIG" 60000

WORK_ALT="$TESTHOME/arbeit-alt"; mkdir -p "$WORK_ALT"
mkdir -p "$TESTHOME/codexsitzungen/alt"
rollout_schreiben "$TESTHOME/codexsitzungen/alt/rollout-C.jsonl" "$WORK_ALT" 82000
touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" \
      "$TESTHOME/codexsitzungen/alt/rollout-C.jsonl"

WORK_OHNE="$TESTHOME/arbeit-ohne-fenster"; mkdir -p "$WORK_OHNE"
aider_verlauf_schreiben "$WORK_OHNE/.aider.chat.history.md"

ORCH_B="$(neuer_pane "$WORK_AIDER" pruef-aider)"
W_AMBIG="$(neuer_pane "$WORK_AMBIG" pruef-codex)"
W_ALT="$(neuer_pane "$WORK_ALT" pruef-codex)"
W_OHNE="$(neuer_pane "$WORK_OHNE" pruef-aider-ohne-fenster)"
W_AGY="$(neuer_pane "$TESTHOME" pruef-agy)"
sleep 2

guard_starten "$ORCH_B" "$W_AMBIG:wambig" "$W_ALT:walt" "$W_OHNE:wohne" "$W_AGY:wagy"

if warte_auf "$GLOG" 'at 61% \(session\)' 25; then
  ok "B1: aiders '> Tokens: 6.1k sent' wird gelesen, Nenner aus contextWindow (61 %)"
  ok "B2: nur die laufende Sitzung zaehlt — die 9.5k (95 %) der Vorsitzung blieben aussen vor"
else
  if grep -qE 'at 95% \(session\)' "$GLOG"; then
    bad "B1/B2: gelesen wurde die VORHERIGE aider-Sitzung (95 %) statt der laufenden (61 %)"
  else
    bad "B1: keine Zeile 'at 61% (session)': $(tail -5 "$GLOG" 2>/dev/null)"
  fi
fi

if warte_auf "$GLOG" 'wambig .*BLIND' 20; then
  ok "B3: zwei lebende codex-Sitzungen im selben Verzeichnis -> BLIND statt einer geratenen Zahl"
else
  bad "B3: der mehrdeutige Pane wurde nicht als BLIND gemeldet: $(grep -c . "$GLOG") Zeilen"
fi
grep -qE 'wambig .*at [0-9]+%' "$GLOG" \
  && bad "B3: fuer den mehrdeutigen Pane wurde doch eine Zahl gemeldet" \
  || ok "B3: fuer den mehrdeutigen Pane wurde keine Zahl gemeldet"

if warte_auf "$GLOG" 'walt .*BLIND' 20; then
  ok "B4: die veraltete Sitzungsdatei wird nicht gelesen -> BLIND"
else
  bad "B4: der Pane mit der alten Sitzungsdatei wurde nicht als BLIND gemeldet"
fi

if warte_auf "$GLOG" 'wohne .*BLIND' 20; then
  if grep -q 'wohne .*kein contextWindow' "$GLOG"; then
    ok "B5: ohne contextWindow wird kein Nenner geraten, und die Meldung nennt das Feld"
  else
    bad "B5: BLIND-Meldung ohne Hinweis auf contextWindow: $(grep 'wohne' "$GLOG" | head -1)"
  fi
else
  bad "B5: der aider-Pane ohne contextWindow wurde nicht als BLIND gemeldet"
fi

if warte_auf "$GLOG" 'wagy .*BLIND' 20; then
  if grep -q "wagy .*weder contextPattern noch eine lesbare Sitzungsquelle" "$GLOG"; then
    ok "B6: der Harness ohne beide Felder wird benannt, samt beider fehlender Felder"
  else
    bad "B6: BLIND-Meldung ohne Nennung beider Felder: $(grep 'wagy' "$GLOG" | head -1)"
  fi
else
  bad "B6: der agy-Pane wurde nicht als BLIND gemeldet"
fi
guard_stoppen

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
