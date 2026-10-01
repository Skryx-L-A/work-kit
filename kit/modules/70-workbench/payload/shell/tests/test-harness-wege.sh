#!/usr/bin/env bash
# test-harness-wege.sh — die doppelte Funktion `pane_harness` darf nicht auseinanderlaufen.
#
# Sie steht in shell/wb-revive UND in shell/context-guard. Die Doppelung ist Absicht:
# eine dritte Datei waere ein weiteres Ausrollteil, und faellt sie aus, ist der Guard
# still blind. Der Preis dafuer ist, dass zwei Fassungen auseinanderlaufen koennen —
# genau das faengt diese Suite ab, nach demselben Muster wie test-app-muster.sh die
# beiden Musterlisten gegeneinander haelt.
#
# Geprueft wird:
#   1  Beide Fassungen sind Zeichen fuer Zeichen gleich.
#   2  Die Ableitung stimmt auch inhaltlich: eingebauter Weg, Registry-Weg, und die
#      Faelle, die NICHT treffen duerfen ('--model claude-opus-5' ist kein
#      claude-Aufruf, ein fremdes Programm ist gar keiner).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d)"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

ausschnitt() {   # <datei> -> die Funktion pane_harness, ohne Kommentare drumherum
  awk '/^pane_harness\(\) \{/{drin=1} drin{print} drin && /^\}$/{exit}' "$1"
}

echo "== test-harness-wege: eine Ableitung, zwei Fassungen =="
A="$TESTHOME/a.sh"; B="$TESTHOME/b.sh"
ausschnitt "$REPO/wb-revive"     > "$A"
ausschnitt "$REPO/context-guard" > "$B"

[ -s "$A" ] && ok "pane_harness in wb-revive gefunden"     || bad "pane_harness fehlt in wb-revive"
[ -s "$B" ] && ok "pane_harness in context-guard gefunden" || bad "pane_harness fehlt in context-guard"
if cmp -s "$A" "$B"; then
  ok "1: beide Fassungen sind zeichengleich"
else
  bad "1: die Fassungen laufen auseinander:"
  diff "$A" "$B" | sed 's/^/        /'
fi

# Inhaltlich: die Funktion aus wb-revive wird geladen und befragt. Ohne wb-state im
# PATH bleibt der Registry-Zweig leer -- genau das ist auch die Zusage (der eingebaute
# Weg braucht die Registry nicht).
HOME="$TESTHOME"
# shellcheck disable=SC1090
. "$A"

pruefe() {   # <erwartet> <befehlszeile>
  local soll="$1" cmd="$2" ist
  ist="$(pane_harness "$cmd")"
  [ "$ist" = "$soll" ] && ok "2: '${cmd:0:52}' -> '${soll:-(leer)}'" \
                       || bad "2: '${cmd:0:52}' -> '$ist' statt '${soll:-(leer)}'"
}

echo
pruefe claude "cd /p && exec /Users/x/.local/bin/claude --model opus --effort high"
pruefe claude "exec claude --model opus"
pruefe pi     "cd /p && exec pi --provider ollama --model lmalpha:9b"
pruefe ""     "cd /p && exec aider --model ollama/lmalpha:9b"
pruefe ""     "sleep 300"
# Der haeufigste Fehlgriff: der Modellname traegt das Wort, der Aufruf ist ein anderer.
pruefe ""     "exec /usr/bin/env agy --model claude-opus-4-6-thinking"
# Registry-Weg ohne wb-state: leer, aber ohne Fehler.
pruefe ""     "exec /Users/x/.local/bin/wb-harness-run --model aider-lmalpha-9b --role worker"

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
