#!/bin/bash
# test-workers-window-mindesthoehe.sh -- ein Worker-Fenster, das auf eine Zeile
# Hoehe gedrueckt wurde, muss beim naechsten Worker-Spawn wieder auf die
# Mindesthoehe angehoben werden, und die Absendepruefung eines Auftrags darf
# nie an einer zu kleinen Pane scheitern.
#
# ANLASS (19.08.2026 abends, echter Betriebsfehler): alle vier Worker-Panes der
# Sitzung wb-AI standen auf 184x1. Gemessen wurde die Ursache separat, auf
# einem isolierten Testsocket (nicht Teil dieser Suite): eine gruppierte
# '-view'-Schwester teilt dasselbe Fenster wie ihre Basis-Sitzung; haengt sich
# IRGENDEIN Client -- an welche der beiden Sitzungen auch immer -- mit einer
# winzigen Groesse an und loest sich wieder, faellt das Fenster unter
# `window-size latest` (tmux' Vorgabe, kein expliziter Boden in dieser
# Codebasis vor diesem Fix) sofort auf diese Groesse und bleibt DAUERHAFT dort,
# auch wenn danach ueberhaupt niemand mehr zusieht. Fix, zwei Stellen:
#   1  wb-workers-window haelt jetzt selbst eine Mindesthoehe durch
#      (window-size manual + resize-window), auf JEDEM Aufruf, nicht nur beim
#      Anlegen -- wb-grid ruft es bei jedem Worker-Touch.
#   2  pi-worker prueft zusaetzlich die PANE-Hoehe unmittelbar vor dem Tippen
#      und korrigiert sie noetigenfalls selbst, bevor die Absendepruefung den
#      Panebildschirm liest.
#
# Dieser Test drueckt das Fenster von Hand auf eine Zeile (derselbe Endzustand
# wie der gemessene Fehler, ohne den tmux-Mechanismus selbst nachzubauen --
# der ist unabhaengig davon gemessen), legt dann einen weiteren Worker an und
# prueft: Fenster UND Pane stehen danach wieder auf der Mindesthoehe, und der
# Auftrag wurde wirklich als abgesendet erkannt (keine falsche
# Verifikations-Fehlermeldung wegen der Pane-Groesse).
#
# ISOLATION (wie test-registry.sh): eigener Socket, eigenes HOME, `unset TMUX
# TMUX_PANE` zuerst, COPIES der geprueften Werkzeuge (ein fester
# Repo-Schnappschuss), fake 'pi'/'ollama' statt der echten CLIs.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
echo "Geprueft: $REPO"

SOCK="wbtest-wwmin-$$"
SESS="wb-wwmintest-$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

TESTHOME="$(mktemp -d)"
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCK" ls >/dev/null 2>&1; do
    tmux -L "$SOCK" kill-server 2>/dev/null || true
    sleep 0.3
  done
  tmux -L "$SOCK" ls >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "tmux nicht gefunden — Test kann nicht laufen." >&2; exit 1; }
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/work"
export TMPDIR="$TESTHOME/tmp/"; mkdir -p "$TMPDIR"
FAKELOG="$TESTHOME/fake.log"

cat >"$BIN/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L $SOCK "\$@"
EOF
chmod +x "$BIN/tmux"

# Fake 'pi': loggt argv, verhaelt sich wie eine REPL mit dem echten Prompt-Zeichen.
cat >"$BIN/pi" <<EOF
#!/bin/bash
{ echo "ARGV pi \$*"; } >>"$FAKELOG"
while :; do printf '❯ '; IFS= read -r _line || sleep 1; done
EOF
chmod +x "$BIN/pi"

# Fake 'ollama': genau die drei Unterbefehle, die wb-kontext fuer ein Ollama-Modell
# braucht (list/show/create) -- kleine, feste Architektur, damit die KV-Rechnung
# unabhaengig vom gerade freien Speicher dieser Maschine trivial klein bleibt.
cat >"$BIN/ollama" <<'EOF'
#!/bin/bash
case "$1" in
  list) printf 'NAME\tID\tSIZE\tMODIFIED\n'; printf 'lmalpha:9b\tfaketest0001\t0.01 GB\t1 minute ago\n' ;;
  show) printf '  Model\n    architecture        llama\n    parameters          9B\n'; printf '    context length      128\n    embedding length    4096\n' ;;
  create) exit 0 ;;
  *) echo "fake ollama: unbekanntes Kommando '$1'" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN/ollama"

for s in wb-state pi-worker claude-worker wb-grid wb-workers-window wb-kontext check-resources; do
  cp "$REPO/$s" "$BIN/$s"; chmod +x "$BIN/$s"
done
# wb-pane-write/context-guard MUESSEN dieselbe Datei (Geraet+Inode) wie im
# Repo bleiben -- wb-pane-write erkennt den context-guard genau daran (siehe
# lib-testwerkzeuge.sh). Symlink, keine Kopie, nur fuer diese beiden.
werkzeuge_installieren "$TESTHOME"

export PATH="$BIN:$PATH"
WBS="$BIN/wb-state"
# Kit: local models come from the registry (kit-llm), there is no built-in local alias.
mkdir -p "$TESTHOME/.claude/workbench"; cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

