#!/usr/bin/env bash
# test-worker-rueckfragen.sh -- der Schalter "Worker ohne Rueckfragen ihrer CLI"
# steht seit dem 06.08. im Menue. Bis heute las ihn niemand.
#
# Gemessen wird an der STARTZEILE eines Workers, nicht am Schalter:
#
#   1  Vorgabe (kein Eintrag): der Worker startet MIT
#      --dangerously-skip-permissions. Das ist der Zustand von gestern, und er
#      bleibt die Vorgabe -- aus heisst, dass jeder Worker an seiner eigenen
#      Rueckfrage stehenbleibt und ein Nachtlauf bis zum Morgen steht.
#   2  `workerSkipPermissions: false`: dieselbe Startzeile OHNE das Flag.
#   3  Der zweite Weg, ueber die Registry (`wb-state models resolve`), verhaelt
#      sich gleich -- sonst haette der Schalter ein Loch, sobald ein Worker
#      ueber die Registry statt ueber den eingebauten Zweig startet.
#   4  Ein ORCHESTRATOR ist kein Worker: fuer ihn bleibt das Flag, auch wenn der
#      Schalter aus ist.
#
# Gemessen wird an dem, was das Programm WIRKLICH bekommt: der falsche `claude`
# schreibt seine Argumente in eine Datei, bevor er sich wie ein Prompt verhaelt.
# Nichts Echtes startet.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME aus mktemp -d,
# eigene Registry. Die echte Einstellungsdatei und die echte Registry bleiben
# unberuehrt -- wb-state schreibt unter $HOME, und HOME zeigt hierher.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/shell"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-rueckfragen-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="r$(date +%s)$$$RANDOM"
ARGLOG="$TESTHOME/claude-argumente.log"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

