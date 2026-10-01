#!/usr/bin/env bash
# test-run-all-skip-zaehlt.sh -- ein uebersprungener Punkt ist ein Fehlschlag,
# ausser seine Voraussetzung gehoert einer anderen Maschine.
#
# ANLASS (der Nutzer, 2026-09-20: "kein einziger darf rot sein oder geskippt";
# Entscheidung ai-78 vom 21.09.): bis dahin zaehlte ein SKIP in run-all.sh gar
# nicht. Eine Suite, der ein Werkzeug fehlte, ein Paket, das niemand gebaut
# hatte, ein Modell, das niemand geladen hatte -- alles endete mit Exit 0 und
# der Meldung "FAIL: 0". Genau dafuer gibt es Tests nicht.
#
# Zulaessig bleibt der eine Fall, den diese Maschine nicht herstellen KANN:
# eine Suite, deren Voraussetzung auf einer anderen liegt (Linux/host2, KDE,
# fremde Hardware, eine Gegenstelle im Netz). Sie sagt das mit dem Kennzeichen
#     UEBERSPRUNGEN: nicht auf dieser Maschine: <Grund>
# und steht in der Schlusszeile als eigene Kategorie.
#
# GEMESSEN WIRD AN EINEM EIGENEN MINIATUR-BAUM, nie am echten Bestand: der Fall
# "Suite ueberspringt sich" laesst sich dort herstellen, ohne eine echte Suite
# zu verbiegen. HOME zeigt dabei in das Wegwerfverzeichnis -- run-all.sh legt
# seine Laufsperre, seine Zeitdatei und sein Ergebnisprotokoll unter
# $HOME/.local/state ab, und ein Test, der das nicht umlenkt, nimmt einem
# echten Lauf die Sperre weg und ueberschreibt sein Protokoll.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/skipzaehlt.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/skipzaehlt.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup INT TERM EXIT

mkdir -p "$TMP/shell/tests" "$TMP/hooks/tests" "$TMP/home"
cp "$REPO/run-all.sh" "$REPO/lib-parallel-sicher.sh" "$TMP/shell/tests/"
RUNALL="$TMP/shell/tests/run-all.sh"

# Eigenes HOME, eigenes tmux-Verzeichnis: die Sperre, das Ergebnisprotokoll und
# das Aufraeumen toter Testsockets bleiben damit in diesem Baum.
lauf() { env HOME="$TMP/home" TMUX_TMPDIR="$TMP/home" "$RUNALL" --shell-only "$@" 2>&1; }

stub() {   # $1 = Dateiname, danach der Rumpf auf stdin
  cat > "$TMP/shell/tests/$1"
  chmod +x "$TMP/shell/tests/$1"
}

# --- Die vier Faelle ---------------------------------------------------------
# 1: maschinenfremd, im Parallel-Pool (keine $HOME-Erwaehnung -> parallelsicher).
stub test-fremd-pool.sh <<'EOF'
#!/usr/bin/env bash
echo "UEBERSPRUNGEN: nicht auf dieser Maschine: braucht eine KDE-Sitzung auf host2"
exit 77
EOF
# 2: maschinenfremd, aber sequenziell -- die Erwaehnung von $HOME ohne eigene
#    Umlenkung nimmt der Suite die Parallelsicherheit (lib-parallel-sicher.sh),
#    und damit laeuft sie durch run_suite statt durch run_suite_bg. Beide Wege
#    muessen dasselbe Urteil faellen.
stub test-fremd-seriell.sh <<'EOF'
#!/usr/bin/env bash
# liest $HOME und laeuft deshalb nicht im Pool
echo "UEBERSPRUNGEN: nicht auf dieser Maschine: fremde Hardware (Tastenblock am host2)"
exit 77
EOF
# 3: der alte, unveraenderte Klassiker OHNE Kennzeichen -- muss zaehlen.
stub test-zaehlt-klassisch.sh <<'EOF'
#!/usr/bin/env bash
echo "UEBERSPRUNGEN: brain fehlt"
exit 77
EOF
# 4: ein FALSCH gesetztes Kennzeichen (Kleinschreibung) darf nicht durchgehen.
stub test-zaehlt-falsches-kennzeichen.sh <<'EOF'
#!/usr/bin/env bash
echo "UEBERSPRUNGEN: nicht auf dieser maschine: absichtlich falsch geschrieben"
exit 77
EOF
stub test-immer-gruen.sh <<'EOF'
#!/usr/bin/env bash
echo "gruen"
exit 0
EOF

