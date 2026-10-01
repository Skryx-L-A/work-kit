#!/usr/bin/env bash
# test-pi-worker-alias-enabled.sh -- feste Claude-Aliase respektieren einen
# vorhandenen enabled=false-Eintrag, bleiben ohne Eintrag aber Katalog-Aliase.
#
# Hermetisch: eigenes HOME, eigene Registry via WB_MODELS_FILE und ein
# ausdruecklicher Test-Trockenlauf vor jedem Pane-Spawn. Kein tmux, kein Agent,
# kein Netz und keine Datei ausserhalb des mktemp-Verzeichnisses.
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PI_WORKER="$REPO_ROOT/shell/pi-worker"
CLAUDE_WORKER="$REPO_ROOT/shell/claude-worker"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/pi-worker-alias-enabled.XXXXXX")"
REGISTRY="$TESTHOME/models.json"
PASS=0; FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
cleanup() {
  case "$TESTHOME" in
    "${TMPDIR:-/tmp}"/pi-worker-alias-enabled.*) rm -rf "$TESTHOME" ;;
    *) printf 'WARNUNG: unerwartetes Testverzeichnis, nicht entfernt: %s\n' "$TESTHOME" >&2 ;;
  esac
}
trap cleanup INT TERM EXIT

mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

# Die Attrappe liest ausschliesslich WB_MODELS_FILE. Damit prueft der Test auch,
# dass ein umgebogener Registry-Eintrag den schnellen Pfad erreicht.
cat > "$TESTHOME/.local/bin/wb-state" <<'EOF'
#!/usr/bin/env python3
import json, os, sys

if sys.argv[1:3] == ["models", "get"] and len(sys.argv) >= 4:
    try:
        registry = json.load(open(os.environ["WB_MODELS_FILE"]))
    except Exception:
        sys.exit(1)
    model_id = sys.argv[3]
    model = next((m for m in registry.get("models", []) if m.get("id") == model_id), None)
    if model is None:
        sys.exit(1)
    if "--field" in sys.argv:
        value = model.get(sys.argv[sys.argv.index("--field") + 1])
        if isinstance(value, bool):
            print("true" if value else "false")
        elif value is not None:
            print(value)
    else:
        print(json.dumps(model))
    sys.exit(0)

# claude-worker fragt nur nach dieser Einstellung, bevor er an pi-worker reicht.
if sys.argv[1:3] == ["settings", "get"]:
    sys.exit(0)
sys.exit(1)
EOF
chmod +x "$TESTHOME/.local/bin/wb-state"

cat > "$REGISTRY" <<'EOF'
{"models":[{"id":"claude-fable-5-1","enabled":false,"notes":"Fable ist abgeschaltet.","notFor":"Nicht fuer Worker verwenden."}]}
EOF

lauf_pi() { # <modell> -> OUT, RC
  OUT="$(HOME="$TESTHOME" WB_MODELS_FILE="$REGISTRY" PI_WORKER_TEST_TROCKENLAUF=1 \
    bash "$PI_WORKER" alias-test "$1" "$TESTHOME/arbeit" 'kein echter Spawn' 2>&1)"
  RC=$?
}

echo "== feste Claude-Aliase: Registry enabled =="
lauf_pi fable51
[ "$RC" -ne 0 ] && ok "fable51 mit enabled=false wird abgelehnt" \
                 || bad "fable51 mit enabled=false lief durch"
printf '%s' "$OUT" | grep -q 'Modell ist abgeschaltet (enabled=false)' \
  && ok "die Ablehnung nennt enabled=false" || bad "enabled=false fehlt: $OUT"
printf '%s' "$OUT" | grep -q 'Fable ist abgeschaltet.' \
  && ok "die Ablehnung nennt den Registry-Grund" || bad "notes-Grund fehlt: $OUT"
printf '%s' "$OUT" | grep -q 'Nicht fuer Worker verwenden.' \
  && ok "die Ablehnung nennt notFor" || bad "notFor fehlt: $OUT"

/usr/bin/python3 - "$REGISTRY" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    registry = json.load(f)
registry["models"][0]["enabled"] = True
with open(sys.argv[1], "w") as f:
    json.dump(registry, f)
PY
lauf_pi fable51
[ "$RC" -eq 0 ] && ok "fable51 mit enabled=true erreicht den Trockenlauf" \
                || bad "fable51 mit enabled=true wurde abgelehnt: $OUT"
printf '%s' "$OUT" | grep -q -- 'Startzeile: claude --model claude-fable-5-1' \
  && ok "die Startzeile enthaelt claude-fable-5-1" || bad "falsche Startzeile: $OUT"

cat > "$REGISTRY" <<'EOF'
{"models":[]}
EOF
lauf_pi opus5
[ "$RC" -eq 0 ] && ok "opus5 ohne Registry-Eintrag bleibt ein Katalog-Alias" \
                || bad "opus5 ohne Eintrag wurde abgelehnt: $OUT"
printf '%s' "$OUT" | grep -q -- 'Startzeile: claude --model claude-opus-5' \
  && ok "opus5 ohne Eintrag behaelt seine bisherige Startzeile" || bad "falsche opus5-Startzeile: $OUT"

# claude-worker hat keine zweite Aufloesung: er reicht den Familien-/Festalias
# mit claude-Praefix an pi-worker weiter. Die Attrappe misst diese Uebergabe.
cat > "$TESTHOME/.local/bin/pi-worker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$HOME/pi-worker-argv"
EOF
chmod +x "$TESTHOME/.local/bin/pi-worker"
HOME="$TESTHOME" WB_MODELS_FILE="$REGISTRY" bash "$CLAUDE_WORKER" alias-test fable51:medium "$TESTHOME/arbeit" 'kein echter Spawn'
grep -q '^alias-test claude-fable51:medium ' "$TESTHOME/pi-worker-argv" \
  && ok "claude-worker reicht fable51 an pi-worker weiter" \
  || bad "claude-worker nahm einen anderen Weg: $(cat "$TESTHOME/pi-worker-argv" 2>/dev/null)"

printf '\nPASS: %s  FAIL: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
