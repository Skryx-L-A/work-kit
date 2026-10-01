#!/usr/bin/env bash
# test-freigabe-rueckkanal.sh -- der Rueckkanal von `wb-freigabe erteilen`: wer die
# Rueckfrage gestellt hat, erfaehrt die Freigabe SOFORT im eigenen Pane, statt beim
# naechsten (blinden) Versuch zu raten (Auftrag 03.09.2026, Wort des Nutzers: "die
# Nachricht mit der Freigabe direkt an den Agent zurueckgeht ... damit diese direkt
# wissen, dass die Freigabe erteilt ist").
#
# ZWEI RICHTUNGEN, wie im Auftrag verlangt:
#   1  Die Freigabe kommt im Pane an -- geprueft mit capture-pane, nicht nur an der
#      Ausgabe von wb-freigabe geglaubt. Zielt auf einen WORKER-Pane, den realen
#      Regelfall (der Blockierte ist so gut wie nie ein Orchestrator-Pane).
#   2  Lehnt `wb-pane-write darf` ab, kommt NICHTS an, `einfuegen` wird gar nicht
#      erst versucht, und wb-freigabe sagt es in der eigenen Ausgabe. Dafuer steht
#      ein eigener Stellvertreter fuer wb-pane-write, der wie eine echte Ablehnung
#      mit Exit 77 antwortet -- die orchestrator-Schutzregel SELBST (wer wirklich
#      abgelehnt wird) ist Sache von test-haerten-rolle-freigabe.sh und wird hier
#      nicht erneut geprueft. Mit derselben (unbedingten) "mensch"-Messung wuerde
#      auch wb-pane-write jeden Zielpane erlauben -- ein Stellvertreter ist darum
#      der einzige Weg, die Ablehnung UNABHAENGIG von wb-freigabes eigener
#      Freigabe-Bedingung nachzustellen.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME aus mktemp -d, ein
# eigener wb-mensch-Platzhalter (unbedingt "mensch", wie in
# test-freigabe-grund-freiwillig.sh) -- ohne ihn wuerde wb-freigabe die eigene
# Freigabe schon ablehnen, bevor der Rueckkanal ueberhaupt drankaeme. Kein Zugriff
# auf eine laufende Session, kein pkill. Die Panes sind `cat`, keine Shell: was
# hineingeschrieben wuerde, darf nie als Kommando laufen.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCKET="wbtest-freigabe-rk-$$"
FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    tmux_socket_beenden_ohne_reste "$SOCKET"
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$FAKEHOME" "$WORK"
}
trap cleanup EXIT

command -v tmux >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: tmux nicht im PATH"; exit 77; }
command -v python3 >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: python3 nicht im PATH"; exit 77; }
[ -x "$REPO/shell/wb-freigabe" ] || { echo "UEBERSPRUNGEN: shell/wb-freigabe fehlt"; exit 77; }
[ -x "$REPO/shell/wb-pane-write" ] || { echo "UEBERSPRUNGEN: shell/wb-pane-write fehlt"; exit 77; }

mkdir -p "$FAKEHOME/.local/bin"
ln -sf "$REPO/shell/wb-pane-write" "$FAKEHOME/.local/bin/wb-pane-write"

# Der Platzhalter steht an der Stelle der MESSUNG, wie in
# test-freigabe-grund-freiwillig.sh: dass eine Freigabe ohne gemessenen Menschen
# ausbleibt, ist Sache jener Suite -- hier soll unbedingt gewaehrt werden koennen,
# damit ueberhaupt geprueft werden kann, was NACH der Freigabe passiert.
cat > "$FAKEHOME/.local/bin/wb-mensch" <<'MENSCHEOF'
#!/bin/sh
printf 'mensch\tSteuerndes Terminal (M1)\n'
MENSCHEOF
chmod +x "$FAKEHOME/.local/bin/wb-mensch"

BLOCKS="$FAKEHOME/blocks"
GRANTS="$FAKEHOME/grants"
VERLAUF="$FAKEHOME/verlauf.log"
mkdir -p "$BLOCKS" "$GRANTS"

# Denselben Namen bildet wb-freigabe aus dem Pane (alles ausser [A-Za-z0-9_.-]
# wird zu '_'), und daran findet es den Marker wieder.
sicher() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9_.-]/_/g'; }

marker_legen() {   # <pane> <command> <muster>
    cat > "$BLOCKS/$(sicher "$1").json" <<EOF
{"pane":"$1","wartet":true,"command":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2"),
 "cwd":"/arbeit","muster":"$3","ts":"2026-09-03T10:00:00Z","session_id":"sitzung-rk"}
EOF
}

anzahl_freigaben() { find "$GRANTS" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

echo "== 1  Die Freigabe kommt im Pane an (Zielrolle: worker) =="

HOME="$FAKEHOME" tm new-session -d -s werkbank -n main cat \
    || { echo "tmux-Testserver liess sich nicht starten" >&2; exit 1; }
tm set -g remain-on-exit on

PANE_A=$(tm list-panes -t "=werkbank" -F '#{pane_id}' | head -1)
tm set -p -t "$PANE_A" @wb_role worker

BEFEHL_A="sudo apt-get update && sudo apt-get upgrade -y"
marker_legen "$PANE_A" "$BEFEHL_A" sudo

VOR_A="$(anzahl_freigaben)"
AUSGABE_A="$(env HOME="$FAKEHOME" AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" \
    AWB_GUARD_LOG="$VERLAUF" WB_TMUX_SOCKET="$SOCKET" \
    bash "$REPO/shell/wb-freigabe" erteilen --ttl 300 --grund "Testfreigabe" "$PANE_A" 2>&1)"
