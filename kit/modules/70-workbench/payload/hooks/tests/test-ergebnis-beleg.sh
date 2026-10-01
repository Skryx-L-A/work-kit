#!/usr/bin/env bash
# test-ergebnis-beleg.sh -- PreToolUse/Write|Edit: verweigert eine
# Ergebnisdatei ohne Beleg (docs/AGENTS-PLAN.md, Abschnitt 4 "Vergeben und
# pruefen"; AUFTRAG hooks5, Bau-Schritt 5).
#
# Was hier belegt wird, in dieser Reihenfolge:
#   1. ohne WB_AUFGABE_ID passiert nichts (kein JSON, Exit 0) -- auch bei
#      einem Ziel unter ~/.pi-workers/results/,
#   2. ein Write auf einen Pfad, der weder unter ~/.pi-workers/results/
#      liegt noch der Ergebnispfad der Aufgabe ist, bleibt unberuehrt,
#   3. ein Write auf einen Worker-Ergebnispfad OHNE jeden Beleg im
#      Transkript wird verweigert (deny, deutsche Begruendung),
#   4. ein Read auf eine namensgleiche, leere Datei (*.log mit tool_result)
#      ist KEIN Beleg -- seit hooks5 Nr. 2 zaehlt kein Read,
#   5. derselbe Write MIT einem abgeschlossenen Testlauf (Bash "pytest ..."
#      mit tool_result) wird erlaubt,
#   6. ein Bash-Testlauf OHNE tool_result (nicht abgeschlossen) zaehlt
#      nicht als Beleg -- weiterhin verweigert,
#   7. ein gelesener Datei, deren Name auf keins der Muster passt (z.B.
#      notizen.md), zaehlt nicht als Beleg,
#   8. der Ergebnispfad DES HAUPTAGENTEN (verlauf.ergebnis.pfad) mit
#      vollstaendig gelaufenen gate_commands wird erlaubt,
#   9. derselbe Pfad mit einem FEHLENDEN Gate-Befehl wird verweigert und
#      nennt den fehlenden Befehl,
#  10. ohne gate_commands (leere Liste) gibt es nichts zu belegen -- erlaubt,
#  11. Edit wird genauso geprueft wie Write,
#  12. das Settings-Snippet ist gueltiges JSON mit dem PreToolUse-Eintrag,
#  13. hooks/README.md beschreibt den Hook,
#  14. tmux-Zusage (Bau-Schritt 5): auf eigenem Socket startet ein Pane mit
#      WB_AUFGABE_ID in der Umgebung, der Hook liest das JSON von stdin wie
#      Claude Code es taete, die Verweigerung kommt aus dem Pane heraus,
#  16. (hooks5 Nr. 2) ein roter Lauf mit "Exit code N" zaehlt, ein
#      abgelehnter Aufruf und ein Read auf ein volles Log nicht; `cd x &&`
#      vor dem Testskript schadet nicht,
#  17. die Zustandsdatei schreibt fort: ein spaeter nachgereichtes Ergebnis
#      zaehlt,
#  18. ein Testlauf am Anfang eines 12-MB-Transkripts zaehlt, beide Aufrufe
#      unter zwei Sekunden.
#
# ISOLATION: eigenes HOME (mktemp -d), wb-aufgabe aus dem Repo ueber
# PATH-Schirm, kein Modell, kein Netz, kein Schreiben ausserhalb des
# Test-HOMEs. HOOKS_DIR waehlt den Pruefling wie in den uebrigen Suiten.
set -uo pipefail
unset TMUX TMUX_PANE

HOOKS_DIR="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
LIB="$HOOKS_DIR/lib/ergebnis_beleg.py"
SNIPPET="$HOOKS_DIR/ergebnis-beleg-gate.settings-snippet.json"
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
WORKTREE="$TESTHOME/worktree"
mkdir -p "$BASE/.claude/workbench/vorrat" "$WORKTREE" "$TESTHOME/home/.pi-workers/results/hooks5test"
export PATH="$REPO_ROOT/shell:$PATH"

trap 'rm -rf "$TESTHOME"; tmux -L wbtest-ergebnisbeleg-$$ kill-server >/dev/null 2>&1 || true' EXIT

