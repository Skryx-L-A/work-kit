#!/usr/bin/env bash
# test-context-guard-absende-verschluckt.sh -- die Absende-Pruefung fuer die Kette
# handoff -> $HCOMPACT -> WEITERARBEITEN.
#
# ANLASS (2026-08-12, Worker chatsdk, Pane %86, Log wb-AI): "17:46 chatsdk (%86) at
# 80% -> handoff requested" stand im Protokoll -- das Enter war laut context-guard
# also raus. Trotzdem stand der Handoff-Text danach fertig getippt in der
# Eingabezeile, die Kompaktierung blieb aus, der Kontext lag weiter bei 812k. Ursache:
# schreib_text() und schreib_taste() gehen zwar seit jeher als ZWEI getrennte
# tmux-Aufruf, aber weder nudge() noch nudge_queue() pruefte je, was aus dem
# getippten Enter wurde -- beide meldeten unbedingt Erfolg (context-guard:1261ff vor
# diesem Fix). tmux send-keys schreibt in den Pane und kehrt sofort zurueck, ohne zu
# warten, bis die TUI die Tasten wirklich verarbeitet hat; bei einem langen Text kann
# das Neuzeichnen der Eingabebox laenger dauern als die eine Sekunde Pause davor.
#
# Dieser Test bildet GENAU diesen Verschluck-Fall nach -- nicht die tmux-interne
# Racebedingung selbst (die ist nicht deterministisch erzwingbar), sondern ihr
# BEOBACHTBARES Symptom: eine TUI, die ein Enter empfaengt (siehe FAKE_LOG), es aber
# nicht wirkt (der Text bleibt in der Eingabezeile stehen). Der Stellvertreter
# fake-worker-swallow.py tut das fuer das ERSTE Enter auf jeden frischen Text und
# nimmt erst das ZWEITE an -- an genau der Stelle, an der die Absende-Pruefung
# (context-guard: absenden_verifizieren(), GUARD_PROMPT_RE='^❯') nachschieben soll.
#
# NACHTRAG (2026-08-19, Auftrag zu den drei Kompaktierungen in wb-AI): fuer den
# Kompaktierbefehl SELBST gilt die "Nachhilfe" (zweites, internes Enter) nicht mehr --
# eine zweite Kompaktierung wirft Kontext weg, den die erste gerade erst gerettet hat,
# darum lieber einmal ungesendet und laut gemeldet als zweimal gesendet (siehe
# shell/context-guard: nudge_kompakt_einmalig(), test-context-guard-kompakt-einmal.sh
# fuer den Regressionstest dazu). Fuer Handoff-Anfrage und WEITERARBEITEN (reiner Text,
# wiederholtes Tippen bleibt harmlos) gilt die Nachhilfe unveraendert weiter. Szenario A
# unten ist entsprechend angepasst: die Kette bleibt fuer Schritt 1 selbstheilend, bricht
# ab Schritt 2 (Kompaktierbefehl) jetzt ABSICHTLICH ehrlich ab, statt sich durch einen
# zweiten Kompaktierversuch durchzumogeln.
#
# GEPRUEFT WIRD:
#   A  Ein Worker, dessen TUI jedes erste Enter schluckt: die Handoff-Anfrage (Schritt 1,
#      reiner Text ueber nudge_queue) laeuft trotzdem durch, MIT genau zwei Enter (eins
#      verschluckt, die Nachhilfe wirkt). Der Kompaktierbefehl (Schritt 2) bekommt seit
#      2026-08-19 KEINE interne Nachhilfe mehr: das eine, verschluckte Enter reicht nicht,
#      die Wache meldet ehrlich "NICHT verifiziert" und tippt ihn in diesem Zyklus NICHT
#      erneut -- macht insgesamt DREI Enter (zwei fuer Schritt 1, eins fuer den einen
#      Kompaktierversuch), nie mehr. Schritt 3 (WEITERARBEITEN) findet folgerichtig nie
#      statt, weil Schritt 2 nie als verifiziert gilt.
#   B  Ein Worker, dessen TUI NIE etwas annimmt (dauerhaft haengender Prompt, wie
#      der 2026-08-12-Fall im schlimmsten Fall aussehen koennte): die Wache behauptet
#      NIE "handoff requested" fuer ihn und sagt stattdessen ehrlich "NICHT
#      verifiziert". Die Gegenprobe zu A: vor dem urspruenglichen Fix waere fuer BEIDE
#      Faelle wortgleich "handoff requested" im Protokoll gestanden.
#
# ISOLATION: eigener Socket, eigenes HOME, eigene Registry -- wie die Schwester-Tests
# test-context-guard-registry.sh (dieselbe Grundstruktur: Harness-Id 'pi' mit
# erfundenem Kontextformat 'KTX <n> %' und Kompaktierbefehl '/verdichte', damit die
# Ladung ausschliesslich aus DIESER Registry stammen kann) und
# test-absende-pruefung.sh (derselbe raw-mode-Stellvertreter-Ansatz wie fake-tui.py,
# hier als eigenes, kleineres Skript fake-worker-swallow.py neben diesem Test).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-worker-swallow.py"

