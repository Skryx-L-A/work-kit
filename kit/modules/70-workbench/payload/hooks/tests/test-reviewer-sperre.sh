#!/usr/bin/env bash
# test-reviewer-sperre.sh -- PreToolUse/Write|Edit|NotebookEdit, /Bash und
# /Skill: haelt die Werkzeug- und Bash-Muster-Sperre einer Rolle mechanisch
# nach (docs/AGENTS-PLAN.md, Abschnitt 4 "Rollen im Team", Absatz "Wie die
# Sperre haelt"; AUFTRAG hooks5, Bau-Schritt 5).
#
# Was hier belegt wird, in dieser Reihenfolge:
#   1. ohne WB_ROLLE passiert nichts, auch bei einem Write ausserhalb
#      jedes moeglichen Ergebnispfads,
#   2. eine Rolle OHNE Schreibsperre laesst Write ueberall zu,
#   3. der Reviewer darf seinen Ergebnispfad schreiben (aus
#      WB_ERGEBNISPFAD, ohne tmux-Pane),
#   4. der Reviewer darf KEINEN anderen Pfad schreiben,
#   5. Bash im Muster der Rolle wird erlaubt,
#   6. Bash ausserhalb des Musters wird verweigert,
#   7. ein Skill aus der Skill-Liste der Rolle wird erlaubt,
#   8. ein fremder Skill wird verweigert,
#   9. eine Rolle mit dem NEUEN Feld schreibsperre: true (nicht
#      "reviewer") bekommt dieselbe Schreibsperre,
#  10. eine Rolle mit leerem bash-Feld bekommt JEDEN Bash-Befehl verweigert
#      ("ohne Treffer Verweigerung"),
#  11. ein nicht auffindbares Profil verweigert FAIL-CLOSED,
#  12. das Settings-Snippet ist gueltiges JSON mit DREI Eintraegen
#      (Write|Edit|NotebookEdit, Bash, Skill),
#  13. hooks/README.md beschreibt den Hook,
#  14. Bau-Schritt 5: ein Lauf bleibt unter zwei Sekunden,
#  15. tmux-Zusage: der Ergebnispfad aus dem Auftragsbuch auftraege.tsv
#      (Worker-Name aus der tmux-Sitzung) gewinnt vor WB_ERGEBNISPFAD, und
#      die Verweigerung eines falschen Pfads kommt aus dem Pane heraus,
#  16. (hooks5 Nr. 2) die Adversarial-Matrix: die Formen des Reviewer-
#      Passes, weitere Formen und Positivfaelle, Symlinks am Ergebnispfad,
#      und die Shell-Huelle Ende zu Ende samt fail-closed-Frist.
#
# ISOLATION: eigenes HOME (mktemp -d), wb-profil aus dem Repo ueber
# PATH-Schirm, kein Modell, kein Netz.
set -uo pipefail
unset TMUX TMUX_PANE

HOOKS_DIR="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
LIB="$HOOKS_DIR/lib/reviewer_sperre.py"
SNIPPET="$HOOKS_DIR/reviewer-sperre.settings-snippet.json"
REPO_ROOT="$(cd -- "$HOOKS_DIR/.." && pwd)"
PASS=0
FAIL=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

command -v python3 >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: python3 fehlt"; exit 77; }
[ -f "$LIB" ] || { echo "UEBERSPRUNGEN: $LIB fehlt"; exit 77; }

TESTHOME="$(mktemp -d)"
BASE="$TESTHOME/base"
ROLLEN="$BASE/.claude/workbench/rollen"
mkdir -p "$ROLLEN" "$TESTHOME/home/.pi-workers/results/reviewer"
export PATH="$REPO_ROOT/shell:$PATH"

trap 'rm -rf "$TESTHOME"; tmux -L wbtest-reviewersperre-$$ kill-server >/dev/null 2>&1 || true' EXIT

cat > "$ROLLEN/reviewer.md" <<'EOF'
---
name: reviewer
description: prueft nur, schreibt nur sein Ergebnis
tools:
  - Read
  - Write
bash:
  - "git diff"
  - "git log"
skills:
  - code-review
stufe: mitglied
absender: werkbank
stand: behalten
---
Reviewer-Prompt.
EOF

cat > "$ROLLEN/laeufer.md" <<'EOF'
---
name: laeufer
description: recherchiert, keine Schreibsperre
tools:
  - Read
  - Write
