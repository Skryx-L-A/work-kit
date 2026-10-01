#!/bin/sh
# Von wb-harness-run geschrieben (SPEC-V4 6.3 Punkt 4). Nicht von Hand aendern:
# jeder Spawn schreibt diese Datei neu, sobald ihr Inhalt abweicht.
#
# Zweck: die Sitzungskennung des Harness an den Pane haengen, in dem er laeuft.
# Der Hook laeuft IM Prozess des Harness und sieht deshalb $TMUX_PANE.
# Er schreibt nichts ausser einer tmux-Option und endet immer mit 0.
set -u
[ -n "${TMUX_PANE:-}" ] || exit 0
sid=$(cat | /usr/bin/python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    for k in ("session_id", "sessionId", "conversation_id", "id"):
        v = d.get(k)
        if isinstance(v, str) and v:
            sys.stdout.write(v)
            break
' 2>/dev/null)
[ -n "$sid" ] || exit 0
t=$(command -v tmux 2>/dev/null) || exit 0
"$t" set-option -p -t "$TMUX_PANE" @wb_chat_session "$sid" >/dev/null 2>&1
exit 0