RESULT_PFAD="$TESTHOME/home/.pi-workers/results/hooks5test/out.md"
NORMAL_PFAD="$WORKTREE/notizen.md"

# ------------------------------------------------------------- Helfer --
aufgabe_setzen() { # <id> <gate_commands,komma,getrennt> <ergebnis_pfad_oder_leer>
  local id="$1" gates="$2" ergebnis="${3:-}"
  python3 - "$id" "$gates" "$ergebnis" "$BASE" <<'PY'
import json, os, sys
id_, gates_roh, ergebnis, base = sys.argv[1:5]
gates = [g for g in gates_roh.split("||") if g]
projekt = os.path.join(base, "projekt")
auftraege = os.path.join(projekt, ".companion", "auftraege")
os.makedirs(auftraege, exist_ok=True)
os.makedirs(os.path.join(base, ".claude", "workbench", "vorrat"), exist_ok=True)
auftrag_pfad = os.path.join(auftraege, "%s.json" % id_)
verlauf_pfad = os.path.join(auftraege, "%s.verlauf.json" % id_)
auftrag = {"schema_version": 1, "id": id_, "project": projekt,
           "goal": "Testaufgabe", "done_criterion": "Suite gruen",
           "reference": None, "guardrails": [], "gate_commands": gates,
           "limits": {"iterations": None, "tokens": None, "time_seconds": None},
           "loop_type": "loop", "model": "opus5", "approval": None,
           "freigaben": {}, "hauptagent": {"model": "opus5", "effort": "high",
                                           "fallback": None},
           "maschine": "mac", "grenzen": {}}
verlauf = {"id": id_, "stand": "laeuft", "grund": "", "maschine": "mac",
           "worker": [], "team": [], "verlauf": [],
           "ergebnis": {"pfad": ergebnis or None, "commit": None, "belege": [],
                        "reviewer_befunde": []},
           "kosten": {"token_schaetzung": None, "lokale_stunden": None},
           "wiederaufnahme": "", "weckzeit": None, "frage": None, "pfade": []}
with open(auftrag_pfad, "w") as f: json.dump(auftrag, f)
with open(verlauf_pfad, "w") as f: json.dump(verlauf, f)
vorrat = {"rang": 1, "projekt": projekt, "auftrag": auftrag_pfad,
          "maschine": "mac", "aufgenommen": "2026-09-10T00:00:00Z"}
with open(os.path.join(base, ".claude", "workbench", "vorrat", "%s.json" % id_), "w") as f:
    json.dump(vorrat, f)
PY
}

transkript_schreiben() { # <datei> <fall>
  local datei="$1" fall="$2"
  python3 - "$datei" "$fall" <<'PY'
import json, sys
datei, fall = sys.argv[1:3]
zeilen = []
ende = "\n"
def tool_use(id_, name, input_):
    return {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "tool_use", "id": id_, "name": name, "input": input_}]}}
def tool_result(id_, content="ok", is_error=False):
    return {"type": "user", "message": {"role": "user",
            "content": [{"type": "tool_result", "tool_use_id": id_, "content": content,
                         "is_error": is_error}]}}

if fall == "leer":
    pass
elif fall == "read-log-belegt":
    zeilen = [tool_use("t1", "Read", {"file_path": "hooks/tests/lauf.log"}), tool_result("t1")]
elif fall == "read-falscher-name":
    zeilen = [tool_use("t1", "Read", {"file_path": "notizen.md"}), tool_result("t1")]
elif fall == "bash-pytest-belegt":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}), tool_result("t1")]
elif fall == "bash-pytest-unbelegt":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"})]
elif fall == "bash-pytest-leer":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}), tool_result("t1", "")]
elif fall == "bash-pytest-fehler":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}), tool_result("t1", "failed", True)]
elif fall == "bash-abgelehnt":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}),
              tool_result("t1", "Permission to use Bash has been denied.", True)]
elif fall == "bash-exit-code":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}),
              tool_result("t1", "Exit code 1\n2 failed, 3 passed", True)]
elif fall == "read-log-voll":
    zeilen = [tool_use("t1", "Read", {"file_path": "hooks/tests/lauf.log"}), tool_result("t1", "PASS: 3  FAIL: 0")]