bash:
  - "curl"
skills:
  - recherche
stufe: mitglied
absender: werkbank
stand: behalten
---
Laeufer-Prompt.
EOF

cat > "$ROLLEN/sperrrolle.md" <<'EOF'
---
name: sperrrolle
description: eine andere Rolle mit Schreibsperre ueber das neue Feld
tools:
  - Read
  - Write
bash: []
skills: []
stufe: mitglied
schreibsperre: true
absender: werkbank
stand: behalten
---
Sperrrolle-Prompt.
EOF

cat > "$ROLLEN/echoer.md" <<'EOF'
---
name: echoer
description: prueft verschachtelte Bash-Formen
tools:
  - Read
bash:
  - "echo"
skills: []
stufe: mitglied
absender: werkbank
stand: behalten
---
Echoer-Prompt.
EOF

for wrapper in env nice nohup command builtin exec time xargs; do
  cat > "$ROLLEN/${wrapper}rolle.md" <<EOF
---
name: ${wrapper}rolle
description: darf keinen generischen Wrapper freigeben
tools:
  - Read
bash:
  - "${wrapper}"
skills: []
stufe: mitglied
absender: werkbank
stand: behalten
---
Wrapper-Prompt.
EOF
done

ERGEBNIS="$TESTHOME/home/.pi-workers/results/reviewer/ergebnis.md"
ANDERER_PFAD="$BASE/pfusch.md"

# ------------------------------------------------------------- Helfer --
write_json() { # <ziel> <file_path>
  python3 - "$1" "$2" <<'PY'
import json, sys
ziel, file_path = sys.argv[1:3]
daten = {"session_id": "sess", "hook_event_name": "PreToolUse", "tool_name": "Write",
         "tool_input": {"file_path": file_path, "content": "x"}, "cwd": "/tmp"}
open(ziel, "w").write(json.dumps(daten))
PY
}

bash_json() { # <ziel> <command>
  python3 - "$1" "$2" <<'PY'
import json, sys
ziel, command = sys.argv[1:3]
daten = {"session_id": "sess", "hook_event_name": "PreToolUse", "tool_name": "Bash",
         "tool_input": {"command": command}, "cwd": "/tmp"}
open(ziel, "w").write(json.dumps(daten))
PY
}

skill_json() { # <ziel> <skill>
  python3 - "$1" "$2" <<'PY'
import json, sys
ziel, skill = sys.argv[1:3]
daten = {"session_id": "sess", "hook_event_name": "PreToolUse", "tool_name": "Skill",
         "tool_input": {"skill": skill}}
open(ziel, "w").write(json.dumps(daten))
PY
}

lauf() { # <input-datei> <rolle> [ergebnispfad]
  local input="$1" rolle="$2" ergebnis="${3:-}"
  HOME="$TESTHOME/home" WB_AUFGABE_ID="t1" WB_ROLLE="$rolle" WB_AUFGABE_BASE="$BASE" WB_ERGEBNISPFAD="$ergebnis" \
    TMUX_PANE= python3 "$LIB" < "$input" 2>"$TESTHOME/stderr"
}

ist_deny() { grep -q '"permissionDecision": "deny"' "$1"; }

# -------------------------------------------------------- Fall 1 --------
section "1: ohne WB_ROLLE -- nichts passiert"
write_json "$TESTHOME/in1.json" "$ANDERER_PFAD"
HOME="$TESTHOME/home" TMUX_PANE= python3 "$LIB" < "$TESTHOME/in1.json" > "$TESTHOME/out1" 2>/dev/null
[ ! -s "$TESTHOME/out1" ] && ok "1: kein JSON ohne WB_ROLLE" || bad "1: Ausgabe trotz fehlender Rolle: $(cat "$TESTHOME/out1")"

section "1b: WB_ROLLE ohne gueltige WB_AUFGABE_ID bleibt vollstaendig unberuehrt"
HOME="$TESTHOME/home" WB_ROLLE="reviewer" WB_AUFGABE_BASE="$BASE" WB_ERGEBNISPFAD="$ERGEBNIS" \
  TMUX_PANE= python3 "$LIB" < "$TESTHOME/in1.json" > "$TESTHOME/out1b" 2>/dev/null
[ ! -s "$TESTHOME/out1b" ] && ok "1b: keine Ausgabe ohne Aufgabenkennung" || bad "1b: Ausgabe ohne Aufgabenkennung: $(cat "$TESTHOME/out1b")"

