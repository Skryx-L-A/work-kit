#!/bin/bash
# test-run-all-lock.sh -- proves the concurrency lock in run-all.sh actually
# excludes a second, simultaneous run instead of letting two instances race
# for shared state (tmux socket namespace, wb-consistency against the live
# machine, the socket-pruning step at the end of run-all.sh).
#
# Anlass (04.08., Abnahme des vorigen Auftrags): zwei run-all.sh aus zwei
# verschiedenen Arbeitsbaeumen liefen gleichzeitig und liessen
# test-doctor-betriebs-befunde.sh grundlos rot werden. Diese Suite haelt die
# Reparatur fest -- mit ECHTEN, gleichzeitig gestarteten Prozessen, nicht nur
# durch Lesen des Codes.
#
# TESTHAKEN statt Mocks: run-all.sh unterstuetzt (nur fuer diese Suite)
# RUN_ALL_LOCK_SELFTEST=1 -- damit erwirbt es die echte Sperre ueber die
# echten acquire_run_lock/release_run_lock-Funktionen, haelt sie
# RUN_ALL_LOCK_SELFTEST_HOLD Sekunden und beendet sich, OHNE eine einzige
# Suite zu starten. Ohne diesen Haken muesste jeder Testlauf hier auf einen
# echten, mehrminuetigen run-all.sh-Lauf warten -- dasselbe Prinzip wie
# WB_NO_DISCOVER=1 in test-registry.sh (siehe dessen Kopfkommentar): der
# gepruefte Mechanismus bleibt echt, nur die teure Nutzlast drumherum wird
# uebersprungen.
#
# ISOLATION:
#   * eigenes HOME (mktemp -d) -- die Sperre liegt unter
#     $HOME/.local/state/wb-run-all-tests.lock.d, damit beruehrt kein Lauf
#     hier die echte Sperre auf dieser Maschine.
#   * `unset TMUX TMUX_PANE` vorneweg, wie ueberall in diesem Repo.
#   * KEIN eigener tmux-Socket: die geprueften Codepfade (Sperre erwerben,
#     Meldung schreiben, Sperre freigeben) starten kein tmux, RUN_ALL_LOCK_
#     SELFTEST beendet sich, bevor run-all.sh ueberhaupt eine Suite anfasst.
#     Ein Socket anzulegen, der nie gebraucht wird, waere hier nur Ballast --
#     bewusst weggelassen, nicht vergessen.
#   * `trap` raeumt HOME und Hintergrundprozesse auf, auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ALL="$SCRIPT_DIR/run-all.sh"
[ -f "$RUN_ALL" ] || { echo "FAIL  $RUN_ALL fehlt"; exit 1; }
REPO_ROOT_EXPECTED="$(cd "$SCRIPT_DIR/../.." && pwd)"