elif fall == "cd-testskript":
    zeilen = [tool_use("t1", "Bash", {"command": "cd /irgendwo && bash hooks/tests/test-a.sh 2>&1 | tail -3"}),
              tool_result("t1", "PASS: 3  FAIL: 0")]
elif fall == "unterminiert":
    zeilen = [tool_use("t1", "Bash", {"command": "pytest hooks/tests/"}), tool_result("t1")]
    ende = ""
elif fall == "gate-vollstaendig":
    zeilen = [tool_use("t1", "Bash", {"command": "bash shell/tests/test-wb-profil.sh"}), tool_result("t1"),
              tool_use("t2", "Bash", {"command": "bash shell/tests/test-wb-aufgabe.sh"}), tool_result("t2")]
elif fall == "gate-unvollstaendig":
    zeilen = [tool_use("t1", "Bash", {"command": "bash shell/tests/test-wb-profil.sh"}), tool_result("t1")]

with open(datei, "w") as f:
    if zeilen:
        f.write("\n".join(json.dumps(z) for z in zeilen) + ende)
PY
}

pretooluse_json() { # <ziel> <datei> <tool> <file_path> <transkript> <cwd>
  local ziel="$1" tool="$2" file_path="$3" transkript="$4" cwd="$5"
  python3 - "$ziel" "$tool" "$file_path" "$transkript" "$cwd" <<'PY'
import json, sys
ziel, tool, file_path, transkript, cwd = sys.argv[1:6]
input_ = {"file_path": file_path, "content": "x"} if tool == "Write" \
    else {"file_path": file_path, "old_string": "a", "new_string": "b"}
daten = {"session_id": "sess", "hook_event_name": "PreToolUse", "tool_name": tool,
         "tool_input": input_, "cwd": cwd, "transcript_path": transkript}
open(ziel, "w").write(json.dumps(daten))
PY
}

lauf() { # <input-datei> [WB_AUFGABE_ID]
  local input="$1" id="${2:-t1}"
  HOME="$TESTHOME/home" WB_AUFGABE_ID="$id" WB_AUFGABE_BASE="$BASE" python3 "$LIB" < "$input" 2>"$TESTHOME/stderr"
}

ist_deny() { grep -q '"permissionDecision": "deny"' "$1"; }

# -------------------------------------------------------- Fall 1 --------
section "1: ohne WB_AUFGABE_ID -- nichts passiert"
aufgabe_setzen "t1" "" ""
pretooluse_json "$TESTHOME/in1.json" "Write" "$RESULT_PFAD" "" "$WORKTREE"
python3 "$LIB" < "$TESTHOME/in1.json" > "$TESTHOME/out1" 2>/dev/null
[ ! -s "$TESTHOME/out1" ] && ok "1: kein JSON ohne WB_AUFGABE_ID" || bad "1: Ausgabe trotz fehlender Kennung: $(cat "$TESTHOME/out1")"

# -------------------------------------------------------- Fall 2 --------
section "2: Write auf einen normalen Pfad bleibt unberuehrt"
pretooluse_json "$TESTHOME/in2.json" "Write" "$NORMAL_PFAD" "" "$WORKTREE"
lauf "$TESTHOME/in2.json" > "$TESTHOME/out2"
[ ! -s "$TESTHOME/out2" ] && ok "2: normaler Pfad -> kein deny" || bad "2: normaler Pfad wurde verweigert: $(cat "$TESTHOME/out2")"

# -------------------------------------------------------- Fall 3 --------
section "3: Ergebnisdatei eines Workers OHNE Beleg -> deny"
transkript_schreiben "$TESTHOME/leer.jsonl" "leer"
pretooluse_json "$TESTHOME/in3.json" "Write" "$RESULT_PFAD" "$TESTHOME/leer.jsonl" "$WORKTREE"
lauf "$TESTHOME/in3.json" > "$TESTHOME/out3"
ist_deny "$TESTHOME/out3" && ok "3: ohne Beleg -> deny" || bad "3: kein deny ohne Beleg: $(cat "$TESTHOME/out3")"

