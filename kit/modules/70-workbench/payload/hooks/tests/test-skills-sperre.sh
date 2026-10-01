#!/usr/bin/env bash
# test-skills-sperre.sh -- PreToolUse-Hook skills-sperre.sh: ein Agentenzug
# nutzt nur die Skills aus seiner skills.json (docs/AGENTS-PLAN.md, Abschnitt 3
# "Die Sperre" und 14 "Sicherungen"; Auftrag agentsskills Nr. 2).
#
# Was hier belegt wird, in dieser Reihenfolge:
#   1. ohne WB_AGENT_ID und WB_WELT keine Ausgabe, auch fuer einen Hausskill,
#   2. fail-closed: fehlende, kaputte, fremde oder manipulierte skills.json,
#      ungueltige Kennung, halbe Umgebung, falsches WB_SKILLS_JSON,
#   3. verweigert: Hausskills, Plugin-Skills, fremde Agentenskills, nicht
#      verzeichnete Bibliotheksskills, geaenderte Weltskills, Schreiben in
#      Welt- und Bibliotheksskills -- ueber Bash (auch verschachtelt), Skill,
#      Read, Grep, Glob, Write und Edit,
#   4. erlaubt: eigene Skills, verzeichnete Welt- und Bibliotheksskills,
#      Skillwurzel als Liste, Projektbaeume mit SKILL.md, gewoehnliche Befehle,
#   5. Punkt 2 des Auftrags: ein Skript unter scripts/ wird mit denselben
#      Regeln geprueft wie ein direkter Befehl (bash-guard, Testschutz), mit
#      Repro-Tabelle und den benannten Grenzen,
#   6. Shell-Huelle Ende zu Ende: Stille, Frist mit beendetem Kern, fehlender
#      Kern, Laufzeit,
#   7. Settings-Snippet und README,
#   8. gespeicherte Skripte (Auftrag agentsskills Nr. 4) wie Skills: eigene
#      frei, Welt und Bibliothek nur verzeichnet und mit passender Version,
#      fremde gesperrt, Inhalt gegen die Pruefkette (Repro-Tabelle).
#
# ISOLATION: eigenes HOME (mktemp -d), eigene Kopie der Hooks, eigene Welt und
# Bibliothek, Snapshot-Guard mit eigener Konfiguration, kein Modell, kein Netz,
# kein tmux. Kein Befehl der Pruefdaten wird ausgefuehrt; der Hook bewertet nur.
set -uo pipefail
unset TMUX TMUX_PANE WB_AGENT_ID WB_WELT WB_SKILLS_JSON WB_AUFGABE_ID WB_ROLLE WB_SKILLS_SPERRE_KETTE

HOOKS_DIR="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd -- "$HOOKS_DIR/.." && pwd)"
PASS=0
FAIL=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

command -v python3 >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: python3 fehlt"; exit 77; }
command -v perl >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: perl fehlt"; exit 77; }
[ -f "$HOOKS_DIR/lib/skills_sperre.py" ] || { echo "UEBERSPRUNGEN: lib/skills_sperre.py fehlt"; exit 77; }
[ -f "$REPO_ROOT/shell/agents_skills.py" ] || { echo "UEBERSPRUNGEN: shell/agents_skills.py fehlt"; exit 77; }

TESTHOME="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TESTHOME"' EXIT

# ------------------------------------------------------ eigene Kopie ----
KOPIE="$TESTHOME/hooks"
mkdir -p "$KOPIE/lib"
cp "$HOOKS_DIR/skills-sperre.sh" "$HOOKS_DIR/bash-guard.py" "$HOOKS_DIR/testschutz-gate.sh" \
   "$HOOKS_DIR/reviewer-sperre.sh" "$KOPIE/"