# -------------------------------------------------------- Fall 2 --------
section "2: Rolle OHNE Schreibsperre laesst Write ueberall zu"
write_json "$TESTHOME/in2.json" "$ANDERER_PFAD"
lauf "$TESTHOME/in2.json" "laeufer" "" > "$TESTHOME/out2"
[ ! -s "$TESTHOME/out2" ] && ok "2: laeufer schreibt ueberall -> allow" || bad "2: laeufer wurde eingeschraenkt: $(cat "$TESTHOME/out2")"

# -------------------------------------------------------- Fall 3 --------
section "3: Reviewer darf seinen Ergebnispfad schreiben"
write_json "$TESTHOME/in3.json" "$ERGEBNIS"
lauf "$TESTHOME/in3.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out3"
[ ! -s "$TESTHOME/out3" ] && ok "3: Ergebnispfad -> allow" || bad "3: Ergebnispfad wurde verweigert: $(cat "$TESTHOME/out3")"

# -------------------------------------------------------- Fall 4 --------
section "4: Reviewer darf KEINEN anderen Pfad schreiben"
write_json "$TESTHOME/in4.json" "$ANDERER_PFAD"
lauf "$TESTHOME/in4.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out4"
ist_deny "$TESTHOME/out4" && ok "4: anderer Pfad -> deny" || bad "4: kein deny: $(cat "$TESTHOME/out4")"

# -------------------------------------------------------- Fall 5 --------
section "5: Bash im Muster der Rolle wird erlaubt"
bash_json "$TESTHOME/in5.json" "git diff --stat"
lauf "$TESTHOME/in5.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out5"
[ ! -s "$TESTHOME/out5" ] && ok "5: 'git diff' im Muster -> allow" || bad "5: Bash im Muster verweigert: $(cat "$TESTHOME/out5")"

# -------------------------------------------------------- Fall 6 --------
section "6: Bash ausserhalb des Musters wird verweigert"
bash_json "$TESTHOME/in6.json" "rm -rf /tmp/x"
lauf "$TESTHOME/in6.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out6"
ist_deny "$TESTHOME/out6" && ok "6: 'rm -rf' ausserhalb Muster -> deny" || bad "6: kein deny: $(cat "$TESTHOME/out6")"

# -------------------------------------------------------- Fall 7 --------
section "7: ein Skill aus der Skill-Liste wird erlaubt"
skill_json "$TESTHOME/in7.json" "code-review"
lauf "$TESTHOME/in7.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out7"
[ ! -s "$TESTHOME/out7" ] && ok "7: erlaubter Skill -> allow" || bad "7: erlaubter Skill verweigert: $(cat "$TESTHOME/out7")"

# -------------------------------------------------------- Fall 8 --------
section "8: ein fremder Skill wird verweigert"
skill_json "$TESTHOME/in8.json" "neue-projekte"
lauf "$TESTHOME/in8.json" "reviewer" "$ERGEBNIS" > "$TESTHOME/out8"
ist_deny "$TESTHOME/out8" && ok "8: fremder Skill -> deny" || bad "8: kein deny: $(cat "$TESTHOME/out8")"

# -------------------------------------------------------- Fall 9 --------
section "9: Rolle mit Feld schreibsperre: true (nicht 'reviewer') -> dieselbe Sperre"
write_json "$TESTHOME/in9.json" "$ANDERER_PFAD"
lauf "$TESTHOME/in9.json" "sperrrolle" "$ERGEBNIS" > "$TESTHOME/out9"
ist_deny "$TESTHOME/out9" && ok "9: schreibsperre:true greift wie beim Reviewer" || bad "9: kein deny: $(cat "$TESTHOME/out9")"

# -------------------------------------------------------- Fall 10 -------
section "10: leeres bash-Feld verweigert JEDEN Befehl"
bash_json "$TESTHOME/in10.json" "echo hallo"
lauf "$TESTHOME/in10.json" "sperrrolle" "$ERGEBNIS" > "$TESTHOME/out10"
ist_deny "$TESTHOME/out10" && ok "10: leeres bash-Feld -> jeder Befehl deny" || bad "10: kein deny bei leerem bash-Feld: $(cat "$TESTHOME/out10")"