# -------------------------------------------------------- Fall 4 --------
section "4: Read auf eine namensgleiche, leere Datei ist kein Testbeleg"
mkdir -p "$WORKTREE/hooks/tests"
touch "$WORKTREE/hooks/tests/lauf.log"
transkript_schreiben "$TESTHOME/log.jsonl" "read-log-belegt"
pretooluse_json "$TESTHOME/in4.json" "Write" "$RESULT_PFAD" "$TESTHOME/log.jsonl" "$WORKTREE"
lauf "$TESTHOME/in4.json" > "$TESTHOME/out4"
ist_deny "$TESTHOME/out4" && ok "4: leerer Read-Beleg (.log) -> deny" || bad "4: leerer Read zaehlte als Beleg: $(cat "$TESTHOME/out4")"

# -------------------------------------------------------- Fall 5 --------
section "5: abgeschlossener pytest-Lauf -> allow"
transkript_schreiben "$TESTHOME/pytest-ok.jsonl" "bash-pytest-belegt"
pretooluse_json "$TESTHOME/in5.json" "Write" "$RESULT_PFAD" "$TESTHOME/pytest-ok.jsonl" "$WORKTREE"
lauf "$TESTHOME/in5.json" > "$TESTHOME/out5"
[ ! -s "$TESTHOME/out5" ] && ok "5: Bash-Testlauf-Beleg -> allow" || bad "5: trotz Testlauf-Beleg verweigert: $(cat "$TESTHOME/out5")"

# -------------------------------------------------------- Fall 6 --------
section "6: pytest-Lauf OHNE tool_result zaehlt nicht als Beleg"
transkript_schreiben "$TESTHOME/pytest-unbelegt.jsonl" "bash-pytest-unbelegt"
pretooluse_json "$TESTHOME/in6.json" "Write" "$RESULT_PFAD" "$TESTHOME/pytest-unbelegt.jsonl" "$WORKTREE"
lauf "$TESTHOME/in6.json" > "$TESTHOME/out6"
ist_deny "$TESTHOME/out6" && ok "6: unabgeschlossener Aufruf -> weiterhin deny" || bad "6: unabgeschlossener Aufruf zaehlte als Beleg: $(cat "$TESTHOME/out6")"

section "6b: leerer oder fehlgeschlagener tool_result zaehlt nicht als Beleg"
for form in bash-pytest-leer bash-pytest-fehler; do
  transkript_schreiben "$TESTHOME/${form}.jsonl" "$form"
  pretooluse_json "$TESTHOME/${form}.json" "Write" "$RESULT_PFAD" "$TESTHOME/${form}.jsonl" "$WORKTREE"
  lauf "$TESTHOME/${form}.json" > "$TESTHOME/${form}.out"
  ist_deny "$TESTHOME/${form}.out" && ok "6b: $form -> deny" || bad "6b: $form zaehlte als Beleg: $(cat "$TESTHOME/${form}.out")"
done

# -------------------------------------------------------- Fall 7 --------
section "7: gelesene Datei ohne passenden Namen zaehlt nicht als Beleg"
transkript_schreiben "$TESTHOME/falscher-name.jsonl" "read-falscher-name"
pretooluse_json "$TESTHOME/in7.json" "Write" "$RESULT_PFAD" "$TESTHOME/falscher-name.jsonl" "$WORKTREE"
lauf "$TESTHOME/in7.json" > "$TESTHOME/out7"
ist_deny "$TESTHOME/out7" && ok "7: falscher Dateiname -> weiterhin deny" || bad "7: falscher Dateiname zaehlte als Beleg: $(cat "$TESTHOME/out7")"

# -------------------------------------------------------- Fall 8 --------
section "8: Ergebnispfad des Hauptagenten mit vollstaendigem Gate-Protokoll -> allow"
HA_ERGEBNIS="$TESTHOME/base/projekt/.companion/hauptagent-ergebnis.md"
aufgabe_setzen "t1" "bash shell/tests/test-wb-profil.sh||bash shell/tests/test-wb-aufgabe.sh" "$HA_ERGEBNIS"
transkript_schreiben "$TESTHOME/gate-voll.jsonl" "gate-vollstaendig"
pretooluse_json "$TESTHOME/in8.json" "Write" "$HA_ERGEBNIS" "$TESTHOME/gate-voll.jsonl" "$WORKTREE"
lauf "$TESTHOME/in8.json" > "$TESTHOME/out8"
[ ! -s "$TESTHOME/out8" ] && ok "8: vollstaendiges Gate-Protokoll -> allow" || bad "8: trotz vollstaendigem Protokoll verweigert: $(cat "$TESTHOME/out8")"