cp "$HOOKS_DIR"/lib/*.py "$KOPIE/lib/"
BLOSS="$TESTHOME/hooks-ohne-kette"   # nur die Sperre, fuer den Gegenbeleg
mkdir -p "$BLOSS/lib"
cp "$HOOKS_DIR/skills-sperre.sh" "$BLOSS/"
cp "$HOOKS_DIR"/lib/*.py "$BLOSS/lib/"

export HOME="$TESTHOME/home"
mkdir -p "$HOME"
export AWB_SETTINGS_FILE="$TESTHOME/keine-settings.json"
export AWB_GUARD_LOG="$TESTHOME/guard-blocks.log"
export AWB_GUARD_BLOCKS_DIR="$TESTHOME/guard-blocks"
export SNAPSHOT_GUARD_CONF="$TESTHOME/snapshot.conf"
export PATH="$REPO_ROOT/shell:$PATH"
export PYTHONDONTWRITEBYTECODE=1
# Der Snapshot-Guard nimmt Wegwerf-Orte (/tmp, /var/folders) aus; in dieser
# Konfiguration gilt nichts davon, damit der Testordner geschuetzt ist.
printf 'exempt_glob=/nie/und/nirgends/*\nsnapshot_dir=%s/snaps\n' "$TESTHOME" > "$SNAPSHOT_GUARD_CONF"

WELT="$TESTHOME/projekt/.werkbank/agents"
BIB="$TESTHOME/bibliothek"
PROT="$TESTHOME/daten/wichtig"
WORKTREE="$TESTHOME/projekt"
BASE="$TESTHOME/base"
mkdir -p "$PROT" "$WORKTREE/tests" "$BASE"
printf 'echter Inhalt, nicht trivial, nirgends gesichert.\n' > "$PROT/inhalt.txt"
printf 'def test_kern():\n    assert True\n' > "$WORKTREE/tests/test_kern.py"

python3 - "$REPO_ROOT/shell" "$WELT" "$BIB" "$HOME" "$PROT" "$WORKTREE" <<'PY'
import os, sys
from pathlib import Path
shell, welt, bib, home, prot, worktree = sys.argv[1:7]
sys.path.insert(0, shell)
sys.path.insert(0, str(Path(shell) / "tests"))
import agents_data as ad
import agents_skills as sk
from herkunft_fixture import aufbau_herkunft

def skill(base, name, scripts=None, beschreibung="Testskill", skripte=""):
    folder = Path(base) / name
    (folder / "scripts").mkdir(parents=True, exist_ok=True)
    (folder / "SKILL.md").write_text("---\nname: %s\ndescription: %s\n%s---\n\n## Auslöser\n\nx\n\n"
                                     "## Vorgehen\n\nx\n\n## Grenzen\n\nx\n"
                                     % (name, beschreibung, "skripte: %s\n" % skripte if skripte else ""))
    for rel, text in (scripts or {}).items():
        path = folder / rel
        path.write_text(text)
        path.chmod(0o755)

def skript(base, name, text, endung=".sh"):
    """Gespeichertes Skript: eine ausfuehrbare Datei mit Anweisungskopf."""
    folder = Path(base) / name
    (folder / "tests").mkdir(parents=True, exist_ok=True)
    shebang, rumpf = text.split("\n", 1)
    datei = folder / (name + endung)
    datei.write_text("%s\n# ---\n# name: %s\n# zweck: Testskript\n# aufruf: %s%s\n# eingaben: keine\n"
                     "# ausgaben: stdout\n# grenzen: nur Test\n# ---\n%s" % (shebang, name, name, endung, rumpf))
    datei.chmod(0o755)
    (folder / "tests" / ("test_%s.py" % name.replace("-", "_"))).write_text("pass\n")

with aufbau_herkunft(ad) as aufbau:
    ad.create_world(Path(welt), name="Sperre", main_name="main", sender=aufbau)
    ad.create_agent(Path(welt), "member", "mitglied", "dev", "Baut", None, None, None, None, None, None,
                    "lokal", aufbau, None, skills=["lib-skill"])
    ad.create_agent(Path(welt), "other", "mitglied", "dev", "Baut anderes", None, None, None, None, None, None,
                    "lokal", aufbau, None)
eigen = Path(welt) / "agents" / "member" / "skills"
skill(eigen, "eigen", {
    "scripts/ok.sh": "#!/bin/sh\necho ok\n",
    "scripts/wipe.sh": "#!/bin/bash\nset -eu\nrm -rf %s\n" % prot,
    "scripts/wipe-arg.sh": "#!/bin/sh\nrm -rf \"$1\"\n",
    "scripts/wipe.py": "#!/usr/bin/env python3\nimport shutil\nshutil.rmtree(%r)\n" % prot,
    "scripts/tests-weg.sh": "#!/bin/sh\nrm tests/test_kern.py\n",
    "scripts/ruft-haus.sh": "#!/bin/sh\nbash %s/.claude/skills/haus/scripts/run.sh\n" % home,
    "scripts/dynamisch.sh": "#!/bin/sh\nziel=$(cat /dev/null)\nrm -rf \"$ziel\"\n",
    "scripts/ruft-helfer.sh": "#!/bin/sh\nsh %s/helfer.sh\n" % worktree,
})
# Kein Skill: ein Hilfsskript im Projekt, das ein Skill-Skript aufruft.
(Path(worktree) / "helfer.sh").write_text("#!/bin/sh\nrm -rf %s\n" % prot)
skill(Path(welt) / "skills", "welt-skill", {"scripts/run.sh": "#!/bin/sh\necho welt\n"})
skill(bib, "lib-skill", {"scripts/x.py": "#!/usr/bin/env python3\nprint('lib')\n"}, skripte="lib-skript")
skill(bib, "lib-fremd", {"scripts/x.sh": "#!/bin/sh\necho fremd\n"})
skill(Path(welt) / "agents" / "other" / "skills", "fremd", {"scripts/x.py": "print('fremd')\n"})
skill(Path(home) / ".claude" / "skills", "haus", {"scripts/run.sh": "#!/bin/sh\necho haus\n"})
skill(Path(home) / ".claude" / "plugins" / "cache" / "p" / "skills", "plug", {"scripts/run.sh": "#!/bin/sh\n"})
skill(Path(worktree) / "doku" / "skills", "demo", {"scripts/run.sh": "#!/bin/sh\necho demo\n"})
# Gespeicherte Skripte: eigene, der Welt, der Bibliothek (neben ihr unter skripte/) und eines anderen Agenten.
eigene_skripte = Path(welt) / "agents" / "member" / "skripte"
skript(eigene_skripte, "eigen-skript", "#!/bin/sh\necho eigen\n")
skript(eigene_skripte, "wipe-skript", "#!/bin/bash\nset -eu\nrm -rf %s\n" % prot)
skript(Path(welt) / "skripte", "welt-skript", "#!/bin/sh\necho welt\n")
skript(Path(welt) / "skripte", "welt-wipe", "#!/bin/sh\nrm -rf %s\n" % prot)
skript_bib = Path(bib).parent / "skripte"
skript(skript_bib, "lib-skript", "#!/usr/bin/env python3\nimport shutil\nshutil.rmtree(%r)\n" % prot, ".py")
skript(skript_bib, "lib-fremd-skript", "#!/bin/sh\necho fremd\n")
skript(Path(welt) / "agents" / "other" / "skripte", "fremd-skript", "#!/bin/sh\necho fremd\n")
sk.write_skill_directory(Path(welt), None, bib)
import json
eintraege = json.loads((Path(welt) / "agents" / "member" / "skills.json").read_text())["skills"]
skripte = sorted(e["name"] for e in eintraege if e.get("art") == "skript")
assert skripte == ["eigen-skript", "lib-skript", "welt-skript", "welt-wipe", "wipe-skript"], skripte
PY
[ -f "$WELT/agents/member/skills.json" ] || { echo "FEHLER: Testwelt nicht angelegt"; exit 1; }
EIGEN="$WELT/agents/member/skills/eigen"
SKRIPTE_EIGEN="$WELT/agents/member/skripte"
SKRIPTBIB="$TESTHOME/skripte"

# Aufgabe mit Gate-Befehl fuer den Testschutz (Form wie tests/test-testschutz.sh).
python3 - "t-skill" "python3 tests/test_kern.py" "$BASE" "$WORKTREE" <<'PY'
import json, os, sys
id_, gate, base, projekt = sys.argv[1:5]
auftraege = os.path.join(projekt, ".companion", "auftraege")
os.makedirs(auftraege, exist_ok=True)
os.makedirs(os.path.join(base, ".claude", "workbench", "vorrat"), exist_ok=True)
auftrag_pfad = os.path.join(auftraege, "%s.json" % id_)
auftrag = {"schema_version": 1, "id": id_, "project": projekt, "goal": "Test", "done_criterion": "gruen",
           "reference": None, "guardrails": [], "gate_commands": [gate],
           "limits": {"iterations": None, "tokens": None, "time_seconds": None}, "loop_type": "loop",
           "model": "opus5", "approval": None, "freigaben": {},
           "hauptagent": {"model": "opus5", "effort": "high", "fallback": None}, "maschine": "mac", "grenzen": {}}
verlauf = {"id": id_, "stand": "laeuft", "grund": "", "maschine": "mac", "worker": [], "team": [], "verlauf": [],
           "ergebnis": {"pfad": None, "commit": None, "belege": [], "reviewer_befunde": []},
           "kosten": {"token_schaetzung": None, "lokale_stunden": None}, "wiederaufnahme": "", "weckzeit": None,
           "frage": None, "pfade": []}
json.dump(auftrag, open(auftrag_pfad, "w"))
json.dump(verlauf, open(os.path.join(auftraege, "%s.verlauf.json" % id_), "w"))
json.dump({"rang": 1, "projekt": projekt, "auftrag": auftrag_pfad, "maschine": "mac",
           "aufgenommen": "2026-09-14T00:00:00Z"},
          open(os.path.join(base, ".claude", "workbench", "vorrat", "%s.json" % id_), "w"))
PY

# -------------------------------------------------------------- Helfer --
eingabe() { # <tool> <feld> <wert> [cwd]  -> JSON auf stdout
  python3 - "$1" "$2" "$3" "${4:-$WORKTREE}" <<'PY'
import json, sys
tool, feld, wert, cwd = sys.argv[1:5]
print(json.dumps({"session_id": "sess", "hook_event_name": "PreToolUse", "tool_name": tool,
                  "tool_input": {feld: wert}, "cwd": cwd}))
PY
}

entscheidung() { # stdin: Hook-Ausgabe -> deny|allow|kaputt
  python3 -c '
import json, sys
roh = sys.stdin.read().strip()
if not roh:
    print("allow"); sys.exit()
try:
    d = json.loads(roh.splitlines()[-1])
    print("deny" if d["hookSpecificOutput"]["permissionDecision"] == "deny" else "kaputt")
except Exception:
    print("kaputt")'
}

LETZTE_AUSGABE=""
ENTSCHEIDUNG=""
sperre() { # <hooks-ordner> <tool> <feld> <wert> [cwd] -- mit Agentenumgebung; setzt LETZTE_AUSGABE, ENTSCHEIDUNG
  LETZTE_AUSGABE="$(eingabe "$2" "$3" "$4" "${5:-}" 2>/dev/null | WB_AGENT_ID=member WB_WELT="$WELT" bash "$1/skills-sperre.sh" 2>/dev/null)"
  ENTSCHEIDUNG="$(printf '%s' "$LETZTE_AUSGABE" | entscheidung)"
}

fall() { # <label> <erwartet> <tool> <feld> <wert> [cwd]
  local label="$1" erwartet="$2" got
  sperre "$KOPIE" "$3" "$4" "$5" "${6:-}"
  got="$ENTSCHEIDUNG"
  if [ "$got" = "$erwartet" ]; then
    ok "$label (erwartet=$erwartet)"
  else
    bad "$label (erwartet=$erwartet, erhalten=$got) $LETZTE_AUSGABE"
  fi
}

grund_enthaelt() { # <label> <text>
  if printf '%s' "$LETZTE_AUSGABE" | grep -qF -- "$2"; then ok "$1"; else bad "$1: '$2' fehlt in $LETZTE_AUSGABE"; fi
}

# ------------------------------------------------------------ Fall 1 ----
section "1: ohne Agentenzug keine Ausgabe"
out="$(eingabe Bash command "bash $HOME/.claude/skills/haus/scripts/run.sh" | bash "$KOPIE/skills-sperre.sh")"
[ -z "$out" ] && ok "1a Hausskill ohne WB_AGENT_ID/WB_WELT -> still" || bad "1a Ausgabe ohne Agentenzug: $out"
out="$(eingabe Skill skill haus | bash "$KOPIE/skills-sperre.sh")"
[ -z "$out" ] && ok "1b Skill-Werkzeug ohne Agentenzug -> still" || bad "1b Ausgabe: $out"

# ------------------------------------------------------------ Fall 2 ----
section "2: fail-closed"
halb="$(eingabe Bash command "ls" | WB_AGENT_ID=member bash "$KOPIE/skills-sperre.sh" | entscheidung)"
[ "$halb" = deny ] && ok "2a nur WB_AGENT_ID -> deny" || bad "2a halbe Umgebung: $halb"
bad_id="$(eingabe Bash command "ls" | WB_AGENT_ID="../main" WB_WELT="$WELT" bash "$KOPIE/skills-sperre.sh" | entscheidung)"
[ "$bad_id" = deny ] && ok "2b ungueltige Agentenkennung -> deny" || bad "2b: $bad_id"
falsch="$(eingabe Bash command "ls" | WB_AGENT_ID=member WB_WELT="$WELT" WB_SKILLS_JSON="$WELT/agents/other/skills.json" \
          bash "$KOPIE/skills-sperre.sh" | entscheidung)"
[ "$falsch" = deny ] && ok "2c WB_SKILLS_JSON eines anderen Agenten -> deny" || bad "2c: $falsch"
cp "$WELT/agents/member/skills.json" "$TESTHOME/skills.json.sicher"
rm "$WELT/agents/member/skills.json"
fall "2d skills.json fehlt, harmloses ls -> deny" deny Bash command "ls"
grund_enthaelt "2d Grund nennt skills.json" "skills.json"
printf '{kaputt' > "$WELT/agents/member/skills.json"
fall "2e skills.json kaputt -> deny" deny Read file_path "$WORKTREE/tests/test_kern.py"
python3 - "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["agent"] = "other"; json.dump(d, open(sys.argv[2], "w"))
PY
fall "2f skills.json eines anderen Agenten -> deny" deny Bash command "ls"
python3 - "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json" "$HOME" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["skills"].append({"name": "haus", "ebene": "welt", "pfad": sys.argv[3] + "/.claude/skills/haus", "version": "0" * 64})
json.dump(d, open(sys.argv[2], "w"))
PY
fall "2g skills.json nennt Hausskill als Weltskill -> deny" deny Bash command "ls"
grund_enthaelt "2g Grund nennt Pfad ausserhalb der Ebene" "outside level"
cp "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json"
fall "2h wiederhergestellte skills.json, ls -> allow" allow Bash command "ls"

# ------------------------------------------------------------ Fall 3 ----
section "3: fremde und veraenderte Skills werden verweigert"
fall "3a bash Hausskript" deny Bash command "bash $HOME/.claude/skills/haus/scripts/run.sh"
grund_enthaelt "3a Grund nennt skills.json" "not in the skills.json"
fall "3b Hausskript direkt ueber ~" deny Bash command "~/.claude/skills/haus/scripts/run.sh"
fall "3c \$HOME in Anfuehrung" deny Bash command "sh \"\$HOME/.claude/skills/haus/scripts/run.sh\""
fall "3d cat SKILL.md eines Hausskills" deny Bash command "cat ~/.claude/skills/haus/SKILL.md"
fall "3e Glob ueber alle Hausskills" deny Bash command "cat ~/.claude/skills/*/SKILL.md"
fall "3f Plugin-Skill unter ~/.claude/plugins" deny Bash command "bash ~/.claude/plugins/cache/p/skills/plug/scripts/run.sh"
fall "3g python3 fremder Agentenskill" deny Bash command "python3 $WELT/agents/other/skills/fremd/scripts/x.py"
fall "3h source nicht verzeichneter Bibliotheksskill" deny Bash command ". $BIB/lib-fremd/scripts/x.sh"
fall "3i verschachtelt: bash -c" deny Bash command "bash -c 'bash ~/.claude/skills/haus/scripts/run.sh'"
fall "3j verschachtelt: \$( )" deny Bash command "echo \$(cat ~/.claude/skills/haus/SKILL.md)"
fall "3k Wrapper env und xargs" deny Bash command "echo x | xargs env bash ~/.claude/skills/haus/scripts/run.sh"
fall "3l eval" deny Bash command "eval bash ~/.claude/skills/haus/scripts/run.sh"
fall "3m Zuweisung im Befehl" deny Bash command "S=~/.claude/skills/haus; bash \$S/scripts/run.sh"
fall "3n cd in fremden Skill" deny Bash command "cd ~/.claude/skills/haus && ./scripts/run.sh"
fall "3o Skriptpfad aus Kommandosubstitution" deny Bash command "bash \$(printf %s x)/run.sh"
fall "3p Umleitung in Weltskill" deny Bash command "echo x >> $WELT/skills/welt-skill/SKILL.md"
grund_enthaelt "3p Grund verweist auf wb-skill vorschlag" "wb-skill vorschlag"
fall "3q rm -rf auf Weltskill" deny Bash command "rm -rf $WELT/skills/welt-skill"
fall "3r sed -i im Bibliotheksskill" deny Bash command "sed -i '' s/a/b/ $BIB/lib-skill/SKILL.md"
fall "3s Skill-Werkzeug haus" deny Skill skill haus
fall "3t Read SKILL.md Hausskill" deny Read file_path "$HOME/.claude/skills/haus/SKILL.md"
fall "3u Grep in fremdem Agentenskill" deny Grep path "$WELT/agents/other/skills/fremd"
fall "3v Glob in Hausskills" deny Glob pattern "$HOME/.claude/skills/*/SKILL.md"
fall "3w Write in Weltskill" deny Write file_path "$WELT/skills/welt-skill/scripts/neu.sh"
fall "3x Edit im Bibliotheksskill" deny Edit file_path "$BIB/lib-skill/SKILL.md"
python3 - "$REPO_ROOT/shell" "$WELT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import agents_skills as sk  # noqa
folder = Path(sys.argv[2]) / "skills" / "spaeter"
(folder / "scripts").mkdir(parents=True)
(folder / "SKILL.md").write_text("---\nname: spaeter\ndescription: x\n---\n## Auslöser\n## Vorgehen\n## Grenzen\n")
(folder / "scripts" / "run.sh").write_text("#!/bin/sh\n")
PY
fall "3w0 ls der Hausskillwurzel" deny Bash command "ls ~/.claude/skills"
fall "3w1 find ueber Hausskills in xargs cat" deny Bash command "find ~/.claude/skills -name SKILL.md | xargs cat"
fall "3w2 Skillwurzel eines anderen Agenten" deny Bash command "ls $WELT/agents/other/skills"
fall "3w3 bash < Hausskript (stdin-Umleitung)" deny Bash command "bash < ~/.claude/skills/haus/scripts/run.sh"
fall "3w4 cat < SKILL.md eines Hausskills" deny Bash command "cat <~/.claude/skills/haus/SKILL.md"
fall "3y0 Pfadargument hinter eigenem Skript" deny Bash command "bash $EIGEN/scripts/ok.sh ~/.claude/skills/haus/SKILL.md"
fall "3y1 skills.json per Umleitung ergaenzen" deny Bash command "echo '{}' > $WELT/agents/member/skills.json"
fall "3y2 skills.json per Write" deny Write file_path "$WELT/agents/member/skills.json"
fall "3y Weltskill nach dem Verzeichnis angelegt" deny Bash command "sh $WELT/skills/spaeter/scripts/run.sh"
printf '\n# heimlich geaendert\n' >> "$WELT/skills/welt-skill/scripts/run.sh"
fall "3z geaenderter Weltskill (Version passt nicht)" deny Bash command "sh $WELT/skills/welt-skill/scripts/run.sh"
grund_enthaelt "3z Grund nennt die Version" "version"
python3 - "$WELT/skills/welt-skill/scripts/run.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read().replace("\n# heimlich geaendert\n", ""); open(p, "w").write(t)
PY