# -------------------------------------------------------- Fall 11 -------
section "11: nicht auffindbares Profil -> FAIL-CLOSED deny"
write_json "$TESTHOME/in11.json" "$ERGEBNIS"
lauf "$TESTHOME/in11.json" "gibtsnicht" "$ERGEBNIS" > "$TESTHOME/out11"
ist_deny "$TESTHOME/out11" && ok "11: unbekannte Rolle -> fail-closed deny" || bad "11: kein deny bei unbekannter Rolle: $(cat "$TESTHOME/out11")"

# -------------------------------------------------------- Fall 12 -------
section "12: Settings-Snippet ist gueltiges JSON mit DREI Eintraegen"
if python3 -c "
import json
d = json.load(open('$SNIPPET'))
hooks = d['hooks']['PreToolUse']
assert len(hooks) == 3, hooks
matcher = sorted(h['matcher'] for h in hooks)
assert matcher == ['Bash', 'Skill', 'Write|Edit|NotebookEdit'], matcher
for h in hooks:
    assert 'reviewer-sperre.sh' in h['hooks'][0]['command']
" 2>"$TESTHOME/snippet-err"; then
  ok "12: Snippet gueltig, drei Eintraege"
else
  bad "12: Snippet ungueltig: $(cat "$TESTHOME/snippet-err")"
fi

# -------------------------------------------------------- Fall 13 -------
section "13: hooks/README.md beschreibt den Hook"
grep -q "reviewer-sperre" "$HOOKS_DIR/README.md" && ok "13: README beschreibt den Hook" \
                                                   || bad "13: README ohne Absatz zum Hook"

# -------------------------------------------------------- Fall 14 -------
section "14: Bau-Schritt 5 -- unter zwei Sekunden (gemessen, nicht behauptet)"
DAUER_MS="$(python3 - "$LIB" "$TESTHOME/in6.json" <<'PY'
import subprocess, sys, time, os
lib, eingabe = sys.argv[1:3]
env = dict(os.environ, WB_AUFGABE_ID="t1", WB_ROLLE="reviewer", WB_AUFGABE_BASE=os.environ.get("BASE", ""))
start = time.monotonic()
with open(eingabe, "rb") as f:
    subprocess.run(["python3", lib], stdin=f, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, env=env)
print(int((time.monotonic() - start) * 1000))
PY
)"
if [ "$DAUER_MS" -lt 2000 ]; then
  ok "14: ein Lauf braucht ${DAUER_MS}ms (< 2000ms)"
else
  bad "14: ein Lauf braucht ${DAUER_MS}ms (>= 2000ms)"
fi

# -------------------------------------------------------- Fall 15 -------
if command -v tmux >/dev/null 2>&1; then
  section "15: tmux -- auftraege.tsv gewinnt vor WB_ERGEBNISPFAD, Verweigerung aus dem Pane"
  TXSOCK="wbtest-reviewersperre-$$"
  TXHOME="$TESTHOME/home"
  SITZUNG="revsperre$$"
  TSVDIR="$TXHOME/.pi-workers/results/$SITZUNG"
  mkdir -p "$TSVDIR"
  AUS_TSV="$TSVDIR/aus-tsv.md"
  printf '# ts\tresult\tpane\tharness\tmodel\tspawned\n' > "$TSVDIR/auftraege.tsv"
  printf '2026-09-10T00:00:00Z\t%s\tpane\tclaude\topus5\t1\n' "$AUS_TSV" >> "$TSVDIR/auftraege.tsv"

  write_json "$TESTHOME/tmux-in-ok.json" "$AUS_TSV"
  write_json "$TESTHOME/tmux-in-falsch.json" "$ERGEBNIS"   # WB_ERGEBNISPFAD, aber auftraege.tsv muss gewinnen
  TSCHIRM="$TESTHOME/tmux-schirm.sh"
  cat > "$TSCHIRM" <<EOF
