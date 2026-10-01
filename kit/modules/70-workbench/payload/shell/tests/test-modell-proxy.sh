#!/bin/bash
# test-modell-proxy.sh — belegt fuer den Auftrag vom 2026-08-13 (bedarfsweiser
# Modellserver-Proxy), dass shell/wb-modell-proxy seine Zusagen wirklich
# einhaelt: Kaltstart per ensureCmd mit durchlaufendem Verkehr, ein
# gescheitertes ensure als HTTP 503 statt als Haenger, Leerlauf-Stopp mit
# GEPRUEFTEM Ende samt Selbstende des Proxys, und ein zweiter Kaltstart danach.
#
# Nach dem Review vom 13.08. sind die Faelle 8 bis 15 dazugekommen — je einer
# fuer jede Luecke, aus der ein Befund entstanden ist: SIGTERM bei OFFENER
# Verbindung (S1), eine Anfrage, die in einen laufenden Stopp hineinlaeuft
# (S3), SIGTERM waehrend ensureCmd noch laeuft (S4), der Notbetrieb bei
# unlesbarer Konfiguration (S5), die Notbremse hardIdleMinutes, die Sperrzeit
# nach Fehlversuchen (S8), die HTTP-Pruefung statt des blossen TCP-Accepts
# (S10) und zwei Backends in EINEM Prozess.
#
# INTERPRETER (S2): der Proxy traegt einen festen Shebang, und dieses Skript
# ruft die Datei direkt auf — Test und Betrieb fahren damit nachweislich
# dasselbe Python. Fall 0 prueft genau das, statt es anzunehmen.
#
# ISOLATION (regeln/tests-und-eingriffe.md): eigenes HOME (mktemp -d), eigene
# Konfigurationsdateien im Testbaum, vom Kernel vergebene freie Testports —
# nie 8080/8081 (Proxy und lmbeta-server), nie 11434 (Ollama), nie 8766/8767
# (MCP). Statt eines echten Modells laeuft ein winziger HTTP-Server aus diesem
# Skript; ensureCmd/stopCmd sind Testskripte, die mitzaehlen, wie oft sie
# gerufen wurden. Die echte ~/.config/wb-modell-proxy/backends.json, die echte
# plist und launchd werden nie angefasst: der Proxy laeuft hier mit
# --selbst-binden. Das launchd-Re-Arm nach dem Selbstende ist von aussen nicht
# nachstellbar und wird hier durch einen zweiten Start von Hand simuliert —
# live geprueft wird es getrennt (siehe Ergebnisdatei des Auftrags).
#
# Lauf:  shell/tests/test-modell-proxy.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
PROXY="$REPO/wb-modell-proxy"
# Kit: the proxy runs on the python3 of PATH (kit fix modell-proxy-shebang) and needs 3.11 or newer
# (Ubuntu 24.04 has 3.12). A machine with an older python3 on PATH cannot run it at all.
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
  echo "UEBERSPRUNGEN: nicht auf dieser Maschine: python3 auf PATH ist aelter als 3.11 ($(python3 -V 2>&1)); wb-modell-proxy braucht 3.11"
  exit 77
fi
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
have() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | tr '\n' '|')" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "'$3' steht in der Ausgabe, darf es aber nicht" ;; *) ok "$1" ;; esac; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }

. "$REPO/tests/lib-testwerkzeuge.sh"