# ------------------------------------------------------------ Fall 4 ----
section "4: erlaubte Aufrufe"
fall "4a eigenes Skript" allow Bash command "bash $EIGEN/scripts/ok.sh"
fall "4b eigenes Skript relativ im Skillordner" allow Bash command "./scripts/ok.sh" "$EIGEN"
fall "4c Weltskill mit passender Version" allow Bash command "$WELT/skills/welt-skill/scripts/run.sh --probe"
fall "4d verzeichneter Bibliotheksskill" allow Bash command "python3 $BIB/lib-skill/scripts/x.py"
fall "4e Skill-Werkzeug lib-skill" allow Skill skill lib-skill
fall "4f Read Weltskill" allow Read file_path "$WELT/skills/welt-skill/SKILL.md"
fall "4g Write eigener Skill" allow Write file_path "$EIGEN/scripts/neu.sh"
fall "4h ls der Weltskillwurzel" allow Bash command "ls $WELT/skills $WELT/agents/member/skills"
fall "4i Projektbaum mit SKILL.md ist Arbeitsmaterial" allow Bash command "bash $WORKTREE/doku/skills/demo/scripts/run.sh"
fall "4j gewoehnlicher Befehl" allow Bash command "git status --short && grep -rn skills README.md"
fall "4k Glob im Projekt" allow Glob pattern "**/*.py"
fall "4l skills.json lesen" allow Read file_path "$WELT/agents/member/skills.json"
start=$(python3 -c 'import time; print(time.time())')
fall "4m eigenes Shell-Skript samt Pruefkette" allow Bash command "sh $EIGEN/scripts/ok.sh"
dauer=$(python3 -c "import time; print(round(time.time() - $start, 2))")
python3 -c "import sys; sys.exit(0 if $dauer < 5 else 1)" && ok "4m Inhaltspruefung unter fuenf Sekunden ($dauer s)" || bad "4m zu langsam: $dauer s"

