#!/usr/bin/env bash
# test-rollenblock-nie-im-commit.sh -- der Rollenblock, den wb-harness-run in die
# Anweisungsdatei des Worktrees schreibt, landet nie in einem Commit.
#
# ANLASS (Kbase-Sitzung, 25.09.2026): ein opencode-Worker im Worktree von
# ~/work/brain bekam den Block `<!-- wb-rolle worker anfang -->` an die versionierte
# AGENTS.md gehaengt; er musste von Hand verworfen werden. Seit AGENTS.md die eine
# Anweisungsdatei jedes Projekts ist (der Nutzer, 25.09.), trifft das jedes Repo.
#
# Gemessen wird der ECHTE Python-Rumpf aus wb-harness-run (zwischen der Zeile mit
# `<<'PY'` hinter ROLLENZIEL und dem schliessenden PY), in einem eigenen Git-Repo
# mit einem erfundenen Harness-Eintrag. Gegen die Fassung vor dem Fix: A2 und B2
# sind dort rot (der Block steht im Commit bzw. im Status).
#   HARNESS_RUN=<pfad> bash test-rollenblock-nie-im-commit.sh   # Gegenprobe
unset TMUX TMUX_PANE
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_RUN="${HARNESS_RUN:-$HERE/../wb-harness-run}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rollenblock.XXXXXX")"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  case "$TMP" in
    "${TMPDIR:-/tmp}"/rollenblock.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

RUMPF="$TMP/rumpf.py"
awk '/ROLLENZIEL=.*<<.PY.$/ {an=1; next} an && /^PY$/ {exit} an {print}' "$HARNESS_RUN" > "$RUMPF"
[ -s "$RUMPF" ] || { echo "Python-Rumpf in $HARNESS_RUN nicht gefunden"; exit 1; }

printf 'ROLLENTEXT-WORKER\n' > "$TMP/rolle.md"
HJSON="$(printf '{"id":"attrappe","systemPrompt":{"style":"file","worker":"%s","projectPath":"AGENTS.md"}}' "$TMP/rolle.md")"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
printf '[user]\n\tname = Test\n\temail = t@example.invalid\n' > "$GIT_CONFIG_GLOBAL"

einspritzen() { /usr/bin/python3 "$RUMPF" "$HJSON" worker "$1" >/dev/null; }

echo "A) versionierte AGENTS.md"
A="$TMP/a"; mkdir -p "$A"; git -C "$A" init -q
printf '# Projektregeln\n' > "$A/AGENTS.md"; git -C "$A" add AGENTS.md; git -C "$A" commit -q -m init
einspritzen "$A"
grep -q 'wb-rolle worker anfang' "$A/AGENTS.md" && ok "A1 Block steht in der Datei (der Worker liest ihn)" \
  || bad "A1 Block fehlt in der Datei"
echo x > "$A/code.txt"; git -C "$A" add -A; git -C "$A" commit -q -m arbeit
git -C "$A" show HEAD:AGENTS.md | grep -q 'wb-rolle' \
  && bad "A2 Block ist mit 'git add -A' im Commit gelandet" \
  || ok "A2 'git add -A' + commit nimmt den Block nicht mit"
git -C "$A" show HEAD --name-only --format= | grep -qx code.txt \
  && ok "A3 die eigentliche Arbeit ist im Commit" || bad "A3 code.txt fehlt im Commit"

echo "B) keine AGENTS.md im Repo"
B="$TMP/b"; mkdir -p "$B"; git -C "$B" init -q
echo y > "$B/code.txt"; git -C "$B" add code.txt; git -C "$B" commit -q -m init
einspritzen "$B"
[ -f "$B/AGENTS.md" ] && ok "B1 Datei neu angelegt" || bad "B1 keine Datei angelegt"
[ -z "$(git -C "$B" status --porcelain)" ] && ok "B2 git status bleibt leer (Datei ausgeschlossen)" \
  || bad "B2 git status zeigt den Rollenblock" "$(git -C "$B" status --porcelain)"
einspritzen "$B"
[ "$(grep -c '^/AGENTS.md$' "$B/.git/info/exclude")" = 1 ] && ok "B3 zweiter Start traegt nicht doppelt ein" \
  || bad "B3 Ausschluss doppelt oder fehlt" "$(cat "$B/.git/info/exclude")"

echo "C) kein Git-Verzeichnis"
C="$TMP/c"; mkdir -p "$C"
einspritzen "$C" && grep -q 'wb-rolle worker anfang' "$C/AGENTS.md" \
  && ok "C1 ohne Repo wird geschrieben, ohne Fehler" || bad "C1 ohne Repo gescheitert"

echo
echo "test-rollenblock-nie-im-commit: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
