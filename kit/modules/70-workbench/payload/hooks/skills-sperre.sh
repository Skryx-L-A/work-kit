#!/bin/bash
# skills-sperre.sh -- PreToolUse/Bash, /Skill, /Read|Grep|Glob und
# /Write|Edit|MultiEdit|NotebookEdit: ein Agentenzug nutzt nur die Skills aus
# seiner skills.json (docs/AGENTS-PLAN.md, Abschnitt 3 "Die Sperre" und
# Abschnitt 14 "Sicherungen"; docs/AGENTS-SKILLS.md).
#
# Event: PreToolUse, vier Matcher, derselbe Aufruf. Die gesamte Logik liegt in
# lib/skills_sperre.py; dieses Skript ist der schmale Einstieg.
#
# NICHT REGISTRIERT: die Registrierung laeuft ueber
# skills-sperre.settings-snippet.json neben dieser Datei -- der Traeger oder
# der Orchestrator traegt die Eintraege beim Ausrollen ein.
#
# Umgebung (setzt der Traeger, siehe agents_traeger._zugumgebung):
# WB_AGENT_ZUG markiert den Agentenkontext; WB_AGENT_ID und WB_WELT binden ihn.
# Fehlen alle drei ausserhalb eines Zuges, tut das Skript nichts. Optional
# WB_SKILLS_JSON (muss auf <WB_WELT>/agents/<id>/skills.json zeigen).
#
# Verhalten: die stdout MUSS durchgehen (Verweigerung als
# hookSpecificOutput.permissionDecision=deny-JSON); stderr geht nach
# <WB_WELT>/agents/<id>/skills-sperre.log, sonst nach /dev/null.
#
# Frist: FAIL-CLOSED wie die Rollen-Sperre. Der Kern verweigert bei seinem
# eigenen Alarm (7 s) selbst. Haengt er trotzdem, beendet diese Huelle nach
# 8 s seine Prozessgruppe samt Kindern und schreibt selbst ein deny-JSON --
# beides vor der 10-Sekunden-Grenze des Settings-Eintrags. Ebenso verweigert
# die Huelle, wenn der Kern fehlt oder ohne Entscheidung mit einem Fehler endet.
set -uo pipefail

HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HOOKS_DIR/lib/skills_sperre.py"
FRIST=8

verweigern() {
  printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Skills lock: %s"}}\n' "$1"
  exit 0
}

# WB_AGENT_ZUG stammt aus der nur lesbar eingebundenen Zugbeschreibung. Der
# Agent kann die Elternumgebung, aus der der Harness den Hook startet, nicht
# entfernen. Im so markierten Zug ist eine fehlende Bindung deshalb ein Fehler.
if [ -n "${WB_AGENT_ZUG:-}" ] && { [ -z "${WB_AGENT_ID:-}" ] || [ -z "${WB_WELT:-}" ]; }; then
  verweigern "Agent turn without binding: WB_AGENT_ID and WB_WELT must both be set."
fi

# Ohne Agentenzug greift der Hook nicht -- keine Ausgabe.
[ -n "${WB_AGENT_ID:-}" ] || [ -n "${WB_WELT:-}" ] || exit 0

[ -f "$LIB" ] || verweigern "check core lib/skills_sperre.py is missing -- without a check nothing is allowed."
command -v python3 >/dev/null 2>&1 || verweigern "python3 is missing -- without a check nothing is allowed."
command -v perl >/dev/null 2>&1 || verweigern "perl is missing, the time guard cannot limit the check safely."

std_err_ziel="/dev/null"
if [[ "${WB_AGENT_ID:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && [ -d "${WB_WELT:-}/agents/$WB_AGENT_ID" ] \
   && [ ! -L "${WB_WELT:-}/agents/$WB_AGENT_ID" ]; then
  log="$WB_WELT/agents/$WB_AGENT_ID/skills-sperre.log"
  if [ ! -L "$log" ] && { : >>"$log"; } 2>/dev/null; then
    std_err_ziel="$log"
  fi
fi

ausgabe="$(mktemp "${TMPDIR:-/tmp}/skills-sperre.XXXXXX")" \
  || verweigern "the time guard cannot create an output file."
zeitmarker="${ausgabe}.frist"
trap 'rm -f "$ausgabe" "$zeitmarker"' EXIT

# stdin ausdruecklich weiterreichen (ein Hintergrundjob bekaeme sonst
# /dev/null); eigene Prozessgruppe, damit ein Signal auch die Pruefkette trifft.
exec 3<&0
perl -e 'setpgrp(0, 0) or die "setpgrp: $!"; exec @ARGV' \
  python3 "$LIB" <&3 >"$ausgabe" 2>>"$std_err_ziel" &
pid=$!
exec 3<&-

(
  sleep "$FRIST" & schlaf=$!
  trap 'kill "$schlaf" 2>/dev/null; exit 0' TERM
  wait "$schlaf"
  if kill -0 "$pid" 2>/dev/null; then
    : >"$zeitmarker"
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    sleep 0.2
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
  fi
) >/dev/null 2>&1 &
waechter=$!

wait "$pid" 2>/dev/null
status=$?
kill -TERM "$waechter" 2>/dev/null
wait "$waechter" 2>/dev/null

if [ -f "$zeitmarker" ]; then
  verweigern "the check ran out of time; its process group was ended, the access stays locked."
fi
if [ "$status" -ne 0 ] && [ ! -s "$ausgabe" ]; then
  verweigern "check core ended with status $status without a decision -- without a check nothing is allowed."
fi
cat "$ausgabe"
exit 0
