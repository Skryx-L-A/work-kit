#!/usr/bin/env bash
# test-ohne-brain.sh -- ein Projekt mit .wb-ohne-brain bekommt im Auftrag ein
# Kbase-VERBOT statt der Pflichtsuche.
#
# ANLASS (der Nutzer, 25.09.2026, ueber die work-kit task): seit 6499ff1b haengt
# pi-worker an JEDEN Auftrag "Vor der ersten Änderung: brain search ...". Fuer
# ~/work-kit -- ein Kit fuer den Firmenlaptop, frei von privaten Daten --
# holt das Inhalte aus dem privaten Kbase in Firmendateien.
#
# Geprueft wird der Baustein (wb-brain-zeile) mit echten Verzeichnissen und der
# Weg in pi-worker am Quelltext: ein voller Spawn braucht einen Harness und ist
# fuer diese eine Zeile nicht verhaeltnismaessig. Gegen die Fassung vor dem Fix
# gemessen: Teil B ist dort rot (fester Pflichtsatz im MSG).
#   PI_WORKER=<pfad> bash test-ohne-brain.sh   # anderer pi-worker fuer die Gegenprobe
unset TMUX TMUX_PANE
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLDIR="$(cd "$HERE/.." && pwd)"
ZEILE="$SHELLDIR/wb-brain-zeile"
PI_WORKER="${PI_WORKER:-$SHELLDIR/pi-worker}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ohnebrain.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/ohnebrain.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

# Eigenes HOME: die Suche nach der Marke endet dort, und nichts Echtes wird gelesen.
H="$TMP/home"; mkdir -p "$H"
# Kit: the search step exists only where the kit's brain CLI is installed (kit fix 1); a stand-in.
mkdir -p "$H/.local/bin"; printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/brain"; chmod +x "$H/.local/bin/brain"
lauf() { HOME="$H" bash "$ZEILE" "$@"; }
ist_verbot()  { case "$1" in *"No knowledge-base search"*) return 0 ;; esac; return 1; }  # Kit: English
ist_pflicht() { case "$1" in *'brain search "<topic of the task>" -k 5'*) return 0 ;; esac; return 1; }

echo "A) Baustein wb-brain-zeile"
mkdir -p "$H/AI/normal/sub" "$H/AI/firma/kit/modul" "$H/wt/firma-worker"
: > "$H/AI/firma/.wb-ohne-brain"

out="$(lauf "$H/AI/normal/sub")"
ist_pflicht "$out" && ! ist_verbot "$out" && ok "ohne Marke: Pflichtsuche" || bad "ohne Marke: Pflichtsuche" "$out"

out="$(lauf "$H/AI/firma")"
ist_verbot "$out" && ! ist_pflicht "$out" && ok "Marke im Projekt: Verbot" || bad "Marke im Projekt: Verbot" "$out"

out="$(lauf "$H/AI/firma/kit/modul")"
ist_verbot "$out" && ok "Marke im Elternordner: Verbot" || bad "Marke im Elternordner: Verbot" "$out"

# Worktree liegt ausserhalb des Projekts; die Marke steht nur im Original.
out="$(lauf "$H/AI/firma/kit" "$H/wt/firma-worker")"
ist_verbot "$out" && ok "Worktree ohne Marke, Original mit Marke: Verbot" \
  || bad "Worktree ohne Marke, Original mit Marke: Verbot" "$out"
out="$(lauf "$H/wt/firma-worker" "$H/AI/firma/kit")"
ist_verbot "$out" && ok "Reihenfolge der Verzeichnisse egal" || bad "Reihenfolge der Verzeichnisse egal" "$out"

# Eine Marke OBERHALB von HOME zaehlt nicht -- sonst schaltete eine vergessene
# Datei in / oder /Users den Kbase fuer alle Projekte ab.
: > "$TMP/.wb-ohne-brain"
out="$(lauf "$H/AI/normal/sub")"
ist_pflicht "$out" && ok "Marke oberhalb von HOME wird ignoriert" || bad "Marke oberhalb von HOME wird ignoriert" "$out"
rm -f "$TMP/.wb-ohne-brain"

out="$(lauf "$H/gibt-es-nicht")"
ist_pflicht "$out" && ok "fehlendes Verzeichnis: Pflichtsuche, kein Fehler" || bad "fehlendes Verzeichnis" "$out"

echo "B) Weg in pi-worker"
msgzeile="$(grep -n '^\[Protocol — always follow\]' "$PI_WORKER" | head -1)"  # Kit: English
case "$msgzeile" in
  *'$BRAIN_ZEILE'*) ok "Protokollzeile nimmt den Satz aus \$BRAIN_ZEILE" ;;
  *) bad "Protokollzeile nimmt den Satz aus \$BRAIN_ZEILE" "${msgzeile:-keine Protokollzeile gefunden}" ;;
esac
case "$msgzeile" in
  *'brain search'*) bad "kein fest eingebauter Pflichtsatz mehr in der Protokollzeile" "$msgzeile" ;;
  *) ok "kein fest eingebauter Pflichtsatz mehr in der Protokollzeile" ;;
esac
if grep -q 'wb-brain-zeile" "\$ORIG_WORKDIR" "\$WORKDIR"' "$PI_WORKER"; then
  ok "pi-worker fragt Original- UND Arbeitsverzeichnis"
else
  bad "pi-worker fragt Original- UND Arbeitsverzeichnis"
fi

echo
echo "test-ohne-brain: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
