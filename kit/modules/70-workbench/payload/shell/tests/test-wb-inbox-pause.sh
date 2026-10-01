#!/usr/bin/env bash
# test-wb-inbox-pause.sh -- der Pausenschalter fuer Agent-Verkehr in wb-inbox
# (Bau-Schritt 3 des Agents-Features, Auftrag traeger3, docs/AGENTS-PLAN.md
# Abschnitt 4 "Kommunikation zwischen Agenten", Anhang "Bremsen").
#
# Prueft: `wb-inbox pause an|aus|status` legt/liest die Merkerdatei unter
# <vorrat>/.agentverkehr-pause (Zeit+Grund, 0600), dieselbe Datei, die
# `wb-traeger status` anzeigt; `sende` lehnt bei gesetztem Schalter nur die
# Absender-Klassen 'hauptagent' (Vorgabe) und 'companion-agent' ab (Exit 4,
# "zurückgehalten", nichts gesendet). 'traeger' und 'mensch' benötigen eine
# messbare Herkunft; ein frei gewähltes Argument hebt die Klasse nicht an.
#
# ISOLATION: eigenes HOME (TESTHOME), Vorrat unter einem eigenen BASIS
# ausserhalb davon (WB_VORRAT bzw. --base je nach Abschnitt). Kein tmux, kein
# Netz -- `sende` scheitert bei den Durchlass-Faellen an der fehlenden
# Sitzung, nicht am Schalter; genau das beweist, dass der Schalter nicht im
# Weg steht.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-inbox-pause-test.XXXXXX")"
BASIS="$(mktemp -d "${TMPDIR:-/tmp}/wb-inbox-pause-basis.XXXXXX")"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

