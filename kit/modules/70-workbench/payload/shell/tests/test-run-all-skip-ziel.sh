#!/usr/bin/env bash
# test-run-all-skip-ziel.sh -- Suiten, die ein GELADENES lokales Modell
# brauchen, haben ein eigenes Ziel, und der Laeufer sagt in jedem Lauf, ob es
# gelaufen ist.
#
# ANLASS (Entscheidung ai-78, 2026-09-21): ein lokales Modell ist auf dem Mac
# nicht maschinenfremd -- es laesst sich laden. Deshalb darf so eine Suite
# nicht unter "nicht auf dieser Maschine" verschwinden. Sie darf aber auch
# nicht jeden Alltagslauf rot faerben: das Laden kostet Speicher, den ein
# Testlauf sich nicht selbst nehmen darf (die Maschine stand deswegen am
# 21.08. und am 29.08.), und es gehoert mit `wb-belegung` und der laufenden
# Werkbank-Sitzung abgestimmt. Der Ausweg ist ein eigenes Ziel:
#     shell/tests/run-all.sh --ziel lokal-modell
# Damit daraus keine stille Luecke wird, nennt JEDER Lauf den Stand des Ziels,
# und ein Baum, der die Pfade der lokalen Modelle aendert, bekommt es laut
# gesagt.
#
# Gemessen an einem eigenen Miniatur-Baum mit eigenem HOME (siehe
# test-run-all-skip-zaehlt.sh): kein echtes Modell, kein echter Bestand, keine
# fremde Laufsperre.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/skipziel.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/skipziel.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup INT TERM EXIT

mkdir -p "$TMP/shell/tests" "$TMP/hooks/tests" "$TMP/home"
cp "$REPO/run-all.sh" "$REPO/lib-parallel-sicher.sh" "$TMP/shell/tests/"
RUNALL="$TMP/shell/tests/run-all.sh"
lauf() { env HOME="$TMP/home" TMUX_TMPDIR="$TMP/home" "$RUNALL" --shell-only "$@" 2>&1; }

# Die Attrappe traegt den Namen, den run-all.sh als Modell-Suite kennt
# (`ist_lokal_modell_suite`). Sie startet nichts: der Laeufer entscheidet VOR
# dem Start, ob sie zu diesem Ziel gehoert -- und genau das wird hier gemessen.
cat > "$TMP/shell/tests/test-contradiction-queue.sh" <<'EOF'
#!/usr/bin/env bash
echo "MODELLSUITE-LIEF"
exit 0
EOF
cat > "$TMP/shell/tests/test-gewoehnlich.sh" <<'EOF'
#!/usr/bin/env bash
echo "GEWOEHNLICH-LIEF"
exit 0
EOF
chmod +x "$TMP/shell/tests/test-contradiction-queue.sh" "$TMP/shell/tests/test-gewoehnlich.sh"

echo "== test-run-all-skip-ziel: das Ziel 'lokal-modell' =="
echo "   Baum: $TMP"
echo

AUS="$(lauf --jobs 2)"; RC=$?
ZEILE="$(printf '%s\n' "$AUS" | grep -E '^ZIEL lokal-modell:' | tail -1)"

case "$ZEILE" in
  "ZIEL lokal-modell: nein (1 Suite(n) nicht gelaufen"*) ok "A1: der Standardlauf sagt, dass das Ziel NICHT lief" ;;
  *) bad "A1: erwartet 'ZIEL lokal-modell: nein (1 Suite(n) ...'" "${ZEILE:-<keine Zeile>}" ;;
esac

if printf '%s\n' "$AUS" | grep -q "MODELLSUITE-LIEF"; then
  bad "A2: die Modell-Suite lief im Standardlauf mit"
else
  ok "A2: die Modell-Suite lief im Standardlauf nicht mit"
fi

if printf '%s\n' "$AUS" | grep -q "GEWOEHNLICH-LIEF"; then
  ok "A3: die gewoehnliche Suite lief"
else
  bad "A3: die gewoehnliche Suite lief nicht" "$(printf '%s\n' "$AUS" | grep -E '^PASS: ')"
fi

[ "$RC" -eq 0 ] \
  && ok "A4: der Standardlauf bleibt gruen, obwohl die Modell-Suite fehlt" \
  || bad "A4: der Standardlauf ist rot (rc=$RC)" "$(printf '%s\n' "$AUS" | grep -E '^PASS: ')"