# ------------------------------------------------------------ Fall 5 ----
section "5: Skripte unter denselben Regeln wie direkte Befehle (Repro-Tabelle)"
guard() { # <tool-json-befehl> [cwd] -> Entscheidung von bash-guard.py (Kopie) allein
  eingabe Bash command "$1" "${2:-$WORKTREE}" | python3 "$KOPIE/bash-guard.py" 2>/dev/null | entscheidung
}
testschutz() { # <befehl> -> Entscheidung von testschutz-gate.sh (Kopie) allein
  eingabe Bash command "$1" | WB_AUFGABE_ID=t-skill WB_AUFGABE_BASE="$BASE" bash "$KOPIE/testschutz-gate.sh" 2>/dev/null | entscheidung
}
mit_aufgabe() { # <hooks> <befehl> -- setzt LETZTE_AUSGABE, ENTSCHEIDUNG
  LETZTE_AUSGABE="$(eingabe Bash command "$2" | WB_AGENT_ID=member WB_WELT="$WELT" WB_AUFGABE_ID=t-skill \
    WB_AUFGABE_BASE="$BASE" bash "$1/skills-sperre.sh" 2>/dev/null)"
  ENTSCHEIDUNG="$(printf '%s' "$LETZTE_AUSGABE" | entscheidung)"
}
TABELLE="$TESTHOME/tabelle.txt"
printf '| %-4s | %-52s | %-10s | %-10s | %-17s | %-17s |\n' "Fall" "Form" "bash-guard" "Testschutz" "Sperre ohne Kette" "Sperre mit Kette" > "$TABELLE"
zeile() { # <fall> <form> <befehl> <erwartet bash-guard> <erwartet testschutz> <erwartet ohne> <erwartet mit>
  local g t o m
  g="$(guard "$3")"; t="$(testschutz "$3")"
  mit_aufgabe "$BLOSS" "$3"; o="$ENTSCHEIDUNG"
  mit_aufgabe "$KOPIE" "$3"; m="$ENTSCHEIDUNG"
  printf '| %-4s | %-52s | %-10s | %-10s | %-17s | %-17s |\n' "$1" "$2" "$g" "$t" "$o" "$m" >> "$TABELLE"
  if [ "$g/$t/$o/$m" = "$4/$5/$6/$7" ]; then
    ok "$1 $2 ($g/$t/$o/$m)"
  else
    bad "$1 $2: erwartet $4/$5/$6/$7, erhalten $g/$t/$o/$m -- $LETZTE_AUSGABE"
  fi
}
zeile R1 "rm -rf <geschuetzt> direkt" "rm -rf $PROT" deny allow allow allow
zeile R2 "bash scripts/wipe.sh (rm -rf im Skript)" "bash $EIGEN/scripts/wipe.sh" allow allow allow deny
grund_enthaelt "R2 Grund nennt Skript und bash-guard" "bash-guard.py"
zeile R3 "scripts/wipe.sh direkt (Shebang bash)" "$EIGEN/scripts/wipe.sh" allow allow allow deny
zeile R4 "source scripts/wipe.sh" "source $EIGEN/scripts/wipe.sh" allow allow allow deny
zeile R5 "sh scripts/wipe-arg.sh <geschuetzt> (\$1)" "sh $EIGEN/scripts/wipe-arg.sh $PROT" allow allow allow deny
zeile R6 "sh scripts/wipe-arg.sh <nicht vorhanden>" "sh $EIGEN/scripts/wipe-arg.sh $TESTHOME/snaps/nichts" allow allow allow allow
zeile R7 "rm tests/test_kern.py direkt (Gate-Pfad)" "rm tests/test_kern.py" allow deny allow allow
zeile R8 "sh scripts/tests-weg.sh (rm im Skript)" "sh $EIGEN/scripts/tests-weg.sh" allow allow allow deny
grund_enthaelt "R8 Grund nennt den Testschutz" "testschutz-gate.sh"
zeile R9 "sh scripts/ruft-haus.sh (Hausskill im Skript)" "sh $EIGEN/scripts/ruft-haus.sh" allow allow deny deny
zeile R10 "sh scripts/ok.sh (harmlos)" "sh $EIGEN/scripts/ok.sh" allow allow allow allow
zeile G1 "Grenze: python3 scripts/wipe.py (shutil.rmtree)" "python3 $EIGEN/scripts/wipe.py" allow allow allow allow
zeile R11 "ziel=\$(...); rm -rf \"\$ziel\" direkt" "ziel=\$(cat /dev/null); rm -rf \"\$ziel\"" deny deny allow allow
zeile R12 "sh scripts/dynamisch.sh (dasselbe im Skript)" "sh $EIGEN/scripts/dynamisch.sh" allow allow allow deny
zeile R13 "bash -c \"\$(cat scripts/wipe.sh)\"" "bash -c \"\$(cat $EIGEN/scripts/wipe.sh)\"" deny deny deny deny
zeile R14 "sh < scripts/wipe.sh (Skript ueber stdin)" "sh < $EIGEN/scripts/wipe.sh" allow allow allow deny
zeile G2 "Grenze: Skill-Skript ruft Projektskript mit rm -rf" "sh $EIGEN/scripts/ruft-helfer.sh" allow allow allow allow
printf '\n'
cat "$TABELLE"