cleanup() {
  for d in "$TESTHOME" "$BASIS"; do
    case "$d" in
      /tmp/wb-inbox-pause-*|/private/tmp/wb-inbox-pause-*|/var/folders/*/wb-inbox-pause-*) rm -rf "$d" ;;
      *) echo "WARNUNG: '$d' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
    esac
  done
}
trap cleanup EXIT INT TERM

echo "== wb-inbox pause (HOME $TESTHOME, Basis $BASIS) =="
[ -x "$REPO/wb-inbox" ] || { echo "UEBERSPRUNGEN: shell/wb-inbox fehlt"; exit 77; }

# wb-mensch als Schirm (Vorgabe: Agent), damit das Ergebnis nicht davon abhaengt, ob ein
# Mensch am Terminal oder ein Agent die Suite startet; WB_TMUX_SOCKET nennt einen Server, den
# es nicht gibt, damit die Sitzungssuche nie den umgebenden tmux-Server fragt.
mkdir -p "$TESTHOME/bin" "$TESTHOME/.local/bin"
printf '#!/bin/sh\n[ "${1:-}" = pruefen ] || exit 2\nexit "$(cat "$HOME/mensch.rc" 2>/dev/null || echo 1)"\n' > "$TESTHOME/.local/bin/wb-mensch"
chmod +x "$TESTHOME/.local/bin/wb-mensch"
TSOCK="wbtest-inbox-pause-$$"
inbox() { HOME="$TESTHOME" PATH="$TESTHOME/bin:$PATH" WB_TMUX_SOCKET="$TSOCK" python3 "$REPO/wb-inbox" "$@"; }
mensch() { printf '%s\n' "$1" > "$TESTHOME/mensch.rc"; }
VORRAT="$BASIS/.claude/workbench/vorrat"
MERKER="$VORRAT/.agentverkehr-pause"

# ==========================================================================
echo; echo "-- A: status ohne Schalter --"
AUS="$(inbox pause status --base "$BASIS" --json)"
echo "$AUS" | grep -q '"aktiv": false' && ok "A: --json meldet aktiv:false ohne Merkerdatei" || bad "A: JSON" "$AUS"
AUS="$(inbox pause status --base "$BASIS")"
[ "$AUS" = "Agent-Verkehr: offen" ] && ok "A: Klartext 'Agent-Verkehr: offen'" || bad "A: Klartext" "$AUS"
[ ! -e "$MERKER" ] && ok "A: status allein legt keine Merkerdatei an" || bad "A: Merkerdatei existiert schon"

# ==========================================================================
echo; echo "-- B: an legt die Merkerdatei mit Grund und Zeit an --"
inbox pause an --base "$BASIS" --grund "Wartungsfenster" >/dev/null
[ -f "$MERKER" ] && ok "B: Merkerdatei angelegt" || bad "B: Merkerdatei fehlt"
RECHTE="$(stat -f '%Lp' "$MERKER" 2>/dev/null || stat -c '%a' "$MERKER" 2>/dev/null)"
[ "$RECHTE" = "600" ] && ok "B: Merkerdatei ist 0600" || bad "B: Rechte" "$RECHTE"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("grund")=="Wartungsfenster" and d.get("seit") else 1)' "$MERKER" \
  && ok "B: Inhalt traegt Grund und Zeit" || bad "B: Inhalt" "$(cat "$MERKER")"
AUS="$(inbox pause status --base "$BASIS")"
echo "$AUS" | grep -q "pausiert" && echo "$AUS" | grep -q "Wartungsfenster" \
  && ok "B: Klartext zeigt 'pausiert ... (Wartungsfenster)'" || bad "B: Klartext" "$AUS"
AUS="$(inbox pause status --base "$BASIS" --json)"
echo "$AUS" | grep -q '"aktiv": true' && ok "B: --json meldet aktiv:true" || bad "B: JSON" "$AUS"

# ==========================================================================
echo; echo "-- C: sende lehnt hauptagent (Vorgabe) bei gesetztem Schalter ab --"
set +e
WB_VORRAT="$VORRAT" inbox sende %kein-pane /dev/null >/tmp/wb-inbox-pause-c.out 2>&1
RC=$?
set -e
[ "$RC" = 4 ] && ok "C: Exit 4 bei Absender hauptagent (Vorgabe)" || bad "C: Exit" "rc=$RC / $(cat /tmp/wb-inbox-pause-c.out)"
grep -q "zurückgehalten" /tmp/wb-inbox-pause-c.out && ok "C: Meldung 'zurückgehalten'" || bad "C: Meldung" "$(cat /tmp/wb-inbox-pause-c.out)"
grep -qi "keine lebende Claude-Sitzung" /tmp/wb-inbox-pause-c.out && bad "C: hat trotzdem nach der Sitzung gesucht" \
  || ok "C: die Suche nach der Sitzung wurde gar nicht erst versucht"
rm -f /tmp/wb-inbox-pause-c.out

echo; echo "-- C2: sende lehnt auch companion-agent ab --"
set +e
WB_VORRAT="$VORRAT" inbox --absender companion-agent sende %kein-pane /dev/null >/tmp/wb-inbox-pause-c2.out 2>&1
RC=$?
set -e
[ "$RC" = 4 ] && ok "C2: Exit 4 bei Absender companion-agent" || bad "C2: Exit" "rc=$RC"
rm -f /tmp/wb-inbox-pause-c2.out

# ==========================================================================
echo; echo "-- D: behauptete Herkunft ohne Beleg wird bei gesetztem Schalter zurückgehalten --"
AUSD="$TESTHOME/d.out"
durch() { [ "$1" != 4 ] && grep -q "keine lebende Claude-Sitzung" "$AUSD"; }
set +e
WB_VORRAT="$VORRAT" inbox --absender traeger sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
[ "$RC" = 4 ] && ok "D: behaupteter traeger ohne Träger in der Elternkette wird zurückgehalten" || bad "D: Exit" "rc=$RC / $(cat "$AUSD")"
set +e
WB_VORRAT="$VORRAT" inbox --absender mensch sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
[ "$RC" = 4 ] && ok "D2: behaupteter mensch, den wb-mensch pruefen verneint, wird zurückgehalten" || bad "D2: Exit" "rc=$RC / $(cat "$AUSD")"

echo; echo "-- D3: ein gemessener Mensch geht durch, das Argument setzt nur herab --"
mensch 0
set +e
WB_VORRAT="$VORRAT" inbox sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
durch "$RC" && ok "D3: ohne --absender leitet sende 'mensch' aus wb-mensch pruefen ab und kommt bis zur Sitzungssuche" \
  || bad "D3: Mensch" "rc=$RC / $(cat "$AUSD")"
set +e
WB_VORRAT="$VORRAT" inbox --absender hauptagent sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
[ "$RC" = 4 ] && ok "D3: --absender hauptagent setzt auch einen Menschen herab" || bad "D3: Herabsetzen" "rc=$RC / $(cat "$AUSD")"
mensch 1

echo; echo "-- D4: nur der laufende Träger in der Elternkette gilt als traeger --"
# Schirm-Träger: registriert sich wie der echte in .traeger.pid und ruft wb-inbox als KIND
# (kein exec, sonst waere er selbst wb-inbox und nicht dessen Elternprozess).
cat > "$TESTHOME/bin/wb-traeger" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" > "$WB_VORRAT/.traeger.pid"
python3 "$WB_INBOX" --absender traeger sende %kein-pane /dev/null
rc=$?
exit $rc
EOF
chmod +x "$TESTHOME/bin/wb-traeger"
set +e
HOME="$TESTHOME" PATH="$TESTHOME/bin:$PATH" WB_TMUX_SOCKET="$TSOCK" WB_VORRAT="$VORRAT" WB_INBOX="$REPO/wb-inbox" \
  "$TESTHOME/bin/wb-traeger" >"$AUSD" 2>&1; RC=$?
set -e
durch "$RC" && ok "D4: der registrierte Träger als Elternprozess kommt am Schalter vorbei bis zur Sitzungssuche" \
  || bad "D4: Träger-Herkunft" "rc=$RC / $(cat "$AUSD")"
printf '%s\n' "$$" > "$VORRAT/.traeger.pid"
set +e
WB_VORRAT="$VORRAT" inbox --absender traeger sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
[ "$RC" = 4 ] && ok "D4: eine PID-Datei, deren Nummer einem Ahnen gehört, der kein Träger ist, gilt nicht" \
  || bad "D4: veraltete PID" "rc=$RC / $(cat "$AUSD")"
sleep 30 & FREMD=$!
printf '%s\n' "$FREMD" > "$VORRAT/.traeger.pid"
set +e
WB_VORRAT="$VORRAT" inbox --absender traeger sende %kein-pane /dev/null >"$AUSD" 2>&1; RC=$?
set -e
kill "$FREMD" 2>/dev/null; wait "$FREMD" 2>/dev/null || true
[ "$RC" = 4 ] && ok "D4: ein lebender Prozess außerhalb der Elternkette gilt nicht als Träger" \
  || bad "D4: fremde PID" "rc=$RC / $(cat "$AUSD")"
rm -f "$AUSD" "$VORRAT/.traeger.pid"

# ==========================================================================
echo; echo "-- E: aus entfernt die Merkerdatei --"
inbox pause aus --base "$BASIS" >/dev/null
[ ! -e "$MERKER" ] && ok "E: Merkerdatei entfernt" || bad "E: Merkerdatei besteht noch"
AUS="$(inbox pause status --base "$BASIS")"
[ "$AUS" = "Agent-Verkehr: offen" ] && ok "E: Status wieder 'offen'" || bad "E: Status" "$AUS"
set +e
WB_VORRAT="$VORRAT" inbox sende %kein-pane /dev/null >/tmp/wb-inbox-pause-e.out 2>&1
RC=$?
set -e
[ "$RC" != 4 ] && ok "E: hauptagent geht nach 'aus' wieder durch" || bad "E: weiterhin zurueckgehalten"
rm -f /tmp/wb-inbox-pause-e.out
inbox pause aus --base "$BASIS" >/dev/null && ok "E: 'aus' ist idempotent (kein Fehler ohne Merkerdatei)" || bad "E: 'aus' ohne Merkerdatei scheitert"

# ==========================================================================
echo; echo "-- F: WB_VORRAT hat Vorrang vor --base --"
ANDERSWO="$BASIS/anderswo"
mkdir -p "$ANDERSWO/.claude/workbench/vorrat"
WB_VORRAT="$ANDERSWO/.claude/workbench/vorrat" inbox pause an --base "$BASIS" --grund "Testvorrang" >/dev/null
[ -f "$ANDERSWO/.claude/workbench/vorrat/.agentverkehr-pause" ] && ok "F: WB_VORRAT bestimmt den Ort, nicht --base" \
  || bad "F: Merkerdatei landete nicht unter WB_VORRAT"
[ ! -f "$VORRAT/.agentverkehr-pause" ] && ok "F: unter --base allein entstand keine Datei" || bad "F: Datei auch unter --base"
WB_VORRAT="$ANDERSWO/.claude/workbench/vorrat" inbox pause aus --base "$BASIS" >/dev/null

# ==========================================================================
echo; echo "-- G: falsche/unbekannte --absender-Werte werden abgelehnt --"
set +e
inbox --absender was-auch-immer sende %x /dev/null >/tmp/wb-inbox-pause-g.out 2>&1
RC=$?
set -e
[ "$RC" = 2 ] && ok "G: unbekannte Absender-Klasse -> Exit 2" || bad "G: Exit" "rc=$RC"
rm -f /tmp/wb-inbox-pause-g.out

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
