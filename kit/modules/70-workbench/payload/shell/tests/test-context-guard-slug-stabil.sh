#!/bin/bash
# "Punkt 0" (2026-08-04): derselbe Orchestrator-Pane muss IMMER denselben Guard-Slug
# ergeben -- unabhaengig davon, ob im Moment der Abfrage gerade eine '-view'-Schwester
# der Session existiert. `tmux display -p -t <pane> '#{session_name}'` liefert fuer
# einen Pane einer Sessiongruppe je nach Zeitpunkt mal die Basis, mal die Sicht
# ('eigen' vs. 'eigen-view') -- gemessen live in Produktion: %0 der wb-AI-Session
# erscheint in EINEM `tmux list-panes -a`-Aufruf unter BEIDEN Namen. Ohne
# Normalisierung auf die Basis (context-guard's base_session_name(), Vorlage:
# wb-session-close's own_base_session()) wuerde derselbe Guard je nach Aufrufzeitpunkt
# einen ANDEREN Slug berechnen und seine gesamte Buchfuehrung (known-workers,
# done-notified, dialog-notified) in zwei inkompatible Dateisaetze zerreissen -- genau
# das, was die Vormarkierung im real gemessenen Fall wirkungslos gemacht hat.
#
# `--stop` ist der leichteste Weg, den Slug von aussen zu beobachten: er berechnet ihn
# ueber socket_slug() und beruehrt sonst nur eine Datei ($STOP_FILE), kein Guard muss
# dafuer laufen.
unset TMUX TMUX_PANE
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
GUARD_SRC="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
[ -x "$GUARD_SRC" ] || { echo "FAIL  $GUARD_SRC fehlt oder ist nicht ausfuehrbar"; exit 1; }
echo "Geprueft: $GUARD_SRC"
SOCK="wbtest-slugstabil-$$"
FAKEHOME="$(mktemp -d)"
SHIM=""
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK"
  rm -rf "$FAKEHOME" "$SHIM"
}
trap cleanup EXIT

mkdir -p "$FAKEHOME/.local/state/wb-context-guard"

# context-guard --stop ruft selbst unflagged `tmux ...` auf -- ohne Bindung faellt
# das auf den DEFAULT-Socket zurueck (siehe test-context-guard-backfill.sh, gleicher
# Vorfall 2026-08-04).
REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "FAIL  tmux nicht gefunden"; exit 1; }
SHIM="$(mktemp -d)"
cat > "$SHIM/tmux" <<EOF
#!/bin/sh
exec "$REALTMUX" -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

tmux -L "$SOCK" new-session -d -s wb-slugtest -c /tmp "cat"
ORCH=$(tmux -L "$SOCK" list-panes -t wb-slugtest -F '#{pane_id}' | head -1)
# Geerbte globale Hooks abschalten (regeln/tests-und-eingriffe.md, 2026-08-04):
# ein frischer Socket laedt trotzdem ~/.tmux.conf mit. Gemeinsamer Baustein
# statt der drei Zeilen, siehe lib-testwerkzeuge.sh.
tmux_live_hooks_kappen "$SOCK"

slug_via_stop() {   # -> Basisname der (einzigen) *.stop-Datei, danach aufgeraeumt
  HOME="$FAKEHOME" "$GUARD_SRC" --stop "$ORCH" >/dev/null 2>&1 || true
  local f name
  f=$(ls "$FAKEHOME/.local/state/wb-context-guard/"*.stop 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    name="$(basename "$f" .stop)"
    rm -f "$FAKEHOME/.local/state/wb-context-guard/"*.stop
    printf '%s' "$name"
  fi
}

echo "-- Slug OHNE existierende '-view' --"
SLUG1="$(slug_via_stop)"
[ -n "$SLUG1" ] && ok "Slug bestimmt: $SLUG1" || bad "kein Slug bestimmbar (kein .stop angelegt)"

echo "-- '-view'-Schwester anlegen (wie wb-worker-tab es tut) --"
tmux -L "$SOCK" new-session -d -t "=wb-slugtest" -s wb-slugtest-view
GRP="$(tmux -L "$SOCK" display -p -t "$ORCH" '#{session_group}' 2>/dev/null)"
[ "$GRP" = "wb-slugtest" ] && ok "Sessiongruppe steht (session_group=wb-slugtest)" \
                            || bad "Sessiongruppe fehlt (session_group='$GRP') -- Testaufbau fehlerhaft"

echo "-- Slug MIT existierender '-view' (derselbe Pane, derselbe Aufruf) --"
SLUG2="$(slug_via_stop)"
[ -n "$SLUG2" ] && ok "Slug bestimmt: $SLUG2" || bad "kein Slug bestimmbar (kein .stop angelegt)"

if [ -n "$SLUG1" ] && [ "$SLUG1" = "$SLUG2" ]; then
  ok "Slug bleibt gleich, ob '-view' existiert oder nicht ($SLUG1)"
else
  bad "Slug AENDERT sich mit der '-view' ($SLUG1 -> $SLUG2) -- Buchfuehrung wuerde zerfallen"
fi

echo "slug-stabil: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