# ------------------------------------------------------------ Fall 6 ----
section "6: Shell-Huelle"
start=$(python3 -c 'import time; print(time.time())')
fall "6a Laufzeit eines gewoehnlichen Befehls" allow Bash command "ls -la"
dauer=$(python3 -c "import time; print(round(time.time() - $start, 2))")
python3 -c "import sys; sys.exit(0 if $dauer < 2 else 1)" && ok "6a unter zwei Sekunden ($dauer s)" || bad "6a zu langsam: $dauer s"
OHNEKERN="$TESTHOME/hooks-ohne-kern"
mkdir -p "$OHNEKERN"
cp "$HOOKS_DIR/skills-sperre.sh" "$OHNEKERN/"
sperre "$OHNEKERN" Bash command ls; got="$ENTSCHEIDUNG"
[ "$got" = deny ] && ok "6b fehlender Kern -> deny" || bad "6b fehlender Kern: $got"
HAENGT="$TESTHOME/hooks-haengt"
mkdir -p "$HAENGT/lib"
cp "$HOOKS_DIR/skills-sperre.sh" "$HAENGT/"
printf 'import signal, time\nsignal.signal(signal.SIGALRM, signal.SIG_IGN)\ntime.sleep(60)\n' > "$HAENGT/lib/skills_sperre.py"
start=$(python3 -c 'import time; print(time.time())')
sperre "$HAENGT" Bash command ls; got="$ENTSCHEIDUNG"
dauer=$(python3 -c "import time; print(round(time.time() - $start, 1))")
[ "$got" = deny ] && ok "6c haengender Kern -> deny nach $dauer s" || bad "6c haengender Kern: $got"
python3 -c "import sys; sys.exit(0 if $dauer < 10 else 1)" && ok "6c vor der 10-Sekunden-Grenze" || bad "6c zu spaet: $dauer s"
sleep 0.5
if pgrep -f "$HAENGT/lib/skills_sperre.py" >/dev/null 2>&1; then
  bad "6c Kern lebt nach der Frist weiter"
  pkill -f "$HAENGT/lib/skills_sperre.py" 2>/dev/null || true
