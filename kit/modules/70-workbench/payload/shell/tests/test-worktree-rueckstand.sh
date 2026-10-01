#!/usr/bin/env bash
# test-worktree-rueckstand.sh — Rueckstandsmessung fuer WIEDERVERWENDETE Worktrees
# in `wb-worktree ensure` (Auftrag 2026-09-04, Befund desselben Tages).
#
# ANLASS: `wb-worktree ensure` gab einen bestehenden Worktree bislang unveraendert
# zurueck, egal wie weit er hinter dem Zielzweig lag — gemessen ueber alle 50
# Baeume unter ~/.pi-workers/worktrees bis zu 1065 Commits. Ein Worker namens
# "melder" ist genau deshalb in eine 1065 Commits alte Fassung eines Werkzeugs
# geraten und haette sie fast ausgerollt, ohne dass ein Test angeschlagen haette.
#
# Diese Suite prueft die drei Faelle aus dem Auftrag: ein sauberer Baum ohne
# eigene Commits wird beim naechsten `ensure` selbst auf den Zielzweig
# nachgezogen; ein Baum mit eigenen Commits ODER unbeachteten Aenderungen wird
# NICHT angefasst, nur gewarnt — mit expliziter Gegenprobe, dass seine Commits
# danach noch dieselben sind. Zusaetzlich: `wb-worktree list` traegt eine
# RUECKSTAND-Spalte.
#
# ISOLATION (wie test-worktree-node-modules.sh begruendet): kein tmux noetig —
# `ensure` und `list` brauchen kein Pane, nur git. Eigenes HOME (mktemp -d),
# ein selbst angelegtes Wegwerf-Repo; die echten Baeume unter
# ~/.pi-workers/worktrees dieser Maschine werden nie angefasst. `wb-worktree`
# wird als KOPIE in ein Test-$BIN gelegt, damit eine Bearbeitung waehrend des
# Laufs den Code unter dem laufenden Test nicht aendert.
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL_SRC="$REPO_ROOT/wb-worktree"
[ -x "$TOOL_SRC" ] || { echo "FAIL  $TOOL_SRC fehlt oder ist nicht ausfuehrbar" >&2; exit 1; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-worktree-rueckstand-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TESTHOME"' EXIT
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN"
cp "$TOOL_SRC" "$BIN/wb-worktree"; chmod +x "$BIN/wb-worktree"
W="$BIN/wb-worktree"
WTROOT="$TESTHOME/.pi-workers/worktrees"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }
have(){ case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | tr '\n' ' ' | cut -c1-300)" ;; esac; }

echo "Geprueft: $TOOL_SRC"
echo "  HOME: $TESTHOME"

mkrepo() { # mkrepo <pfad>
  mkdir -p "$1"
  git -c init.defaultBranch=main init -q "$1"
  git -C "$1" config user.email "test@example.invalid"
  git -C "$1" config user.name  "Worktree Rueckstand Test"
  git -C "$1" config commit.gpgsign false
  printf 'hallo\n' > "$1/a.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m "init"
}
REPO="$TESTHOME/projekt"; mkrepo "$REPO"

# --- Ausgangslage: drei Baeume, alle auf demselben Commit wie main ---------
WT_A="$("$W" ensure wa "$REPO" 2>/dev/null)"
WT_B="$("$W" ensure wb "$REPO" 2>/dev/null)"
WT_C="$("$W" ensure wc "$REPO" 2>/dev/null)"
[ -d "$WT_A" ] && [ -d "$WT_B" ] && [ -d "$WT_C" ] \
  && ok "alle drei Baeume entstanden" \
  || bad "alle drei Baeume entstanden" "wa=$WT_A wb=$WT_B wc=$WT_C"

# main laeuft zwei Commits weiter — genau der Zustand, den keiner der drei
# Baeume je zu sehen bekommt, ohne dass ensure ihn misst.
printf 'zweiter\n' >> "$REPO/a.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "zweiter"
printf 'dritter\n' >> "$REPO/a.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "dritter"
MAIN_HEAD="$(git -C "$REPO" rev-parse main)"

# wb bekommt einen EIGENEN Commit, bevor der Rueckstand gemessen wird.
printf 'eigene arbeit\n' > "$WT_B/eigen.txt"
git -C "$WT_B" add -A >/dev/null 2>&1
git -C "$WT_B" commit -q -m "eigene Arbeit von wb"
OWN_SHA="$(git -C "$WT_B" rev-parse HEAD)"

# wc bekommt eine UNBEACHTETE (nicht committete) Aenderung.
printf 'unfertig\n' > "$WT_C/unfertig.txt"