[ -x "$PROXY" ] || { echo "FEHLT: $PROXY ist nicht ausfuehrbar"; exit 1; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-modell-proxy-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
STATE="$TESTHOME/state"; BIN="$TESTHOME/bin"
mkdir -p "$STATE" "$BIN"
export PATH="$BIN:$PATH"
PROXY_PID=""
NEBEN_PIDS=""

alles_beenden() {
  local p f
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null
  for p in $NEBEN_PIDS; do kill "$p" 2>/dev/null; done
  for f in "$STATE"/dummy-*.pid; do
    [ -f "$f" ] || continue
    kill "$(cat "$f" 2>/dev/null)" 2>/dev/null
  done
  sleep 0.5
  [ -n "$PROXY_PID" ] && kill -9 "$PROXY_PID" 2>/dev/null
  for p in $NEBEN_PIDS; do kill -9 "$p" 2>/dev/null; done
  for f in "$STATE"/dummy-*.pid; do
    [ -f "$f" ] || continue
    kill -9 "$(cat "$f" 2>/dev/null)" 2>/dev/null
  done
  case "$TESTHOME" in
    /tmp/wb-modell-proxy-test.*|/private/tmp/wb-modell-proxy-test.*|/var/folders/*/wb-modell-proxy-test.*)
      rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: TESTHOME='$TESTHOME' sieht nicht nach einem Testverzeichnis aus — NICHT geloescht." >&2 ;;
  esac
}
trap alles_beenden EXIT INT TERM

freier_port() {
  python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}
lauscht() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1; }
lebt()    { kill -0 "$1" 2>/dev/null; }

LPORT="$(freier_port)";  BPORT="$(freier_port)"
LPORT3="$(freier_port)"; BPORT3="$(freier_port)"
LPORT6="$(freier_port)"; BPORT6="$(freier_port)"
LPORTA="$(freier_port)"; BPORTA="$(freier_port)"
LPORTB="$(freier_port)"; BPORTB="$(freier_port)"
LPORTC="$(freier_port)"; BPORTC="$(freier_port)"
echo "Testports: lausch $LPORT/$LPORT3/$LPORT6/$LPORTA/$LPORTB/$LPORTC"

# ── Das Ersatz-Backend: ein HTTP-Server, der antworten und stroemen kann ─────
cat >"$STATE/dummy-backend.py" <<'PYEOF'
import sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# argv: <port> [health-verzug-s] [wie-viele-erste-health-anfragen-verzoegern]
# Der Verzug bildet den Fall nach, den das Re-Review gemessen hat: ein Modell,
# das gerade rechnet, beantwortet /health nicht innerhalb der Frist.
VERZUG = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
VERZUG_ANZAHL = int(sys.argv[3]) if len(sys.argv) > 3 else 0
_zaehler = {"health": 0}
_sperre = threading.Lock()

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"          # ohne Content-Length, Ende per close
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/health" and VERZUG > 0:
            with _sperre:
                _zaehler["health"] += 1
                dran = _zaehler["health"] <= VERZUG_ANZAHL
            if dran:
                time.sleep(VERZUG)
        if self.path in ("/ping", "/health"):
            leib = b"pong\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(leib)))
            self.end_headers()
            self.wfile.write(leib)
        elif self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            for i in (1, 2, 3):
                self.wfile.write(("chunk%d\n" % i).encode())
                self.wfile.flush()
                if i < 3:
                    time.sleep(1.0)
        else:
            self.send_response(404); self.end_headers()

ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PYEOF

# Ein Lauscher, der Verbindungen ANNIMMT und nie ein Byte sagt — die
# Gegenprobe zu "TCP-Accept heisst betriebsbereit" (Fall 13).
cat >"$STATE/stummer-lauscher.py" <<'PYEOF'
import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(8)
haltet = []
while True:
    c, _ = s.accept()
    haltet.append(c)          # nie antworten, nie schliessen
PYEOF

# ── ensureCmd / stopCmd als mitzaehlende Testskripte ─────────────────────────
# schreibe_werkzeuge <marke> <backendport> <stop-art:ehrlich|luege|langsam>
#                    [<ensure-verzoegerung-s>]
schreibe_werkzeuge() {
  local marke="$1" bport="$2" art="$3" verzug="${4:-0}"
  cat >"$BIN/ensure-$marke" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-$marke.zaehler"
printf '%s' "\${WB_EIGENTUEMER_LAUNCHD:-}" >"$STATE/label-$marke.txt"
if ! curl -fsS --max-time 1 "http://127.0.0.1:$bport/ping" >/dev/null 2>&1; then
  python3 "$STATE/dummy-backend.py" $bport >"$STATE/dummy-$marke.log" 2>&1 &
  echo \$! >"$STATE/dummy-$marke.pid"
  for i in \$(seq 1 60); do
    curl -fsS --max-time 1 "http://127.0.0.1:$bport/ping" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi
if ! curl -fsS --max-time 1 "http://127.0.0.1:$bport/ping" >/dev/null 2>&1; then
  echo "Ersatz-Backend kam auf $bport nicht hoch" >&2
  exit 1
fi
[ "$verzug" != "0" ] && sleep $verzug
exit 0
EOF
  case "$art" in
    ehrlich|langsam)
      local vorlauf=""
      [ "$art" = "langsam" ] && vorlauf="sleep 3"
      cat >"$BIN/stop-$marke" <<EOF
#!/bin/bash
echo stop >>"$STATE/stop-$marke.zaehler"
$vorlauf
pid="\$(cat "$STATE/dummy-$marke.pid" 2>/dev/null)"
[ -n "\$pid" ] && kill "\$pid" 2>/dev/null
for i in \$(seq 1 40); do
  curl -fsS --max-time 1 "http://127.0.0.1:$bport/ping" >/dev/null 2>&1 || exit 0
  sleep 0.2
done
echo "Ersatz-Backend auf $bport laeuft weiter" >&2
exit 1
EOF
      ;;
    luege)
      # meldet Erfolg, beendet aber nichts
      cat >"$BIN/stop-$marke" <<EOF
#!/bin/bash
echo stop >>"$STATE/stop-$marke.zaehler"
echo "angeblich beendet"
exit 0
EOF
      ;;
  esac
  chmod +x "$BIN/ensure-$marke" "$BIN/stop-$marke"
}

# schreibe_konfig <datei> <lauschport> <backendport> <marke> <idleMinutes>
#                 <exitIdleSeconds> <tick> [<hardIdleMinutes|->] [<label|->]
schreibe_konfig() {
  local hart="${8:--}" label="${9:--}" hartzeile="" labelzeile=""
  [ "$hart" != "-" ] && hartzeile="      \"hardIdleMinutes\": $hart,"
  [ "$label" != "-" ] && labelzeile="  \"launchdLabel\": \"$label\","
  cat >"$1" <<EOF
{
$labelzeile
  "tickSeconds": $7,
  "exitIdleSeconds": $6,
  "backends": {
    "$2": {
      "name": "$4",
      "backendPort": $3,
      "ensureCmd": "$BIN/ensure-$4",
      "stopCmd": "$BIN/stop-$4",
$hartzeile
      "idleMinutes": $5,
      "ensureTimeoutSeconds": 40,
      "stopTimeoutSeconds": 30
    }
  }
}
EOF
}

starte_proxy() {   # <konfig> <logmarke>
  WB_MODELL_PROXY_STDERR=1 "$PROXY" --selbst-binden --konfig "$1" --log "$STATE/$2.log" \
    >"$STATE/$2.stderr" 2>&1 &
  PROXY_PID=$!
}

# Kommt der Proxy nicht hoch, sind alle folgenden Zusagen des Abschnitts
# wertlos — das wird laut gesagt statt mit '|| true' verschluckt.
proxy_bereit() {   # <lauschport> <logmarke>
  if warte_auf_bedingung 15 "Proxy lauscht auf $1" "lauscht $1" "$STATE/$2.stderr"; then
    return 0
  fi
  bad "Proxy kam nicht hoch — die folgenden Zusagen dieses Abschnitts sind nicht aussagekraeftig"
  return 1
}

zaehler() { [ -f "$1" ] && wc -l <"$1" | tr -d ' ' || echo 0; }

echo
echo "== 0. Ein fester Interpreter, in Test und Betrieb derselbe (S2) =="
SHEBANG="$(head -1 "$PROXY" | sed 's|^#!||')"
# Kit: '/usr/bin/env python3' by design (no Homebrew path on a laptop); the test resolves it.
case "$SHEBANG" in
  "/usr/bin/env python3") SHEBANG="$(command -v python3)"; ok "der Shebang nimmt python3 aus PATH ($SHEBANG)" ;;
  /*) ok "der Shebang nennt einen absoluten Interpreterpfad ($SHEBANG)" ;;
  *)  bad "der Shebang ist '$SHEBANG'" ;;
esac
if [ -x "$SHEBANG" ]; then
  ok "dieser Interpreter existiert und ist ausfuehrbar"
  SB_VERSION="$("$SHEBANG" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
else
  bad "Interpreter '$SHEBANG' ist nicht ausfuehrbar"; SB_VERSION=""
fi
schreibe_werkzeuge lang "$BPORT" ehrlich
schreibe_konfig "$STATE/lang.json" "$LPORT" "$BPORT" lang 5 300 0.5
out="$("$PROXY" --pruefen --konfig "$STATE/lang.json" --log "$STATE/pruef.log" 2>&1)"
have "--pruefen nennt Lausch- und Backendport" "$out" "lauscht 127.0.0.1:$LPORT -> 127.0.0.1:$BPORT"
have "--pruefen nennt die HTTP-Pruefung" "$out" "health=/health"
[ -n "$SB_VERSION" ] && have "der laufende Proxy meldet genau dieses Python ($SB_VERSION)" "$out" "python=$SB_VERSION"
"$PROXY" --pruefen --konfig "$STATE/gibtsnicht.json" --log "$STATE/pruef.log" >/dev/null 2>&1
eq "fehlende Konfiguration ist ein Fehler, kein stiller Start" "$?" "2"

echo
echo "== 1. Kaltstart: erste Verbindung startet das Backend und wird bedient =="
rm -f "$STATE/ensure-lang.zaehler"
starte_proxy "$STATE/lang.json" proxy1
if proxy_bereit "$LPORT" proxy1; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  eq "Antwort kommt durch den Proxy vom Ersatz-Backend" "$antwort" "pong"
  eq "ensureCmd lief genau einmal" "$(zaehler "$STATE/ensure-lang.zaehler")" "1"
  if lauscht "$BPORT"; then ok "Backend laeuft jetzt auf $BPORT"; else bad "Backend laeuft jetzt auf $BPORT"; fi
  antwort="$(curl -fsS --max-time 10 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  eq "zweite Anfrage wird ebenfalls bedient" "$antwort" "pong"
  eq "ensureCmd lief NICHT erneut (warmer Weg)" "$(zaehler "$STATE/ensure-lang.zaehler")" "1"
fi

echo
echo "== 2. Streaming laeuft durch, statt gepuffert am Ende anzukommen =="
: >"$STATE/stream.out"
curl -N -s --max-time 20 "http://127.0.0.1:$LPORT/stream" >"$STATE/stream.out" 2>/dev/null &
CURL_PID=$!
sleep 0.6
teil="$(cat "$STATE/stream.out" 2>/dev/null)"
have "erstes Stueck ist schon da, waehrend das Backend noch schreibt" "$teil" "chunk1"
hasnt "letztes Stueck ist noch nicht da" "$teil" "chunk3"
wait "$CURL_PID" 2>/dev/null
voll="$(cat "$STATE/stream.out" 2>/dev/null)"
have "am Ende ist alles angekommen (chunk2)" "$voll" "chunk2"
have "am Ende ist alles angekommen (chunk3)" "$voll" "chunk3"

echo
echo "== 3. Ein hart abgeschossenes Backend gilt sofort als weg (Nebenbefund) =="
# Der Reviewer sah nach dem Abschuss seines Ersatz-Backends ein "stop
# GESCHEITERT — Port antwortet weiterhin" und liess offen, ob TIME_WAIT oder
# der antwortet()-Weg schuld ist. Hier wird beides gemessen: der Lauschsocket
# verschwindet mit dem Prozess, und der Proxy faehrt das Backend beim naechsten
# Zugriff sauber neu hoch.
DUMMY_PID="$(cat "$STATE/dummy-lang.pid" 2>/dev/null)"
kill -9 "$DUMMY_PID" 2>/dev/null
warte_auf_bedingung 10 "Backendport $BPORT wird nach SIGKILL frei" '! lauscht '"$BPORT"
if lauscht "$BPORT"; then bad "Backendport ist nach SIGKILL frei (kein TIME_WAIT-Rest)"; else ok "Backendport ist nach SIGKILL frei (kein TIME_WAIT-Rest)"; fi
antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
eq "der Proxy faehrt das weggestorbene Backend neu hoch" "$antwort" "pong"
eq "ensureCmd lief dafuer ein zweites Mal" "$(zaehler "$STATE/ensure-lang.zaehler")" "2"
log1="$(cat "$STATE/proxy1.log" 2>/dev/null)"
hasnt "kein falsches 'stop GESCHEITERT' im Protokoll" "$log1" "stop GESCHEITERT"

echo
echo "== 4. SIGTERM mit OFFENER Verbindung beendet trotzdem das Backend (S1) =="
# Genau der Fall, an dem der Review den Zweig gekippt hat: eine ungenutzte,
# offene Verbindung darf das Abschalten des Backends nicht aufhalten.
exec 3<>"/dev/tcp/127.0.0.1/$LPORT" && ok "eine ungenutzte Verbindung liegt offen auf dem Proxy" \
  || bad "konnte keine Rohverbindung zum Proxy oeffnen"
sleep 0.5
kill "$PROXY_PID" 2>/dev/null
warte_auf_bedingung 25 "Proxy endet trotz offener Verbindung" '! lebt "$PROXY_PID"' "$STATE/proxy1.stderr"
if lebt "$PROXY_PID"; then bad "Proxy ist nach SIGTERM beendet"; else ok "Proxy ist nach SIGTERM beendet"; fi
if lauscht "$BPORT"; then bad "Backend $BPORT ist mit dem Proxy beendet worden" "es laeuft weiter — genau der Befund S1"; else ok "Backend $BPORT ist mit dem Proxy beendet worden"; fi
eq "stopCmd lief dabei genau einmal" "$(zaehler "$STATE/stop-lang.zaehler")" "1"
exec 3>&- 2>/dev/null
exec 3<&- 2>/dev/null
PROXY_PID=""

echo
echo "== 5. Gescheitertes ensure: HTTP 503 mit Klartext, danach Sperrzeit (S8) =="
schreibe_werkzeuge fehl "$BPORT3" ehrlich
cat >"$BIN/ensure-fehl" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-fehl.zaehler"
echo "nur 3000 MiB frei, mindestens 20480 MiB noetig — Start abgebrochen" >&2
exit 1
EOF
chmod +x "$BIN/ensure-fehl"
schreibe_konfig "$STATE/fehl.json" "$LPORT3" "$BPORT3" fehl 5 300 0.5
starte_proxy "$STATE/fehl.json" proxy3
if proxy_bereit "$LPORT3" proxy3; then
  code="$(curl -s -o "$STATE/503.body" -w '%{http_code}' --max-time 30 "http://127.0.0.1:$LPORT3/v1/models" 2>/dev/null)"
  eq "Client bekommt 503 statt einer haengenden Verbindung" "$code" "503"
  have "der Grund steht im Klartext in der Antwort" "$(cat "$STATE/503.body" 2>/dev/null)" "mindestens 20480 MiB noetig"
  if lauscht "$BPORT3"; then bad "kein Backend gestartet"; else ok "kein Backend gestartet"; fi
  code="$(curl -s -o "$STATE/503b.body" -w '%{http_code}' --max-time 30 "http://127.0.0.1:$LPORT3/v1/models" 2>/dev/null)"
  eq "die naechste Anfrage bekommt ebenfalls 503" "$code" "503"
  have "sie nennt die Sperrzeit statt es sofort wieder zu versuchen" "$(cat "$STATE/503b.body" 2>/dev/null)" "fruehestens in"
  eq "ensureCmd wurde in der Sperrzeit NICHT erneut gerufen" "$(zaehler "$STATE/ensure-fehl.zaehler")" "1"
fi
kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null; PROXY_PID=""

echo
echo "== 6. Ein luegendes stopCmd wird nicht geglaubt =="
schreibe_werkzeuge luege "$BPORT6" luege
schreibe_konfig "$STATE/luege.json" "$LPORT6" "$BPORT6" luege 0.03 1 0.5
starte_proxy "$STATE/luege.json" proxy6
if proxy_bereit "$LPORT6" proxy6; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT6/ping" 2>&1)"
  eq "Backend antwortet zunaechst" "$antwort" "pong"
  warte_auf_bedingung 25 "stopCmd wurde wegen Leerlauf gerufen" '[ -f "$STATE/stop-luege.zaehler" ]' "$STATE/proxy6.stderr"
  sleep 2
  if lebt "$PROXY_PID"; then ok "Proxy beendet sich NICHT, solange das Backend nachweislich weiterlaeuft"; else bad "Proxy beendet sich NICHT, solange das Backend nachweislich weiterlaeuft" "er ist weg"; fi
  have "das Protokoll nennt den gescheiterten Stopp" "$(cat "$STATE/proxy6.log" 2>/dev/null)" "stop GESCHEITERT"
fi
kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null; PROXY_PID=""
kill "$(cat "$STATE/dummy-luege.pid" 2>/dev/null)" 2>/dev/null

echo
echo "== 7. Leerlauf: Backend gestoppt, danach beendet sich der Proxy selbst =="
rm -f "$STATE/ensure-lang.zaehler" "$STATE/stop-lang.zaehler"
schreibe_konfig "$STATE/kurz.json" "$LPORT" "$BPORT" lang 0.03 1 0.5   # 1,8 s Leerlauf
starte_proxy "$STATE/kurz.json" proxy4
if proxy_bereit "$LPORT" proxy4; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  eq "Kaltstart nach dem Stopp funktioniert wieder" "$antwort" "pong"
  eq "ensureCmd lief dafuer erneut" "$(zaehler "$STATE/ensure-lang.zaehler")" "1"
  warte_auf_bedingung 30 "Proxy beendet sich nach dem Leerlauf-Stopp selbst" '! lebt "$PROXY_PID"' "$STATE/proxy4.stderr"
  if lebt "$PROXY_PID"; then bad "Proxy hat sich selbst beendet"; else ok "Proxy hat sich selbst beendet"; fi
  eq "stopCmd lief genau einmal" "$(zaehler "$STATE/stop-lang.zaehler")" "1"
  if lauscht "$BPORT"; then bad "Backend $BPORT ist frei"; else ok "Backend $BPORT ist frei"; fi
  if lauscht "$LPORT"; then bad "Lauschport $LPORT ist frei (launchd wuerde ihn jetzt re-armieren)"; else ok "Lauschport $LPORT ist frei (launchd wuerde ihn jetzt re-armieren)"; fi
  have "das Protokoll nennt Stopp und Selbstende" "$(cat "$STATE/proxy4.log" 2>/dev/null)" "Proxy beendet sich"
fi
PROXY_PID=""

echo
echo "== 8. Zweiter Kaltstart nach dem Selbstende (launchd-Re-Arm von Hand) =="
starte_proxy "$STATE/kurz.json" proxy5
if proxy_bereit "$LPORT" proxy5; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  eq "der zweite Kaltstart bedient genauso" "$antwort" "pong"
  eq "ensureCmd lief dafuer ein zweites Mal" "$(zaehler "$STATE/ensure-lang.zaehler")" "2"
  warte_auf_bedingung 30 "Proxy beendet sich auch beim zweiten Mal" '! lebt "$PROXY_PID"' "$STATE/proxy5.stderr"
  if lebt "$PROXY_PID"; then bad "Proxy hat sich auch beim zweiten Mal beendet"; else ok "Proxy hat sich auch beim zweiten Mal beendet"; fi
  if lauscht "$BPORT"; then bad "Backend ist auch danach frei"; else ok "Backend ist auch danach frei"; fi
fi
PROXY_PID=""

echo
echo "== 9. Eine Anfrage in den laufenden Stopp hinein wird nicht abgeschnitten (S3) =="
# Vorher lief sie ungeprueft in das sterbende Backend und bekam eine
# abgeschnittene Antwort mit HTTP 200. Jetzt muss sie hinter dem Stopp warten
# und danach einen sauberen Kaltstart bekommen.
schreibe_werkzeuge langsam "$BPORTA" langsam
schreibe_konfig "$STATE/langsam.json" "$LPORTA" "$BPORTA" langsam 0.03 300 0.5
starte_proxy "$STATE/langsam.json" proxy7
if proxy_bereit "$LPORTA" proxy7; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORTA/ping" 2>&1)"
  eq "erste Anfrage wird bedient" "$antwort" "pong"
  warte_auf_bedingung 25 "stopCmd hat begonnen" '[ -f "$STATE/stop-langsam.zaehler" ]' "$STATE/proxy7.stderr"
  sleep 0.5      # mitten im 3-Sekunden-Vorlauf des stopCmd
  antwort="$(curl -fsS --max-time 60 "http://127.0.0.1:$LPORTA/ping" 2>&1)"
  eq "die Anfrage im laufenden Stopp bekommt eine VOLLSTAENDIGE Antwort" "$antwort" "pong"
  eq "sie hat dafuer einen echten Kaltstart bekommen" "$(zaehler "$STATE/ensure-langsam.zaehler")" "2"
  have "das Protokoll nennt den Stopp vor dem Neustart" "$(cat "$STATE/proxy7.log" 2>/dev/null)" "gestoppt und geprueft"
fi
kill "$PROXY_PID" 2>/dev/null
warte_auf_bedingung 25 "Proxy endet" '! lebt "$PROXY_PID"' "$STATE/proxy7.stderr"
if lauscht "$BPORTA"; then bad "Backend $BPORTA ist am Ende beendet"; else ok "Backend $BPORTA ist am Ende beendet"; fi
PROXY_PID=""

echo
echo "== 10. SIGTERM waehrend des Kaltstarts laesst keine Waise zurueck (S4) =="
# ensureCmd startet das Backend und trödelt danach noch — genau das Fenster,
# in dem 'bereit' noch False ist, obwohl der Modellserver schon laeuft.
schreibe_werkzeuge troedel "$BPORTB" ehrlich 20
schreibe_konfig "$STATE/troedel.json" "$LPORTB" "$BPORTB" troedel 5 300 0.5
starte_proxy "$STATE/troedel.json" proxy8
if proxy_bereit "$LPORTB" proxy8; then
  curl -s -o /dev/null --max-time 60 "http://127.0.0.1:$LPORTB/ping" &
  CURL_PID=$!
  warte_auf_bedingung 25 "das Backend ist waehrend des Kaltstarts oben" 'lauscht '"$BPORTB" "$STATE/proxy8.stderr"
  sleep 0.5
  kill "$PROXY_PID" 2>/dev/null
  warte_auf_bedingung 30 "Proxy endet mitten im Kaltstart" '! lebt "$PROXY_PID"' "$STATE/proxy8.stderr"
  if lebt "$PROXY_PID"; then bad "Proxy ist beendet"; else ok "Proxy ist beendet"; fi
  if lauscht "$BPORTB"; then bad "kein verwaister Modellserver zurueckgeblieben" "Backend $BPORTB laeuft weiter"; else ok "kein verwaister Modellserver zurueckgeblieben"; fi
  have "das Protokoll nennt den abgebrochenen Startlauf" "$(cat "$STATE/proxy8.log" 2>/dev/null)" "wird abgebrochen"
  wait "$CURL_PID" 2>/dev/null
fi
PROXY_PID=""

echo
echo "== 11. hardIdleMinutes: eine offene, aber stumme Verbindung haelt nichts ewig =="
rm -f "$STATE/ensure-lang.zaehler" "$STATE/stop-lang.zaehler"
schreibe_konfig "$STATE/hart.json" "$LPORT" "$BPORT" lang 60 1 0.5 0.05   # hart: 3 s
starte_proxy "$STATE/hart.json" proxy9
if proxy_bereit "$LPORT" proxy9; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  eq "Backend ist oben" "$antwort" "pong"
  exec 4<>"/dev/tcp/127.0.0.1/$LPORT" && ok "eine stumme Verbindung liegt offen" || bad "Rohverbindung fehlgeschlagen"
  warte_auf_bedingung 30 "die harte Grenze greift trotz offener Verbindung" '[ -f "$STATE/stop-lang.zaehler" ]' "$STATE/proxy9.stderr"
  eq "stopCmd lief wegen der harten Grenze" "$(zaehler "$STATE/stop-lang.zaehler")" "1"
  if lauscht "$BPORT"; then bad "Backend wurde beendet"; else ok "Backend wurde beendet"; fi
  have "das Protokoll nennt die harte Leerlaufgrenze" "$(cat "$STATE/proxy9.log" 2>/dev/null)" "harte Leerlaufgrenze"
  exec 4>&- 2>/dev/null
  exec 4<&- 2>/dev/null
fi
kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null; PROXY_PID=""

echo
echo "== 12. Unlesbare Konfiguration: 503 mit Grund statt wortlosem Ende (S5) =="
# Zuvor beendete sich der Prozess, bevor er auch nur eine Verbindung annahm —
# launchd startete ihn gedrosselt immer wieder, und der Client bekam nie ein
# Byte. Die zuletzt gueltigen Socketnamen liegen aus den Laeufen oben schon im
# Zustandsverzeichnis.
printf '{ das ist kein JSON\n' >"$STATE/kaputt.json"
starte_proxy "$STATE/kaputt.json" proxy4      # proxy4.log: dort liegen die gemerkten Namen
if proxy_bereit "$LPORT" proxy4; then
  code="$(curl -s -o "$STATE/notbetrieb.body" -w '%{http_code}' --max-time 20 "http://127.0.0.1:$LPORT/v1/models" 2>/dev/null)"
  eq "auch im Notbetrieb kommt eine Antwort" "$code" "503"
  have "sie nennt die unlesbare Konfiguration" "$(cat "$STATE/notbetrieb.body" 2>/dev/null)" "Konfiguration unbrauchbar"
  if lauscht "$BPORT"; then bad "kein Backend gestartet"; else ok "kein Backend gestartet"; fi
fi
kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null; PROXY_PID=""

echo
echo "== 13. Betriebsbereit heisst HTTP, nicht nur ein angenommener Socket (S10) =="
python3 "$STATE/stummer-lauscher.py" "$BPORTC" >/dev/null 2>&1 &
STUMM_PID=$!; NEBEN_PIDS="$NEBEN_PIDS $STUMM_PID"
warte_auf_bedingung 10 "der stumme Lauscher haelt $BPORTC" 'lauscht '"$BPORTC"
cat >"$BIN/ensure-stumm" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-stumm.zaehler"
echo "hier wird absichtlich nichts gestartet" >&2
exit 1
EOF
cat >"$BIN/stop-stumm" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$BIN/ensure-stumm" "$BIN/stop-stumm"
schreibe_konfig "$STATE/stumm.json" "$LPORTC" "$BPORTC" stumm 5 300 0.5
starte_proxy "$STATE/stumm.json" proxyA
if proxy_bereit "$LPORTC" proxyA; then
  curl -s -o /dev/null --max-time 30 "http://127.0.0.1:$LPORTC/v1/models" 2>/dev/null
  eq "ein Lauscher ohne HTTP gilt NICHT als bereit — ensureCmd wurde gerufen" "$(zaehler "$STATE/ensure-stumm.zaehler")" "1"
  hasnt "kein 'antwortet bereits' im Protokoll" "$(cat "$STATE/proxyA.log" 2>/dev/null)" "antwortet bereits"
fi
kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null; PROXY_PID=""
kill "$STUMM_PID" 2>/dev/null

echo
echo "== 14. Zwei Backends in EINEM Prozess, plus WB_EIGENTUEMER_LAUNCHD =="
rm -f "$STATE/ensure-lang.zaehler" "$STATE/stop-lang.zaehler" \
      "$STATE/ensure-zwei.zaehler" "$STATE/stop-zwei.zaehler"
LPORTD="$(freier_port)"; BPORTD="$(freier_port)"
schreibe_werkzeuge zwei "$BPORTD" ehrlich
cat >"$STATE/doppelt.json" <<EOF
{
  "launchdLabel": "agent-workbench.testproxy",
  "tickSeconds": 0.5,
  "exitIdleSeconds": 300,
  "backends": {
    "$LPORT": {
      "name": "lang", "backendPort": $BPORT,
      "ensureCmd": "$BIN/ensure-lang", "stopCmd": "$BIN/stop-lang",
      "idleMinutes": 5, "ensureTimeoutSeconds": 40, "stopTimeoutSeconds": 30
    },
    "$LPORTD": {
      "name": "zwei", "backendPort": $BPORTD,
      "ensureCmd": "$BIN/ensure-zwei", "stopCmd": "$BIN/stop-zwei",
      "idleMinutes": 5, "ensureTimeoutSeconds": 40, "stopTimeoutSeconds": 30
    }
  }
}
EOF
starte_proxy "$STATE/doppelt.json" proxyB
if proxy_bereit "$LPORT" proxyB && proxy_bereit "$LPORTD" proxyB; then
  eq "EIN Prozess bedient beide Lauschports" "$(pgrep -P $$ -f "wb-modell-proxy" | wc -l | tr -d ' ')" "1"
  a="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORT/ping" 2>&1)"
  b="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORTD/ping" 2>&1)"
  eq "erstes Backend antwortet" "$a" "pong"
  eq "zweites Backend antwortet" "$b" "pong"
  eq "jedes hat sein eigenes ensureCmd gerufen (1)" "$(zaehler "$STATE/ensure-lang.zaehler")" "1"
  eq "jedes hat sein eigenes ensureCmd gerufen (2)" "$(zaehler "$STATE/ensure-zwei.zaehler")" "1"
  eq "ensureCmd bekam WB_EIGENTUEMER_LAUNCHD" "$(cat "$STATE/label-zwei.txt" 2>/dev/null)" "agent-workbench.testproxy"
  kill "$PROXY_PID" 2>/dev/null
  warte_auf_bedingung 30 "Proxy endet" '! lebt "$PROXY_PID"' "$STATE/proxyB.stderr"
  if lauscht "$BPORT"; then bad "erstes Backend beendet"; else ok "erstes Backend beendet"; fi
  if lauscht "$BPORTD"; then bad "zweites Backend beendet"; else ok "zweites Backend beendet"; fi
fi
kill "$PROXY_PID" 2>/dev/null; PROXY_PID=""

echo
echo "== 15. Ein fremdes Backend wird bedient, aber nicht beendet =="
# Gelernt an einem lebenden Gegenbeispiel waehrend der Reparaturrunde: ein
# anderer Lauf hatte lmbeta-server aus seinem eigenen Pane gestartet, der Proxy
# klinkte sich ein ("antwortet bereits") — und haette ihn nach seiner
# Leerlaufzeit beendet. Wer sich nur einklinkt, klinkt sich auch nur aus.
LPORTE="$(freier_port)"; BPORTE="$(freier_port)"
schreibe_werkzeuge fremd "$BPORTE" ehrlich
python3 "$STATE/dummy-backend.py" "$BPORTE" >"$STATE/dummy-fremd.log" 2>&1 &
FREMD_PID=$!; NEBEN_PIDS="$NEBEN_PIDS $FREMD_PID"
warte_auf_bedingung 15 "das fremde Backend haelt $BPORTE" 'lauscht '"$BPORTE"
schreibe_konfig "$STATE/fremd.json" "$LPORTE" "$BPORTE" fremd 0.03 1 0.5
starte_proxy "$STATE/fremd.json" proxyC
if proxy_bereit "$LPORTE" proxyC; then
  antwort="$(curl -fsS --max-time 30 "http://127.0.0.1:$LPORTE/ping" 2>&1)"
  eq "das fremde Backend wird bedient" "$antwort" "pong"
  eq "ensureCmd wurde dafuer NICHT gerufen" "$(zaehler "$STATE/ensure-fremd.zaehler")" "0"
  warte_auf_bedingung 30 "Proxy beendet sich nach der Leerlaufzeit" '! lebt "$PROXY_PID"' "$STATE/proxyC.stderr"
  if lebt "$PROXY_PID"; then bad "Proxy hat sich beendet"; else ok "Proxy hat sich beendet (kein Prozess im Leerlauf)"; fi
  eq "stopCmd wurde NIE gerufen" "$(zaehler "$STATE/stop-fremd.zaehler")" "0"
  if lauscht "$BPORTE"; then ok "das fremde Backend laeuft unangetastet weiter"; else bad "das fremde Backend wurde beendet — genau das darf nicht passieren"; fi
  have "das Protokoll sagt, dass nur ausgeklinkt wurde" "$(cat "$STATE/proxyC.log" 2>/dev/null)" "nicht gestartet"
fi
PROXY_PID=""
kill "$FREMD_PID" 2>/dev/null

echo
echo "== 16. Eine langsame /health-Probe macht ein fremdes Backend nicht zu eigenem (R1, Weg 1) =="
# Der gemessene Schaden aus dem Re-Review: die erste /health-Probe verpasst
# ihre Frist, weil das Modell rechnet; der Proxy haelt das Backend fuer
# abwesend, ruft das IDEMPOTENTE ensureCmd, bekommt Exit 0 — und bucht ein
# fremdes Backend als eigenes ein. Entschieden wird jetzt am Portzustand
# unmittelbar vor dem ensureCmd, und der ist von der HTTP-Frist unabhaengig.
LPORTF="$(freier_port)"; BPORTF="$(freier_port)"
# ensureCmd wie `lmbeta-server ensure`, wenn schon etwas laeuft: meldet Erfolg,
# startet nichts.
cat >"$BIN/ensure-langsam1" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-langsam1.zaehler"
exit 0
EOF
cat >"$BIN/stop-langsam1" <<EOF
#!/bin/bash
echo stop >>"$STATE/stop-langsam1.zaehler"
kill "\$(cat "$STATE/dummy-langsam1.pid" 2>/dev/null)" 2>/dev/null
exit 0
EOF
chmod +x "$BIN/ensure-langsam1" "$BIN/stop-langsam1"
python3 "$STATE/dummy-backend.py" "$BPORTF" 5 1 >"$STATE/dummy-langsam1.log" 2>&1 &
LANGSAM_PID=$!; NEBEN_PIDS="$NEBEN_PIDS $LANGSAM_PID"
echo "$LANGSAM_PID" >"$STATE/dummy-langsam1.pid"
warte_auf_bedingung 15 "das fremde Backend haelt $BPORTF" 'lauscht '"$BPORTF"
cat >"$STATE/langsam1.json" <<EOF
{
  "tickSeconds": 0.5, "exitIdleSeconds": 1,
  "backends": { "$LPORTF": {
      "name": "langsam1", "backendPort": $BPORTF,
      "ensureCmd": "$BIN/ensure-langsam1", "stopCmd": "$BIN/stop-langsam1",
      "idleMinutes": 0.03, "healthTimeoutSeconds": 1,
      "ensureTimeoutSeconds": 40, "stopTimeoutSeconds": 30 } }
}
EOF
starte_proxy "$STATE/langsam1.json" proxyD
if proxy_bereit "$LPORTF" proxyD; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORTF/ping" 2>&1)"
  eq "das fremde Backend wird trotz verpasster Probe bedient" "$antwort" "pong"
  eq "das idempotente ensureCmd lief (die Probe hatte ja versagt)" "$(zaehler "$STATE/ensure-langsam1.zaehler")" "1"
  have "das Protokoll sagt, dass der Port schon belegt war" "$(cat "$STATE/proxyD.log" 2>/dev/null)" "bleibt aber fremd"
  warte_auf_bedingung 30 "Proxy beendet sich nach der Leerlaufzeit" '! lebt "$PROXY_PID"' "$STATE/proxyD.stderr"
  eq "stopCmd wurde NIE gerufen — kein Eigentum gebucht" "$(zaehler "$STATE/stop-langsam1.zaehler")" "0"
  if lauscht "$BPORTF"; then ok "das fremde Backend laeuft unangetastet weiter"; else bad "das fremde Backend wurde beendet — genau der Schaden aus R1"; fi
fi
PROXY_PID=""
kill "$LANGSAM_PID" 2>/dev/null

echo
echo "== 17. Weg 2: fremder Starter parallel zum eigenen ensureCmd (bekannter Restfall) =="
# Hier ist der Port beim Beschluss frei, ein anderer Starter faehrt das Backend
# aber waehrend unseres ensureCmd hoch. Dieser Fall ist ohne eine Sperre, die
# sich beide Starter teilen, nicht aufloesbar; die getroffene Festlegung ist:
# es entscheidet der Portzustand im Augenblick des Beschlusses, der Proxy fuehlt
# sich also zustaendig. Dieser Fall haelt genau diese Festlegung fest, damit
# eine spaetere Aenderung auffaellt.
LPORTG="$(freier_port)"; BPORTG="$(freier_port)"
cat >"$BIN/ensure-weg2" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-weg2.zaehler"
sleep 3
exit 0
EOF
cat >"$BIN/stop-weg2" <<EOF
#!/bin/bash
echo stop >>"$STATE/stop-weg2.zaehler"
kill "\$(cat "$STATE/dummy-weg2.pid" 2>/dev/null)" 2>/dev/null
for i in \$(seq 1 40); do lsof -nP -iTCP:$BPORTG -sTCP:LISTEN -t >/dev/null 2>&1 || exit 0; sleep 0.2; done
exit 1
EOF
chmod +x "$BIN/ensure-weg2" "$BIN/stop-weg2"
schreibe_konfig "$STATE/weg2.json" "$LPORTG" "$BPORTG" weg2 0.03 1 0.5
starte_proxy "$STATE/weg2.json" proxyE
if proxy_bereit "$LPORTG" proxyE; then
  curl -fsS --max-time 40 "http://127.0.0.1:$LPORTG/ping" >"$STATE/weg2.out" 2>&1 &
  CURL_PID=$!
  warte_auf_bedingung 15 "ensureCmd laeuft" '[ -f "$STATE/ensure-weg2.zaehler" ]' "$STATE/proxyE.stderr"
  sleep 0.5
  python3 "$STATE/dummy-backend.py" "$BPORTG" >"$STATE/dummy-weg2.log" 2>&1 &
  WEG2_PID=$!; NEBEN_PIDS="$NEBEN_PIDS $WEG2_PID"
  echo "$WEG2_PID" >"$STATE/dummy-weg2.pid"
  wait "$CURL_PID" 2>/dev/null
  eq "die Anfrage wird bedient" "$(cat "$STATE/weg2.out" 2>/dev/null)" "pong"
  hasnt "der Port war beim Beschluss frei — kein 'bleibt aber fremd'" "$(cat "$STATE/proxyE.log" 2>/dev/null)" "bleibt aber fremd"
  warte_auf_bedingung 30 "Proxy beendet sich nach der Leerlaufzeit" '! lebt "$PROXY_PID"' "$STATE/proxyE.stderr"
  eq "der Proxy fuehlt sich zustaendig und stoppt (festgelegtes Verhalten)" "$(zaehler "$STATE/stop-weg2.zaehler")" "1"
  if lauscht "$BPORTG"; then bad "Backend beendet"; else ok "Backend beendet"; fi
fi
PROXY_PID=""
kill "${WEG2_PID:-0}" 2>/dev/null

echo
echo "== 18. Ein haengender Server nach dem stopCmd gilt NICHT als beendet (R2) =="
# Gemessen im Re-Review: der Proxy schrieb "gestoppt und geprueft — Port frei",
# waehrend der Prozess lebte und den Port hielt. Ursache war, dass die
# Stopp-Pruefung dieselbe HTTP-Probe benutzte wie die Bereitschaftsfrage.
cat >"$STATE/haenger.py" <<'PYEOF'
import signal, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass
    def do_GET(self):
        leib = b"pong\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(leib)))
        self.end_headers()
        self.wfile.write(leib)

srv = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H)

def bei_sigterm(*a):
    # Aufhoeren zu ANTWORTEN, den Lauschsocket aber offen halten — genau der
    # Zustand eines Modellservers, der gerade 20 GB freigibt.
    threading.Thread(target=srv.shutdown, daemon=True).start()

signal.signal(signal.SIGTERM, bei_sigterm)
threading.Thread(target=srv.serve_forever, daemon=True).start()
while True:
    time.sleep(1)
PYEOF
LPORTH="$(freier_port)"; BPORTH="$(freier_port)"
cat >"$BIN/ensure-haenger" <<EOF
#!/bin/bash
echo start >>"$STATE/ensure-haenger.zaehler"
python3 "$STATE/haenger.py" $BPORTH >"$STATE/haenger.log" 2>&1 &
echo \$! >"$STATE/dummy-haenger.pid"
for i in \$(seq 1 60); do curl -fsS --max-time 1 "http://127.0.0.1:$BPORTH/health" >/dev/null 2>&1 && exit 0; sleep 0.2; done
exit 1
EOF
cat >"$BIN/stop-haenger" <<EOF
#!/bin/bash
echo stop >>"$STATE/stop-haenger.zaehler"
kill "\$(cat "$STATE/dummy-haenger.pid" 2>/dev/null)" 2>/dev/null
sleep 1
exit 0                      # behauptet Erfolg, obwohl der Prozess den Port haelt
EOF
chmod +x "$BIN/ensure-haenger" "$BIN/stop-haenger"
schreibe_konfig "$STATE/haenger.json" "$LPORTH" "$BPORTH" haenger 0.03 1 0.5
starte_proxy "$STATE/haenger.json" proxyF
if proxy_bereit "$LPORTH" proxyF; then
  antwort="$(curl -fsS --max-time 40 "http://127.0.0.1:$LPORTH/ping" 2>&1)"
  eq "das eigene Backend antwortet zunaechst" "$antwort" "pong"
  warte_auf_bedingung 25 "stopCmd wurde wegen Leerlauf gerufen" '[ -f "$STATE/stop-haenger.zaehler" ]' "$STATE/proxyF.stderr"
  sleep 3
  HPID="$(cat "$STATE/dummy-haenger.pid" 2>/dev/null)"
  if lebt "$HPID"; then ok "der Backend-Prozess lebt noch (das ist die Versuchsanordnung)"; else bad "der Haenger ist beendet — die Versuchsanordnung greift nicht"; fi
  if lauscht "$BPORTH"; then ok "und er haelt den Port weiterhin"; else bad "der Port ist frei — die Versuchsanordnung greift nicht"; fi
  loghf="$(cat "$STATE/proxyF.log" 2>/dev/null)"
  have "das Protokoll nennt den gescheiterten Stopp" "$loghf" "stop GESCHEITERT"
  have "und sagt, dass der Port weiterhin belegt ist" "$loghf" "weiterhin belegt"
  hasnt "keine Zeile behauptet, der Port nehme nichts mehr an" "$loghf" "nimmt keine Verbindung mehr an"
  if lebt "$PROXY_PID"; then ok "der Proxy beendet sich NICHT — das Eigentum bleibt bestehen"; else bad "der Proxy hat sich beendet und einen eigenen Prozess stehen lassen"; fi
  kill "$PROXY_PID" 2>/dev/null
  warte_auf_bedingung 30 "Proxy endet nach SIGTERM" '! lebt "$PROXY_PID"' "$STATE/proxyF.stderr"
  have "auch beim Abschalten wird es noch einmal versucht" "$(cat "$STATE/proxyF.log" 2>/dev/null)" "Proxy endet"
  kill -9 "$HPID" 2>/dev/null
fi
PROXY_PID=""

echo
echo "== 19. Ohne brauchbaren Lauschport: laute Ablehnung statt Port 0 oder Schweigen =="
# Zwei kleinere Beobachtungen des Re-Reviews in einem Fall. Im Notbetrieb ist
# der Konfigschluessel der SOCKETNAME; in der Auslieferung heisst er "lmbeta" und
# ist damit keine Portnummer. Unter --selbst-binden band der Prozess dafuer
# frueher Port 0, also einen zufaelligen, den nie jemand findet. Und blieb am
# Ende kein einziger Socket uebrig, endete er wortlos mit 1.
NOT="$STATE/notdir"; mkdir -p "$NOT"
printf '{"namen": ["lmbeta"]}\n' >"$NOT/socketnamen.json"
printf '{ kaputt\n' >"$NOT/backends.json"
"$PROXY" --selbst-binden --konfig "$NOT/backends.json" --log "$NOT/proxy.log" >"$NOT/err" 2>&1
eq "der Prozess endet mit 1" "$?" "1"
lognot="$(cat "$NOT/proxy.log" 2>/dev/null)"
have "der Notbetrieb wird benannt" "$lognot" "Konfiguration unbrauchbar"
have "der nicht-numerische Name wird ausdruecklich abgelehnt" "$lognot" "braucht dieser Eintrag einen Lauschport"
have "und das Ende nennt seinen Grund" "$lognot" "kein einziger Socket"
have "mitsamt der versuchten Socketnamen" "$lognot" "lmbeta"
have "der Grund steht auch auf stderr (unter launchd: launchd.log)" "$(cat "$NOT/err" 2>/dev/null)" "kein einziger Socket"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