# -------------------------------------------------------- Fall 9 --------
section "9: Ergebnispfad des Hauptagenten mit FEHLENDEM Gate-Befehl -> deny, nennt ihn"
transkript_schreiben "$TESTHOME/gate-unvoll.jsonl" "gate-unvollstaendig"
pretooluse_json "$TESTHOME/in9.json" "Write" "$HA_ERGEBNIS" "$TESTHOME/gate-unvoll.jsonl" "$WORKTREE"
lauf "$TESTHOME/in9.json" > "$TESTHOME/out9"
ist_deny "$TESTHOME/out9" && ok "9: fehlender Gate-Befehl -> deny" || bad "9: kein deny bei fehlendem Gate-Befehl: $(cat "$TESTHOME/out9")"
grep -q "test-wb-aufgabe.sh" "$TESTHOME/out9" && ok "9: die Begruendung nennt den fehlenden Befehl" \
                                                || bad "9: Begruendung nennt den fehlenden Befehl nicht: $(cat "$TESTHOME/out9")"

# -------------------------------------------------------- Fall 10 -------
section "10: ohne gate_commands gibt es nichts zu belegen -- allow"
aufgabe_setzen "t1" "" "$HA_ERGEBNIS"
transkript_schreiben "$TESTHOME/leer2.jsonl" "leer"
pretooluse_json "$TESTHOME/in10.json" "Write" "$HA_ERGEBNIS" "$TESTHOME/leer2.jsonl" "$WORKTREE"
lauf "$TESTHOME/in10.json" > "$TESTHOME/out10"
[ ! -s "$TESTHOME/out10" ] && ok "10: leere gate_commands -> allow" || bad "10: ohne gate_commands trotzdem verweigert: $(cat "$TESTHOME/out10")"

# -------------------------------------------------------- Fall 11 -------
section "11: Edit wird genauso geprueft wie Write"
aufgabe_setzen "t1" "" ""
transkript_schreiben "$TESTHOME/leer3.jsonl" "leer"
pretooluse_json "$TESTHOME/in11.json" "Edit" "$RESULT_PFAD" "$TESTHOME/leer3.jsonl" "$WORKTREE"
lauf "$TESTHOME/in11.json" > "$TESTHOME/out11"
ist_deny "$TESTHOME/out11" && ok "11: Edit ohne Beleg -> deny" || bad "11: Edit wurde nicht geprueft: $(cat "$TESTHOME/out11")"

# -------------------------------------------------------- Fall 12 -------
section "12: Settings-Snippet ist gueltiges JSON"
if python3 -c "
import json
d = json.load(open('$SNIPPET'))
hooks = d['hooks']['PreToolUse']
assert len(hooks) == 1
assert hooks[0]['matcher'] == 'Write|Edit'
assert 'ergebnis-beleg-gate.sh' in hooks[0]['hooks'][0]['command']
" 2>"$TESTHOME/snippet-err"; then
  ok "12: Snippet gueltig, ein PreToolUse-Eintrag auf Write|Edit"
else
  bad "12: Snippet ungueltig: $(cat "$TESTHOME/snippet-err")"
fi

# -------------------------------------------------------- Fall 13 -------
section "13: hooks/README.md beschreibt den Hook"
grep -q "ergebnis-beleg-gate" "$HOOKS_DIR/README.md" && ok "13: README beschreibt den Hook" \
                                                       || bad "13: README ohne Absatz zum Hook"