SOCKET="wbtest-cgverschluckt-$$"
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

# Dieselbe Registry-Form wie test-context-guard-registry.sh: Harness-Id 'pi', ein
# erfundenes Kontextformat, ein erfundener Kompaktierbefehl -- ein Treffer kann nur
# aus DIESER Registry stammen.
cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi (Absende-Pruefung)", "command": "pi",
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

echo "== test-context-guard-absende-verschluckt: die Absende-Pruefung fuer handoff -> \$HCOMPACT -> WEITERARBEITEN =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgv -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

STEUER="$(tm new-window -d -t "=wb-Cgv:" -P -F '#{pane_id}')"
ORCH="$(tm new-window -d -t "=wb-Cgv:" -P -F '#{pane_id}' "PATH='$PANE_PATH' cat")"

LOG_A="$TESTHOME/enter-schluckt.log"; : > "$LOG_A"
LOG_B="$TESTHOME/enter-hart.log"; : > "$LOG_B"
WA="swallowA"; WB="swallowB"

neuer_worker() {   # <fake-kind> <log> -> setzt PANE_ID
  local kind="$1" log="$2"
  PANE_ID="$(tm new-window -d -t "=wb-Cgv:" -P -F '#{pane_id}' \
      "PATH='$PANE_PATH' FAKE_KIND='$kind' FAKE_LOG='$log' FAKE_PCT=90 FAKE_PCT_NACH=10 FAKE_COMPACT_TRIGGER='/verdichte' pi" 2>/dev/null)"
  tm set -p -t "$PANE_ID" @wb_cmd "exec pi"
}
neuer_worker schluckt "$LOG_A"; WORKER_A="$PANE_ID"
neuer_worker hart     "$LOG_B"; WORKER_B="$PANE_ID"
sleep 2

GLOG="$TESTHOME/guard.log"
tm send-keys -t "$STEUER" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 ORCH_PCT=95 WARN_PCT=50 \
     ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$TESTHOME' \
     context-guard '$ORCH' '$WORKER_A:$WA' '$WORKER_B:$WB'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
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
enter_anzahl() { grep -c '^ENTER' "$1" 2>/dev/null | tr -d ' '; }

echo "-- A: Worker 'schluckt' -- die Kette laeuft trotz verschlucktem Enter durch --"

if warte_auf "$GLOG" "$WA \($WORKER_A\) at 90% -> handoff requested" 30; then
  ok "A1: die Handoff-Anfrage gilt als abgeschickt, obwohl das erste Enter verschluckt wurde"
else
  bad "A1: keine 'handoff requested' fuer $WA: $(tail -8 "$GLOG" 2>/dev/null)"
fi
N="$(enter_anzahl "$LOG_A")"
[ "$N" = "2" ] \
  && ok "A1: die TUI hat genau ZWEI Enter empfangen (eins verschluckt, die Nachhilfe wirkte)" \
  || bad "A1: $N Enter bei der TUI angekommen statt 2"

# Der Worker haette jetzt seine Uebergabe geschrieben -- das simuliert der Test.
printf 'Uebergabe (Test)\n' >"$TESTHOME/HANDOFF-$WA.md"

