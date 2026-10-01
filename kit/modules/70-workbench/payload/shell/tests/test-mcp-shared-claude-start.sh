#!/usr/bin/env bash
# Dauerhafter Riegel gegen Plugin-Updates, die Playwright wieder auf einen
# privaten stdio-MCP je Claude-Sitzung stellen.
#
# Isolation: eigenes HOME, eigener Plugin-Cache, ein gefaelschtes wb-state,
# Claude-Attrappe und nc-Attrappen. Kein Server wird gestartet und keine echte
# Konfiguration gelesen oder geschrieben.
set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HIER/.." && pwd)"
LAUF="$REPO/wb-harness-run"
TESTBASIS="${TMPDIR:-$PWD}"
mkdir -p "$TESTBASIS"
TESTROOT="$(mktemp -d "$TESTBASIS/mcp-shared-start.XXXXXX")"
trap 'rm -rf -- "$TESTROOT"' EXIT INT TERM
HEIM="$TESTROOT/home"
ARBEIT="$TESTROOT/arbeit"
BIN="$HEIM/.local/bin"
CACHE="$HEIM/.claude/plugins/cache/claude-plugins-official/playwright"
mkdir -p "$BIN" "$ARBEIT" "$CACHE/v1" "$CACHE/v2" \
  "$HEIM/.claude/plugins/cache/synced/vanta/v1"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

cat >"$BIN/wb-state" <<'SH'
#!/bin/sh
if [ "$1 $2" = "models resolve" ]; then
  printf 'harness\tclaude\n'
  printf 'cmd\tcd %s && exec claude --model testmodell\n' "$WB_TEST_ARBEIT"
elif [ "$1 $2" = "harness get" ]; then
  printf '%s\n' '{"id":"claude","session":{}}'
else
  exit 2
fi
SH
cat >"$BIN/claude" <<'SH'
#!/bin/sh
printf 'gestartet\n' >>"$WB_TEST_LAEUFE"
SH
cat >"$TESTROOT/nc-live" <<'SH'
#!/bin/sh
printf 'live\n' >>"$WB_TEST_NC_CALLS"
exit 0
SH
cat >"$TESTROOT/nc-tot" <<'SH'
#!/bin/sh
printf 'tot\n' >>"$WB_TEST_NC_CALLS"
exit 1
SH
chmod +x "$BIN/wb-state" "$BIN/claude" "$TESTROOT/nc-live" "$TESTROOT/nc-tot"

stdio_datei() {
  cat >"$1" <<'JSON'
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest"]
  }
}
JSON
}

ist_http() {
  /usr/bin/python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("playwright") or {}
raise SystemExit(0 if p == {"type": "http", "url": "http://localhost:8767/mcp"} else 1)
PY
}

ist_stdio() {
  /usr/bin/python3 - "$1" <<'PY'
import json, sys
p = (json.load(open(sys.argv[1])).get("playwright") or {})
raise SystemExit(0 if p.get("command") == "npx" and "@playwright/mcp" in " ".join(p.get("args") or []) else 1)
PY
}

lauf() {
  env HOME="$HEIM" PATH="$BIN:/usr/bin:/bin" \
    WB_TEST_ARBEIT="$ARBEIT" WB_TEST_LAEUFE="$TESTROOT/laeufe" \
    WB_TEST_NC_CALLS="$TESTROOT/nc-aufrufe" \
    MCP_SHARED_NC="$1" "$LAUF" --model claude-test --role worker --dir "$ARBEIT"
}

STDIO1="$CACHE/v1/.mcp.json"
STDIO2="$CACHE/v2/.mcp.json"
FREMD="$HEIM/.claude/plugins/cache/synced/vanta/v1/.mcp.json"
stdio_datei "$STDIO1"
printf '%s\n' '{"vanta":{"command":"vanta-mcp"}}' >"$FREMD"

echo "-- lebender Shared-Server: vor dem Claude-Start umschreiben --"
AUS1="$(lauf "$TESTROOT/nc-live" 2>&1)"
if ist_http "$STDIO1"; then
  ok "stdio-Playwright wurde vor dem Harness-Start auf Shared HTTP umgestellt"