echo
echo "== 1. sauber, keine eigenen Commits: wird selbst nachgezogen =="
out="$("$W" ensure wa "$REPO" 2>"$TESTHOME/err-wa")"
eq   "ensure liefert weiter denselben Pfad" "$out" "$WT_A"
have "meldet den Rueckstand vor dem Nachziehen" "$(cat "$TESTHOME/err-wa")" "2 Commit(s) hinter main"
have "meldet das automatische Nachziehen" "$(cat "$TESTHOME/err-wa")" "automatisch nachgezogen"
eq   "der Baum steht jetzt auf demselben Commit wie main" "$(git -C "$WT_A" rev-parse HEAD)" "$MAIN_HEAD"
eq   "Rueckstand ist danach 0" "$(git -C "$WT_A" rev-list --count "HEAD..main")" "0"
[ -f "$WT_A/a.txt" ] && [ "$(cat "$WT_A/a.txt")" = "$(cat "$REPO/a.txt")" ] \
  && ok "der Inhalt von main ist im Baum angekommen" \
  || bad "der Inhalt von main ist NICHT im Baum angekommen"

echo
echo "== 2. eigene Commits: wird NICHT angefasst =="
out="$("$W" ensure wb "$REPO" 2>"$TESTHOME/err-wb")"
eq   "ensure liefert weiter denselben Pfad" "$out" "$WT_B"
have "meldet den Rueckstand" "$(cat "$TESTHOME/err-wb")" "2 Commit(s) hinter main"
have "meldet die eigenen Commits als Grund" "$(cat "$TESTHOME/err-wb")" "eigene Commit(s)"
have "nennt einen Weg zum Aufholen" "$(cat "$TESTHOME/err-wb")" "merge main"
hasnt_geklont() { case "$1" in *"automatisch nachgezogen"*) return 1 ;; *) return 0 ;; esac; }
hasnt_geklont "$(cat "$TESTHOME/err-wb")" \
  && ok "kein 'automatisch nachgezogen' — es wurde nichts angefasst" \
  || bad "faelschlich 'automatisch nachgezogen' gemeldet, obwohl eigene Commits da sind"
# Gegenprobe (Auftrag Zeile 31): der Baum traegt danach GENAU dieselben Commits.
eq   "der eigene Commit ist unveraendert derselbe (kein Ueberschreiben)" "$(git -C "$WT_B" rev-parse HEAD)" "$OWN_SHA"
[ -f "$WT_B/eigen.txt" ] && ok "die eigene Datei ist unangetastet" || bad "die eigene Datei ist WEG"

echo
echo "== 3. unbeachtete Aenderungen: wird NICHT angefasst =="
VORHER_HEAD="$(git -C "$WT_C" rev-parse HEAD)"
out="$("$W" ensure wc "$REPO" 2>"$TESTHOME/err-wc")"
eq   "ensure liefert weiter denselben Pfad" "$out" "$WT_C"
have "meldet den Rueckstand" "$(cat "$TESTHOME/err-wc")" "2 Commit(s) hinter main"
have "meldet die unbeachteten Aenderungen als Grund" "$(cat "$TESTHOME/err-wc")" "unbeachtete Aenderungen"
hasnt_geklont "$(cat "$TESTHOME/err-wc")" \
  && ok "kein 'automatisch nachgezogen' — es wurde nichts angefasst" \
  || bad "faelschlich 'automatisch nachgezogen' gemeldet, obwohl der Baum schmutzig ist"
eq   "HEAD ist unveraendert (kein Merge, kein Checkout)" "$(git -C "$WT_C" rev-parse HEAD)" "$VORHER_HEAD"
[ -f "$WT_C/unfertig.txt" ] && [ "$(cat "$WT_C/unfertig.txt")" = "unfertig" ] \
  && ok "die unbeachtete Datei ist unangetastet" \
  || bad "die unbeachtete Datei ist WEG oder veraendert"

echo
echo "== 4. wb-worktree list traegt eine RUECKSTAND-Spalte =="
LISTOUT="$("$W" list)"
have "Kopfzeile nennt RUECKSTAND" "$LISTOUT" "RUECKSTAND"
eq  "wa: 0 eigene Commits in der Liste (nachgezogen)" "$(printf '%s\n' "$LISTOUT" | awk '$1=="wa"{print $4}')" "0"
eq  "wa: 0 Rueckstand in der Liste (nachgezogen)"      "$(printf '%s\n' "$LISTOUT" | awk '$1=="wa"{print $5}')" "0"
eq  "wb: 1 eigener Commit in der Liste"                "$(printf '%s\n' "$LISTOUT" | awk '$1=="wb"{print $4}')" "1"
eq  "wb: weiterhin 2 Commits Rueckstand in der Liste"  "$(printf '%s\n' "$LISTOUT" | awk '$1=="wb"{print $5}')" "2"
eq  "wc: 0 eigene Commits in der Liste"                "$(printf '%s\n' "$LISTOUT" | awk '$1=="wc"{print $4}')" "0"
eq  "wc: weiterhin 2 Commits Rueckstand in der Liste"  "$(printf '%s\n' "$LISTOUT" | awk '$1=="wc"{print $5}')" "2"

echo
echo "wb-worktree (Rueckstand): $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
