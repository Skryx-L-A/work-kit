#!/bin/bash
# test-doctor-hook-pfade.sh -- wb-doctor muss tmux-Hooks finden, die ins Leere
# zeigen oder ein Pane einfrieren koennen.
#
# Anlass (2026-08-29): drei Hooks auf host2 zeigten nach $HOME, einen
# Benutzer, den es dort seit dem Umbau auf Omarchy nicht mehr gibt. Jeder Aufruf
# endete mit exit 127; tmux zeigt Ausgabe UND Fehlercode eines run-shell im
# aktiven Pane an, und dieses Pane steht danach im view-mode, wo keine Eingabe
# ankommt. Weil die Hooks an after-split-window, pane-exited und pane-died
# haengen, fror das Fenster bei JEDEM Worker-Start und -Ende ein. Mehrere Agenten
# haben ueber Wochen nur das festsitzende Pane befreit.
#
# ISOLATION: eigener tmux-Server ueber einen Wrapper auf PATH, damit wb-doctor
# gegen den TEST-Server prueft und nicht gegen laufende des Nutzers Sitzung. Ohne
# den Wrapper wuerde dieser Test die echten Hooks veraendern.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO/wb-doctor"
SOCK="wbtest-hookpfade-$$"
TESTDIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-hookpfade.XXXXXX")" && pwd)"
BIN="$TESTDIR/bin"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

aufraeumen() {
  /usr/bin/env tmux -L "$SOCK" kill-server 2>/dev/null
  rm -rf "$TESTDIR"
}
trap aufraeumen EXIT

echte_tmux="$(command -v tmux)"
[ -n "$echte_tmux" ] || { echo "tmux fehlt -- SKIP"; exit 0; }

# Der Wrapper MUSS tmux mit absolutem Pfad rufen: 'env tmux' faende ueber die
# gleich gesetzte PATH wieder sich selbst und liefe endlos.
mkdir -p "$BIN"
cat > "$BIN/tmux" <<WRAP
#!/bin/bash
exec "$echte_tmux" -L "$SOCK" "\$@"
WRAP
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

tmux new-session -d -s probe -x 120 -y 40 2>/dev/null
sleep 1

doctor_zwoelf() {
  # Nur den Abschnitt der Pruefung 12 herausschneiden. wb-doctor prueft mehr,
  # und die uebrigen Befunde dieser Maschine gehen diesen Test nichts an.
  "$DOCTOR" 2>&1 | awk '/^12\./ { drin = 1 } drin && /^$/ { exit } drin { print }'
}

echo "Geprueft: $DOCTOR gegen tmux-Socket $SOCK"

# 1 — GESUNDER FALL zuerst. Eine Pruefung, die immer meckert, ist wertlos.
tmux set-hook -g after-split-window \
  "run-shell -b -d 1 \"/bin/echo dummy >/dev/null 2>&1 || true\"" 2>/dev/null
a="$(doctor_zwoelf)"
case "$a" in
  *"ok"*) ok "erreichbarer, abgeschirmter Hook gilt als in Ordnung" ;;
  *) bad "erreichbarer, abgeschirmter Hook gilt als in Ordnung" "$(printf '%s' "$a" | tr '\n' ' ')" ;;
esac

# 2 — DER FALL VOM 29.08.: der Pfad zeigt ins Leere.
tmux set-hook -g after-split-window \
  "run-shell -b -d 1 \"/home/gibt-es-nicht/bin/wb-grid #{window_id} >/dev/null 2>&1 || true\"" 2>/dev/null
b="$(doctor_zwoelf)"
case "$b" in
  *"gibt es nicht oder nicht ausfuehrbar"*) ok "toter Hook-Pfad wird gemeldet" ;;
  *) bad "toter Hook-Pfad wird gemeldet" "$(printf '%s' "$b" | tr '\n' ' ')" ;;
esac

# 3 — der zweite Befund: erreichbar, aber ungeschirmt. Genau so friert der
#     naechste Fehlschlag wieder ein Fenster ein.
tmux set-hook -g after-split-window \
  "run-shell -b -d 1 \"/bin/echo dummy #{window_id}\"" 2>/dev/null
c="$(doctor_zwoelf)"
case "$c" in
  *"nicht abgeschirmt"*) ok "ungeschirmter Hook wird gemeldet" ;;
  *) bad "ungeschirmter Hook wird gemeldet" "$(printf '%s' "$c" | tr '\n' ' ')" ;;
esac

# 4 — pane-exited und pane-died liegen im WINDOW-Scope und fehlen in
#     'show-hooks -g'. Wer nur den Session-Scope abfragt, sieht zwei von drei
#     Hooks nie -- daran ist die Suche am 29.08. zuerst haengengeblieben.
tmux set-hook -gu after-split-window 2>/dev/null
tmux set-hook -g pane-died \
  "run-shell -b \"/home/gibt-es-nicht/bin/wb-autorevive #{hook_pane} >/dev/null 2>&1 || true\"" 2>/dev/null
d="$(doctor_zwoelf)"
case "$d" in
  *"pane-died"*) ok "ein Hook im Window-Scope wird ebenfalls gefunden" ;;
  *) bad "ein Hook im Window-Scope wird ebenfalls gefunden" "$(printf '%s' "$d" | tr '\n' ' ')" ;;
esac

# 5 — ein ABGESCHALTETER Hook darf nichts melden. 'set-hook -gu' laesst den
#     Namen ohne Befehl stehen, und genau so kappt lib-testwerkzeuge.sh die
#     Leitungen zur lebenden Maschine. Ohne diese Unterscheidung hielt die
#     Pruefung jeden gekappten Hook fuer ungeschirmt und faerbte betriebslauf.sh
#     mit 45 Fehlschlaegen rot -- gefunden im ersten vollen Lauf nach dem Einbau.
tmux set-hook -gu pane-died 2>/dev/null
tmux set-hook -gu after-split-window 2>/dev/null
tmux set-hook -gu pane-exited 2>/dev/null
e="$(doctor_zwoelf)"
case "$e" in
  *"nicht abgeschirmt"*|*"gibt es nicht"*)
    bad "abgeschalteter Hook wird nicht beanstandet" "$(printf '%s' "$e" | tr '\n' ' ')" ;;
  *) ok "abgeschalteter Hook wird nicht beanstandet" ;;
esac

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