RC_A=$?

[ "$RC_A" = 0 ] && ok "wb-freigabe erteilen gelingt (Exit 0)" \
    || bad "wb-freigabe erteilen scheiterte (Exit $RC_A): $AUSGABE_A"
[ "$(anzahl_freigaben)" = "$((VOR_A + 1))" ] \
    && ok "und legt tatsaechlich eine Freigabedatei an" \
    || bad "keine neue Freigabedatei: $(anzahl_freigaben) statt $((VOR_A + 1))"
printf '%s' "$AUSGABE_A" | grep -q "^Rueckkanal: Hinweis in Pane $PANE_A eingefuegt" \
    && ok "die Ausgabe meldet: Hinweis eingefuegt" \
    || bad "die Ausgabe meldet keinen eingefuegten Hinweis: $AUSGABE_A"

warte_auf_bedingung 10 "der Hinweis erscheint im Pane" \
    "tm capture-pane -p -J -t '$PANE_A' | grep -q '\\[wb-freigabe\\]'"
INHALT_A="$(tm capture-pane -p -J -t "$PANE_A")"
printf '%s' "$INHALT_A" | grep -q '\[wb-freigabe\] Approved (sudo):' \
    && ok "der Hinweis nennt das angeschlagene Muster" \
    || bad "das Muster fehlt im Pane: $INHALT_A"
printf '%s' "$INHALT_A" | grep -qF "$BEFEHL_A" \
    && ok "der Hinweis nennt den freigegebenen Befehl im Wortlaut" \
    || bad "der Befehl fehlt im Pane: $INHALT_A"
printf '%s' "$INHALT_A" | grep -q "repeat the command now" \
    && ok "und sagt, dass der Befehl jetzt wiederholt werden kann" \
    || bad "die Aufforderung zum Wiederholen fehlt: $INHALT_A"
# cat echot eine Zeile erst NACH einem Zeilenumbruch (Enter). Bleibt der Prompt der
# Login-Shell (falls noch sichtbar) unveraendert eine Zeile ueber dem Hinweis und
# erscheint der Hinweistext nur EINMAL, wurde nichts abgeschickt, nur eingefuegt.
ANZAHL_TREFFER="$(printf '%s' "$INHALT_A" | grep -c '\[wb-freigabe\]')"
[ "$ANZAHL_TREFFER" = 1 ] \
    && ok "der Hinweis steht genau einmal im Pane -- kein zweites Echo durch ein abgeschicktes Enter" \
    || bad "der Hinweis steht $ANZAHL_TREFFER mal im Pane (ein Echo deutete auf ein gesendetes Enter hin)"

echo
echo "== 2  Lehnt wb-pane-write darf ab, kommt nichts an, und es wird gesagt =="

PANE_B=$(tm new-window -t "=werkbank" -n zweite -P -F '#{pane_id}' cat)
tm set -p -t "$PANE_B" @wb_role worker

BEFEHL_B="rm -rf /irgendwas"
marker_legen "$PANE_B" "$BEFEHL_B" rm

STUB="$WORK/wb-pane-write-ablehnend"
cat > "$STUB" <<EOF
#!/bin/sh
echo "\$*" >> "$WORK/stub.log"
case "\$1" in
    darf) exit 77 ;;
    *) exit 90 ;;
esac
EOF
chmod +x "$STUB"

VOR_B="$(anzahl_freigaben)"
AUSGABE_B="$(env HOME="$FAKEHOME" AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" \
    AWB_GUARD_LOG="$VERLAUF" WB_TMUX_SOCKET="$SOCKET" WB_PANE_WRITE="$STUB" \
    bash "$REPO/shell/wb-freigabe" erteilen --ttl 300 --grund "Testfreigabe" "$PANE_B" 2>&1)"
RC_B=$?

[ "$RC_B" = 0 ] && ok "die Freigabe selbst gelingt trotzdem (Exit 0) -- der Rueckkanal ist nur ein Hinweis" \
    || bad "die Freigabe scheiterte, obwohl nur der Hinweis abgelehnt wurde (Exit $RC_B): $AUSGABE_B"
[ "$(anzahl_freigaben)" = "$((VOR_B + 1))" ] \
    && ok "und legt weiterhin eine Freigabedatei an" \
    || bad "keine neue Freigabedatei: $(anzahl_freigaben) statt $((VOR_B + 1))"
printf '%s' "$AUSGABE_B" | grep -q "^Rueckkanal:.*NICHT geschickt" \
    && ok "die Ausgabe sagt ausdruecklich, dass nichts geschickt wurde" \
    || bad "die Ausgabe schweigt ueber die Ablehnung: $AUSGABE_B"
grep -q '^darf ' "$WORK/stub.log" 2>/dev/null \
    && ok "'darf' wurde gefragt" \
    || bad "'darf' wurde nie gerufen: $(cat "$WORK/stub.log" 2>/dev/null)"
grep -q '^einfuegen ' "$WORK/stub.log" 2>/dev/null \
    && bad "'einfuegen' wurde trotz Ablehnung versucht: $(cat "$WORK/stub.log")" \
    || ok "'einfuegen' wurde NICHT versucht -- nach einer Ablehnung wird nicht nachgefasst"
INHALT_B="$(tm capture-pane -p -J -t "$PANE_B")"
printf '%s' "$INHALT_B" | grep -q '\[wb-freigabe\]' \
    && bad "im Pane steht trotzdem ein Hinweis: $INHALT_B" \
    || ok "im Pane des abgelehnten Ziels steht kein Hinweis -- es kam wirklich nichts an"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ] || exit 1