#!/bin/bash
python3 "$LIB" < "$TESTHOME/tmux-in-ok.json" > "$TESTHOME/tmux-out-ok" 2>"$TESTHOME/tmux-err-ok"
python3 "$LIB" < "$TESTHOME/tmux-in-falsch.json" > "$TESTHOME/tmux-out-falsch" 2>"$TESTHOME/tmux-err-falsch"
touch "$TESTHOME/tmux-fertig"
EOF
  chmod +x "$TSCHIRM"
  rm -f "$TESTHOME/tmux-fertig"
  (
    export HOME="$TXHOME" WB_AUFGABE_ID="t1" WB_ROLLE="reviewer" WB_AUFGABE_BASE="$BASE" WB_ERGEBNISPFAD="$ERGEBNIS"
    unset TMUX TMUX_PANE
    tmux -L "$TXSOCK" new-session -d -s "$SITZUNG" -x 120 -y 40 "bash $TSCHIRM"
  ) >/dev/null 2>&1
  fertig=0
  for _ in $(seq 1 100); do
    [ -f "$TESTHOME/tmux-fertig" ] && { fertig=1; break; }
    sleep 0.2
  done
  if [ "$fertig" = "1" ] && [ ! -s "$TESTHOME/tmux-out-ok" ] && ist_deny "$TESTHOME/tmux-out-falsch"; then
    ok "15: auftraege.tsv-Pfad erlaubt, WB_ERGEBNISPFAD-Pfad verweigert -- auftraege.tsv gewinnt, aus dem Pane heraus"
  else
    bad "15: tmux-Fall nicht wie erwartet (fertig=$fertig ok=$(cat "$TESTHOME/tmux-out-ok" 2>/dev/null) falsch=$(cat "$TESTHOME/tmux-out-falsch" 2>/dev/null) err=$(cat "$TESTHOME/tmux-err-ok" 2>/dev/null | head -1))"
  fi
  tmux -L "$TXSOCK" kill-server >/dev/null 2>&1 || true
else
  printf '  SKIP  tmux fehlt -- tmux-Fall uebersprungen\n'
fi

# ---------------------------------------------------------------------------
# Adversarial-Matrix (AUFTRAG hooks5 Nr. 2): die Formen des Reviewer-Passes
# (R01-R28 -- der Pass nennt 29, seine Tabelle zaehlt 9 + 19 = 28
# verschiedene Formen auf), dazu Formen, die beim Umbau selbst auffielen
# (X..). Gesperrt heisst: deny-JSON mit einer Begruendung, die die Form
# nennt. Die Befehle laufen nie, der Hook bekommt nur ihr PreToolUse-JSON.
for spec in "globrolle|git diff *|npm run test*" "regexrolle|git.*" "bashrolle|bash|echo"; do
  rolle="${spec%%|*}"
  IFS='|' read -ra teile <<< "${spec#*|}"
  {
    printf -- '---\nname: %s\ndescription: Matrix-Rolle\ntools:\n  - Read\nbash:\n' "$rolle"
    for m in "${teile[@]}"; do printf '  - "%s"\n' "$m"; done
    printf 'skills: []\nstufe: mitglied\nabsender: werkbank\nstand: behalten\n---\nMatrix-Prompt.\n'
  } > "$ROLLEN/$rolle.md"
done

MATRIX_NR=0
rf() { # rf <deny|allow> <rolle> <name> <befehl> [muss-im-grund-stehen]
  local erwartung="$1" rolle="$2" name="$3" befehl="$4" pflicht="${5:-}" nr out grund
  MATRIX_NR=$((MATRIX_NR + 1)); nr=$MATRIX_NR; out="$TESTHOME/rmatrix-$nr.out"
  bash_json "$TESTHOME/rmatrix-$nr.json" "$befehl"
  lauf "$TESTHOME/rmatrix-$nr.json" "$rolle" "$ERGEBNIS" > "$out"
  grund="$(sed -n 's/.*"permissionDecisionReason": "Role lock (role [^)]*): \(.*\) -- without a match.*/\1/p' "$out")"
  if [ "$erwartung" = deny ]; then
    if ist_deny "$out" && [ -n "$grund" ] && { [ -z "$pflicht" ] || grep -q "$pflicht" "$out"; }; then
      ok "$name [$rolle] -> deny ($grund)"
    else
      bad "$name [$rolle] nicht wie erwartet gesperrt: $(cat "$out")"
    fi
  elif [ ! -s "$out" ]; then
    ok "$name [$rolle] -> allow"
  else
    bad "$name [$rolle] verweigert: $(cat "$out")"
  fi
}

