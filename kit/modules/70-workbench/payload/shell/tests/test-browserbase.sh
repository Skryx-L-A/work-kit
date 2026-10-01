#!/usr/bin/env bash
# Test fuer wb-browserbase und die Browserwahl des Playwright-MCP.
#
# Isolation: Fake-API als Python-HTTP-Server auf Port 0 (Port aus der Ausgabe
# gelesen, Prozessgruppe am Ende beendet), BROWSERBASE_API zeigt dorthin,
# WB_BROWSERBASE_STATE und MCP_SHARED_STATE in mktemp -d, Key ueber Umgebung.
# Kein echter Netzzugriff, kein echtes npx, kein security-Aufruf.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BB="$REPO/wb-browserbase"
MPS="$REPO/mcp-playwright-start"
MCP="${MCP_SHARED:-$REPO/mcp-shared}"
for f in "$BB" "$MPS" "$MCP"; do
  [ -x "$f" ] || { echo "  FAIL  $f fehlt oder ist nicht ausfuehrbar"; exit 1; }
done
echo "Geprueft: $BB + $MPS + $MCP"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

ARBEIT="$(mktemp -d)"
SRV=""
# Den Fake-Server ueber seine PID beenden, nicht ueber eine Prozessgruppe: der
# Test ist kein Gruppenfuehrer, `kill -- -$$` traf nichts, und der Server blieb
# mit dem geerbten stdout haengen -- ein `| tail` auf diese Suite wartete ewig
# (gemessen 2026-09-09).
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$ARBEIT"' EXIT
mkdir -p "$ARBEIT/bin"

LOGJSON="$ARBEIT/api-log.json"

# --- Fake-API -----------------------------------------------------------------
cat > "$ARBEIT/fake-api.py" <<'PY'
import json, os, signal, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = os.environ["FAKE_LOG"]
USAGE_DATEI = os.environ["FAKE_USAGE_DATEI"]   # je Anfrage gelesen, der Test schreibt sie um
SESSIONS = {}          # id -> dict
NEXT = [0]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _lesen(self):
        n = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(n).decode() if n else ""
    def _antworten(self, code, d):
        b = json.dumps(d).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        with open(LOG, 'a') as f:
            # Klartext, eine Zeile je Anfrage: METHODE PFAD KEY BODY -- kein
            # JSON-Escaping, damit die Tests den Body wortgleich greppen koennen.
            f.write("GET %s %s\n" % (self.path, self.headers.get('X-BB-API-Key')))
        if self.path == '/v1/projects/p-1/usage':
            with open(USAGE_DATEI) as f:
                minuten = int(f.read().strip() or "0")
            self._antworten(200, {"browserMinutes": minuten, "proxyBytes": 0})
        elif self.path.startswith('/v1/sessions?'):
            self._antworten(200, [{"id": "sess-1", "createdAt": "2026-09-09T10:00:00Z"},
                                  {"id": "sess-2", "createdAt": "2026-09-09T11:00:00Z"}])
        elif '/debug' in self.path:
            sid = self.path.split('/')[3]
            self._antworten(200, {"debuggerFullscreenUrl": f"https://live.browserbase.com/s/{sid}"})
        else:
            self._antworten(404, {"error": "not found"})
    def do_POST(self):
        body = self._lesen()
        with open(LOG, 'a') as f:
            f.write("POST %s %s %s\n" % (self.path, self.headers.get('X-BB-API-Key'), body))
        if self.path == '/v1/sessions':
            NEXT[0] += 1
            sid = f"sess-neu-{NEXT[0]}"
            SESSIONS[sid] = json.loads(body or "{}")
            self._antworten(200, {"id": sid, "connectUrl": "wss://x", "status": "RUNNING"})
        elif self.path.startswith('/v1/sessions/'):
            sid = self.path.split('/')[3]
            if sid not in SESSIONS and not sid.startswith('sess-neu-'):
                self._antworten(404, {"message": "Session not found"})
            else:
                self._antworten(200, {"id": sid, "status": "REQUEST_RELEASE"})
        else:
            self._antworten(404, {"error": "not found"})

srv = HTTPServer(('127.0.0.1', 0), H)
def einsatz():
    import threading
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(srv.server_port, flush=True)
    signal.pause()
signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))
einsatz()
PY
echo 5 > "$ARBEIT/usage.txt"
FAKE_LOG="$LOGJSON" FAKE_USAGE_DATEI="$ARBEIT/usage.txt" \
  /usr/bin/python3 "$ARBEIT/fake-api.py" > "$ARBEIT/port.txt" 2>/dev/null </dev/null &
