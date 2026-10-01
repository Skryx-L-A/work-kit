#!/usr/bin/env bash
# test-run-all-nurlast-rot.sh -- eine Suite, die nur unter Last rot ist, faerbt
# den Gesamtlauf rot.
#
# ANLASS (Auflage des Nutzers vom 2026-09-20, ueber ai-78 am 21.09. entschieden):
# ein Gesamtlauf hat kein einziges Rot und keinen uebersprungenen Punkt. Bis
# dahin zaehlte ausgerechnet der haeufigste Fall nicht mit: eine Suite, die im
# Pool rot ist und einzeln gruen, nahm der Bestaetigungslauf aus FAIL_COUNT
# heraus und legte sie nach NURLAST_COUNT. Der Lauf endete dann mit 0, obwohl
# die Tabelle darueber ausdruecklich "erledigt ist das NICHT" schrieb. So
# rutschte ein bekannter Wackler ueber Wochen als gruen durch.
#
# Gemessen wird an einem EIGENEN kleinen Baum mit erfundenen Suiten, nicht am
# echten: dieser Test darf den laufenden Bestand nicht anfassen und braucht
# einen Fall, der zuverlaessig "im Pool rot, einzeln gruen" ist. Die Attrappe
# stellt das ueber eine Merkdatei her -- der erste Lauf scheitert, der zweite
# (der Bestaetigungslauf) gelingt.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nurlast.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/nurlast.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

# Ein Miniatur-Baum mit STELLVERTRETERN statt Luecken: jede Stelle, an der
# run-all.sh etwas sucht, bekommt hier etwas zu finden.
# hooks/tests MUSS es geben, wenn auch leer: fehlt der Ordner im Baum, faellt
# run-all.sh auf die INSTALLIERTEN Hook-Suiten unter ~/.claude zurueck. Der
# erste Entwurf lief deshalb 28 fremde Suiten mit, und die Gegenprobe war rot
# wegen einer davon -- gemessen, nicht vermutet.
# shell/wb-consistency braucht ebenfalls einen Stellvertreter, seit ein Skip als
# rot zaehlt (daad585a): ohne die Datei meldet der Lauf einen uebersprungenen
# Punkt, und die Gegenprobe "sauberer Lauf endet mit 0" waere rot, ohne dass
# irgendetwas an der gemessenen Sache falsch waere.
mkdir -p "$TMP/shell/tests" "$TMP/hooks/tests"
cp "$REPO/run-all.sh" "$REPO/lib-parallel-sicher.sh" "$TMP/shell/tests/"
# PYTHON, nicht sh: run-all.sh startet wb-consistency ausdruecklich mit python3
# (`run_suite "$WB_CONSISTENCY" "shell" python3 --repo …`). Ein sh-Stellvertreter
# lief deshalb in einen Syntaxfehler und faerbte die Gegenprobe rot -- gemessen.
printf '#!/usr/bin/env python3\nimport sys\nprint("Stellvertreter: nichts zu pruefen", sys.argv[1:])\n' > "$TMP/shell/wb-consistency"
chmod +x "$TMP/shell/wb-consistency"
RUNALL="$TMP/shell/tests/run-all.sh"

# EIGENES HOME fuer jeden Lauf (Befund von Agents-plans Worker, 2026-09-21).
# Ohne das liegt die Laufsperre von run-all.sh fest unter
# $HOME/.local/state/wb-run-all-tests.lock.d: innerhalb eines Gesamtlaufs bricht
# der innere Lauf mit "run-all.sh laeuft bereits" ab, und schlimmer -- die
# LEBENDEN Statusdateien (…ergebnis.tsv, …timings.tsv) wurden bei jedem Lauf
# dieses Tests ueberschrieben, sodass dort ein Drei-Zeilen-Lauf stand statt der
# letzten vollen Inventur. Dieselbe Fehlerklasse wie der Socket-Vorfall vom
# 04.08.: ein Test, der in die lebende Umgebung schreibt.
mkdir -p "$TMP/home"
laufe() {   # laufe <argumente...> -> Ausgabe auf stdout, Rueckgabewert wie run-all
  env HOME="$TMP/home" TMUX_TMPDIR="$TMP/home" "$RUNALL" "$@" 2>&1
}

# Die wackelige Attrappe: beim ERSTEN Lauf rot, danach gruen.
cat > "$TMP/shell/tests/test-wackelt.sh" <<EOF
#!/usr/bin/env bash
# Attrappe fuer den Fall "im Pool rot, einzeln gruen".
if [ -e "$TMP/schon-gelaufen" ]; then
  echo "zweiter Lauf: gruen"
  exit 0
fi
: > "$TMP/schon-gelaufen"
echo "erster Lauf: rot"
exit 1
EOF
cat > "$TMP/shell/tests/test-immer-gruen.sh" <<'EOF'
#!/usr/bin/env bash
echo "gruen"
exit 0
EOF
chmod +x "$TMP/shell/tests/"*.sh

echo "== test-run-all-nurlast-rot: 'nur unter Last rot' ist rot =="
echo "   Baum: $TMP"
echo

AUS="$(laufe --shell-only --jobs 2)"; RC=$?
if printf '%s' "$AUS" | grep -q "NUR-UNTER-LAST: 1"; then
  ok "A1: der Lauf hat den Fall wirklich hergestellt (eine Suite nur unter Last rot)"
else
  bad "A1: der Fall wurde nicht hergestellt — der Test misst sonst nichts" "$(printf '%s' "$AUS" | grep -E '^PASS:' | head -1)"
fi
if [ "$RC" -ne 0 ]; then
  ok "A2: der Gesamtlauf endet rot (rc=$RC)"
else
  bad "A2: der Gesamtlauf endete mit 0, obwohl eine Suite nur unter Last rot war"
fi

echo
echo "-- Gegenprobe: ohne Wackler bleibt der Lauf gruen --"
rm -f "$TMP/shell/tests/test-wackelt.sh" "$TMP/schon-gelaufen"
AUS2="$(laufe --shell-only --jobs 2)"; RC2=$?
if [ "$RC2" -eq 0 ]; then
  ok "B1: ein Lauf ohne Wackler endet weiterhin mit 0"
else
  bad "B1: ein sauberer Lauf endet rot (rc=$RC2) — die Verschaerfung greift zu weit" "$(printf '%s' "$AUS2" | grep -E '^PASS:|FAIL' | head -3)"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
