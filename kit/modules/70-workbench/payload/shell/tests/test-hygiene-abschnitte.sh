#!/usr/bin/env bash
# Tests fuer die beiden neuen Meldeabschnitte in wb-hygiene ("Repo und
# Installation auseinander", "Liegengebliebene Test-Sockets").
#
# Anlass (2026-08-04): drei Werkzeuge (wb-hygiene selbst, wb-consistency,
# wb-dod) lagen monatelang NUR unter ~/.local/bin — keine Historie, kein
# git diff. wb-hygiene meldet das jetzt, aendert aber nichts (siehe dessen
# Kopfkommentar) — genau das prueft diese Datei: Meldung ja, Reparatur nein.
#
# Isolation: HOME-Redirect (WB_REPO_SHELL + BIN leiten aus $HOME ab, also
# ein WEGWERF-HOME statt des echten ~/.local/bin) und ein eigener
# TMUX_TMPDIR fuer den Socket-Abschnitt — beruehrt weder die echte
# Installation noch den echten tmux-Server.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_HYGIENE:-$REPO/wb-hygiene}"
[ -x "$TOOL" ] || { echo "  FAIL  $TOOL fehlt oder ist nicht ausfuehrbar"; exit 1; }
echo "Geprueft: $TOOL"

FAKEHOME="$(mktemp -d)"
FAKEREPO="$(mktemp -d)"
# BEWUSST kein `mktemp -d` fuer den Socket-Ordner: dessen Pfad haengt unter dem
# langen macOS-$TMPDIR (/private/var/folders/.../T/tmp.XXXXXXXX), zusammen mit
# 'tmux-<uid>/<name>' reisst das die ~104-Byte-Grenze von AF_UNIX-Pfaden --
# `tmux new-session` scheiterte hier mit "File name too long". Ein kurzer,
# fester Pfad direkt unter /tmp bleibt darunter.
FAKETMPDIR="/tmp/wbtest-hygiene-tmpdir-$$"
mkdir -p "$FAKETMPDIR"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  # Panes VOR dem kill-server einsammeln und jeden Ueberlebenden direkt
  # beenden statt sich auf das SIGHUP zu verlassen -- dasselbe Muster wie
  # Aufgeraeumt wird ueber die gemeinsame Funktion aus lib-testwerkzeuge.sh --
  # sie nimmt seit dem 24.08. Vorargumente entgegen (hier keine noetig) und
  # beendet ausser den Panes auch die uebrigen Kinder des Serverprozesses. Die
  # handgebaute Schleife, die bis dahin hier stand, kannte nur die Pane-Liste
  # und liess damit genau die Shells stehen, die ein kill-session ueberlebt
  # hatten (Auftrag "was bei zwanzig gleichzeitig passiert", 2026-08-24).
  TMUX_TMPDIR="$FAKETMPDIR" tmux_socket_beenden_ohne_reste wbtest-hygiene-lebendig
  rm -rf "$FAKEHOME" "$FAKEREPO" "$FAKETMPDIR"
}
trap cleanup EXIT

mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.local/state"

# --- Attrappen fuer "Repo und Installation auseinander" ---------------------
# gleich: identischer Inhalt auf beiden Seiten -> muss STUMM bleiben.
printf '#!/bin/bash\necho gleich\n' > "$FAKEREPO/gleich"
chmod +x "$FAKEREPO/gleich"
cp "$FAKEREPO/gleich" "$FAKEHOME/.local/bin/gleich"

# weicht-ab: gleicher Name, unterschiedlicher Inhalt -> muss ALS ABWEICHEND gemeldet werden.
printf '#!/bin/bash\necho repo-fassung\n' > "$FAKEREPO/weicht-ab"
chmod +x "$FAKEREPO/weicht-ab"
printf '#!/bin/bash\necho installierte-fassung\n' > "$FAKEHOME/.local/bin/weicht-ab"
chmod +x "$FAKEHOME/.local/bin/weicht-ab"

# nur-repo: existiert nur im Repo -> muss ALS FEHLEND (nicht als "abweichend") gemeldet werden.
printf '#!/bin/bash\necho nur-repo\n' > "$FAKEREPO/nur-repo"
chmod +x "$FAKEREPO/nur-repo"