SRV=$!
# Port erst lesen, wenn er geschrieben ist (Port 0: der Server waehlt ihn selbst).
frist=$((SECONDS + 10))
while [ ! -s "$ARBEIT/port.txt" ] && [ $SECONDS -lt $frist ]; do sleep 0.1; done
PORT="$(cat "$ARBEIT/port.txt")"
[ -n "$PORT" ] || { echo "  FAIL  Fake-API hat keinen Port gemeldet"; exit 1; }
mkdir -p "$ARBEIT/state-bb" "$ARBEIT/state-mcp"
# security-Attrappe: der echte Schluesselbund dieser Maschine darf im Test nie
# gelesen werden -- Fall 1 prueft gerade den Weg OHNE Schluessel.
printf '#!/bin/sh\nexit 44\n' > "$ARBEIT/bin/security"; chmod +x "$ARBEIT/bin/security"
nutzung_setzen() { echo "$1" > "$ARBEIT/usage.txt"; }
export BROWSERBASE_API="http://127.0.0.1:$PORT"
export BROWSERBASE_API_KEY="test-key"
export BROWSERBASE_PROJECT_ID="p-1"
export WB_BROWSERBASE_STATE="$ARBEIT/state-bb"
export MCP_SHARED_STATE="$ARBEIT/state-mcp"
export PATH="$ARBEIT/bin:$PATH"

api_log() { [ -f "$LOGJSON" ] && cat "$LOGJSON" || true; }

# --- Faelle 1-9: wb-browserbase -----------------------------------------------

# 1. ohne Key: Exit 2, Meldung enthaelt "kein API-Key"
out="$(env -u BROWSERBASE_API_KEY PATH="$ARBEIT/bin:/usr/bin:/bin" HOME="$ARBEIT" \
  bash "$BB" nutzung 2>&1)"; rc=$?
if [ $rc -eq 2 ] && grep -q 'kein API-Key' <<<"$out"; then
  ok "ohne Key: Exit 2 mit 'kein API-Key'"
else
  bad "ohne Key: rc=$rc, Ausgabe: $out"
fi

# 1b. hilfe braucht keinen Key
out="$(env -u BROWSERBASE_API_KEY PATH="$ARBEIT/bin:/usr/bin:/bin" HOME="$ARBEIT" bash "$BB" hilfe 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -q 'Exit-Codes' <<<"$out"; then
  ok "hilfe ohne Key: Exit 0"
else
  bad "hilfe ohne Key: rc=$rc"
fi

# 2. nutzung mit browserMinutes 5
out="$(bash "$BB" nutzung 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -q '5 von 60' <<<"$out"; then
  ok "nutzung bei 5 Minuten: '$out'"
else
  bad "nutzung bei 5 Minuten: rc=$rc, Ausgabe: $out"
fi

# 3. nutzung mit browserMinutes 55 -> Exit 3
nutzung_setzen 55
out="$(bash "$BB" nutzung 2>&1)"; rc=$?
nutzung_setzen 5
if [ $rc -eq 3 ]; then
  ok "nutzung bei 55 Minuten: Exit 3"
else
  bad "nutzung bei 55 Minuten: rc=$rc, Ausgabe: $out"
fi

# 3a. nutzung --json bei 5 Minuten: Exit 0, gueltiges JSON, browserMinutes 5, frei 45, budgetOk true
nutzung_setzen 5
out="$(bash "$BB" nutzung --json 2>/dev/null)"; rc=$?
if [ $rc -eq 0 ] \
   && /usr/bin/python3 -c 'import json,sys; json.load(sys.stdin)' <<<"$out" 2>/dev/null \
   && [ "$(/usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["browserMinutes"], d["frei"], str(d["budgetOk"]).lower())' <<<"$out")" = "5 45 true" ]; then
  ok "nutzung --json bei 5 Minuten: Exit 0, JSON mit browserMinutes 5, frei 45, budgetOk true"
else
  bad "nutzung --json bei 5 Minuten: rc=$rc, Ausgabe: $out"
fi

# 3b. nutzung --json bei 55 Minuten: Exit 3, budgetOk false, frei 0
nutzung_setzen 55
out="$(bash "$BB" nutzung --json 2>/dev/null)"; rc=$?
nutzung_setzen 5
if [ $rc -eq 3 ] \
   && /usr/bin/python3 -c 'import json,sys; json.load(sys.stdin)' <<<"$out" 2>/dev/null \
   && [ "$(/usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["browserMinutes"], d["frei"], str(d["budgetOk"]).lower())' <<<"$out")" = "55 0 false" ]; then
  ok "nutzung --json bei 55 Minuten: Exit 3, budgetOk false, frei 0"
