#!/usr/bin/env bash
# Test fuer die Einordnung der Helferprozesse in mcp-shared.
#
# Anlass (2026-09-04): Die Liste der "geteilten" Ports stand fest im Text und
# nannte nur 8766 und 8767. Die Bedarfsschaltung vom 20.08. hat den echten
# Server aber auf die BACKEND-Ports 8776/8777 gelegt; der haengt an launchd und
# hat nie einen Claude-Vorfahren. Er wurde deshalb als "verwaist" gefuehrt --
# und `mcp-shared kill-orphans` haette den geteilten Server erschlagen, den
# dieses Werkzeug gerade schuetzen soll.
#
# Isolation: ein gefaelschtes `ps` vor dem echten im PATH. Es laeuft kein
# Prozess, es wird keiner beendet, und die echte Prozessliste wird nie gelesen.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${MCP_SHARED:-$REPO/mcp-shared}"
[ -x "$TOOL" ] || { echo "  FAIL  $TOOL fehlt oder ist nicht ausfuehrbar"; exit 1; }
echo "Geprueft: $TOOL"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT
mkdir -p "$ARBEIT/bin" "$ARBEIT/home/.claude/workbench"
cat > "$ARBEIT/home/.claude/workbench/models.json" <<'JSON'
{"harnesses":[{"id":"sonder","command":"/opt/werkbank/custom-run"}]}
JSON

# PID 1 ist launchd, 4711 der Backend-Server daran, 4712 ein Helfer unter einer
# lebenden Claude-Sitzung (4700), 4713 ein echter Waise. Dazu kommen ein
# Codex-Worker mit einem Playwright-Paar, Pi, OpenCode, ein dynamisch registrierter
# Harness, ein Claude-Unteragent aus einem Versionspfad und ein unbekannter Prozess
# unter einer lebenden tmux-Pane-Wurzel. Keiner dieser gebundenen Faelle darf fuer
# reap zum Kandidaten werden.
cat > "$ARBEIT/bin/ps" <<'PSEOF'
#!/bin/sh
if [ "${1:-}" = "-p" ]; then
  case "${2:-}" in
    4711) echo 'npm exec @playwright/mcp@latest --port 8777 --host 127.0.0.1 --headless --isolated' ;;
    4712) echo 'node $HOME/.npm/_npx/x/node_modules/.bin/playwright-mcp --port 9001' ;;
    4713) echo 'node $HOME/.npm/_npx/x/node_modules/.bin/playwright-mcp --port 9002' ;;
    4811) echo 'npm exec @playwright/mcp@latest' ;;
    4812) echo 'node /tmp/playwright-mcp' ;;
    4911) echo 'npm exec @playwright/mcp@latest' ;;
    5011) echo 'node /tmp/playwright-mcp' ;;
    5111) echo 'node /tmp/playwright-mcp' ;;
    5211) echo 'node /tmp/playwright-mcp' ;;
    5311) echo 'node /tmp/playwright-mcp' ;;
  esac
  exit 0
fi
cat <<'ROWS'
    1     0 06-01:00:00   9000 /sbin/launchd
 4700     1    01:00:00 500000 $HOME/.local/bin/claude --dangerously-skip-permissions
 4711     1    00:02:00 216000 npm exec @playwright/mcp@latest --port 8777 --host 127.0.0.1 --headless --isolated
 4712  4700    00:03:00 130000 node $HOME/.npm/_npx/x/node_modules/.bin/playwright-mcp --port 9001
 4713     1    00:04:00 120000 node $HOME/.npm/_npx/x/node_modules/.bin/playwright-mcp --port 9002
 4800     1    00:20:00 250000 codex --model gpt-5.6-sol
 4811  4800    00:19:00  80000 npm exec @playwright/mcp@latest
 4812  4811    00:19:00  60000 node /tmp/playwright-mcp
 4900     1    00:18:00 240000 $HOME/.local/share/claude/versions/2.1.270 --agent-id probe
 4911  4900    00:17:00  81000 npm exec @playwright/mcp@latest
 5000     1    00:16:00  12000 /bin/zsh
 5011  5000    00:15:00  59000 node /tmp/playwright-mcp
 5100     1    00:14:00 180000 pi --provider openai
 5111  5100    00:13:00  58000 node /tmp/playwright-mcp
 5200     1    00:12:00 170000 opencode run
 5211  5200    00:11:00  57000 node /tmp/playwright-mcp
 5300     1    00:10:00 160000 /opt/werkbank/custom-run --agent
 5311  5300    00:09:00  56000 node /tmp/playwright-mcp
ROWS
PSEOF
chmod +x "$ARBEIT/bin/ps"

cat > "$ARBEIT/bin/tmux" <<'TMUXEOF'
#!/bin/sh
printf '5000\t0\n'
TMUXEOF
chmod +x "$ARBEIT/bin/tmux"

AUSGABE="$(HOME="$ARBEIT/home" PATH="$ARBEIT/bin:$PATH" bash "$TOOL" helfer 2>&1)" \
  || AUSGABE="$(HOME="$ARBEIT/home" PATH="$ARBEIT/bin:$PATH" bash "$TOOL" status 2>&1)"

ZEILE="$(printf '%s\n' "$AUSGABE" | grep -m1 'Helferprozesse:')"
case "$ZEILE" in
  *'1 geteilt'*)  ok "der Backend-Server auf 8777 zaehlt als geteilt: $ZEILE" ;;
  *) bad "Backend-Server falsch eingeordnet: ${ZEILE:-keine Zeile gefunden}" ;;
esac
case "$ZEILE" in
  *'8 an lebende Sessions gebunden'*) ok "Claude, Codex, Pi, OpenCode, Registry-Harness und Pane-Ahne bleiben gebunden" ;;
  *) bad "lebende Harness-/Pane-Helfer falsch eingeordnet: $ZEILE" ;;
esac
case "$ZEILE" in
  *'1 verwaist'*) ok "der echte Waise wird weiterhin als verwaist gemeldet" ;;
  *) bad "echter Waise nicht erkannt -- die Meldung sieht jetzt gar nichts mehr: $ZEILE" ;;
esac

# Die harte Zusage: `reap` darf den geteilten Server NIE anfassen. Geprueft im
# Trockenlauf -- er nennt, was er beenden WUERDE, und beendet nichts.
TROCKEN="$(HOME="$ARBEIT/home" PATH="$ARBEIT/bin:$PATH" bash "$TOOL" reap --dry-run 2>&1)"
if printf '%s\n' "$TROCKEN" | grep -q 'PID 4711'; then
  bad "reap wuerde den geteilten Backend-Server (4711) beenden: $TROCKEN"
else
  ok "reap fasst den geteilten Backend-Server nicht an"
fi
if printf '%s\n' "$TROCKEN" | grep -q 'PID 4713'; then
  ok "reap nennt den echten Waisen (4713)"
else
  bad "reap nennt den echten Waisen nicht: $TROCKEN"
fi
for GEBUNDEN in 4712 4811 4812 4911 5011 5111 5211 5311; do
  if printf '%s\n' "$TROCKEN" | grep -q "PID $GEBUNDEN"; then
    bad "reap wuerde gebundene PID $GEBUNDEN beenden: $TROCKEN"
  else
    ok "reap erzeugt keinen Kill-Kandidaten fuer gebundene PID $GEBUNDEN"
  fi
done

echo
echo "mcp-shared Backend-Ports: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