# nicht-ausfuehrbar im Repo: darf gar nicht erst als Werkzeug zaehlen (kein Fund).
printf 'kein Skript\n' > "$FAKEREPO/notizen.txt"

# --- ein lebender und ein toter Socket im FAKETMPDIR -------------------------
TMUX_TMPDIR="$FAKETMPDIR" tmux -L wbtest-hygiene-lebendig new-session -d -s probe -c /tmp
DEADSOCK="$FAKETMPDIR/tmux-$(id -u)/wbtest-hygiene-tot"
mkdir -p "$(dirname "$DEADSOCK")"
# Ein AF_UNIX-Socket, gebunden und sofort verlassen (kein listen(), kein accept()):
# genau der Zustand eines Sockets, dessen Server abgestuerzt ist -- die Datei
# bleibt liegen, aber niemand nimmt Verbindungen an. Reproduziert den Befund vom
# 2026-08-04 (13 liegengebliebene Sockets aus Handarbeit), ohne einen echten
# tmux-Server erst abstuerzen lassen zu muessen.
python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
" "$DEADSOCK"

# --- Lauf ---------------------------------------------------------------------
OUT="$(HOME="$FAKEHOME" WB_REPO_SHELL="$FAKEREPO" TMUX_TMPDIR="$FAKETMPDIR" "$TOOL" 2>&1)"
ABSCHNITT_REPO="$(printf '%s\n' "$OUT" | sed -n '/## Repo und Installation auseinander/,/^## /p')"
ABSCHNITT_SOCK="$(printf '%s\n' "$OUT" | sed -n '/## Liegengebliebene Test-Sockets/,$p')"

echo "-- Repo und Installation auseinander --"
case "$ABSCHNITT_REPO" in *"gleich"*) bad "'gleich' wurde erwaehnt, obwohl beide Seiten identisch sind" ;;
                          *)          ok "identischer Stand bleibt stumm" ;; esac
case "$ABSCHNITT_REPO" in *"ABWEICHEND    weicht-ab"*) ok "unterschiedlicher Inhalt wird als ABWEICHEND gemeldet" ;;
                          *) bad "Abweichung nicht gemeldet: $ABSCHNITT_REPO" ;; esac
case "$ABSCHNITT_REPO" in
  *"nur im Repo, nicht installiert: nur-repo"*) ok "fehlende installierte Seite wird als fehlend benannt" ;;
  *"ABWEICHEND    nur-repo"*) bad "fehlende Seite wurde faelschlich als ABWEICHEND statt als fehlend gemeldet" ;;
  *) bad "fehlende installierte Seite nicht gemeldet: $ABSCHNITT_REPO" ;;
esac
case "$ABSCHNITT_REPO" in *"notizen"*) bad "eine nicht-ausfuehrbare Datei wurde faelschlich als Werkzeug gezaehlt" ;;
                          *)          ok "nicht-ausfuehrbare Dateien bleiben aussen vor" ;; esac

echo "-- Liegengebliebene Test-Sockets --"
case "$ABSCHNITT_SOCK" in
  *"liegengebliebene Socket(s)"*) ok "toter Socket wird gezaehlt" ;;
  *) bad "toter Socket nicht gemeldet: $ABSCHNITT_SOCK" ;;
esac
case "$ABSCHNITT_SOCK" in
  *"1 lebendig"*) ok "genau der eine lebende Socket zaehlt als lebendig" ;;
  *) bad "lebendiger Socket falsch gezaehlt: $ABSCHNITT_SOCK" ;;
esac
# Der Name des toten Sockets darf nicht als "lebendig" durchgehen -- die Zahl
# davor (1 tot) ist der eigentliche Beleg, hier zusaetzlich die Wortprobe.
case "$ABSCHNITT_SOCK" in
  *$'\n''  1 liegengebliebene'*) ok "genau ein toter Socket gezaehlt (nicht mehr, nicht weniger)" ;;
  *) bad "falsche Anzahl toter Sockets: $ABSCHNITT_SOCK" ;;
esac

echo
echo "wb-hygiene-Abschnitte: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
