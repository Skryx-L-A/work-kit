#!/usr/bin/env bash
# Tests fuer die Widerspruchs-Warteschlange (`brain contradict --queue-add/--queue`
# + `brain-maintain --contradict-only`).
#
# Anlass (2026-08-04): der volle `brain contradict --since ... --write`-Scan lief
# bisher SYNCHRON bei jedem Sessionende (~100s je geaenderter Notiz, lokales
# Modell) und blockierte damit den Abschluss. Neu: Sessionende haengt nur noch
# Pfade an `_meta/state/contradiction-queue.txt` an (Millisekunden); das
# Abarbeiten passiert bei den anderen wiederkehrenden Laeufen (brain-maintain,
# Mo/Mi launchd) oder von Hand.
#
# Laeuft komplett gegen einen TEMPORAEREN Kbase (BRAIN_MAINTAIN_KBASE / --kbase),
# nie gegen ~/work/brain — der echte Kbase-Inhalt bleibt unberuehrt. Ein Teil
# dieses Tests loest einen echten Judge-Aufruf (lokales Modell, ~1-2 Min) aus,
# weil genau das die Eigenschaft ist, die "Warteschlange abgearbeitet" beweisen
# soll — kein Mock des Scans, nur des Sessionende-Aufrufers.
#
# NACHTRAG 2026-08-10, der eigentliche Grund fuer die Haertung unten: Der Satz
# ueber dem Strich war fuer den INHALT des Kbases richtig und fuer den ZUSTAND
# daneben falsch. `brain --kbase <wegwerf> contradict --write` schrieb bis heute
# in den Embedding-Store des ECHTEN Kbases, weil `--kbase` den Korpus verschob,
# `config.STATE_DIR` aber am Werkzeugverzeichnis haengen blieb; jeder
# Einbettungspass endet mit `prune_embeddings`. Dieser Test hat am 2026-08-04 um
# 03:21 Uhr 249 Vektoren aus ~/work/brain geloescht, recall@1 fiel von 0,784 auf
# 0,297, und es fiel sechs Tage niemandem auf. Behoben ist es an der Wurzel
# (`gardener.config.bind_kbase`); hier steht seither der Waechter, der es
# gemerkt haette: Der echte Store wird vor und nach dem Lauf gezaehlt.
#
# NACHTRAG 2026-09-13: der "echte Judge-Aufruf" oben ging ueber `lmbeta-server
# ensure` an den ECHTEN MLX-Server auf dieser Maschine. Das hatte zwei Folgen:
# ohne tmux-Pane (launchd, `env -i`, run-all ausserhalb der Werkbank) weigerte
# sich wb-nohup, einen Server ohne Eigentuemer zu starten, und die Suite war
# rot, ohne dass am Warteschlangen-Code etwas kaputt war; und lief schon ein
# Server mit anderem Kontext, beendete `ensure` ihn fuer den Modellwechsel
# (gemessen am 13.09., ein laufender lmgamma-Server war danach weg). Ein Test
# startet und stoppt keinen Dienst der Maschine. Deshalb jetzt:
#   * `lmbeta-server` ist ein Stellvertreter vorn im PATH, der nur mitschreibt;
#   * der Richter ist ein Wegwerf-Endpunkt (OpenAI-Form, freier hoher Port,
#     LMBETA_BASE_URL), der fuer jedes Paar ein woertlich zitiertes Urteil gibt.
# Der Scan selbst bleibt echt: Einbettung, Nachbarsuche, HTTP-Aufruf des
# Richters, Befundspeicher, Marker und das Leeren der Warteschlange.
set -uo pipefail

BRAIN="${BRAIN_BIN:-$HOME/.local/bin/brain}"
MAINTAIN="${BRAIN_MAINTAIN_BIN:-$HOME/.local/bin/brain-maintain}"
ECHTER_STORE="${BRAIN_ECHTER_STORE:-$HOME/work/brain/_meta/tools/gardener/state/gardener.db}"
WORK="$(mktemp -d)"
KBASE="$WORK/kbase"
pass=0; fail=0