TESTHOME="$(mktemp -d)"
BGPID=""
cleanup() {
  [ -n "$BGPID" ] && kill "$BGPID" >/dev/null 2>&1
  [ -n "$BGPID" ] && wait "$BGPID" 2>/dev/null
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

export HOME="$TESTHOME"
export RUN_ALL_LOCK_SELFTEST=1
LOCKDIR="$TESTHOME/.local/state/wb-run-all-tests.lock.d"

echo "== Test 1: zwei echte, gleichzeitige Laeufe -- der zweite weicht sofort und sichtbar zurueck =="
export RUN_ALL_LOCK_SELFTEST_HOLD=3
OUT1="$TESTHOME/out1.log"; OUT2="$TESTHOME/out2.log"

bash "$RUN_ALL" > "$OUT1" 2>&1 &
BGPID=$!

# NICHT raten, wie lange der erste Lauf braucht, um die Sperre zu erwerben --
# darauf POLLEN, dass die Info-Datei wirklich da ist, bevor der zweite Lauf
# ueberhaupt startet.
deadline=$((SECONDS + 5))
while [ ! -s "$LOCKDIR/info" ] && [ $SECONDS -lt $deadline ]; do sleep 0.05; done
if [ -s "$LOCKDIR/info" ]; then
  ok "1: der erste Lauf haelt die Sperre wirklich (Info-Datei existiert und ist nicht leer)"
else
  bad "1: die Sperre wurde nicht rechtzeitig sichtbar -- Testaufbau fehlerhaft"
fi

bash "$RUN_ALL" > "$OUT2" 2>&1
RC2=$?
cat "$OUT2" | sed 's/^/  [zweiter Lauf] /'

[ "$RC2" -eq 2 ] && ok "1: der zweite, gleichzeitige Lauf bricht mit dem eigenen Exit-Code 2 ab (rc=$RC2)" \
                  || bad "1: falscher Exit-Code fuer den zweiten Lauf" "erwartet 2, war $RC2"
grep -q "laeuft bereits" "$OUT2" \
  && ok "1: die Meldung sagt klar, dass schon ein Lauf laeuft" \
  || bad "1: keine Meldung, dass schon ein Lauf laeuft"
grep -q "Halter-PID: $BGPID\$" "$OUT2" \
  && ok "1: die Meldung nennt die richtige Halter-PID ($BGPID)" \
  || bad "1: die Halter-PID fehlt oder ist falsch in der Meldung"
grep -q "laeuft seit:" "$OUT2" \
  && ok "1: die Meldung nennt, seit wann der Halter laeuft" \
  || bad "1: kein 'laeuft seit' in der Meldung"
grep -q "Arbeitsbaum: $REPO_ROOT_EXPECTED\$" "$OUT2" \
  && ok "1: die Meldung nennt den Arbeitsbaum des Halters" \
  || bad "1: der Arbeitsbaum fehlt oder ist falsch in der Meldung"

wait "$BGPID"
RC1=$?
BGPID=""
[ "$RC1" -eq 0 ] && ok "1: der erste Lauf selbst beendet sich sauber (rc=$RC1)" \
                  || bad "1: der erste Lauf schlug unerwartet fehl" "rc=$RC1"
echo

echo "== Test 2: nach dem Ende des ersten Laufs ist die Sperre wieder frei =="
unset RUN_ALL_LOCK_SELFTEST_HOLD
bash "$RUN_ALL" > "$TESTHOME/out3.log" 2>&1
RC3=$?
[ "$RC3" -eq 0 ] && ok "2: ein dritter Lauf NACH dem ersten bekommt die Sperre sofort wieder (rc=$RC3)" \
                  || bad "2: ein Lauf nach dem Ende des vorigen scheitert -- die Sperre haengt" "rc=$RC3"
[ ! -e "$LOCKDIR" ] && ok "2: kein Sperrordner bleibt nach einem sauberen Lauf liegen" \
                      || bad "2: Sperrordner blieb nach einem sauberen Lauf liegen"
echo

echo "== Test 3: eine liegengebliebene Sperre einer TOTEN PID blockiert nicht dauerhaft =="
# Eine wirklich freie PID zur Laufzeit suchen statt eine feste Zahl zu raten --
# HERGESTELLT, nicht angenommen.
DEADPID=99999
while ps -p "$DEADPID" -o pid= >/dev/null 2>&1; do DEADPID=$((DEADPID + 1)); done
mkdir -p "$LOCKDIR"
printf '%s\t%s\t%s\t%s\t%s\n' "$DEADPID" "0" "1970-01-01T00:00:00Z" "/irgendein/alter/baum" "bash" > "$LOCKDIR/info"

start=$(date +%s)
bash "$RUN_ALL" > "$TESTHOME/out4.log" 2>&1
RC4=$?
end=$(date +%s)
elapsed=$((end - start))

[ "$RC4" -eq 0 ] && ok "3: nach einer toten Halter-PID laeuft ein neuer Lauf trotzdem sofort durch (rc=$RC4)" \
                  || bad "3: eine tote Halter-PID blockiert den naechsten Lauf" "rc=$RC4"
[ "$elapsed" -le 5 ] && ok "3: die Uebernahme war sofort (${elapsed}s), kein Warten auf eine Verfallsfrist" \
                       || bad "3: die Uebernahme hat ungewoehnlich lange gedauert" "${elapsed}s"
grep -q "Uebernehme liegengebliebene run-all.sh-Sperre" "$TESTHOME/out4.log" \
  && ok "3: die Uebernahme wird sichtbar gemeldet, nicht stillschweigend" \
  || bad "3: keine sichtbare Meldung ueber die Uebernahme"
echo

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