else
  bad "nutzung --json bei 55 Minuten: rc=$rc, Ausgabe: $out"
fi

# 4. sitzung neu: POST, Body, stdout genau die ID, TSV-Zeile, Key nicht sichtbar
rm -f "$LOGJSON"
out_err="$ARBEIT/err4.txt"
bash "$BB" sitzung neu > "$ARBEIT/out4.txt" 2> "$out_err"; rc=$?
cp "$ARBEIT/out4.txt" "$ARBEIT/id4"; id="$(cat "$ARBEIT/id4")"
neu_post="$(grep -c '^POST /v1/sessions ' "$LOGJSON" || true)"
body_ok="$(grep '^POST /v1/sessions ' "$LOGJSON" | grep -q 'projectId' && grep '^POST /v1/sessions ' "$LOGJSON" | grep -q '"timeout": 900' && echo ja)"
if [ $rc -eq 0 ] && [ "$(wc -l < "$ARBEIT/id4" | tr -d ' ')" = 1 ] && [ -n "$id" ] \
   && [ "$neu_post" -ge 1 ] && [ "$body_ok" = ja ] \
   && [ "$(wc -l < "$ARBEIT/state-bb/sitzungen.tsv" | tr -d ' ')" = 1 ] \
   && ! grep -q 'test-key' "$ARBEIT/out4.txt" "$out_err"; then
  ok "sitzung neu: ID '$id', POST mit projectId + timeout 900, TSV-Zeile, kein Key"
else
  bad "sitzung neu: rc=$rc id=$id posts=$neu_post body=$body_ok"
fi

# 5. sitzung neu --minuten 20: timeout 1200
rm -f "$LOGJSON"
id5="$(bash "$BB" sitzung neu --minuten 20)" && rc5=0 || rc5=$?
if [ $rc5 -eq 0 ] && grep '^POST /v1/sessions ' "$LOGJSON" | grep -q '"timeout": 1200'; then
  ok "sitzung neu --minuten 20: timeout 1200"
else
  bad "sitzung neu --minuten 20: rc=$rc5"
fi

# 6. sitzung neu bei Budget 55: Exit 3, KEIN POST
rm -f "$LOGJSON"
nutzung_setzen 55
out="$(bash "$BB" sitzung neu 2>&1)"; rc=$?
nutzung_setzen 5
posts="$(grep -c '^POST /v1/sessions ' "$LOGJSON" 2>/dev/null)"; posts="${posts:-0}"
if [ $rc -eq 3 ] && [ "$posts" = 0 ]; then
  ok "sitzung neu bei Budget 55: Exit 3, kein POST"
else
  bad "sitzung neu bei Budget 55: rc=$rc posts=$posts"
fi

# 7a. sitzung ende <id>: POST mit REQUEST_RELEASE, Eintrag weg
rm -f "$LOGJSON"
bash "$BB" sitzung neu >/dev/null 2>&1
id7="$(bash "$BB" sitzung neu)"
out="$(bash "$BB" sitzung ende "$id7" 2>&1)"; rc=$?
rel_ok="$(grep "^POST /v1/sessions/$id7 " "$LOGJSON" 2>/dev/null | grep -q REQUEST_RELEASE && echo ja)"
if [ $rc -eq 0 ] && [ "$rel_ok" = ja ] && ! grep -q "^$id7	" "$ARBEIT/state-bb/sitzungen.tsv"; then
  ok "sitzung ende <id>: REQUEST_RELEASE, Eintrag weg"
else
  bad "sitzung ende <id>: rc=$rc rel=$rel_ok"
fi

# 7b. ende bei 404: trotzdem Exit 0, Eintrag weg (der Eintrag wird von Hand
#     gesetzt -- der Fake kennt diese ID nicht und antwortet 404)
printf 'fehlt-serverseitig\t2026-09-09T00:00:00Z\ttest\n' >> "$ARBEIT/state-bb/sitzungen.tsv"
out="$(bash "$BB" sitzung ende "fehlt-serverseitig" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && ! grep -q '^fehlt-serverseitig	' "$ARBEIT/state-bb/sitzungen.tsv"; then
  ok "sitzung ende bei 404: Exit 0, Eintrag weg"
else
  bad "sitzung ende bei 404: rc=$rc"
fi