else
  ok "6c Prozessgruppe des Kerns beendet"
fi

# ------------------------------------------------------------ Fall 7 ----
section "7: Settings-Snippet und README"
if python3 - "$HOOKS_DIR/skills-sperre.settings-snippet.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
eintraege = d["hooks"]["PreToolUse"]
matcher = [e["matcher"] for e in eintraege]
assert matcher == ["Bash", "Skill", "Read|Grep|Glob", "Write|Edit|MultiEdit|NotebookEdit"], matcher
assert all(h["hooks"][0]["command"] == 'bash "$HOME/.claude/hooks/skills-sperre.sh"' and h["hooks"][0]["timeout"] == 60
           for h in eintraege)
PY
then ok "7a Snippet mit vier Mattchern"; else bad "7a Snippet ungueltig"; fi
grep -q "skills-sperre.sh" "$HOOKS_DIR/README.md" && ok "7b README beschreibt den Hook" || bad "7b README ohne Abschnitt"

# ------------------------------------------------------------ Fall 8 ----
section "8: gespeicherte Skripte wie Skills"
fall "8a eigenes Skript mit sh" allow Bash command "sh $SKRIPTE_EIGEN/eigen-skript/eigen-skript.sh"
fall "8b eigenes Skript direkt" allow Bash command "$SKRIPTE_EIGEN/eigen-skript/eigen-skript.sh"
fall "8c Weltskript mit passender Version" allow Bash command "sh $WELT/skripte/welt-skript/welt-skript.sh"
fall "8d Bibliotheksskript, von lib-skill verwiesen" allow Bash command "python3 $SKRIPTBIB/lib-skript/lib-skript.py"
fall "8e Read Bibliotheksskript" allow Read file_path "$SKRIPTBIB/lib-skript/lib-skript.py"
fall "8f Write eigenes Skript" allow Write file_path "$SKRIPTE_EIGEN/eigen-skript/eigen-skript.sh"
fall "8g ls der Welt- und der eigenen Skriptwurzel" allow Bash command "ls $WELT/skripte $SKRIPTE_EIGEN"
fall "8h nicht verwiesenes Bibliotheksskript" deny Bash command "sh $SKRIPTBIB/lib-fremd-skript/lib-fremd-skript.sh"
grund_enthaelt "8h Grund nennt skills.json" "not in the skills.json"
fall "8i Skript eines anderen Agenten" deny Bash command "sh $WELT/agents/other/skripte/fremd-skript/fremd-skript.sh"
fall "8j Skriptwurzel eines anderen Agenten" deny Bash command "ls $WELT/agents/other/skripte"
fall "8k Glob ueber fremde Skripte" deny Bash command "cat $WELT/agents/other/skripte/*/*.sh"
fall "8l Umleitung in Weltskript" deny Bash command "echo x >> $WELT/skripte/welt-skript/welt-skript.sh"
grund_enthaelt "8l Grund verweist auf wb-skill skript vorschlag" "wb-skill skript vorschlag"
fall "8m Edit im Bibliotheksskript" deny Edit file_path "$SKRIPTBIB/lib-skript/lib-skript.py"
fall "8n rm -rf auf Weltskript" deny Bash command "rm -rf $WELT/skripte/welt-skript"
fall "8o Skill-Werkzeug mit Skriptnamen" deny Skill skill eigen-skript
python3 - "$WELT" <<'PY'
import sys
from pathlib import Path
folder = Path(sys.argv[1]) / "skripte" / "spaeter-skript"
folder.mkdir(parents=True)
(folder / "spaeter-skript.sh").write_text("#!/bin/sh\n# ---\n# name: spaeter-skript\n# zweck: x\n# aufruf: x\n"
                                          "# eingaben: x\n# ausgaben: x\n# grenzen: x\n# ---\necho spaet\n")