# Seit 2026-08-19 KEINE interne Nachhilfe mehr fuer den Kompaktierbefehl (siehe
# Kopfkommentar): das eine verschluckte Enter bleibt verschluckt, die Wache meldet
# ehrlich statt sich durchzumogeln -- und tippt NICHT erneut.
if warte_auf "$GLOG" "Kompaktierbefehl an $WORKER_A NICHT verifiziert" 30; then
  ok "A2: der Kompaktierbefehl wird ehrlich als NICHT verifiziert gemeldet (kein zweites Enter mehr fuer ihn)"
else
  bad "A2: keine 'Kompaktierbefehl ... NICHT verifiziert'-Zeile fuer $WORKER_A: $(tail -12 "$GLOG" 2>/dev/null)"
fi
if grep -qE "$WA \($WORKER_A\) -> /verdichte typed" "$GLOG" 2>/dev/null; then
  bad "A2: '/verdichte typed' steht faelschlich im Protokoll -- die Absendung war nie verifiziert"
else
  ok "A2: kein faelschliches '/verdichte typed' im Protokoll"
fi
N="$(enter_anzahl "$LOG_A")"
[ "$N" = "3" ] \
  && ok "A2: insgesamt drei Enter bei der TUI (zwei fuer den Handoff, EINS fuer den einen Kompaktierversuch)" \
  || bad "A2: $N Enter bei der TUI insgesamt statt 3"

# Kurze Stabilisierungspause statt eines langen Timeouts: ohne den Fix haette der
# naechste Poll (POLL unten ist kurz gesetzt) laengst einen zweiten Kompaktierversuch
# samt drittem Enter nachgelegt. Mit dem Fix bleibt $WORKER_A in `compacted` und wird
# in diesem Zyklus nie wieder angefasst -- Schritt 3 (WEITERARBEITEN) findet darum nie
# statt.
sleep 8
if grep -qE "$WA \($WORKER_A\) -> resumed" "$GLOG" 2>/dev/null; then
  bad "A3: 'resumed' steht im Protokoll -- WEITERARBEITEN haette nach einer unverifizierten Kompaktierung nie folgen duerfen"
else
  ok "A3: kein 'resumed' fuer $WA -- Schritt 3 findet folgerichtig nicht statt, Schritt 2 galt nie als verifiziert"
fi
N="$(enter_anzahl "$LOG_A")"
[ "$N" = "3" ] \
  && ok "A3: weiterhin genau drei Enter -- kein zweiter Kompaktierversuch in einem spaeteren Poll" \
  || bad "A3: $N Enter bei der TUI statt weiterhin 3 -- ein spaeterer Poll hat erneut getippt"
N_UNVERIF="$(grep -c "Kompaktierbefehl an $WORKER_A NICHT verifiziert" "$GLOG" 2>/dev/null | tr -d ' ')"
[ "$N_UNVERIF" = "1" ] \
  && ok "A3: genau EINE 'NICHT verifiziert'-Zeile fuer den Kompaktierbefehl -- nicht eine je Poll" \
  || bad "A3: ${N_UNVERIF}x 'NICHT verifiziert' fuer den Kompaktierbefehl (erwartet: 1)"

echo
echo "-- B: Worker 'hart' -- nie 'handoff requested', stattdessen ehrlich 'NICHT verifiziert' --"
if warte_auf "$GLOG" "an $WORKER_B NICHT verifiziert" 30; then
  ok "B1: die Wache meldet ehrlich, dass die Absendung an $WB nicht verifiziert werden konnte"
else
  bad "B1: keine 'NICHT verifiziert'-Zeile fuer $WB: $(tail -15 "$GLOG" 2>/dev/null)"
fi
if grep -qE "$WB \($WORKER_B\) at 90% -> handoff requested" "$GLOG" 2>/dev/null; then
  bad "B2: 'handoff requested' steht faelschlich fuer $WB im Protokoll -- der Text kam nie an"
else
  ok "B2: kein 'handoff requested' fuer $WB -- vor diesem Fix haette hier wortgleich wie bei A gestanden"
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