# 7c. sitzung liste: zwei Sitzungen vom Fake, eine davon eigen (aus der TSV)
printf 'sess-1\t2026-09-09T10:00:00Z\ttest\n' > "$ARBEIT/state-bb/sitzungen.tsv"
out="$(bash "$BB" sitzung liste 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -q '^sess-1  2026-09-09T10:00:00Z  (eigen)$' <<<"$out" \
   && grep -q '^sess-2  .*(fremd)$' <<<"$out"; then
  ok "sitzung liste: eigen/fremd je Zeile"
else
  bad "sitzung liste: rc=$rc out=$out"
fi
: > "$ARBEIT/state-bb/sitzungen.tsv"

# 8. cdp-url <id>: sessionId + apiKey=test-key
out="$(bash "$BB" cdp-url sess-1)"
case "$out" in
  *"apiKey=test-key"*"sessionId=sess-1"*) ok "cdp-url enthaelt sessionId und apiKey" ;;
  *) bad "cdp-url falsch: $out" ;;
esac

# 9. schau <id>: debuggerFullscreenUrl des Fake
out="$(bash "$BB" schau sess-1 2>&1)"
if [ "$out" = "https://live.browserbase.com/s/sess-1" ]; then
  ok "schau gibt debuggerFullscreenUrl aus"
else
  bad "schau falsch: $out"
fi

# --- Faelle 10-12: mcp-playwright-start ---------------------------------------

# npx-Attrappe: schreibt Argumente in $FAKE_NPX_LOG, beendet sich.
cat > "$ARBEIT/bin/npx" <<'NPXEOF'
#!/bin/sh
printf '%s\n' "$@" >> "$FAKE_NPX_LOG"
exit 0
NPXEOF
chmod +x "$ARBEIT/bin/npx"
# wb-browserbase-Attrappe fuer Fall 11/12 (keine echte API noetig).
cat > "$ARBEIT/bin/wb-browserbase" <<'BBEOF'
#!/bin/bash
case "$1 $2" in
  "sitzung neu") echo sess-1 ;;
  "cdp-url "*)   echo "wss://connect.browserbase.com?apiKey=test-key&sessionId=$2" ;;
  "sitzung ende") exit 0 ;;
  *) exit 0 ;;
esac
BBEOF
chmod +x "$ARBEIT/bin/wb-browserbase"

export WB_PLAYWRIGHT_NPX="$ARBEIT/bin/npx"
export WB_PLAYWRIGHT_PORT=8777
export FAKE_NPX_LOG="$ARBEIT/npx.log"

# 10. Zustand lokal: --headless, kein --cdp-endpoint
echo lokal > "$MCP_SHARED_STATE/playwright-browser"
: > "$FAKE_NPX_LOG"
out_err="$(bash "$MPS" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -q -- '--headless' "$FAKE_NPX_LOG" \
   && ! grep -q -- '--cdp-endpoint' "$FAKE_NPX_LOG" \
   && grep -q 'Browser lokal' <<<"$out_err" \
   && grep -A1 -- '--allowed-hosts' "$FAKE_NPX_LOG" | grep -q 'localhost:8767'; then
  ok "Start bei lokal: --headless, kein --cdp-endpoint, Proxy-Host erlaubt"
else
  bad "Start bei lokal: rc=$rc npx.log=$(cat "$FAKE_NPX_LOG") err=$out_err"
fi

# 11. Zustand browserbase: --cdp-endpoint mit sess-1, kein --headless,
#     Sitzungsdatei sess-1, Key nicht auf stderr
echo browserbase > "$MCP_SHARED_STATE/playwright-browser"
rm -f "$MCP_SHARED_STATE/playwright-browserbase-session"
: > "$FAKE_NPX_LOG"
out_err="$(bash "$MPS" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -q -- '--cdp-endpoint' "$FAKE_NPX_LOG" \
   && grep -q 'sessionId=sess-1' "$FAKE_NPX_LOG" \
   && ! grep -q -- '--headless' "$FAKE_NPX_LOG" \
   && ! grep -q -- '--isolated' "$FAKE_NPX_LOG" \
   && [ "$(cat "$MCP_SHARED_STATE/playwright-browserbase-session")" = sess-1 ] \
   && grep -A1 -- '--allowed-hosts' "$FAKE_NPX_LOG" | grep -q 'localhost:8767' \
   && ! grep -q 'test-key' <<<"$out_err"; then
  ok "Start bei browserbase: cdp-endpoint mit sess-1, kein --headless, kein --isolated, Key unsichtbar"