RICHTER_PID=""
cleanup() {
  [ -n "$RICHTER_PID" ] && kill "$RICHTER_PID" 2>/dev/null && wait "$RICHTER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Fingerabdruck des echten Embedding-Stores: Anzahl plus die sortierten Pfade.
# Fehlt die Datei, ist der Fingerabdruck "kein-store" - auch das ist ein Wert,
# der sich nicht aendern darf.
store_fingerprint() {
  [ -f "$ECHTER_STORE" ] || { echo "kein-store"; return; }
  sqlite3 "file:$ECHTER_STORE?mode=ro" \
    "SELECT count(*) FROM embeddings; SELECT rel FROM embeddings ORDER BY rel;" 2>/dev/null \
    | shasum | cut -d' ' -f1
}

# Der Wartungslauf schreibt sein Log sonst nach ~/.local/state - Live-Zustand,
# der einen Test nichts angeht.
export BRAIN_MAINTAIN_LOG="$WORK/brain-maintain.log"
live_log_groesse() {
  [ -f "$HOME/.local/state/brain-maintain.log" ] \
    && wc -c < "$HOME/.local/state/brain-maintain.log" | tr -d ' ' || echo 0
}

VORHER="$(store_fingerprint)"
LIVE_LOG_VORHER="$(live_log_groesse)"

# --- Stellvertreter fuer lmbeta-server: kein echter Server wird gestartet oder
# gestoppt. `status` meldet "nicht aktiv" (Exit 1), damit der Lauf sich als
# Eigentuemer sieht und am Ende `stop` ruft -- beides landet nur im Protokoll.
STUB_BIN="$WORK/bin"
LMBETA_PROTOKOLL="$WORK/lmbeta-server.aufrufe"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/lmbeta-server" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LMBETA_PROTOKOLL"
case "\$1" in
  status) echo "lmbeta-server-Stellvertreter: nicht aktiv"; exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB_BIN/lmbeta-server"
export PATH="$STUB_BIN:$PATH"

# --- Wegwerf-Richter: OpenAI-Form auf einem freien hohen Port ------------------
# Er zitiert aus jeder der beiden Notizen im Prompt die Zeile mit
# "Deploy-Fenster fuer testproj" -- woertlich, sonst verwirft contradict das
# Urteil als halluziniert.
RICHTER_PROTOKOLL="$WORK/richter.anfragen"
cat > "$WORK/richter.py" <<'PY'
import json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

protokoll = sys.argv[1]

def zitat(block):
    for zeile in block.splitlines():
        if "Deploy-Fenster fuer testproj" in zeile:
            return zeile.strip()
    return ""

