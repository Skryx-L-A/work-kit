#!/bin/bash
# test-run-all-drosselung.sh -- die Parallelitaet von run-all.sh darf die Maschine
# nicht mehr zum Stehen bringen.
#
# Anlass (2026-08-29): ein voller Testlauf startete neben dem geladenen
# lmgamma-27B (rund 16 GiB) samt Entwerfer und einem Worker mit 262k Kontext.
# Vier Minuten spaeter erzwang der Watchdog einen harten Neustart --
# "watchdog timeout: no checkins from watchdogd in 91 seconds". Am 21.08. war
# dasselbe schon einmal passiert, damals neben einem 28-GiB-Modellserver.
#
# Eine Regel dagegen war beide Male notiert und wurde beide Male nicht befolgt.
# Deshalb rechnet run-all.sh die Zahl jetzt selbst aus, und dieser Test misst
# diese Rechnung -- besonders die Gegenrichtung: eine Drosselung, die IMMER
# greift, waere genauso falsch, weil sie jeden gesunden Lauf ausbremst.
#
# Gemessen wird ueber '--zeige-jobs': das nennt die ermittelte Zahl und endet,
# bevor die Laufsperre gesetzt wird. Dieser Test kann deshalb gefahrlos aus
# einem laufenden run-all.sh heraus starten, ohne ihm die Sperre wegzunehmen.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNALL="$REPO/tests/run-all.sh"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

# jobs_bei <frei_mib> <groesster_prozess_mib> [weitere Argumente]
jobs_bei() {
  local frei="$1" groesster="$2"; shift 2
  WB_FREI_MIB_TEST="$frei" WB_GROESSTER_MIB_TEST="$groesster" \
    "$RUNALL" --zeige-jobs "$@" 2>/dev/null | tail -1
}

meldung_bei() {
  local frei="$1" groesster="$2"; shift 2
  WB_FREI_MIB_TEST="$frei" WB_GROESSTER_MIB_TEST="$groesster" \
    "$RUNALL" --zeige-jobs "$@" 2>&1 >/dev/null
}

kerne="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
echo "Geprueft: $RUNALL (Kerne: $kerne)"

# 1 — die Lage vom 29.08.: reichlich freier Speicher, aber ein geladenes Modell.
#     Genau hier haette eine reine Speicherrechnung nichts gemerkt.
j="$(jobs_bei 20000 16000)"
if [ "$j" -le 4 ] 2>/dev/null; then
  ok "geladenes Modell drosselt trotz 20 GiB frei (auf $j)"
else
  bad "geladenes Modell drosselt trotz 20 GiB frei" "bekam $j, erwartet hoechstens 4"
fi

# 2 — GEGENPROBE, und der eigentliche Punkt: ohne grossen Prozess wird bei
#     demselben freien Speicher NICHT gedrosselt. Eine Bremse, die immer zieht,
#     waere so schaedlich wie gar keine.
j="$(jobs_bei 20000 600)"
if [ "$j" = "$kerne" ]; then
  ok "ohne grossen Prozess bleibt die volle Parallelitaet ($j)"
else
  bad "ohne grossen Prozess bleibt die volle Parallelitaet" "bekam $j, erwartet $kerne"
fi

# 3 — echter Speichermangel drosselt auch ohne Modell.
j="$(jobs_bei 5000 600)"
if [ "$j" -le 2 ] 2>/dev/null; then
  ok "5 GiB frei drosseln auf $j"
else
  bad "5 GiB frei drosseln" "bekam $j, erwartet hoechstens 2"
fi

# 4 — reichlich Speicher, kein Modell: keine Drosselung.
j="$(jobs_bei 60000 600)"
if [ "$j" = "$kerne" ]; then
  ok "60 GiB frei lassen die Parallelitaet unangetastet ($j)"
else
  bad "60 GiB frei lassen die Parallelitaet unangetastet" "bekam $j, erwartet $kerne"
fi

# 5 — ein ausdrueckliches --jobs wird nicht ueberstimmt. Dieselbe Linie wie
#     ueberall im Haus: warnen ja, den Start eines Menschen verhindern nein.
j="$(jobs_bei 5000 16000 --jobs 12)"
if [ "$j" = "12" ]; then
  ok "ausdrueckliches --jobs behaelt Vorrang"
else
  bad "ausdrueckliches --jobs behaelt Vorrang" "bekam $j, erwartet 12"
fi

# 6 — ... aber es wird gewarnt, sonst fuehrt genau dieser Weg wieder am Schutz vorbei.
m="$(meldung_bei 5000 16000 --jobs 12)"
case "$m" in
  *WARNUNG*) ok "ausdrueckliches --jobs warnt bei Knappheit" ;;
  *) bad "ausdrueckliches --jobs warnt bei Knappheit" "keine Warnung in: $(printf '%s' "$m" | head -2 | tr '\n' ' ')" ;;
esac

# 7 — und keine Warnung, wo nichts knapp ist.
m="$(meldung_bei 60000 600 --jobs 12)"
case "$m" in
  *WARNUNG*) bad "keine Warnung bei gesunder Lage" "warnte trotzdem: $(printf '%s' "$m" | head -1)" ;;
  *) ok "keine Warnung bei gesunder Lage" ;;
esac

# 8 — die Messung selbst muss auf dieser Maschine ueberhaupt eine Zahl liefern;
#     ohne sie faellt die Drosselung still aus.
j="$("$RUNALL" --zeige-jobs 2>/dev/null | tail -1)"
if [ "$j" -ge 1 ] 2>/dev/null; then
  ok "auf der echten Maschine kommt eine Zahl heraus ($j)"
else
  bad "auf der echten Maschine kommt eine Zahl heraus" "bekam '$j'"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
