#!/usr/bin/env bash
# test-belegung-spiegel.sh -- der ausgelieferte Spiegel von wb-belegung traegt
# dieselbe Zuschlagsformel wie der Quelltext im Worktree.
#
# ANLASS (20.08.2026, Auftrag "zwei Rechnungen, die auseinanderlaufen"):
# test-kontext-messungen.sh Abschnitt 4 fiel rot, weil `wb-kontext` fuer
# 'plaetze' den echten Waechter live fragt (plaetze_wirklich() in
# shell/wb-kontext, N7-Fix) -- aber IMMER ueber den festen Pfad
# $HOME/.local/bin/wb-belegung, nie ueber den Worktree. Als der Zuschlag in
# shell/wb-belegung von 0,6 GiB/Sequenz auf 2,0 GiB fest + 2,3 GiB je Sequenz
# gehoben wurde (gemessen, siehe der Kommentar bei ZUSCHLAG_JE_SEQUENZ_GIB
# dort), blieb der ausgelieferte Spiegel unter ~/.local/bin auf dem alten
# Stand -- Spiegel-Disziplin vergessen. `wb-kontext` versprach danach
# 'plaetze' nach der ALTEN, guenstigeren Formel, waehrend derselbe Aufruf bei
# `wb-belegung darf` (Worktree-Fassung, NEUE Formel) abgelehnt wurde. Die
# Formel selbst steht nur an EINER Stelle (shell/wb-belegung); dieser Test
# haelt fest, dass der ZWEITE, ausgelieferte Textkoerper davon nicht
# abweichen darf -- rein durch Dateivergleich, unabhaengig davon, WELCHE
# Konstante als naechstes angepasst wird.
#
# Bewusst NICHT hermetisch: geprueft wird der echte $HOME/.local/bin, weil
# genau das der Pfad ist, den wb-kontext fest verdrahtet aufruft (BIN =
# os.path.join(HOME, ".local", "bin") in shell/wb-kontext). Ein isoliertes
# Fake-HOME wuerde den eigentlichen Fehlerkanal gar nicht sehen. Es wird
# NICHTS geschrieben, nur gelesen und noetigenfalls -- mit Ansage -- selbst
# nachgezogen.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUELLE="$REPO/wb-belegung"
SPIEGEL="$HOME/.local/bin/wb-belegung"
echo "Geprueft: $QUELLE gegen $SPIEGEL"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

if [ ! -f "$SPIEGEL" ]; then
  printf '  SKIP  kein ausgelieferter Spiegel unter %s auf dieser Maschine\n' "$SPIEGEL"
  printf '\ntest-belegung-spiegel.sh: 0 ok, 0 FAIL, 1 SKIP\n'
  exit 0
fi

if diff -q "$QUELLE" "$SPIEGEL" >/dev/null 2>&1; then
  ok "Spiegel deckungsgleich -- jeder Aufrufer (auch wb-kontext ueber den festen .local/bin-Pfad) sieht dieselbe Formel"
else
  bad "Spiegel WEICHT vom Worktree ab -- wb-kontexts 'plaetze' rechnet dann mit einer anderen Zuschlagsformel als wb-belegungs eigenes 'darf'. Nachziehen: cp '$QUELLE' '$SPIEGEL' && chmod +x '$SPIEGEL'"
fi

printf '\ntest-belegung-spiegel.sh: %d ok, %d FAIL\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