else
  bad "Playwright blieb auf stdio: $AUS1"
fi
if [ "$(cat "$TESTROOT/laeufe" 2>/dev/null)" = "gestartet" ]; then
  ok "der Claude-Harness startete nach der Reparatur"
else
  bad "der Claude-Harness wurde von der Reparatur blockiert"
fi
if find "$HEIM/.local/trash-snapshots" -name 'playwright-v1.mcp.json' -type f | grep -q .; then
  ok "die stdio-Fassung wurde wie bei mcp-shared apply gesichert"
else
  bad "keine Sicherung der umgeschriebenen Plugin-Datei gefunden"
fi
if grep -q '"vanta-mcp"' "$FREMD"; then
  ok "ein anderer Plugin-MCP blieb unangetastet"
else
  bad "ein anderer Plugin-MCP wurde veraendert"
fi

echo "-- zweiter Lauf: idempotent, keine neue Schreibbewegung --"
STAND_VOR="$(/usr/bin/python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$STDIO1")"
NC_VOR="$(wc -l <"$TESTROOT/nc-aufrufe")"
AUS2="$(lauf "$TESTROOT/nc-live" 2>&1)"
STAND_NACH="$(/usr/bin/python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$STDIO1")"
NC_NACH="$(wc -l <"$TESTROOT/nc-aufrufe")"
if [ "$STAND_VOR" = "$STAND_NACH" ] && [ "$NC_VOR" = "$NC_NACH" ] && [ -z "$AUS2" ]; then
  ok "der zweite Start liess Datei und Portprobe vollstaendig in Ruhe"
else
  bad "der zweite Start schrieb oder meldete erneut: $AUS2"
fi

echo "-- gestoppter Shared-Server: stdio behalten, warnen, weiter starten --"
stdio_datei "$STDIO2"
AUS3="$(lauf "$TESTROOT/nc-tot" 2>&1)"
if ist_stdio "$STDIO2"; then
  ok "bei gestopptem Shared-Server blieb die funktionsfaehige stdio-Fassung stehen"
else
  bad "bei gestopptem Server wurde stdio trotzdem ersetzt"
fi
case "$AUS3" in
  *"nicht erreichbar"*) ok "der Start warnte genau ueber den nicht erreichbaren Shared-Server" ;;
  *) bad "Warnung ueber den gestoppten Shared-Server fehlt: $AUS3" ;;
esac
if [ "$(wc -l <"$TESTROOT/laeufe")" -eq 3 ]; then
  ok "auch der Start mit gestopptem Server wurde nicht blockiert"
else
  bad "der Harness lief nicht in allen drei Startfaellen"
fi

echo "-- fehlendes mcp-shared: warnen und weiter starten --"
stdio_datei "$STDIO2"
AUS4="$(env HOME="$HEIM" PATH="$BIN:/usr/bin:/bin" \
  WB_TEST_ARBEIT="$ARBEIT" WB_TEST_LAEUFE="$TESTROOT/laeufe" \
  WB_TEST_NC_CALLS="$TESTROOT/nc-aufrufe" \
  WB_MCP_SHARED="$TESTROOT/fehlt" MCP_SHARED_NC="$TESTROOT/nc-live" \
  "$LAUF" --model claude-test --role worker --dir "$ARBEIT" 2>&1)"
if ist_stdio "$STDIO2" && [ "$(wc -l <"$TESTROOT/laeufe")" -eq 4 ]; then
  ok "fehlendes mcp-shared liess stdio und den Harness-Start intakt"
else
  bad "fehlendes mcp-shared blockierte oder schrieb die Konfiguration"
fi
case "$AUS4" in
  *"mcp-shared fehlt"*) ok "fehlendes mcp-shared wurde in einer Zeile gemeldet" ;;
  *) bad "Warnung fuer fehlendes mcp-shared fehlt: $AUS4" ;;
esac

echo
printf 'mcp-shared Claude-Vorstart: %d ok, %d fehlgeschlagen\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