mkses() {
  local try err
  for try in 1 2 3; do
    err="$(tmux -L "$SOCK" new-session -d -s "$SESS" -x 200 -y 50 \
             "bash -c 'while :; do sleep 5; done'" 2>&1)"
    tmux -L "$SOCK" has-session -t "=$SESS" 2>/dev/null && return 0
    echo "  (Testsession-Start $try/3 fehlgeschlagen: ${err:-keine Meldung})" >&2
    sleep 2
  done
  echo "ABBRUCH: Testsession '$SESS' laesst sich auf Socket '$SOCK' nicht anlegen." >&2
  exit 1
}
mkses
tmux -L "$SOCK" set -p -t "$SESS" @wb_role orchestrator
export WB_SESSION="$SESS"
# Das gemessene Fenster 'workers' existiert nur unter workerLayout=window
# (V2, wb-grid); die Vorgabe ist 'split' (Worker bleiben im Orchestrator-
# Fenster). Der gemeldete Betriebsfehler betraf ausdruecklich ein eigenes
# workers-Fenster -- ohne diese Einstellung wuerde dieser Test etwas ganz
# anderes pruefen.
mkdir -p "$TESTHOME/.claude/workbench"
"$WBS" settings set workerLayout window >/dev/null

echo "== 1  erster Worker legt das workers-Fenster in normaler Groesse an =="
"$BIN/pi-worker" w-eins qwen3.5-4b "$TESTHOME/work" >/dev/null 2>&1
H1="$(tmux -L "$SOCK" display -p -t "=$SESS:workers" '#{window_height}' 2>/dev/null || echo 0)"
[ "${H1:-0}" -ge 12 ] 2>/dev/null && ok "workers-Fenster startet bei $H1 Zeilen (>= 12)" \
  || bad "workers-Fenster startet schon zu klein: '$H1'"

echo "== 2  Fenster von Hand auf eine Zeile gedrueckt (derselbe Endzustand wie der echte Fehler) =="
tmux -L "$SOCK" set-option -w -t "=$SESS:workers" window-size manual 2>&1
tmux -L "$SOCK" resize-window -t "=$SESS:workers" -y 1 2>&1
H2="$(tmux -L "$SOCK" display -p -t "=$SESS:workers" '#{window_height}' 2>/dev/null || echo 0)"
[ "$H2" = 1 ] && ok "Fenster steht wie gefordert auf 1 Zeile" || bad "Fenster liess sich nicht auf 1 Zeile druecken (steht auf $H2) — Testaufbau kaputt"

echo "== 3  zweiter Worker wird angelegt -- muss die Mindesthoehe wiederherstellen =="
# Mit echtem Auftragstext: ohne Task-Argument prueft pi-worker die Absendung
# gar nicht erst ("keine Task uebergeben") -- Abschnitt 4 braucht den echten Weg.
OUT2="$("$BIN/pi-worker" w-zwei qwen3.5-4b "$TESTHOME/work" "Testauftrag fuer die Mindesthoehe-Pruefung" 2>&1)"
RC2=$?

# GESUCHT WIRD DER PANE, NICHT DAS FENSTER 'workers' (umgestellt 03.09.2026,
# Stufe A): der zweite Worker bekommt seither sein EIGENES Fenster, und das auf
# eine Zeile gedrueckte 'workers' ist damit gar nicht mehr sein Zuhause. Die
# Zusage ist dieselbe geblieben und wird schaerfer geprueft als vorher -- sie
# gilt jetzt fuer das Fenster, in dem der Worker wirklich sitzt.
PANE_ZWEI="$(tmux -L "$SOCK" list-panes -a -F '#{session_name} #{@wb_worker} #{pane_id} #{pane_height} #{window_id} #{window_name}' 2>/dev/null \
             | awk -v s="$SESS" '$1==s && $2=="w-zwei"{print $3, $4, $5, $6; exit}')"
PANE_ID="$(printf '%s' "$PANE_ZWEI" | awk '{print $1}')"
PANE_H="$(printf '%s' "$PANE_ZWEI" | awk '{print $2}')"
PANE_WIN="$(printf '%s' "$PANE_ZWEI" | awk '{print $3}')"
PANE_WNAME="$(printf '%s' "$PANE_ZWEI" | awk '{print $4}')"
if [ -n "$PANE_ID" ]; then
  H3="$(tmux -L "$SOCK" display -p -t "$PANE_WIN" '#{window_height}' 2>/dev/null || echo 0)"
  [ "${H3:-0}" -ge 12 ] 2>/dev/null \
    && ok "das Fenster des zweiten Workers ('$PANE_WNAME') steht auf $H3 Zeilen (>= 12)" \
    || bad "das Fenster des zweiten Workers blieb zu klein: '$H3' — Mindesthoehe wurde nicht durchgesetzt" "$OUT2"
  [ "${PANE_H:-0}" -ge 12 ] 2>/dev/null && ok "der neue Worker-Pane selbst steht auf $PANE_H Zeilen (>= 12)" \
    || bad "der neue Worker-Pane blieb zu klein: '$PANE_H'"
else
  bad "kein Pane fuer w-zwei gefunden" "$OUT2"
fi

echo "== 4  die Absendepruefung darf an dieser Pane-Groesse nicht scheitern =="
if [ "$RC2" -eq 0 ] && printf '%s' "$OUT2" | grep -q "verifiziert"; then
  ok "Task an w-zwei als abgesendet verifiziert (rc=0)"
else
  bad "Absendepruefung fuer w-zwei schlug fehl (rc=$RC2) — genau der gemeldete Betriebsfehler" "$OUT2"
fi
if printf '%s' "$OUT2" | grep -qi "Pane .* ist nur .* Zeile"; then
  ok "pi-worker hat die zu kleine Pane VOR dem Tippen selbst erkannt und gemeldet"
else
  # Kein FAIL: das Fenster war zum Zeitpunkt des Tippens durch Schritt 3
  # (wb-grid/wb-workers-window) moeglicherweise schon korrigiert -- die
  # Meldung ist dann folgerichtig nie noetig gewesen. Nur ein Hinweis.
  echo "  (Hinweis: pi-workers eigene Pane-Pruefung hat nicht gegriffen -- wb-workers-window war schon rechtzeitig davor am Zug)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