# -------------------------------------------------------- Fall 14 -------
section "14: Bau-Schritt 5 -- unter zwei Sekunden (gemessen, nicht behauptet)"
DAUER_MS="$(python3 - "$LIB" "$TESTHOME/in3.json" <<'PY'
import subprocess, sys, time, os
lib, eingabe = sys.argv[1:3]
env = dict(os.environ, WB_AUFGABE_ID="t1")
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
  section "15: tmux -- Verweigerung aus einem echten Worker-Pane"
  TXSOCK="wbtest-ergebnisbeleg-$$"
  TXHOME="$TESTHOME/home"
  aufgabe_setzen "t1" "" ""
  transkript_schreiben "$TESTHOME/tmux-leer.jsonl" "leer"
  pretooluse_json "$TESTHOME/tmux-in.json" "Write" "$RESULT_PFAD" "$TESTHOME/tmux-leer.jsonl" "$WORKTREE"
  TSCHIRM="$TESTHOME/tmux-schirm.sh"
  cat > "$TSCHIRM" <<EOF
#!/bin/bash
python3 "$LIB" < "$TESTHOME/tmux-in.json" > "$TESTHOME/tmux-out" 2>"$TESTHOME/tmux-err"
touch "$TESTHOME/tmux-fertig"
EOF
  chmod +x "$TSCHIRM"
  rm -f "$TESTHOME/tmux-fertig" "$TESTHOME/tmux-out"
  (
    export HOME="$TXHOME" WB_AUFGABE_ID="t1" WB_AUFGABE_BASE="$BASE"
    unset TMUX TMUX_PANE
    tmux -L "$TXSOCK" new-session -d -s ergebnisbeleg -x 120 -y 40 "bash $TSCHIRM"
  ) >/dev/null 2>&1
  fertig=0
  for _ in $(seq 1 100); do
    [ -f "$TESTHOME/tmux-fertig" ] && { fertig=1; break; }
    sleep 0.2
  done
  if [ "$fertig" = "1" ] && ist_deny "$TESTHOME/tmux-out"; then
    ok "15: Verweigerung kommt aus dem Pane heraus (WB_AUFGABE_ID aus der Pane-Umgebung)"
  else
    bad "15: keine Verweigerung aus dem Pane (err=$(cat "$TESTHOME/tmux-err" 2>/dev/null | head -1))"
  fi
  tmux -L "$TXSOCK" kill-server >/dev/null 2>&1 || true
else
  printf '  SKIP  tmux fehlt -- tmux-Fall uebersprungen\n'
fi

# -------------------------------------------------------- Fall 16 -------
section "16: was als ausgefuehrter Testlauf zaehlt (AUFTRAG hooks5 Nr. 2, Fehler 7)"
aufgabe_setzen "t1" "" ""
for fall in bash-exit-code:allow bash-abgelehnt:deny read-log-voll:deny cd-testskript:allow unterminiert:allow; do
  form="${fall%%:*}"; erwartung="${fall##*:}"
  transkript_schreiben "$TESTHOME/$form.jsonl" "$form"
  pretooluse_json "$TESTHOME/$form.json" "Write" "$RESULT_PFAD" "$TESTHOME/$form.jsonl" "$WORKTREE"
  lauf "$TESTHOME/$form.json" > "$TESTHOME/$form.out"
  if [ "$erwartung" = deny ]; then
    ist_deny "$TESTHOME/$form.out" && ok "16: $form -> deny" || bad "16: $form zaehlte als Beleg: $(cat "$TESTHOME/$form.out")"
  else
    [ ! -s "$TESTHOME/$form.out" ] && ok "16: $form -> allow" || bad "16: $form verweigert: $(cat "$TESTHOME/$form.out")"
  fi
done

