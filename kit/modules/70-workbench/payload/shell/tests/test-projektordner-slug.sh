#!/usr/bin/env bash
# Der Ordnername einer Sitzung unter ~/.claude/projects
#
# WARUM DIESE SUITE (08.08.2026): Zwei Stellen leiten aus einem Arbeitsverzeichnis den
# Namen des Ordners ab, in dem Claude Code das Transkript ablegt -- die Kontextwache
# (letzte Rueckfallquelle, wenn die Statuszeile abgeschnitten ist) und die Auswertung der
# Worker-Antraege (Tokenzahlen je Kind). Beide ersetzten nur den Schraegstrich durch einen
# Bindestrich. Claude Code ersetzt aber JEDES Zeichen ausser [A-Za-z0-9-].
#
# Aufgefallen ist es an einem versteckten Ordner: seit dem 04.08. arbeitet jeder Worker in
# ~/.pi-workers/worktrees/<name>. Die alte Regel ergab "-Users-<user>-.pi-workers-..." statt
# "-Users-<user>--pi-workers-...", der Ordner existierte nicht, und damit war die letzte
# Rueckfallquelle der Wache fuer JEDEN Worker still tot. Sichtbar wurde das erst, als zwei
# Panes ausserdem zu niedrig fuer die Statuszeile waren und der Guard sie als BLIND meldete.
#
# Die Suite fasst nichts Laufendes an: sie prueft die Regel gegen gemessene Paare und
# stellt sicher, dass keine Stelle im Repo zur alten Ersetzung zurueckfaellt.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1   # …/claude-workbench
ok=0; fail=0
pruefe() {  # <name> <erwartet> <ist>
    if [[ "$2" == "$3" ]]; then ok=$((ok+1))
    else fail=$((fail+1)); echo "FAIL $1"; echo "     erwartet: $2"; echo "     ist:      $3"; fi
}

# --- 1. Die Regel selbst, gegen Paare aus dem echten Bestand (08.08.2026 abgelesen) ---
slug() { /usr/bin/python3 -c 'import re,sys; print(re.sub(r"[^A-Za-z0-9-]", "-", sys.argv[1]))' "$1"; }

pruefe "worktree eines Workers (versteckter Ordner)" \
    "-Users-u--pi-workers-worktrees-harness4" \
    "$(slug /Users/u/.pi-workers/worktrees/harness4)"  # Kit: fixed paths, any HOME
pruefe "Projektordner ohne Punkt" \
    "-Users-u-AI" "$(slug /Users/u/AI)"
pruefe "Bindestrich im Namen bleibt stehen" \
    "-Users-u-AI-TTSApp-wt-fix3" "$(slug /Users/u/AI/TTSApp-wt-fix3)"
pruefe "zwei versteckte Ordner hintereinander" \
    "-Users-u--claude-skills" "$(slug /Users/u/.claude-skills)"
pruefe "Unterstrich wird ebenfalls ersetzt" \
    "-tmp-a-b" "$(slug /tmp/a_b)"

# --- 2. Keine Stelle im Repo faellt auf die alte Ersetzung zurueck ---
# Gesucht wird die Form, die NUR den Schraegstrich kennt. Die Testdateien selbst sind
# ausgenommen -- diese hier muss die alte Form zitieren duerfen, um sie zu verbieten.
alt=$(grep -rn 'replace("/", "-")' shell/ 2>/dev/null | grep -v '^shell/tests/' || true)
if [[ -z "$alt" ]]; then ok=$((ok+1)); else
    fail=$((fail+1)); echo "FAIL alte Ersetzung noch im Baum:"; echo "$alt"; fi

# --- 3. Beide bekannten Stellen tragen die neue Regel ---
for f in shell/context-guard shell/wb-request; do
    if grep -q 'A-Za-z0-9-' "$f"; then ok=$((ok+1))
    else fail=$((fail+1)); echo "FAIL $f traegt die Regel nicht"; fi
done

# --- 4. Und sie ist auch ausfuehrbar: der import steht da, wo sie benutzt wird ---
# Ein re.sub ohne "import re" faellt erst zur Laufzeit auf, und zwar in genau dem
# Moment, in dem die Wache gebraucht wird.
if /usr/bin/python3 - <<'PY'
import re, sys
s = open("shell/context-guard").read()
i = s.find('re.sub(r"[^A-Za-z0-9-]"')
if i < 0:
    sys.exit(1)
# der Python-Block, in dem die Zeile steht, beginnt beim letzten <<'PY' davor
b = s.rfind("<<'PY'", 0, i)
sys.exit(0 if b >= 0 and re.search(r"^import .*\bre\b", s[b:i], re.M) else 1)
PY
then ok=$((ok+1)); else fail=$((fail+1)); echo "FAIL context-guard: re.sub ohne import re im selben Block"; fi

echo "== Ergebnis: $ok ok, $fail FAIL =="
[[ $fail -eq 0 ]]