section "Adversarial-Matrix: Bash-Formen aus dem Reviewer-Pass"
rf deny  reviewer   "R01 Semikolon"             "git diff --stat; rm /tmp/x"
rf deny  reviewer   "R02 &&"                    "git diff --stat && rm /tmp/x"
rf deny  reviewer   "R03 Pipeline"              "git diff --stat | rm /tmp/x"
rf deny  reviewer   "R04 Zeilenumbruch"         $'git diff --stat\nrm /tmp/x'
rf deny  echoer     "R05 Anker-Teilstring"      "echoevil hallo"
rf deny  regexrolle "R06 Regexzeichen im Profil" "gitxyz --stat"
rf allow reviewer   "R07 git diff --stat"       "git diff --stat"
rf allow echoer     "R10 aeusseres echo"        "echo hallo"
rf deny  echoer     "R11 \$( )"                 "echo \$(rm /tmp/x)"
rf deny  echoer     "R12 Backticks"             "echo \`rm /tmp/x\`"
rf deny  echoer     "R13 zitierte Substitution" "echo \"\$(rm /tmp/x)\""
rf deny  echoer     "R14 Python-Substitution"   "echo \$(python3 -c \"import os; os.remove('/tmp/x')\")"
rf deny  echoer     "R15 bash -c"               "bash -c 'rm /tmp/x'"
rf deny  echoer     "R16 Bash-Here-Doc"         $'bash <<\'EOF\'\nrm /tmp/x\nEOF'
rf deny  envrolle   "R17 env"                   "env rm /tmp/x"          "generische"
rf deny  envrolle   "R18 env X=..."             "env X=1 rm /tmp/x"      "generische"
rf deny  nicerolle  "R19 nice"                  "nice rm /tmp/x"         "generische"
rf deny  nohuprolle "R20 nohup"                 "nohup rm /tmp/x"        "generische"
rf deny  commandrolle "R21 command"             "command rm /tmp/x"      "generische"
rf deny  builtinrolle "R22 builtin"             "builtin rm /tmp/x"      "generische"
rf deny  execrolle  "R23 exec"                  "exec rm /tmp/x"         "generische"
rf deny  echoer     "R24 Umleitung >"           "echo x > /tmp/verboten"
rf deny  echoer     "R25 Umleitung >>"          "echo x >> /tmp/verboten"

section "Weitere Formen (beim Umbau gefunden) und Positivfaelle"
rf deny  timerolle  "X01 time"                  "time rm /tmp/x"         "generische"
rf deny  xargsrolle "X02 xargs als Muster"      "printf x | xargs rm"    "generische"
rf deny  echoer     "X03 xargs mit rm"          "echo x | xargs rm"
rf allow echoer     "X04 xargs mit echo"        "echo x | xargs echo"
rf deny  echoer     "X05 bash -lc"              "bash -lc 'rm /tmp/x'"
rf deny  echoer     "X06 nice -n 5"             "nice -n 5 rm /tmp/x"
rf deny  echoer     "X07 IFS-Expansion"         "r\${IFS}m /tmp/x"
rf deny  echoer     "X08 gequotetes << davor"   $'echo "<<X"\nrm /tmp/x'
rf deny  echoer     "X09 Kommentar davor"       $'echo a # <<X\nrm /tmp/x'
rf deny  echoer     "X10 Here-String an bash"   "bash <<< 'rm /tmp/x'"
rf deny  echoer     "X11 eval"                  "eval 'rm /tmp/x'"
rf deny  echoer     "X12 env -S"                "env -S 'rm /tmp/x'"
rf deny  echoer     "X13 Arithmetik mit \$( )"  "echo \$(( \$(rm /tmp/x) + 1 ))"
rf deny  globrolle  "X14 Anker hinter Glob"     "git diffevil"
rf deny  bashrolle  "X15 nackter Interpreter"   "bash boese.sh"          "generische"
rf allow echoer     "X16 Umleitung auf den Ergebnispfad" "echo x > $ERGEBNIS"
rf allow echoer     "X17 Umleitung nach /dev/null" "echo x 2>/dev/null"
rf allow echoer     "X18 Arithmetik"            "echo \$((1 + 2))"
rf allow globrolle  "X19 Glob-Muster mit Argumenten" "git diff --stat HEAD~1"
rf allow globrolle  "X20 Glob-Muster ohne Argument"  "git diff"
rf allow globrolle  "X21 Glob mitten im Wort"   "npm run test:unit"
rf allow bashrolle  "X22 gueltiges Muster neben generischem" "echo ok"
rf deny  reviewer   "X23 unzerlegbar"           "'unterbrochen"
rf deny  echoer     "X27 Funktionsdefinition"   "f(){ rm /tmp/x; }; f"
rf deny  echoer     "X28 bash <( )"             "bash <(echo 'rm /tmp/x')" "process substitution"
rf deny  echoer     "X29 source <( )"           "source <(echo 'rm /tmp/x')" "process substitution"
rf deny  echoer     "X30 (echo) | bash"         "(echo 'rm /tmp/x') | bash"
rf allow echoer     "X31 Unterschale vor erlaubter Pipe" "(echo a) | echo b"
rf allow echoer     "X32 <( ) als Argument"     "echo <(echo a)"

