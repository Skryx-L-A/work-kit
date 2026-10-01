#!/bin/bash
# test-wb-window-quittung.sh — prueft, dass wb-window auf die Quittungszeile
# wartet, die der URI-Handler der Extension schreibt (extension/src/
# uriReceiptLog.ts, ~/.local/state/wb-window-uri.log), statt blind zu senden
# und zu hoffen. Anlass (2026-08-04): eine gesendete URI liess sich von
# aussen nicht von einer verlorenen unterscheiden — eine halbe Stunde
# Diagnose fuer nichts.
#
# Fasst NIE ein echtes VS Code oder eine echte vscode://-URI an: `code` wird
# durch ein No-Op-Fake auf einem eigenen PATH ersetzt, die Quittungsdatei ist
# eine temporaere Datei ueber WB_WINDOW_RECEIPT_LOG, nie ~/.local/state, und
# HOME zeigt auf ein eigenes mktemp-Verzeichnis (Regel: Tests fassen die
# Live-Umgebung nie an).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # …/claude-workbench/shell
WB_WINDOW="${WB_WINDOW_BIN:-$REPO/wb-window}"
echo "Geprueft: $WB_WINDOW"
export HOME
HOME="$(mktemp -d)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

FAKE_BIN="$(mktemp -d)"
cat > "$FAKE_BIN/code" <<'EOF'
#!/bin/bash
# Fake-code: tut nur so, als sei die URI verschickt worden — fasst nichts an,
# oeffnet kein Fenster, ruft kein echtes VS Code.
exit 0
EOF
chmod +x "$FAKE_BIN/code"
export PATH="$FAKE_BIN:$PATH"

LOG="$(mktemp -u)"   # bewusst noch nicht angelegt — die erste Pruefung laeuft ohne Datei
export WB_WINDOW_RECEIPT_LOG="$LOG"

cleanup() { rm -rf "$FAKE_BIN" "$HOME"; rm -f "$LOG"; }
trap cleanup EXIT

echo "== Quittung erscheint rechtzeitig (Datei existiert vorher noch nicht) =="
(
  sleep 0.5
  printf '2026-08-04T09:36:00.000Z\treload\t$HOME/AI/claude-workbench\n' >> "$LOG"
) &
BGPID=$!
out=$(WB_WINDOW_TIMEOUT=5 "$WB_WINDOW" reload 2>&1); rc=$?
wait "$BGPID" 2>/dev/null
[ "$rc" -eq 0 ] && ok "Quittung da: exit 0" || bad "Quittung da: exit 0" "rc=$rc; out=$out"
case "$out" in
  *"angekommen"*"claude-workbench"*"reload"*) ok "Meldung nennt Fenster und Aktion" ;;
  *) bad "Meldung nennt Fenster und Aktion" "$out" ;;
esac

echo
echo "== Keine Quittung: Timeout greift, exit 4 =="
: > "$LOG"
out=$(WB_WINDOW_TIMEOUT=1 "$WB_WINDOW" reload 2>&1); rc=$?
[ "$rc" -eq 4 ] && ok "kein Empfang: exit 4" || bad "kein Empfang: exit 4" "rc=$rc; out=$out"
case "$out" in
  *"keine Quittung"*) ok "Meldung sagt 'keine Quittung'" ;;
  *) bad "Meldung sagt 'keine Quittung'" "$out" ;;
esac

echo
echo "== Alte Zeilen vor dem Senden zaehlen nicht als Quittung =="
printf '2026-08-04T08:00:00.000Z\tworker-tab\t/tmp/alt\n' > "$LOG"
out=$(WB_WINDOW_TIMEOUT=1 "$WB_WINDOW" reload 2>&1); rc=$?
[ "$rc" -eq 4 ] && ok "alte Zeile ignoriert: exit 4" \
  || bad "alte Zeile ignoriert: exit 4" "rc=$rc; out=$out (haette die alte Zeile faelschlich als Treffer genommen)"

echo
echo "== Neue Zeile NACH einer alten wird trotzdem erkannt =="
(
  sleep 0.5
  printf '2026-08-04T09:37:00.000Z\tworker-tab\t$HOME/AI/anderes-projekt\n' >> "$LOG"
) &
BGPID=$!
out=$(WB_WINDOW_TIMEOUT=5 "$WB_WINDOW" worker-tab 2>&1); rc=$?
wait "$BGPID" 2>/dev/null
[ "$rc" -eq 0 ] && ok "neue Zeile nach alter: exit 0" || bad "neue Zeile nach alter: exit 0" "rc=$rc; out=$out"
case "$out" in
  *"anderes-projekt"*"worker-tab"*) ok "Meldung nennt die NEUE Zeile, nicht die alte" ;;
  *) bad "Meldung nennt die NEUE Zeile, nicht die alte" "$out" ;;
esac

echo
echo "== Ein leerer Ordner in der Quittung wird lesbar dargestellt =="
: > "$LOG"
(
  sleep 0.5
  printf '2026-08-04T09:38:00.000Z\treload\t\n' >> "$LOG"
) &
BGPID=$!
out=$(WB_WINDOW_TIMEOUT=5 "$WB_WINDOW" reload 2>&1); rc=$?
wait "$BGPID" 2>/dev/null
[ "$rc" -eq 0 ] && ok "leerer Ordner: trotzdem exit 0" || bad "leerer Ordner: trotzdem exit 0" "rc=$rc; out=$out"
case "$out" in
  *"kein Ordner offen"*) ok "leerer Ordner wird als 'kein Ordner offen' gemeldet, nicht als leere Luecke" ;;
  *) bad "leerer Ordner wird als 'kein Ordner offen' gemeldet" "$out" ;;
esac

echo
echo "== Unbekanntes Kommando bleibt exit 1, ohne je auf die Quittung zu warten =="
: > "$LOG"
out=$("$WB_WINDOW" bogus 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "unbekanntes Kommando: exit 1" || bad "unbekanntes Kommando: exit 1" "rc=$rc"

echo
echo "== Ergebnis: $PASS ok, $FAIL FAIL =="
[ "$FAIL" -eq 0 ]