echo "== test-run-all-skip-zaehlt: SKIP zaehlt, ausser 'nicht auf dieser Maschine' =="
echo "   Baum: $TMP"
echo

AUS="$(lauf --jobs 2)"; RC=$?
SUMME="$(printf '%s\n' "$AUS" | grep -E '^PASS: ' | tail -1)"

[ "$RC" -ne 0 ] \
  && ok "A1: der Lauf endet rot, weil zwei Punkte uebersprungen wurden (rc=$RC)" \
  || bad "A1: der Lauf endete mit 0, obwohl zwei Punkte uebersprungen wurden" "$SUMME"

case "$SUMME" in
  *"SKIP: 2"*) ok "A2: beide Skips ohne gueltiges Kennzeichen zaehlen (SKIP: 2)" ;;
  *) bad "A2: erwartet 'SKIP: 2'" "$SUMME" ;;
esac

case "$SUMME" in
  *"nicht auf dieser Maschine: 2"*) ok "A3: die maschinenfremden stehen als eigene Kategorie (2)" ;;
  *) bad "A3: erwartet 'nicht auf dieser Maschine: 2'" "$SUMME" ;;
esac

# Der Anker, den shell/wb-testsuite-run liest -- er steht dort als fester
# Ausdruck im Quelltext, und eine Zeile, die ihn verfehlt, laesst die
# Statusdatei der Werkbank ohne Zahlen zurueck ("parse_ok=0").
if printf '%s\n' "$SUMME" | grep -qE '^PASS: [0-9]+  FAIL: [0-9]+  SKIP: [0-9]+'; then
  ok "A4: die Schlusszeile passt weiter auf das Muster von wb-testsuite-run"
else
  bad "A4: wb-testsuite-run findet in dieser Zeile keine Zahlen mehr" "$SUMME"
fi

# Beide Wege durch den Laeufer, Pool und sequenziell, urteilen gleich.
if printf '%s\n' "$AUS" | grep -q 'test-fremd-pool.sh *FREMD' \
   && printf '%s\n' "$AUS" | grep -q 'test-fremd-seriell.sh *FREMD'; then
  ok "A5: Pool-Weg und sequenzieller Weg kennzeichnen beide als FREMD"
else
  bad "A5: einer der beiden Wege hat das Kennzeichen nicht gelesen" \
      "$(printf '%s\n' "$AUS" | grep -E 'test-fremd-(pool|seriell)' | tail -2)"
fi

if printf '%s\n' "$AUS" | grep -q 'test-zaehlt-falsches-kennzeichen.sh *SKIP'; then
  ok "A6: ein falsch geschriebenes Kennzeichen zaehlt (fail-closed)"
else
  bad "A6: das falsch geschriebene Kennzeichen wurde als maschinenfremd durchgelassen" \
      "$(printf '%s\n' "$AUS" | grep 'falsches-kennzeichen' | tail -1)"
fi

if printf '%s\n' "$AUS" | grep -q 'zaehlen:' \
   && printf '%s\n' "$AUS" | grep -q 'test-zaehlt-klassisch.sh  UEBERSPRUNGEN: brain fehlt'; then
  ok "A7: die zaehlenden Skips stehen mit Grund in der Klartextliste"
else
  bad "A7: die Klartextliste nennt den zaehlenden Skip nicht" \
      "$(printf '%s\n' "$AUS" | grep -A4 'zaehlen:' | tail -4)"
fi

echo
echo "-- Gegenprobe: nur noch maschinenfremde Skips, der Lauf bleibt gruen --"
rm -f "$TMP/shell/tests/test-zaehlt-klassisch.sh" "$TMP/shell/tests/test-zaehlt-falsches-kennzeichen.sh"
AUS2="$(lauf --jobs 2)"; RC2=$?
SUMME2="$(printf '%s\n' "$AUS2" | grep -E '^PASS: ' | tail -1)"
[ "$RC2" -eq 0 ] \
  && ok "B1: ein Lauf mit nur maschinenfremden Skips endet mit 0" \
  || bad "B1: der Lauf ist rot (rc=$RC2) -- die Ausnahme greift nicht" "$SUMME2"
case "$SUMME2" in
  *"SKIP: 0"*"nicht auf dieser Maschine: 2"*) ok "B2: die Zahlen stimmen (SKIP: 0, fremd: 2)" ;;
  *) bad "B2: erwartet 'SKIP: 0 ... nicht auf dieser Maschine: 2'" "$SUMME2" ;;
esac

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
