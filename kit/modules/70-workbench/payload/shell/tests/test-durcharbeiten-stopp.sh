#!/usr/bin/env bash
# test-durcharbeiten-stopp.sh -- ein Werkzeug überstimmt keinen Menschen.
#
# ANLASS (der Nutzer, 2026-09-21, wörtlich): „ich habe gerade versucht den qwen zu
# stoppen, es geht aber nicht weil sofort ein Wächterprompt zum weiterarbeiten
# kommt, das darf nicht passieren."
#
# `wb-durcharbeiten` stößt einen Worker wieder an, der seinen Zug ohne
# Werkzeugaufruf beendet hat. Als Stopp kannte sie nur ein GETIPPTES Wort. Ein
# Abbruch per Escape schickt keine Nachricht -- der Zug endet, die letzte
# Assistentennachricht hat weder Werkzeugaufruf noch DONE, also stieß sie sofort
# wieder an. Zweitens lief sie überhaupt in einer ORCHESTRATOR-Sitzung, weil
# deren Auftragstext zufällig den Pfad `.pi-workers/results/` enthielt.
#
# GEMESSEN, nicht geraten (21.09., eigene Ereignisprobe in einem echten
# Worker-Pane): ein abgebrochener Zug erscheint als `message_end` mit
# role "assistant" und `stopReason: "aborted"`; `agent_end` trägt dazu nichts,
# ein eigenes Abbruch-Ereignis gibt es nicht. Genau 1,5 ms nach dem Abbruch stand
# im Protokoll der Anstoß der Erweiterung.
#
# Geprüft wird hier, was NICHT passieren darf: nach einem Abbruch kommt ein
# Anstoß. Dazu die beiden Gegenproben — ohne sie wäre eine Erweiterung, die
# NIEMALS anstößt, genauso grün wie die richtige.
#
# Die Erweiterung ist TypeScript und läuft sonst nur in einer pi-Sitzung; hier
# fährt sie unter `deno` gegen eine Attrappe von `pi` (siehe
# durcharbeiten-probe.ts). Fehlt deno, ist das ein Grund zum Überspringen, der
# zur Maschine gehört und nicht zur Sache.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO/tests/durcharbeiten-probe.ts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/durcharb.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/durcharb.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

if ! command -v deno >/dev/null 2>&1; then
  echo "UEBERSPRUNGEN: nicht auf dieser Maschine: deno fehlt, die Erweiterung ist TypeScript"
  exit 77
fi

# tmux-Attrappe: die Erweiterung fragt damit die Rolle des eigenen Panes ab. Der
# echte tmux wird NICHT gefragt -- diese Suite fasst keine lebende Sitzung an.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/tmux" <<'EOF'
#!/bin/sh
# Antwortet auf `tmux show -p -t <pane> -v @wb_role` mit dem gewuenschten Wert.
case "$*" in
  *@wb_role*) printf '%s\n' "${WB_PROBE_ROLLE:-}" ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/tmux"

echo "== test-durcharbeiten-stopp: nach einem Abbruch kommt kein Anstoss =="
echo

AUS="$(cd "$REPO/tests" && PATH="$TMP/bin:$PATH" deno run --quiet --allow-env --allow-read --allow-run "$PROBE" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ]; then
  bad "Pruefstand lief nicht" "$(printf '%s' "$AUS" | tr '\n' '|' | cut -c1-300)"
else
  hole() { printf '%s\n' "$AUS" | awk -v f="$1" '$1==f {sub(/^.*anstoesse=/,""); print; exit}'; }

  N="$(hole worker-normal)"
  if [ "${N:-}" = "1" ]; then
    ok "A: ein Worker, der ohne Werkzeugaufruf endet, wird angestossen (Gegenprobe: $N)"
  else
    bad "A: kein Anstoss im Normalfall (anstoesse=${N:-?}) — die Erweiterung tut gar nichts mehr"
  fi

  N="$(hole worker-abgebrochen)"
  if [ "${N:-}" = "0" ]; then
    ok "B: nach einem vom Menschen abgebrochenen Zug kommt KEIN Anstoss"
  else
    bad "B: nach dem Abbruch kam ein Anstoss (anstoesse=${N:-?}) — genau Befund des Nutzers"
  fi

  N="$(hole orchestrator-normal)"
  if [ "${N:-}" = "0" ]; then
    ok "C: in einem Orchestrator-Pane bleibt sie stumm"
  else
    bad "C: im Orchestrator-Pane wurde angestossen (anstoesse=${N:-?})"
  fi
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