else
  bad "Start bei browserbase: rc=$rc log=$(cat "$FAKE_NPX_LOG") err=$out_err"
fi

# 12. browserbase scheitert (Attrappe mit Exit 3): Rueckfall lokal
cat > "$ARBEIT/bin/wb-browserbase" <<'BBEOF'
#!/bin/bash
case "$1 $2" in
  "sitzung neu") echo "wb-browserbase: Budget aufgebraucht" >&2; exit 3 ;;
  *) exit 0 ;;
esac
BBEOF
chmod +x "$ARBEIT/bin/wb-browserbase"
echo browserbase > "$MCP_SHARED_STATE/playwright-browser"
: > "$FAKE_NPX_LOG"
out_err="$(bash "$MPS" 2>&1)"; rc=$?
zustand="$(cat "$MCP_SHARED_STATE/playwright-browser")"
if [ $rc -eq 0 ] && [ "$zustand" = lokal ] \
   && grep -q 'Rueckfall lokal' <<<"$out_err" \
   && grep -q -- '--headless' "$FAKE_NPX_LOG"; then
  ok "Start bei scheiternder Browserbase: Rueckfall lokal, Zustand lokal"
else
  bad "Rueckfall: rc=$rc zustand=$zustand err=$out_err"
fi

# --- Faelle 13-14: mcp-shared browser / halt ----------------------------------

# launchctl-Attrappe (Fall 14): tut nichts.
printf '#!/bin/sh\nexit 0\n' > "$ARBEIT/bin/launchctl"
chmod +x "$ARBEIT/bin/launchctl"
# curl-Attrappe (Fall 13/14): meldet den Backend-Port als frei, damit
# `browser browserbase` den Server nicht neu anwirft und `halt` sofort fertig ist.
cat > "$ARBEIT/bin/curl" <<'CURLEOF'
#!/bin/sh
exit 7   # Verbindungsfehler = Port frei
CURLEOF
chmod +x "$ARBEIT/bin/curl"

# 13. mcp-shared browser: ohne Argument lokal; mit Argument browserbase
out="$(PATH="$ARBEIT/bin:$PATH" bash "$MCP" browser)"; rc=$?
if [ $rc -eq 0 ] && grep -q 'Browser: lokal' <<<"$out"; then
  ok "mcp-shared browser ohne Argument: 'lokal'"
else
  bad "mcp-shared browser ohne Argument: rc=$rc out=$out"
fi
out="$(PATH="$ARBEIT/bin:$PATH" bash "$MCP" browser browserbase 2>&1)"; rc=$?
zustand="$(cat "$MCP_SHARED_STATE/playwright-browser" 2>/dev/null)"
if [ $rc -eq 0 ] && [ "$zustand" = browserbase ]; then
  ok "mcp-shared browser browserbase: Zustandsdatei browserbase"
else
  bad "mcp-shared browser browserbase: rc=$rc zustand=$zustand out=$out"
fi

# 14. mcp-shared halt playwright mit Sitzungsdatei: wb-browserbase-Attrappe mit
#     'sitzung ende <id>' gerufen, Sitzungsdatei weg, Zustand lokal.
rm -f "$ARBEIT/bb-aufrufe.log"
cat > "$ARBEIT/bin/wb-browserbase" <<'BBEOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BB_END_LOG"
exit 0
BBEOF
chmod +x "$ARBEIT/bin/wb-browserbase"
export BB_END_LOG="$ARBEIT/bb-aufrufe.log"
echo sess-9 > "$MCP_SHARED_STATE/playwright-browserbase-session"
echo browserbase > "$MCP_SHARED_STATE/playwright-browser"
out="$(PATH="$ARBEIT/bin:$PATH" bash "$MCP" halt playwright 2>&1)"; rc=$?
zustand="$(cat "$MCP_SHARED_STATE/playwright-browser" 2>/dev/null)"
if [ $rc -eq 0 ] && grep -q 'sitzung ende sess-9' "$BB_END_LOG" \
   && [ ! -e "$MCP_SHARED_STATE/playwright-browserbase-session" ] \
   && [ "$zustand" = lokal ]; then
  ok "halt playwright: Browserbase-Sitzung beendet, Datei weg, Zustand lokal"
else
  bad "halt playwright: rc=$rc zustand=$zustand aufrufe=$(cat "$BB_END_LOG" 2>/dev/null) out=$out"
fi

# --- Bilanz -------------------------------------------------------------------
echo "Geprueft: $pass ok, $fail bad"
[ "$fail" -eq 0 ] || exit 1
exit 0