# -------------------------------------------------------- Fall 17 -------
section "17: Fortschreibung -- ein Aufruf ohne Ergebnis wartet, das spaetere Ergebnis zaehlt"
INKR="$TESTHOME/inkrementell.jsonl"
transkript_schreiben "$INKR" "bash-pytest-unbelegt"
pretooluse_json "$TESTHOME/inkr.json" "Write" "$RESULT_PFAD" "$INKR" "$WORKTREE"
lauf "$TESTHOME/inkr.json" > "$TESTHOME/inkr1.out"
ist_deny "$TESTHOME/inkr1.out" && ok "17: Aufruf noch ohne Ergebnis -> deny" || bad "17: ohne Ergebnis erlaubt: $(cat "$TESTHOME/inkr1.out")"
python3 - "$INKR" <<'PY'
import json, sys
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t1", "content": "3 passed", "is_error": False}]}}) + "\n")
PY
lauf "$TESTHOME/inkr.json" > "$TESTHOME/inkr2.out"
[ ! -s "$TESTHOME/inkr2.out" ] && ok "17: nachgereichtes Ergebnis -> allow" || bad "17: nachgereichtes Ergebnis verweigert: $(cat "$TESTHOME/inkr2.out")"
if python3 - "$INKR" "$BASE" <<'PY'
import hashlib, json, os, sys
transkript, base = sys.argv[1:3]
schluessel = hashlib.sha1(os.path.abspath(transkript).encode()).hexdigest()[:16]
z = json.load(open(os.path.join(base, ".local", "state", "wb-ergebnis-beleg", "t1.%s.json" % schluessel)))
assert z["offset"] == os.path.getsize(transkript), (z["offset"], os.path.getsize(transkript))
assert z["befehle"] == ["pytest hooks/tests/"], z["befehle"]
assert z["offene"] == {}, z["offene"]
PY
then
  ok "17: Zustandsdatei steht am Dateiende, kennt den Lauf, wartet auf nichts mehr"
else
  bad "17: Zustandsdatei nicht wie erwartet fortgeschrieben"
fi

# -------------------------------------------------------- Fall 18 -------
section "18: langes Transkript -- ein frueher Testlauf faellt aus keinem 8-MB-Fenster mehr"
GROSS="$TESTHOME/gross.jsonl"
python3 - "$GROSS" <<'PY'
import json, sys
anfang = [
    {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "pytest hooks/tests/"}}]}},
    {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t1", "content": "5 passed", "is_error": False}]}},
]
fueller = json.dumps({"type": "assistant", "message": {"role": "assistant",
                      "content": [{"type": "text", "text": "x" * 4000}]}}) + "\n"
with open(sys.argv[1], "w") as f:
    for z in anfang:
        f.write(json.dumps(z) + "\n")
    for _ in range(12 * 1024 * 1024 // len(fueller) + 1):
        f.write(fueller)
PY
pretooluse_json "$TESTHOME/gross.json" "Write" "$RESULT_PFAD" "$GROSS" "$WORKTREE"
GROSS_MB=$(( $(wc -c < "$GROSS") / 1024 / 1024 ))
MESSUNG="$(HOME="$TESTHOME/home" WB_AUFGABE_ID=t1 WB_AUFGABE_BASE="$BASE" python3 - "$LIB" "$TESTHOME/gross.json" "$GROSS" <<'PY'
import subprocess, sys, time
lib, eingabe, transkript = sys.argv[1:4]
def lauf():
    start = time.monotonic()
    with open(eingabe, "rb") as f:
        r = subprocess.run(["python3", lib], stdin=f, capture_output=True)
    return r.stdout.strip() == b"", int((time.monotonic() - start) * 1000)
erlaubt1, ms1 = lauf()
with open(transkript, "a") as f:
    f.write('{"type": "assistant", "message": {"role": "assistant", "content": []}}\n')
erlaubt2, ms2 = lauf()
print(int(erlaubt1), ms1, int(erlaubt2), ms2)
PY
)"
read -r G_OK1 G_MS1 G_OK2 G_MS2 <<< "$MESSUNG"
if [ "$G_OK1" = 1 ] && [ "$G_OK2" = 1 ]; then
  ok "18: Testlauf am Anfang eines ${GROSS_MB}-MB-Transkripts zaehlt (erster und fortgeschriebener Aufruf)"
else
  bad "18: frueher Testlauf ging verloren (Messung: $MESSUNG)"
fi
if [ "$G_MS1" -lt 2000 ] && [ "$G_MS2" -lt 2000 ]; then
  ok "18: voller Erstlauf ${G_MS1}ms, Fortschreibung ${G_MS2}ms (beide < 2000ms)"
else
  bad "18: zu langsam (Erstlauf ${G_MS1}ms, Fortschreibung ${G_MS2}ms)"
fi

printf '\n======================================================================\n'
printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
