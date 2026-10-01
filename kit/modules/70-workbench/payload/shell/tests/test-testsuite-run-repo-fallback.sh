#!/usr/bin/env bash
# test-testsuite-run-repo-fallback.sh -- die WB_REPO_SHELL-Rueckfallebene aus
# shell/wb-testsuite-run.
#
# ANLASS (22.08.2026): die nach ~/.local/bin ausgerollte Kopie von
# wb-testsuite-run hat kein tests/ neben sich (das liegt nur im Repo). Ueber
# den PATH aufgerufen lief das Skript deshalb in ein exit 127 -- und schrieb
# TROTZDEM eine Statusdatei mit parse_ok=0, die die Ampel als fehlgeschlagenen
# Lauf liest. Der launchd-Job hat es nie getroffen (er ruft den Repo-Pfad
# direkt); seit es keinen Job mehr gibt und ein Mensch oder Agent den Befehl
# selbst tippt, trifft es jeden Aufruf ueber den PATH. Der Fix faellt auf eine
# feste Repo-Wurzel zurueck (WB_REPO_SHELL, ueberschreibbar) und bricht sonst
# mit einer lesbaren Meldung und Exit 2 ab statt mit 127.
#
# DIE DREI ZUSAGEN, von Hand gemessen (siehe Auftrag):
#   1  Ohne Nachbarn und ohne gueltiges WB_REPO_SHELL: Exit 2 und eine
#      Meldung, die den gesuchten Pfad nennt -- NICHT 127.
#   2  Ohne Nachbarn, aber mit WB_REPO_SHELL auf ein Verzeichnis mit
#      tests/run-all.sh: der Lauf findet es und startet.
#   3  Es wird KEINE Statusdatei mit parse_ok=0 geschrieben, wenn der
#      Wrapper den Runner gar nicht erst findet -- ein nicht gestarteter
#      Lauf darf die Ampel nicht faerben.
#
# ISOLATION: HOME ist fuer JEDEN Fall ein eigenes Wegwerf-Verzeichnis
# (mktemp -d) -- sonst schriebe der Wrapper unter ~/.local/state/ und
# faelschte echte des Nutzers Ampel, genau die Falle, an der das Messen fuer
# diesen Fix fast selbst haengengeblieben ist (siehe Auftragstext). Der
# Wrapper selbst liegt NUR isoliert in einem eigenen Verzeichnis ohne
# tests/-Nachbarn -- eine Kopie, keine Aenderung am Original im Repo. Ein
# fake wb-belegung im PATH meldet "frei", damit Fall 2 nicht in den
# GPU-Waechter laeuft und eine Stunde wartet. Kein echter run-all.sh-Lauf,
# keine echte GPU-Abfrage, keine echte Statusdatei.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER_ORIG="$REPO/shell/wb-testsuite-run"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

[ -x "$WRAPPER_ORIG" ] || { echo "UEBERSPRUNGEN: $WRAPPER_ORIG fehlt oder nicht ausfuehrbar"; exit 77; }
command -v jq >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: jq nicht im PATH (fuer Fall 2 gebraucht)"; exit 77; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/wb-testsuite-run-fallback.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Der Wrapper OHNE tests/-Nachbarn, wie unter ~/.local/bin -- Kopie statt
# Original, damit hier nichts am Repo veraendert wird.
ISOL_BIN="$WORK/isoliert"
mkdir -p "$ISOL_BIN"
cp "$WRAPPER_ORIG" "$ISOL_BIN/wb-testsuite-run"
chmod +x "$ISOL_BIN/wb-testsuite-run"

echo "== test-testsuite-run-repo-fallback (Arbeitsverzeichnis $WORK) =="

# --- Fall 1: kein Nachbar, kein gueltiges WB_REPO_SHELL --------------------
HOME1="$WORK/home1"
mkdir -p "$HOME1"
NICHT_VORHANDEN="$WORK/nicht-vorhanden-$$"
out1=$(HOME="$HOME1" WB_REPO_SHELL="$NICHT_VORHANDEN" "$ISOL_BIN/wb-testsuite-run" 2>&1)
rc1=$?

if [ "$rc1" -eq 2 ]; then
  ok "Fall 1: Exit 2 statt 127 ($rc1)"
else
  bad "Fall 1: erwartet Exit 2, bekam $rc1 (Ausgabe: $out1)"
fi
if printf '%s' "$out1" | grep -qF "$NICHT_VORHANDEN"; then
  ok "Fall 1: Meldung nennt den gesuchten Pfad"
else
  bad "Fall 1: Meldung nennt den gesuchten Pfad nicht -- Ausgabe: $out1"
fi
STATUS1="$HOME1/.local/state/wb-testsuite-status.txt"
if [ ! -e "$STATUS1" ]; then
  ok "Fall 1: keine Statusdatei geschrieben -- ein nicht gestarteter Lauf faerbt die Ampel nicht"
else
  bad "Fall 1: Statusdatei wurde trotzdem geschrieben: $(cat "$STATUS1")"
fi

# --- Fall 2: kein Nachbar, aber WB_REPO_SHELL zeigt auf einen echten Fund --
HOME2="$WORK/home2"
mkdir -p "$HOME2"
REPO_SHELL="$WORK/repo-shell"
mkdir -p "$REPO_SHELL/tests"
MARKER="$WORK/lief-$$"
cat > "$REPO_SHELL/tests/run-all.sh" <<EOF
#!/bin/bash
touch "$MARKER"
echo "PASS: 1  FAIL: 0  SKIP: 0  gesamt 1"
echo "VOLLSTAENDIG: ja"
exit 0
EOF
chmod +x "$REPO_SHELL/tests/run-all.sh"

# fake wb-belegung: meldet "frei" (ollama_status ausserhalb von
# ladungen/unbekannt), damit der GPU-Waechter den Lauf sofort durchlaesst.
BIN2="$WORK/bin2"
mkdir -p "$BIN2"
cat > "$BIN2/wb-belegung" <<'EOF'
#!/bin/sh
echo '{"belegungen": [], "ollama_status": "frei"}'
EOF
chmod +x "$BIN2/wb-belegung"

PATH="$BIN2:$PATH" HOME="$HOME2" WB_REPO_SHELL="$REPO_SHELL" "$ISOL_BIN/wb-testsuite-run" >/dev/null 2>&1
rc2=$?

if [ -e "$MARKER" ]; then
  ok "Fall 2: der gefundene run-all.sh unter WB_REPO_SHELL wurde tatsaechlich gestartet"
else
  bad "Fall 2: run-all.sh unter WB_REPO_SHELL wurde NICHT gestartet (rc=$rc2)"
fi
if [ "$rc2" -eq 0 ]; then
  ok "Fall 2: Exit 0, der fingierte Lauf war gruen"
else
  bad "Fall 2: erwartet Exit 0, bekam $rc2"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