class Richter(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def antwort(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.antwort({"status": "ok", "effective_context_limit": 8192})

    def do_POST(self):
        rumpf = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        prompt = rumpf["messages"][-1]["content"]
        with open(protokoll, "a") as f:
            f.write(self.path + "\n")
        m = re.search(r"Note A:.*?\n---\n(.*?)\n\nNote B:.*?\n---\n(.*?)\n\nDo these", prompt, re.S)
        a, b = (zitat(m.group(1)), zitat(m.group(2))) if m else ("", "")
        urteil = {"verdict": "contradiction", "confidence": 0.9,
                  "claim_a": a, "claim_b": b, "why": "zwei Wochentage fuer dasselbe Fenster"}
        self.antwort({"choices": [{"message": {"content": json.dumps(urteil, ensure_ascii=False)},
                                   "finish_reason": "stop"}],
                      "usage": {"prompt_tokens": 1, "completion_tokens": 1}})

server = HTTPServer(("127.0.0.1", 0), Richter)
print(server.server_address[1], flush=True)
server.serve_forever()
PY
python3 "$WORK/richter.py" "$RICHTER_PROTOKOLL" > "$WORK/richter.port" 2>"$WORK/richter.err" &
RICHTER_PID=$!
RICHTER_PORT=""
for _ in $(seq 1 50); do
  RICHTER_PORT="$(head -1 "$WORK/richter.port" 2>/dev/null)"
  [ -n "$RICHTER_PORT" ] && break
  sleep 0.1
done
if [ -z "$RICHTER_PORT" ]; then
  echo "Wegwerf-Richter startete nicht: $(cat "$WORK/richter.err")"
  exit 1
fi
export LMBETA_BASE_URL="http://127.0.0.1:$RICHTER_PORT"

mkdir -p "$KBASE/_meta/state" "$KBASE/20-projects/testproj"
cat > "$KBASE/20-projects/testproj/deploy-fenster-a.md" <<'EOF'
# Deploy-Fenster

Das Deploy-Fenster fuer testproj ist montags 09:00-10:00 Uhr.
EOF
cat > "$KBASE/20-projects/testproj/deploy-fenster-b.md" <<'EOF'
# Deploy-Fenster (zweite Notiz)

Das Deploy-Fenster fuer testproj ist freitags 16:00-17:00 Uhr.
EOF
QFILE="$KBASE/_meta/state/contradiction-queue.txt"

echo "-- (i) --queue-add: dedupliziert, auch relativ vs. absolut --"
OUT="$("$BRAIN" --kbase "$KBASE" contradict --queue-add \
  "20-projects/testproj/deploy-fenster-a.md" \
  "20-projects/testproj/deploy-fenster-b.md" \
  "20-projects/testproj/deploy-fenster-a.md" \
  "$KBASE/20-projects/testproj/deploy-fenster-b.md" 2>&1)"
RC=$?
[ "$RC" -eq 0 ] || bad "--queue-add exit $RC: $OUT"
LINES="$(wc -l < "$QFILE" 2>/dev/null | tr -d ' ')"
[ "$LINES" = "2" ] && ok "2 eindeutige Pfade in der Warteschlange (4 Aufrufe, 2 Dubletten)" \
                    || bad "erwartet 2 Zeilen in $QFILE, gefunden $LINES"
sort -u "$QFILE" | wc -l | grep -qx " *2" && ok "keine Dublette nach sort -u" \
                                            || bad "sort -u zeigt Dubletten: $(cat "$QFILE")"

echo "-- (ii) brain-maintain --contradict-only arbeitet die Warteschlange ab und leert sie --"
BEFORE_LINES="$LINES"
OUT2="$(BRAIN_MAINTAIN_KBASE="$KBASE" "$MAINTAIN" --contradict-only 2>&1)"
RC2=$?
echo "$OUT2" | sed 's/^/    /'
[ "$RC2" -eq 0 ] && ok "brain-maintain --contradict-only exit 0 (verarbeitete $BEFORE_LINES Eintraege)" \
                  || bad "brain-maintain --contradict-only exit $RC2"
if [ -s "$QFILE" ]; then
  bad "Warteschlange ist nach dem Lauf NICHT leer: $(cat "$QFILE")"
else
  ok "Warteschlangendatei ist nach dem Lauf leer/entfernt"
fi
if [ -f "$KBASE/_meta/state/contradictions.json" ]; then
  ok "contradictions.json wurde geschrieben (echter Scan lief, kein No-Op)"
else
  bad "contradictions.json fehlt - hat der Scan wirklich stattgefunden?"
fi
printf '%s\n' "$OUT2" | grep -q "geprueft: 2 Notiz(en)" \
  && ok "Ausgabe bestaetigt: 2 Notizen geprueft" \
  || bad "Ausgabe nennt nicht 'geprueft: 2 Notiz(en)': $OUT2"
ANFRAGEN="$(grep -c '^/v1/chat/completions$' "$RICHTER_PROTOKOLL" 2>/dev/null)"; ANFRAGEN="${ANFRAGEN:-0}"
[ "$ANFRAGEN" -ge 1 ] && ok "der Wegwerf-Richter hat $ANFRAGEN Urteil(e) gesprochen (kein echtes Modell)" \
                      || bad "der Wegwerf-Richter bekam keine Anfrage -- wohin ging das Urteil?"
grep -qx 'ensure' "$LMBETA_PROTOKOLL" 2>/dev/null && grep -qx 'stop' "$LMBETA_PROTOKOLL" 2>/dev/null \
  && ok "lmbeta-server ensure/stop gingen an den Stellvertreter, nicht an den echten Server" \
  || bad "lmbeta-server-Stellvertreter nicht wie erwartet gerufen: $(tr '\n' ' ' < "$LMBETA_PROTOKOLL" 2>/dev/null)"

echo "-- (iii) leerer Lauf tut nichts und scheitert nicht --"
OUT3="$(BRAIN_MAINTAIN_KBASE="$KBASE" "$MAINTAIN" --contradict-only 2>&1)"
RC3=$?
[ "$RC3" -eq 0 ] && ok "zweiter Lauf (leere Warteschlange) exit 0" \
                  || bad "zweiter Lauf schlug fehl, exit $RC3: $OUT3"
printf '%s\n' "$OUT3" | grep -qi "leer" && ok "Ausgabe meldet 'leer' statt eines Scans" \
                                          || bad "Ausgabe erwaehnt 'leer' nicht: $OUT3"

echo
echo "-- (iv) der echte Kbase-Zustand ist unberuehrt geblieben --"
NACHHER="$(store_fingerprint)"
if [ "$VORHER" = "$NACHHER" ]; then
  ok "Embedding-Store von ~/work/brain unveraendert ($VORHER)"
else
  bad "der Lauf hat den ECHTEN Embedding-Store veraendert: $VORHER -> $NACHHER (Vorfall 2026-08-04)"
fi
if [ -f "$KBASE/_meta/tools/gardener/state/gardener.db" ]; then
  ok "der Wegwerf-Kbase hat seinen eigenen Zustand bekommen"
else
  bad "im Wegwerf-Kbase liegt kein eigener Store - der Zustand ist woanders gelandet"
fi
LIVE_LOG_NACHHER="$(live_log_groesse)"
if [ "$LIVE_LOG_VORHER" = "$LIVE_LOG_NACHHER" ]; then
  ok "das Live-Log unter ~/.local/state ist unveraendert ($LIVE_LOG_NACHHER Byte)"
else
  bad "brain-maintain hat ins LIVE-Log geschrieben: $LIVE_LOG_VORHER -> $LIVE_LOG_NACHHER Byte"
fi

echo
echo "contradiction-queue: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