# Die Vollstaendigkeitszeile darf nicht behaupten, alles sei gelaufen.
VOLL="$(printf '%s\n' "$AUS" | grep -E '^VOLLSTAENDIG:' | tail -1)"
case "$VOLL" in
  "VOLLSTAENDIG: ja"*"eigenes Ziel"*) ok "A5: die Vollstaendigkeitszeile nennt die Modell-Suite gesondert" ;;
  *) bad "A5: die Vollstaendigkeitszeile verschweigt das eigene Ziel" "${VOLL:-<keine Zeile>}" ;;
esac

echo
echo "-- Das Ziel selbst faehrt nur seine Suiten --"
AUS2="$(lauf --jobs 2 --ziel lokal-modell)"
ZEILE2="$(printf '%s\n' "$AUS2" | grep -E '^ZIEL lokal-modell:' | tail -1)"
case "$ZEILE2" in
  "ZIEL lokal-modell: ja"*) ok "B1: der Ziellauf sagt, dass das Ziel lief" ;;
  *) bad "B1: erwartet 'ZIEL lokal-modell: ja ...'" "${ZEILE2:-<keine Zeile>}" ;;
esac
# Zwei zulaessige Ausgaenge, je nachdem ob auf dieser Maschine gerade ein
# Modell laeuft: entweder die Suite laeuft (Modell da), oder run-all.sh
# ueberspringt sie VOR dem Start mit seinem eigenen Grund -- und dieser Skip
# zaehlt dann, faerbt den Ziellauf also rot. Genau so soll es sein: wer das
# Ziel faehrt, faehrt es mit geladenem Modell. Was NICHT passieren darf, ist
# dass die Suite im Ziellauf gar nicht erst ausgewaehlt wird.
if printf '%s\n' "$AUS2" | grep -q "MODELLSUITE-LIEF"; then
  ok "B2: die Modell-Suite lief im Ziellauf"
elif printf '%s\n' "$AUS2" | grep -qE 'test-contradiction-queue\.sh +SKIP'; then
  ok "B2: die Modell-Suite war ausgewaehlt und zaehlt als uebersprungen (kein Modell geladen)"
else
  bad "B2: die Modell-Suite war im Ziellauf gar nicht dabei" "$(printf '%s\n' "$AUS2" | grep -E '^PASS: ')"
fi
if printf '%s\n' "$AUS2" | grep -q "GEWOEHNLICH-LIEF"; then
  bad "B3: der Ziellauf hat auch die gewoehnliche Suite gefahren"
else
  ok "B3: der Ziellauf laesst die gewoehnlichen Suiten aus"
fi
if printf '%s\n' "$AUS2" | grep -q '^VOLLSTAENDIG: nein'; then
  ok "B4: ein Ziellauf ist ausdruecklich kein vollstaendiger Lauf"
else
  bad "B4: der Ziellauf gibt sich als vollstaendiger Lauf aus" \
      "$(printf '%s\n' "$AUS2" | grep -E '^VOLLSTAENDIG:')"
fi

echo
echo "-- Ein Baum, der die Modellpfade aendert, bekommt es laut gesagt --"
# Ein eigenes git-Repo im Wegwerfbaum: run-all.sh fragt git nach den
# geaenderten Dateien. Ein erster Commit mit EINER Datei unter shell/ reicht --
# ohne ihn fasst `git status` den ganzen unbekannten Ordner zu einer einzigen
# Zeile zusammen ("?? shell/"), statt die einzelne Datei zu nennen.
GITTEST=(git -C "$TMP" -c user.name=Test -c user.email=test@example.invalid)
"${GITTEST[@]}" init -q >/dev/null 2>&1
"${GITTEST[@]}" add shell/tests/run-all.sh >/dev/null 2>&1
"${GITTEST[@]}" commit -qm "erster Stand" >/dev/null 2>&1
printf '#!/usr/bin/env bash\n: geaendert\n' > "$TMP/shell/wb-mlx-server"
AUS3="$(lauf --jobs 2)"
if printf '%s\n' "$AUS3" | grep -q 'ZIEL lokal-modell IST NOETIG' \
   && printf '%s\n' "$AUS3" | grep -q 'shell/wb-mlx-server'; then
  ok "C1: der Laeufer nennt den geaenderten Modellpfad und verlangt das Ziel"
else
  bad "C1: die Warnung fehlt, obwohl shell/wb-mlx-server geaendert ist" \
      "$(printf '%s\n' "$AUS3" | grep -E '^ZIEL|NOETIG' | tail -2)"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