section "Adversarial-Matrix: Skill, Write und Ergebnispfad"
LINK_ERGEBNIS="$TESTHOME/home/.pi-workers/results/reviewer/link.md"
ln -s "$ANDERER_PFAD" "$LINK_ERGEBNIS"
mkdir -p "$TESTHOME/home/.pi-workers/results/fremd"
: > "$TESTHOME/home/.pi-workers/results/fremd/ergebnis.md"
FREMD_LINK="$TESTHOME/home/.pi-workers/results/reviewer/fremd.md"
ln -s "$TESTHOME/home/.pi-workers/results/fremd/ergebnis.md" "$FREMD_LINK"
sonder() { # sonder <deny|allow|leer> <name> <json> <ergebnispfad> [ohne-aufgabe]
  local erwartung="$1" name="$2" json="$3" ergebnis="$4" out="$TESTHOME/sonder-$RANDOM.out"
  if [ -n "${5:-}" ]; then
    HOME="$TESTHOME/home" WB_AUFGABE_ID="$5" WB_ROLLE="reviewer" WB_AUFGABE_BASE="$BASE" \
      WB_ERGEBNISPFAD="$ergebnis" TMUX_PANE= python3 "$LIB" < "$json" > "$out" 2>/dev/null
  else
    lauf "$json" reviewer "$ergebnis" > "$out"
  fi
  case "$erwartung" in
    deny)  ist_deny "$out" && ok "$name -> deny" || bad "$name nicht gesperrt: $(cat "$out")" ;;
    *)     [ ! -s "$out" ] && ok "$name -> keine Ausgabe (allow)" || bad "$name gab aus: $(cat "$out")" ;;
  esac
}
skill_json "$TESTHOME/s-fremd.json" "neue-projekte"
skill_json "$TESTHOME/s-ok.json" "code-review"
write_json "$TESTHOME/w-anders.json" "$ANDERER_PFAD"
write_json "$TESTHOME/w-ergebnis.json" "$ERGEBNIS"
write_json "$TESTHOME/w-link.json" "$LINK_ERGEBNIS"
write_json "$TESTHOME/w-fremd.json" "$FREMD_LINK"
sonder deny  "R08 fremder Skill"                      "$TESTHOME/s-fremd.json"    "$ERGEBNIS"
sonder deny  "R09 Write ausserhalb des Ergebnispfads" "$TESTHOME/w-anders.json"   "$ERGEBNIS"
sonder allow "R26 erlaubter Skill"                    "$TESTHOME/s-ok.json"       "$ERGEBNIS"
sonder allow "R27 erlaubter Ergebnis-Write"           "$TESTHOME/w-ergebnis.json" "$ERGEBNIS"
sonder deny  "R28 Symlink-Ergebnis nach aussen"       "$TESTHOME/w-link.json"     "$LINK_ERGEBNIS"
sonder deny  "X24 Symlink auf fremdes Ergebnis"       "$TESTHOME/w-fremd.json"    "$FREMD_LINK"
sonder deny  "X25 Ergebnispfad ausserhalb results/"   "$TESTHOME/w-anders.json"   "$ANDERER_PFAD"
sonder leer  "X26 ungueltige WB_AUFGABE_ID"           "$TESTHOME/w-anders.json"   "$ERGEBNIS" "../x"