aufraeumen() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS + 5))
  while [ $SECONDS -lt $d ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  # Das Ziel steht in einer eigenen Variablen und wird geprueft: waere
  # `mktemp -d` fehlgeschlagen, hiesse die naive Form `rm -rf ""`.
  local ziel="$TESTHOME"
  case "$ziel" in
    /*/tmp.*|/tmp/tmp.*|/var/folders/*) rm -rf "$ziel" ;;
    *) echo "WARNUNG: '$ziel' sieht nicht nach mktemp aus, nichts geloescht" >&2 ;;
  esac
}
trap aufraeumen EXIT
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== Worker-Rueckfragen (Socket $SOCKET, HOME $TESTHOME, Marke $MARKE) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-state" ] || ueberspringen "shell/wb-state fehlt"
command -v python3 >/dev/null 2>&1 || ueberspringen "python3 nicht im PATH"

# --- Die Testumgebung, vollstaendig selbst hergestellt ---------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent. Er schreibt ZUERST seine Argumente mit -- das ist die
# Messung -- und verhaelt sich danach so, dass pi-worker bis zum Absenden kommt:
# einmal das Bereitschaftszeichen, dann eine leere Eingabezeile. Er fuehrt
# nichts aus, echot den empfangenen Text aber weiter (die Absende-Pruefung
# belegt seit 2026-08-17 auch den Inhalt). pi-worker ruft ihn absolut unter
# ~/.local/bin/claude auf.
cat > "$TESTHOME/.local/bin/claude" <<SHIMEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$ARGLOG"
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec cat
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"

for leer in wb-grid context-guard wb-worktree; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-mensch"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

ARBEIT="$TESTHOME/arbeit"
pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" >>"$TESTHOME/pi.log" 2>&1
}
wbs() { env HOME="$TESTHOME" "$REPO/wb-state" "$@"; }
startzeile() { tail -1 "$ARGLOG" 2>/dev/null; }

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

# --- 1: die Vorgabe ---------------------------------------------------------
VORGABE="$(wbs settings get workerSkipPermissions)"
[ "$VORGABE" = "true" ] && ok "1: die Vorgabe steht auf an (workerSkipPermissions=true)" \
                        || bad "1: die Vorgabe ist '$VORGABE' statt true"

pi "wan$MARKE" claude-opus5 "$ARBEIT" "Aufgabe $MARKE"
ZEILE_AN="$(startzeile)"
case "$ZEILE_AN" in
  *--dangerously-skip-permissions*)
    ok "1: der Worker startet MIT dem Flag — an der Startzeile gemessen" ;;
  "")
    bad "1: der Worker hat gar nicht gestartet (kein Eintrag im Argument-Log); $(tail -3 "$TESTHOME/pi.log" | tr '\n' ' ')" ;;
  *)
    bad "1: das Flag fehlt schon bei der Vorgabe: $ZEILE_AN" ;;
esac

# --- 2: abgeschaltet --------------------------------------------------------
wbs settings set workerSkipPermissions false >/dev/null
pi "waus$MARKE" claude-opus5 "$ARBEIT" "Aufgabe $MARKE"
ZEILE_AUS="$(startzeile)"
case "$ZEILE_AUS" in
  *--dangerously-skip-permissions*)
    bad "2: das Flag steht immer noch in der Startzeile: $ZEILE_AUS" ;;
  "")
    bad "2: der zweite Worker hat nicht gestartet; $(tail -3 "$TESTHOME/pi.log" | tr '\n' ' ')" ;;
  *)
    ok "2: derselbe Aufruf startet OHNE das Flag ($ZEILE_AUS)" ;;
esac
# Und es ist wirklich dieselbe Zeile bis auf das Flag -- sonst haette sich
# irgendetwas anderes geaendert und die Messung waere wertlos.
OHNE_FLAG="$(printf '%s' "$ZEILE_AN" | sed 's/ --dangerously-skip-permissions//')"
if [ -n "$ZEILE_AUS" ] && [ "$OHNE_FLAG" = "$ZEILE_AUS" ]; then
  ok "2: die beiden Startzeilen unterscheiden sich in GENAU diesem Flag"
else
  bad "2: die Startzeilen unterscheiden sich noch woanders:
      an : $ZEILE_AN
      aus: $ZEILE_AUS"
fi

# --- 3: derselbe Schalter auf dem Registry-Weg ------------------------------
# `models resolve` baut die Startzeile fuer jeden registrierten Harness. Ohne
# dieselbe Bedingung dort haette der Schalter ein Loch.
printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/claude-echt-egal"
RES_AUS="$(wbs models resolve claude-sonnet-5 --role worker --dir "$ARBEIT" --name "t$MARKE" 2>&1)"
case "$RES_AUS" in
  *--dangerously-skip-permissions*) bad "3: der Registry-Weg haengt das Flag trotzdem an" ;;
  *"nicht startbar"*|*FEHLER*) bad "3: resolve scheiterte: $(printf '%s' "$RES_AUS" | head -2 | tr '\n' ' ')" ;;
  *) ok "3: der Registry-Weg laesst das Flag ebenfalls weg" ;;
esac

# --- 4: der Orchestrator ist kein Worker ------------------------------------
RES_ORCH="$(wbs models resolve claude-sonnet-5 --role orchestrator --dir "$ARBEIT" --name "t$MARKE" 2>&1)"
case "$RES_ORCH" in
  *--dangerously-skip-permissions*)
    ok "4: fuer den Orchestrator bleibt das Flag — der Schalter spricht von Workern" ;;
  *) bad "4: dem Orchestrator wurde das Flag mit weggenommen: $(printf '%s' "$RES_ORCH" | head -2 | tr '\n' ' ')" ;;
esac

# --- 5: wieder an, und das Flag ist zurueck ---------------------------------
wbs settings set workerSkipPermissions true >/dev/null
pi "wwieder$MARKE" claude-opus5 "$ARBEIT" "Aufgabe $MARKE"
case "$(startzeile)" in
  *--dangerously-skip-permissions*) ok "5: nach dem Wiedereinschalten ist das Flag zurueck" ;;
  *) bad "5: nach dem Wiedereinschalten fehlt das Flag: $(startzeile)" ;;
esac

# --- Die Zusage -------------------------------------------------------------
for echt in "$HOME/.claude/workbench/settings.json" "$HOME/.claude/workbench/models.json"; do
  if [ -f "$echt" ] && grep -q "$MARKE" "$echt" 2>/dev/null; then
    bad "die echte Datei $echt traegt das Erkennungsmerkmal dieses Laufs"
  else
    ok "unberuehrt: $(basename "$echt")"
  fi
done

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