(folder / "spaeter-skript.sh").chmod(0o755)
PY
fall "8p Weltskript nach dem Verzeichnis angelegt" deny Bash command "sh $WELT/skripte/spaeter-skript/spaeter-skript.sh"
printf '\n# heimlich geaendert\n' >> "$WELT/skripte/welt-skript/welt-skript.sh"
fall "8q geaendertes Weltskript (Version passt nicht)" deny Bash command "sh $WELT/skripte/welt-skript/welt-skript.sh"
grund_enthaelt "8q Grund nennt Skript und Version" "Skript 'welt-skript' (welt) differs from the version"
python3 - "$WELT/skripte/welt-skript/welt-skript.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read().replace("\n# heimlich geaendert\n", ""); open(p, "w").write(t)
PY
fall "8r wiederhergestelltes Weltskript" allow Bash command "sh $WELT/skripte/welt-skript/welt-skript.sh"
python3 - "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json" "$WELT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
eintrag = next(e for e in d["skills"] if e["name"] == "eigen")
d["skills"].append(dict(eintrag, art="skript"))   # Skripteintrag, der auf einen Skillordner zeigt
json.dump(d, open(sys.argv[2], "w"))
PY
fall "8s skills.json: Skripteintrag im Skillordner" deny Bash command "ls"
grund_enthaelt "8s Grund nennt die Ebene" "outside level"
python3 - "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["skills"][0]["art"] = "vorlage"; json.dump(d, open(sys.argv[2], "w"))
PY
fall "8t skills.json: unbekannte Art" deny Bash command "ls"
cp "$TESTHOME/skills.json.sicher" "$WELT/agents/member/skills.json"
fall "8u wiederhergestellt, ls" allow Bash command "ls"