# ---------------------------------------------------------------------------
section "Huelle reviewer-sperre.sh: Ende zu Ende, Frist fail-closed"
ECHTES_PYTHON="$(command -v python3)"  # der Messlaeufer darf nie der gefaelschte sein
huelle() { # huelle <input> <output> [PATH-Vorsatz] [WB_AUFGABE_ID] -> Dauer in ms
  HOME="$TESTHOME/home" WB_AUFGABE_ID="${4-t1}" WB_ROLLE="reviewer" WB_AUFGABE_BASE="$BASE" \
    WB_ERGEBNISPFAD="$ERGEBNIS" TMUX_PANE= PATH="${3:+$3:}$PATH" \
    "$ECHTES_PYTHON" - "$HOOKS_DIR/reviewer-sperre.sh" "$1" "$2" <<'PY'
import subprocess, sys, time
huelle, eingabe, ausgabe = sys.argv[1:4]
start = time.monotonic()
with open(eingabe, "rb") as f:
    # Ueber eine Pipe gelesen, wie Claude Code es tut: gemessen wird bis
    # zum Ende der Ausgabe, nicht nur bis zum Ende des Prozesses.
    r = subprocess.run(["bash", huelle], stdin=f, capture_output=True)
open(ausgabe, "wb").write(r.stdout)
print(int((time.monotonic() - start) * 1000))
PY
}
bash_json "$TESTHOME/h-deny.json" "rm -rf /tmp/x"
bash_json "$TESTHOME/h-allow.json" "git diff --stat"
huelle "$TESTHOME/h-deny.json" "$TESTHOME/h-deny.out" >/dev/null
ist_deny "$TESTHOME/h-deny.out" && ok "E1 Huelle reicht stdin durch und verweigert rm" \
                                || bad "E1 Huelle verweigert nicht: $(cat "$TESTHOME/h-deny.out")"
H_MS="$(huelle "$TESTHOME/h-allow.json" "$TESTHOME/h-allow.out")"
if [ ! -s "$TESTHOME/h-allow.out" ] && [ "$H_MS" -lt 2000 ]; then
  ok "E2 erlaubter Befehl durch die Huelle: keine Ausgabe, ${H_MS}ms bis Ausgabe-Ende (< 2000ms)"
else
  bad "E2 erlaubter Befehl: ${H_MS}ms, Ausgabe: $(cat "$TESTHOME/h-allow.out")"
fi
huelle "$TESTHOME/h-deny.json" "$TESTHOME/h-ohne.out" "" "" >/dev/null
[ ! -s "$TESTHOME/h-ohne.out" ] && ok "E3 ohne WB_AUFGABE_ID keine Ausgabe" \
                                 || bad "E3 Ausgabe ohne Aufgabe: $(cat "$TESTHOME/h-ohne.out")"

FAKEBIN="$TESTHOME/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/python3" <<EOF
#!/bin/bash
echo \$\$ > "$TESTHOME/fake.pid"
sleep 30 &
echo \$! > "$TESTHOME/fake-kind.pid"
wait
EOF
chmod +x "$FAKEBIN/python3"
H_MS="$(huelle "$TESTHOME/h-allow.json" "$TESTHOME/h-frist.out" "$FAKEBIN")"
sleep 0.5
FAKE_PID="$(cat "$TESTHOME/fake.pid" 2>/dev/null)"
KIND_PID="$(cat "$TESTHOME/fake-kind.pid" 2>/dev/null)"
if ist_deny "$TESTHOME/h-frist.out" && [ "$H_MS" -lt 9500 ]; then
  ok "E4 haengender Kern: deny-JSON nach ${H_MS}ms (vor der 10-s-Grenze des Settings-Eintrags)"
else
  bad "E4 haengender Kern: kein rechtzeitiger deny (${H_MS}ms, Ausgabe: $(cat "$TESTHOME/h-frist.out"))"
fi
if [ -n "$FAKE_PID" ] && [ -n "$KIND_PID" ] && ! kill -0 "$FAKE_PID" 2>/dev/null && ! kill -0 "$KIND_PID" 2>/dev/null; then
  ok "E4 Kern und sein Kindprozess sind beendet (Prozessgruppe)"
else
  bad "E4 Prozesse leben noch (kern=$FAKE_PID kind=$KIND_PID)"
  kill "$FAKE_PID" "$KIND_PID" 2>/dev/null
fi
printf '#!/bin/bash\ncat >/dev/null\nexit 3\n' > "$FAKEBIN/python3"
huelle "$TESTHOME/h-allow.json" "$TESTHOME/h-status.out" "$FAKEBIN" >/dev/null
grep -q "status 3" "$TESTHOME/h-status.out" && ok "E5 Kern bricht ohne Entscheidung ab -> deny" \
                                           || bad "E5 Abbruch des Kerns kam durch: $(cat "$TESTHOME/h-status.out")"

printf '\n======================================================================\n'
printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
