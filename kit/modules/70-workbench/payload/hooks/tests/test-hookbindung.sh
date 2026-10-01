#!/usr/bin/env bash
# Bindungsregression: Im vom Traeger markierten Agentenzug duerfen die Sperr-Hooks
# ohne WB_AGENT_ID/WB_WELT nicht still durchlassen. Auf dem Host bleiben sie still.
set -uo pipefail

HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EINGABE='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }

deny_mit_bindungsgrund() {
  python3 -c 'import json, sys
d = json.load(sys.stdin)
h = d.get("hookSpecificOutput") or {}
reason = h.get("permissionDecisionReason") or ""
assert h.get("permissionDecision") == "deny"
assert "Agent turn without binding" in reason
assert "WB_AGENT_ID" in reason and "WB_WELT" in reason
' >/dev/null 2>&1
}

pruefe_hook() {
  local name="$1" ausgabe host
  ausgabe="$(printf '%s\n' "$EINGABE" | env -u WB_AGENT_ID -u WB_WELT \
    WB_AGENT_ZUG=/tmp/zug-bindungsprobe bash "$HOOKS_DIR/$name")"
  if printf '%s\n' "$ausgabe" | deny_mit_bindungsgrund; then
    ok "$name verweigert im Agentenkontext ohne Bindungen mit ausdruecklichem Grund"
  else
    bad "$name liess fehlende Bindungen durch oder nannte keinen Bindungsgrund: $ausgabe"
  fi

  host="$(printf '%s\n' "$EINGABE" | env -u WB_AGENT_ID -u WB_WELT -u WB_AGENT_ZUG \
    bash "$HOOKS_DIR/$name")"
  if [ -z "$host" ]; then
    ok "$name bleibt ausserhalb des Agentenkontexts still"
  else
    bad "$name veraendert den Host-Aufruf: $host"
  fi
}

pruefe_kern() {
  local name="$1" ausgabe
  ausgabe="$(printf '%s\n' "$EINGABE" | env -u WB_AGENT_ID -u WB_WELT \
    WB_AGENT_ZUG=/tmp/zug-bindungsprobe python3 "$HOOKS_DIR/lib/$name")"
  if printf '%s\n' "$ausgabe" | deny_mit_bindungsgrund; then
    ok "$name verweigert auch bei direktem Aufruf ohne Bindungen"
  else
    bad "$name liess den direkten Aufruf ohne Bindungen durch: $ausgabe"
  fi
}

pruefe_hook profil-sperre.sh
pruefe_hook skills-sperre.sh
pruefe_kern profil_sperre.py
pruefe_kern skills_sperre.py

printf 'Ergebnis: %d bestanden, %d fehlgeschlagen\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