TABELLE="$TESTHOME/tabelle-skripte.txt"
printf '| %-4s | %-52s | %-10s | %-10s | %-17s | %-17s |\n' "Fall" "Form" "bash-guard" "Testschutz" "Sperre ohne Kette" "Sperre mit Kette" > "$TABELLE"
zeile S1 "sh <eigen>/wipe-skript.sh (rm -rf im Skript)" "sh $SKRIPTE_EIGEN/wipe-skript/wipe-skript.sh" allow allow allow deny
grund_enthaelt "S1 Grund nennt Skript und bash-guard" "bash-guard.py"
zeile S2 "<welt>/skripte/welt-wipe.sh direkt (Shebang sh)" "$WELT/skripte/welt-wipe/welt-wipe.sh" allow allow allow deny
zeile S3 "bash < <eigen>/wipe-skript.sh (ueber stdin)" "bash < $SKRIPTE_EIGEN/wipe-skript/wipe-skript.sh" allow allow allow deny
zeile S4 "sh <eigen>/eigen-skript.sh (harmlos)" "sh $SKRIPTE_EIGEN/eigen-skript/eigen-skript.sh" allow allow allow allow
zeile S5 "sh <welt>/welt-skript.sh (harmlos)" "sh $WELT/skripte/welt-skript/welt-skript.sh" allow allow allow allow
zeile G3 "Grenze: python3 <bibliothek>/lib-skript.py (rmtree)" "python3 $SKRIPTBIB/lib-skript/lib-skript.py" allow allow allow allow
printf '\n'
cat "$TABELLE"

printf '\n=== ZUSAMMENFASSUNG ===\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
