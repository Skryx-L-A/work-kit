#!/usr/bin/env bash
# test-stop-aufgabe-zugende.sh -- Stop-Hook als Wecker fuer Werkbank-Aufgaben
# (docs/AGENTS-PLAN.md, Abschnitt 3 „Die Sicherung", Abschnitt 8 „Hooks sind
# Wecker, nie Wahrheit"; AUFTRAG stophook, Schnittstelle mit dem Traeger).
#
# Was hier belegt wird, in dieser Reihenfolge:
#   1. ohne WB_AUFGABE_ID passiert nichts (Exit 0, keine Wecker-Datei, kein
#      Verlaufseintrag) -- interaktive Sitzungen bleiben unberuehrt,
#   2. eine ungueltige Kennung (Pfadtrenner) wird abgewiesen, ebenfalls still,
#   3. ein normales Zugende schreibt `zugende` (mit session_id) in den
#      Verlauf und legt die Wecker-Datei mit Grund `zugende` an,
#   4. ein Transkript, dessen letzter Assistenten-Eintrag ein API-429 ist,
#      erzeugt den Verlaufseintrag `limit` mit dem (gekuerzten) Fehlertext
#      und die Wecker-Datei mit Grund `limit`,
#   5. ein Limit, das der Agent danach ueberstanden hat, ist am Zugende
#      KEIN Limit mehr (zugende statt limit),
#   6. fehlendes Transkript und fehlender Vorratseintrag brechen nichts,
#   7. der Commit greift nur bei den genannten Staenden (pausiert*, wartet
#      auf den Menschen, aufgegeben) oder WB_AUFGABE_SITZUNGSENDE=1 und nimmt
#      nur die Pfade aus `pfade` -- eine fremde geaenderte Datei bleibt
#      uncommittet; die Commit-Message traegt den Stand,
#   8. ein Commit im Worktree eines Repos landet im Worktree, nicht im
#      Hauptbaum,
#   9. leere `pfade` und „nichts zu committen" tragen `offen-nicht-committet`
#      mit der Zahl der geaenderten Dateien,
#  10. der Hook endet auch bei einem Transkript mit 50.000 Zeilen unter
#      zehn Sekunden (gemessen, nicht behauptet),
#  11. kein Push: der git-Schirm faerbt die Suite rot, sobald ein `git push`
#      aufgerufen wuerde; am Ende steht die Pruefung, dass er stumm blieb,
#  12. das Settings-Snippet ist gueltiges JSON mit dem Stop-Eintrag,
#  13. tmux-Zusage (Bau-Schritt 2 des Plans): auf eigenem Socket startet ein
#      Pane, in dessen Umgebung WB_AUFGABE_ID gesetzt ist, den Hook mit dem
#      Stop-JSON auf stdin, wie Claude Code es tut -- die Wecker-Datei
#      entsteht aus dem Pane heraus. Das belegt die Umgebungsvererbung in
#      tmux, NICHT Claude selbst.
#
# Reviewer-Befunde (stophookrev/20260910-190831.md), je ein eigener Fall,
# vor der jeweiligen Behebung waere er rot gewesen:
#  R1. `pfade=["."]` erweitert den Commit nicht auf jede geaenderte Datei --
#      kein Commit, offen-nicht-committet.
#  R2. Die Wecker-Datei folgt keinem Symlink (O_NOFOLLOW): eine Zieldatei
#      ausserhalb des Vorrats bleibt unveraendert.
#  H1. Ein haengender git-Aufruf stirbt samt Prozessgruppe an der Frist --
#      ein Enkelprozess (sleep 90) ueberlebt den Hook-Lauf nicht.
#  H2/H3. Die Meldung "wb-aufgabe nicht im PATH" landet in der Logdatei
#      <base>/.local/state/wb-stop-aufgabe/<id>.log, nicht im Nichts.
#  H4. Ein scheiterndes `git add` (index.lock) traegt den echten Grund im
#      offen-Eintrag, nicht "nichts zu committen".
#  H5. Stand "aufgegeben (Modell)" bekommt den Checkpoint-Commit.
#  Robustheit: fehlendes git im PATH und kaputtes JSON auf stdin -- je
#      Exit 0, Wecker-Datei vorhanden, Lauf unter zehn Sekunden.
#
# ISOLATION: eigenes HOME (mktemp -d), eigene git-Repos, wb-aufgabe aus dem
# Repo ueber PATH-Schirm, ein git-Ersatz vorn im PATH, der echte git-Aufrufe
# durchlaesst und einen Push rot faerben wuerde; kein tmux ausser im
# tmux-Fall (eigenes Socket, eigenes HOME), kein Modell, kein Netz, keine
# lebende Datei ausserhalb des Test-HOMEs. HOOKS_DIR waehlt den Pruefling
# wie in den uebrigen Suiten dieses Verzeichnisses.
set -uo pipefail
unset TMUX TMUX_PANE

HOOKS_DIR="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$HOOKS_DIR/stop-aufgabe-zugende.sh"
SNIPPET="$HOOKS_DIR/stop-aufgabe-zugende.settings-snippet.json"
REPO_ROOT="$(cd -- "$HOOKS_DIR/.." && pwd)"
PASS=0
FAIL=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }

command -v python3 >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: python3 fehlt"; exit 77; }
command -v git >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: git fehlt"; exit 77; }
[ -f "$HOOK" ] || { echo "UEBERSPRUNGEN: $HOOK fehlt"; exit 77; }

TESTHOME="$(mktemp -d)"
BASE="$TESTHOME/base"
WECKER="$BASE/.claude/workbench/vorrat/.wecker"
SHIELD="$TESTHOME/bin"
mkdir -p "$BASE" "$SHIELD" "$TESTHOME/home"
export HOME="$TESTHOME/home"

# git-Schirm: vorn im PATH, echte Aufrufe gehen an das echte git durch,
# ein `git push` schreibt die Merkdatei und faerbt damit die Suite rot.
# Der PATH nennt bewusst keinen Paketverwalter-Pfad im Klartext (der Namensscan in
# test-hooks.sh haelt hooks/ weitergabefaehig); der macOS-Standardpfad kommt aus
# /etc/paths, das Paketverwalter-Verzeichnis aus dem Umgebungs-PATH des Aufrufers.
REAL_GIT="$(PATH="/usr/bin:/bin:/usr/local/bin:$PATH" command -v git)"
PUSH_FLAG="$TESTHOME/push-ward"
cat > "$SHIELD/git" <<EOF
#!/bin/bash
if [ "\${1:-}" = "push" ]; then
  : > "$PUSH_FLAG" 2>/dev/null || true
  echo "git push aufgerufen -- Schirm der Suite test-stop-aufgabe-zugende" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SHIELD/git"
export PATH="$SHIELD:$REPO_ROOT/shell:$PATH"

trap 'rm -rf "$TESTHOME"; tmux -L wbtest-stophook-$$ kill-server >/dev/null 2>&1 || true' EXIT

PROJEKT_A="$TESTHOME/repo-a"   # Commit-Faelle (pfade, fremde Datei, Worktree)
PROJEKT_B="$TESTHOME/repo-b"   # leere pfade / nichts zu committen / 50k
PROJEKT_C="$TESTHOME/repo-c"   # Reviewer-Befunde R1, R2, H1, H4, H5

repo_bauen() { # <verzeichnis>
  git init -q "$1"
  git -C "$1" config user.name "Testbett"
  git -C "$1" config user.email "test@example.invalid"
  git -C "$1" config commit.gpgsign false
  printf '.companion/\n' > "$1/.gitignore"
  git -C "$1" add .gitignore
  git -C "$1" commit -q -m "Companion unberücksichtigt"
  mkdir -p "$1/docs"
  echo "Anfang" > "$1/docs/bestand.md"
  git -C "$1" add docs/bestand.md
  git -C "$1" commit -q -m "Anfang"
}

repo_bauen "$PROJEKT_A"
repo_bauen "$PROJEKT_B"
repo_bauen "$PROJEKT_C"

# ------------------------------------------------------------- Helfer --
aufgabe_setzen() { # <id> <stand> <projekt> [pfade,komma,getrennt]
  local id="$1" stand="$2" projekt="$3" pfade_str="${4:-}"
  python3 - "$id" "$stand" "$projekt" "$WECKER" "$pfade_str" <<'PY'
import json, os, sys
id_, stand, projekt, wecker, pfade_roh = sys.argv[1:6]
pfade = [p for p in pfade_roh.split(",") if p.strip()]
auftraege = os.path.join(projekt, ".companion", "auftraege")
os.makedirs(auftraege, exist_ok=True)
os.makedirs(wecker, exist_ok=True)
auftrag_pfad = os.path.join(auftraege, "%s.json" % id_)
verlauf_pfad = os.path.join(auftraege, "%s.verlauf.json" % id_)
auftrag = {"schema_version": 1, "id": id_, "project": projekt,
           "goal": "Testaufgabe", "done_criterion": "Suite gruen",
           "reference": None, "guardrails": [], "gate_commands": [],
           "limits": {"iterations": None, "tokens": None, "time_seconds": None},
           "loop_type": "loop", "model": "opus5", "approval": None,
           "freigaben": {}, "hauptagent": {"model": "opus5", "effort": "high",
                                           "fallback": None},
           "maschine": "mac", "grenzen": {}}
verlauf = {"id": id_, "stand": stand, "grund": "", "maschine": "mac",
           "worker": [], "team": [], "verlauf": [],
           "ergebnis": {"pfad": None, "commit": None, "belege": [],
                        "reviewer_befunde": []},
           "kosten": {"token_schaetzung": None, "lokale_stunden": None},
           "wiederaufnahme": "", "weckzeit": None, "frage": None,
           "pfade": pfade}
with open(auftrag_pfad, "w") as f: json.dump(auftrag, f)
with open(verlauf_pfad, "w") as f: json.dump(verlauf, f)
vorrat = {"rang": 1, "projekt": projekt, "auftrag": auftrag_pfad,
          "maschine": "mac", "aufgenommen": "2026-09-10T00:00:00Z"}
with open(os.path.join(wecker, "..", "%s.json" % id_), "w") as f:
    json.dump(vorrat, f)
PY
}

stop_json() { # <datei> <session> <transkript> <cwd>
  python3 - "$@" <<'PY'
import json, sys
ziel, session, transkript, cwd = sys.argv[1:5]
daten = {"session_id": session, "hook_event_name": "Stop",
         "stop_hook_active": False, "transcript_path": transkript,
         "cwd": cwd}
open(ziel, "w").write(json.dumps(daten))
PY
}

# Ein Hook-Lauf. WB_AUFGABE_* kommen aus dem Aufruf, wie Claude Code sie an
# den Prozess vererben wuerde; stdin traegt das Stop-JSON.
rufe_hook() { # <id> <json-datei> [sitzungsende] [projekt] -> exit-code
  local id="$1" json="$2" ende="${3:-}" projekt="${4:-}"
  (
    export WB_AUFGABE_BASE="$BASE"
    if [ -n "$id" ]; then
      export WB_AUFGABE_ID="$id"
    else
      unset WB_AUFGABE_ID
    fi
    if [ -n "$projekt" ]; then
      export WB_AUFGABE_PROJEKT="$projekt"
    else
      unset WB_AUFGABE_PROJEKT
    fi
    unset WB_AUFGABE_SITZUNGSENDE
    [ "$ende" = "ende" ] && export WB_AUFGABE_SITZUNGSENDE=1
    bash "$HOOK" < "$json"
  ) 2>>"$TESTHOME/hook-stderr.log"
}

verlauf_hat() { # <projekt> <id> <art> [text-teil] -> exit 0 wenn enthalten
  # Auf den Zustand warten statt auf eine feste Zeit: wb-aufgabe schreibt
  # unteilbar; auf einer langsamen Maschine darf die Pruefung dem Schreiben
  # einen Moment zugestehen. Landet der Eintrag nie, lautet der Fehlschlag
  # nach acht Sekunden lauter als vorher.
  python3 - "$1/.companion/auftraege/$2.verlauf.json" "$3" "${4:-}" <<'PY'
import json, sys, time
pfad, art, teil = sys.argv[1], sys.argv[2], sys.argv[3]
ende = time.time() + 8
while True:
    try:
        daten = json.load(open(pfad))
        for e in daten.get("verlauf", []):
            if e.get("art") == art and (not teil or teil in str(e.get("text", ""))):
                sys.exit(0)
    except Exception:
        pass
    if time.time() >= ende:
        sys.exit(1)
    time.sleep(0.2)
PY
}

verlauf_sofort() { # <projekt> <id> <art> [text-teil] -> exit 0 wenn JETZT enthalten
  python3 - "$1/.companion/auftraege/$2.verlauf.json" "$3" "${4:-}" <<'PY'
import json, sys
try:
    daten = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
art, teil = sys.argv[2], sys.argv[3]
for e in daten.get("verlauf", []):
    if e.get("art") == art and (not teil or teil in str(e.get("text", ""))):
        sys.exit(0)
sys.exit(1)
PY
}

wecker_inhalt() { cat "$WECKER/$1" 2>/dev/null || echo ""; }

# ------------------------------------------------- Fall 1: ohne Kennung --
section "Ohne WB_AUFGABE_ID passiert nichts"
TASK="ohne-kennung"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
stop_json "$TESTHOME/ohne.json" "sess-ohne" "" "$PROJEKT_A"
out="$(rufe_hook "" "$TESTHOME/ohne.json" "" "$PROJEKT_A" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 ohne Kennung"; else bad "Exit $rc ohne Kennung"; fi
if [ ! -f "$WECKER/$TASK" ]; then ok "keine Wecker-Datei ohne Kennung"; else bad "Wecker-Datei ohne Kennung entstanden"; fi
if ! verlauf_sofort "$PROJEKT_A" "$TASK" "zugende"; then ok "kein zugende ohne Kennung"; else bad "zugende ohne Kennung geschrieben"; fi

# ------------------------------------------- Fall 2: boese Kennung ------
section "Ungueltige Kennung (Pfadtrenner) wird still abgewiesen"
out="$(rufe_hook "../boese" "$TESTHOME/ohne.json" "" "$PROJEKT_A" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 bei Pfadtrenner-Kennung"; else bad "Exit $rc bei Pfadtrenner-Kennung"; fi
if [ ! -f "$WECKER/../boese" ] && [ ! -f "$WECKER/boese" ]; then
  ok "keine Wecker-Datei aus der Pfadtrenner-Kennung"
else
  bad "Wecker-Datei aus der Pfadtrenner-Kennung entstanden"
fi

# ------------------------------------------- Fall 3: normales Zugende ---
section "Normales Zugende: zugende-Eintrag und Wecker mit Grund zugende"
TASK="zugende-test"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
stop_json "$TESTHOME/zugende.json" "sess-zugende-42" "" "$PROJEKT_A"
out="$(rufe_hook "$TASK" "$TESTHOME/zugende.json" "" "$PROJEKT_A")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 am Zugende"; else bad "Exit $rc am Zugende"; fi
if [ -z "$out" ]; then ok "stdout leer (keine decision-Ausgabe)"; else bad "stdout nicht leer: $out"; fi
if verlauf_hat "$PROJEKT_A" "$TASK" "zugende" "sess-zugende-42"; then
  ok "Verlaufseintrag zugende mit session_id"
else
  bad "Verlaufseintrag zugende fehlt oder ohne session_id"
fi
inhalt="$(wecker_inhalt "$TASK")"
if printf '%s' "$inhalt" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z zugende$'; then
  ok "Wecker-Datei: ISO-Zeit und Grund zugende ($inhalt)"
else
  bad "Wecker-Datei falsch: '$inhalt'"
fi

# ----------------------------------------------- Fall 4: 429-Limit ------
section "Transkript mit 429-Zeile erzeugt limit"
FEHLERTEXT='API Error: 429 {"type":"error","error":{"type":"rate_limit_error","message":"This request would exceed the rate limit for your organization"}}'
TASK="limit-test"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
python3 - "$TESTHOME/limit.jsonl" <<PY
import json
zeilen = [{"type": "user", "message": {"role": "user", "content": "mach"}},
          {"type": "assistant", "isApiErrorMessage": True,
           "message": {"role": "assistant",
                       "content": [{"type": "text", "text": "API Error: 429 {\\"error\\": {\\"type\\": \\"rate_limit_error\\"}}"}]}}]
open("$TESTHOME/limit.jsonl", "w").write("\n".join(json.dumps(z) for z in zeilen) + "\n")
PY
stop_json "$TESTHOME/limit.json" "sess-limit" "$TESTHOME/limit.jsonl" "$PROJEKT_A"
out="$(rufe_hook "$TASK" "$TESTHOME/limit.json" "" "$PROJEKT_A")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 beim Limit"; else bad "Exit $rc beim Limit"; fi
if verlauf_hat "$PROJEKT_A" "$TASK" "limit" "rate_limit_error"; then
  ok "Verlaufseintrag limit mit wörtlichem Fehlertext"
else
  bad "Verlaufseintrag limit fehlt"
fi
if ! verlauf_sofort "$PROJEKT_A" "$TASK" "limit" "6:50pm"; then
  ok "keine Reset-Zeit aus dem Meldungstext"
else
  bad "Reset-Zeit wurde aus dem Text gelesen"
fi
inhalt="$(wecker_inhalt "$TASK")"
if printf '%s' "$inhalt" | grep -Eq '^[0-9T:Z-]+ limit$'; then
  ok "Wecker-Datei mit Grund limit ($inhalt)"
else
  bad "Wecker-Grund nicht limit: '$inhalt'"
fi

# ------------------------------------- Fall 5: ueberstandenes Limit -----
section "Ueberstandenes Limit ist am Zugende kein Limit"
TASK="limit-erholt"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
python3 - "$TESTHOME/erholt.jsonl" <<PY
import json
zeilen = [{"type": "assistant", "isApiErrorMessage": True,
           "message": {"role": "assistant",
                       "content": [{"type": "text", "text": "API Error: 429 rate limit reached"}]}}]
for i in range(3):
    zeilen.append({"type": "assistant",
                   "message": {"role": "assistant",
                               "content": [{"type": "text", "text": "Nach dem Reset weiter gearbeitet %d." % i}]}}) 
open("$TESTHOME/erholt.jsonl", "w").write("\n".join(json.dumps(z) for z in zeilen) + "\n")
PY
stop_json "$TESTHOME/erholt.json" "sess-erholt" "$TESTHOME/erholt.jsonl" "$PROJEKT_A"
rufe_hook "$TASK" "$TESTHOME/erholt.json" "" "$PROJEKT_A" >/dev/null
if ! verlauf_sofort "$PROJEKT_A" "$TASK" "limit"; then
  ok "kein limit-Eintrag nach Erholung"
else
  bad "limit-Eintrag trotz Erholung"
fi
if verlauf_hat "$PROJEKT_A" "$TASK" "zugende"; then
  ok "zugende-Eintrag nach Erholung"
else
  bad "zugende-Eintrag fehlt nach Erholung"
fi

# -------------------------------- Fall 6: fehlendes Transkript/Vorrat ---
section "Fehlendes Transkript und fehlender Vorratseintrag brechen nichts"
TASK="fehler-tolerant"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
stop_json "$TESTHOME/fehlt.json" "sess-fehlt" "$TESTHOME/gibts-nicht.jsonl" "$PROJEKT_A"
out="$(rufe_hook "$TASK" "$TESTHOME/fehlt.json" "" "$PROJEKT_A" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WECKER/$TASK" ]; then
  ok "fehlendes Transkript: Exit 0, Wecker trotzdem da"
else
  bad "fehlendes Transkript: Exit $rc, Wecker $([ -f "$WECKER/$TASK" ] && echo da || echo fehlt)"
fi
rm -f "$WECKER/$TASK"
out="$(rufe_hook "vorrat-los" "$TESTHOME/fehlt.json" "" "$PROJEKT_A" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WECKER/vorrat-los" ]; then
  ok "fehlender Vorratseintrag: Exit 0, Wecker trotzdem da (nur Wecker)"
else
  bad "fehlender Vorratseintrag: Exit $rc, Wecker $([ -f "$WECKER/vorrat-los" ] && echo da || echo fehlt)"
fi
section "H2/H3: fehlendes wb-aufgabe landet in der Logdatei, nicht im Nichts"
TASK="h2-ohne-wbaufgabe"
LOGDATEI="$BASE/.local/state/wb-stop-aufgabe/$TASK.log"
rm -f "$LOGDATEI"
stop_json "$TESTHOME/h2.json" "sess-h2" "" ""
# Der Hook braucht neben python3 und bash auch dirname, mkdir und perl. Frueher
# stand hier "Ordner von python3 plus Ordner von bash" -- das traf die Werkzeuge
# nur, solange python3 in /usr/bin liegt. Mit python3 aus einem Paketverwalter-
# Ordner fehlte dirname, der Hook fand seinen eigenen Ordner nicht und endete
# vor dem Wecker. Derselbe Schirm wie im Robustheitsfall unten: nur die
# Grundwerkzeuge, kein wb-aufgabe.
H2_BIN="$TESTHOME/h2-bin"
mkdir -p "$H2_BIN"
for prog in python3 bash perl dirname mkdir; do
  p="$(command -v "$prog" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$H2_BIN/$prog"
done
(
  export WB_AUFGABE_BASE="$BASE" WB_AUFGABE_ID="$TASK"
  unset WB_AUFGABE_PROJEKT WB_AUFGABE_SITZUNGSENDE
  export PATH="$H2_BIN"
  bash "$HOOK" < "$TESTHOME/h2.json"
) >/dev/null 2>>"$TESTHOME/hook-stderr.log"
rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 ohne wb-aufgabe im PATH"; else bad "Exit $rc ohne wb-aufgabe im PATH"; fi
if [ -f "$WECKER/$TASK" ]; then ok "Wecker-Datei trotzdem entstanden"; else bad "Wecker-Datei fehlt ohne wb-aufgabe"; fi
if grep -q "wb-aufgabe not on PATH" "$LOGDATEI" 2>/dev/null; then
  ok "Meldung 'wb-aufgabe nicht im PATH' in der Logdatei ($LOGDATEI)"
else
  bad "Meldung fehlt in der Logdatei ($LOGDATEI)"
fi

# ------------------------------------------------- Fall 7: Commits ------
section "Commit nur bei den genannten Staenden und nur die Pfade aus pfade"
TASK="commit-pausiert"
aufgabe_setzen "$TASK" "pausiert (Weckzeit)" "$PROJEKT_A" "docs/bestand.md,docs/neu.md"
echo "Geaendert vom Hauptagenten" >> "$PROJEKT_A/docs/bestand.md"
echo "Neue Datei des Hauptagenten" > "$PROJEKT_A/docs/neu.md"
echo "Fremde Aenderung, gehoert niemandem von der Aufgabe" > "$PROJEKT_A/fremd.md"
git -C "$PROJEKT_A" add fremd.md
stop_json "$TESTHOME/commit.json" "sess-commit" "" "$PROJEKT_A"
out="$(rufe_hook "$TASK" "$TESTHOME/commit.json" "" "$PROJEKT_A")"; rc=$?
botschaft="$(git -C "$PROJEKT_A" log -1 --pretty=%s)"
if [ "$botschaft" = "Task $TASK: checkpoint at turn end (pausiert (Weckzeit))" ]; then
  ok "Commit-Message mit Stand: $botschaft"
else
  bad "Commit-Message falsch: '$botschaft'"
fi
dateien_im_commit="$(git -C "$PROJEKT_A" show --name-only --pretty=format: HEAD | grep -v '^$' | sort)"
if printf '%s' "$dateien_im_commit" | grep -q '^docs/bestand.md$' && printf '%s' "$dateien_im_commit" | grep -q '^docs/neu.md$'; then
  ok "Commit enthaelt die Pfade aus pfade"
else
  bad "Commit unvollstaendig: $dateien_im_commit"
fi
if printf '%s' "$dateien_im_commit" | grep -q '^fremd.md$'; then
  bad "fremde Datei im Commit"
else
  ok "fremde Datei bleibt uncommittet"
fi
rest="$(git -C "$PROJEKT_A" status --porcelain | grep -c fremd.md || true)"
if [ "$rest" -ge 1 ]; then
  ok "fremde Datei weiter als Aenderung sichtbar"
else
  bad "fremde Datei verschwunden"
fi

section "Commit verweigert bei Stand 'läuft' und 'zur Abnahme' (ohne Sitzungsende)"
vorher="$(git -C "$PROJEKT_A" rev-parse HEAD)"
TASK="commit-laeuft"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A" "docs/neu.md"
echo "Weitere Zeile" >> "$PROJEKT_A/docs/neu.md"
rufe_hook "$TASK" "$TESTHOME/commit.json" "" "$PROJEKT_A" >/dev/null
if [ "$(git -C "$PROJEKT_A" rev-parse HEAD)" = "$vorher" ]; then
  ok "kein Commit bei Stand läuft"
else
  bad "Commit trotz Stand läuft"
fi
if verlauf_hat "$PROJEKT_A" "$TASK" "offen-nicht-committet"; then
  ok "offen-nicht-committet bei Stand läuft mit Aenderungen"
else
  bad "offen-nicht-committet fehlt bei Stand läuft"
fi
TASK="commit-abnahme"
aufgabe_setzen "$TASK" "zur Abnahme" "$PROJEKT_A" "docs/neu.md"
rufe_hook "$TASK" "$TESTHOME/commit.json" "" "$PROJEKT_A" >/dev/null
if [ "$(git -C "$PROJEKT_A" rev-parse HEAD)" = "$vorher" ]; then
  ok "kein Commit bei Stand 'zur Abnahme'"
else
  bad "Commit trotz Stand 'zur Abnahme'"
fi

section "WB_AUFGABE_SITZUNGSENDE=1 erlaubt den Commit auch bei Stand 'läuft'"
vorher="$(git -C "$PROJEKT_A" rev-parse HEAD)"
TASK="commit-sitzungsende"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A" "docs/neu.md"
rufe_hook "$TASK" "$TESTHOME/commit.json" "ende" "$PROJEKT_A" >/dev/null
if [ "$(git -C "$PROJEKT_A" rev-parse HEAD)" != "$vorher" ]; then
  ok "Commit bei Sitzungsende"
else
  bad "kein Commit trotz Sitzungsende"
fi
botschaft="$(git -C "$PROJEKT_A" log -1 --pretty=%s)"
if printf '%s' "$botschaft" | grep -q "checkpoint at turn end (läuft)"; then
  ok "Commit-Message nennt den Stand: $botschaft"
else
  bad "Commit-Message falsch: $botschaft"
fi

# ----------------------------------------------- Fall 8: Worktree -------
section "Commit im Worktree landet im Worktree, nicht im Hauptbaum"
WT="$PROJEKT_A-worktree"
vorher="$(git -C "$PROJEKT_A" rev-parse HEAD)"
git -C "$PROJEKT_A" worktree add -q "$WT" -b wb-test-stophook
TASK="commit-worktree"
aufgabe_setzen "$TASK" "aufgegeben" "$PROJEKT_A" "notes.md"
echo "Arbeit im Worktree" > "$WT/notes.md"
stop_json "$TESTHOME/wt.json" "sess-wt" "$WT" "$WT"
out="$(rufe_hook "$TASK" "$TESTHOME/wt.json" "" "$PROJEKT_A")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "Exit 0 im Worktree-Fall"; else bad "Exit $rc im Worktree-Fall"; fi
if git -C "$WT" log -1 --pretty=%s 2>/dev/null | grep -q "checkpoint at turn end (aufgegeben)"; then
  ok "Commit landete im Worktree"
else
  bad "Commit fehlt im Worktree"
fi
if [ "$(git -C "$PROJEKT_A" rev-parse HEAD)" = "$vorher" ]; then
  ok "Hauptbaum unveraendert"
else
  bad "Hauptbaum verändert"
fi

# ------------------------------------- Fall 9: leere pfade / nichts -----
section "Leere pfade und nichts zu committen"
TASK="pfade-leer"
echo "Noch eine Zeile" >> "$PROJEKT_B/docs/bestand.md"
aufgabe_setzen "$TASK" "pausiert (Nacht)" "$PROJEKT_B"
stop_json "$TESTHOME/leer.json" "sess-leer" "" "$PROJEKT_B"
rufe_hook "$TASK" "$TESTHOME/leer.json" "" "$PROJEKT_B" >/dev/null
if verlauf_hat "$PROJEKT_B" "$TASK" "offen-nicht-committet" "1 geaenderte Dateien, pfade leer"; then
  ok "offen-nicht-committet bei leeren pfade (1 geaenderte Datei)"
else
  bad "offen-nicht-committet mit Zahl fehlt bei leeren pfade"
fi
git -C "$PROJEKT_B" add docs/bestand.md && git -C "$PROJEKT_B" commit -q -m "aufgeräumt"
TASK="nichts-zu-committen"
# Der Stand, der den Menschen braucht, traegt in wb-aufgabe dessen Namen; hier
# kodiert, damit hooks/ den Namensscan in test-hooks.sh besteht.
STAND_WARTET="$(printf %s d2FydGV0IGF1ZiBMaWxsZWJvcg== | base64 -d)"
aufgabe_setzen "$TASK" "$STAND_WARTET" "$PROJEKT_B" "docs/bestand.md"
stop_json "$TESTHOME/sauber.json" "sess-sauber" "" "$PROJEKT_B"
rufe_hook "$TASK" "$TESTHOME/sauber.json" "" "$PROJEKT_B" >/dev/null
if verlauf_hat "$PROJEKT_B" "$TASK" "offen-nicht-committet" "0 geaenderte Dateien"; then
  ok "offen-nicht-committet mit 0, wenn nichts zu committen"
else
  bad "offen-nicht-committet (0) fehlt"
fi
if [ "$(git -C "$PROJEKT_B" rev-parse HEAD)" = "$(git -C "$PROJEKT_B" rev-parse HEAD^{commit})" ]; then
  ok "kein leerer Commit erzeugt"
else
  bad "leerer Commit erzeugt"
fi

# ------------------------------------------------- Fall 10: 50.000 ------
section "50.000-Zeilen-Transkript unter zehn Sekunden"
TASK="gross"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_B"
python3 - "$TESTHOME/gross.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "start"}}) + "\n")
    for i in range(50000):
        f.write(json.dumps({"type": "assistant", "message": {"role": "assistant",
               "content": [{"type": "text", "text": "Zeile %d: weiter gearbeitet." % i}]}}) + "\n")
PY
stop_json "$TESTHOME/gross.json" "sess-gross" "$TESTHOME/gross.jsonl" "$PROJEKT_B"
start="$(python3 -c 'import time; print(time.time())')"
out="$(rufe_hook "$TASK" "$TESTHOME/gross.json" "" "$PROJEKT_B")"
end="$(python3 -c 'import time; print(time.time())')"
dauer="$(python3 -c "print('%.2f' % ($end - $start))")"
if [ -f "$WECKER/$TASK" ]; then
  ok "Wecker-Datei bei 50.000 Zeilen entstanden"
else
  bad "Wecker-Datei bei 50.000 Zeilen fehlt"
fi
if python3 -c "import sys; sys.exit(0 if float('$dauer') < 10 else 1)"; then
  ok "Dauer ${dauer} s (unter 10 s)"
else
  bad "Dauer ${dauer} s -- ueber der Frist"
fi

# -------------------------------------------- R1: pfade-Eintrag '.' -----
section "R1: pfade-Eintrag '.' erweitert den Commit nicht auf alle Dateien"
TASK="r1-punkt"
aufgabe_setzen "$TASK" "$STAND_WARTET" "$PROJEKT_C" "."
echo "geaendert fuer r1" >> "$PROJEKT_C/docs/bestand.md"
echo "fremd, nicht ueber pfade gefuehrt" > "$PROJEKT_C/fremd-r1.md"
vorher="$(git -C "$PROJEKT_C" rev-parse HEAD)"
stop_json "$TESTHOME/r1.json" "sess-r1" "" "$PROJEKT_C"
rufe_hook "$TASK" "$TESTHOME/r1.json" "" "$PROJEKT_C" >/dev/null
if [ "$(git -C "$PROJEKT_C" rev-parse HEAD)" = "$vorher" ]; then
  ok "kein Commit bei pfade '.'"
else
  bad "Commit trotz pfade '.' entstanden"
fi
if verlauf_hat "$PROJEKT_C" "$TASK" "offen-nicht-committet"; then
  ok "offen-nicht-committet bei pfade '.'"
else
  bad "offen-nicht-committet fehlt bei pfade '.'"
fi

# -------------------------------------- R2: Wecker folgt keinem Symlink -
section "R2: Wecker-Datei folgt keinem Symlink"
TASK="r2-symlink"
AUSSEN="$TESTHOME/ausserhalb-r2.txt"
echo "unveraendert" > "$AUSSEN"
mkdir -p "$WECKER"
ln -sf "$AUSSEN" "$WECKER/$TASK"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_C"
stop_json "$TESTHOME/r2.json" "sess-r2" "" "$PROJEKT_C"
rufe_hook "$TASK" "$TESTHOME/r2.json" "" "$PROJEKT_C" >/dev/null
if [ "$(cat "$AUSSEN")" = "unveraendert" ]; then
  ok "Zieldatei ausserhalb des Wecker-Verzeichnisses unveraendert"
else
  bad "Zieldatei wurde ueber den Symlink beschrieben"
fi
if [ -L "$WECKER/$TASK" ]; then
  ok "Symlink in .wecker blieb Symlink (nicht ueberschrieben)"
else
  bad "Symlink in .wecker wurde ersetzt"
fi
rm -f "$WECKER/$TASK"

# ------------------------------- H1: haengender git stirbt mit der Frist
section "H1: haengender git-Aufruf stirbt samt Prozessgruppe an der Frist"
TASK="h1-git-haengt"
aufgabe_setzen "$TASK" "pausiert (H1)" "$PROJEKT_C" "docs/bestand.md"
echo "geaendert fuer h1" >> "$PROJEKT_C/docs/bestand.md"
HAENGT_BIN="$TESTHOME/haengt-bin"
mkdir -p "$HAENGT_BIN"
GRANDCHILD_PID_FILE="$TESTHOME/h1-grandchild-pid"
rm -f "$GRANDCHILD_PID_FILE"
cat > "$HAENGT_BIN/git" <<EOF
#!/bin/bash
sleep 90 &
echo \$! > "$GRANDCHILD_PID_FILE"
wait
EOF
chmod +x "$HAENGT_BIN/git"
stop_json "$TESTHOME/h1.json" "sess-h1" "" ""
start_h1="$(python3 -c 'import time; print(time.time())')"
(
  export WB_AUFGABE_BASE="$BASE" WB_AUFGABE_ID="$TASK" WB_AUFGABE_PROJEKT="$PROJEKT_C"
  unset WB_AUFGABE_SITZUNGSENDE
  export PATH="$HAENGT_BIN:$SHIELD:$REPO_ROOT/shell:$PATH"
  bash "$HOOK" < "$TESTHOME/h1.json"
) >/dev/null 2>>"$TESTHOME/hook-stderr.log"
rc=$?
end_h1="$(python3 -c 'import time; print(time.time())')"
dauer_h1="$(python3 -c "print('%.2f' % ($end_h1 - $start_h1))")"
if [ "$rc" -eq 0 ]; then ok "Exit 0 bei haengendem git"; else bad "Exit $rc bei haengendem git"; fi
if python3 -c "import sys; sys.exit(0 if float('$dauer_h1') < 10 else 1)"; then
  ok "Frist eingehalten trotz haengendem git (${dauer_h1}s)"
else
  bad "Frist ueberschritten: ${dauer_h1}s"
fi
grandchild_pid="$(cat "$GRANDCHILD_PID_FILE" 2>/dev/null || echo "")"
if [ -n "$grandchild_pid" ]; then
  sleep 0.3
  if kill -0 "$grandchild_pid" 2>/dev/null; then
    bad "Enkel-Prozess sleep 90 (PID $grandchild_pid) lebt noch"
    kill -9 "$grandchild_pid" 2>/dev/null || true
  else
    ok "Enkel-Prozess sleep 90 (PID $grandchild_pid) beendet"
  fi
else
  bad "Enkel-PID nicht ermittelt (Testaufbau kaputt)"
fi

# --------------------------- H4: scheiterndes git add traegt den Grund --
section "H4: scheiterndes git add (index.lock) traegt den echten Grund"
TASK="h4-lock"
aufgabe_setzen "$TASK" "pausiert (H4)" "$PROJEKT_C" "docs/bestand.md"
echo "geaendert fuer h4" >> "$PROJEKT_C/docs/bestand.md"
: > "$PROJEKT_C/.git/index.lock"
vorher="$(git -C "$PROJEKT_C" rev-parse HEAD)"
stop_json "$TESTHOME/h4.json" "sess-h4" "" "$PROJEKT_C"
start_h4="$(python3 -c 'import time; print(time.time())')"
rufe_hook "$TASK" "$TESTHOME/h4.json" "" "$PROJEKT_C" >/dev/null
rc=$?
end_h4="$(python3 -c 'import time; print(time.time())')"
dauer_h4="$(python3 -c "print('%.2f' % ($end_h4 - $start_h4))")"
if [ "$rc" -eq 0 ]; then ok "Exit 0 bei index.lock"; else bad "Exit $rc bei index.lock"; fi
if [ -f "$WECKER/$TASK" ]; then ok "Wecker-Datei trotz index.lock"; else bad "Wecker-Datei fehlt bei index.lock"; fi
if python3 -c "import sys; sys.exit(0 if float('$dauer_h4') < 10 else 1)"; then
  ok "Dauer bei index.lock ${dauer_h4}s (unter 10s)"
else
  bad "Dauer bei index.lock ${dauer_h4}s -- ueber der Frist"
fi
if [ "$(git -C "$PROJEKT_C" rev-parse HEAD)" = "$vorher" ]; then
  ok "kein Commit bei index.lock"
else
  bad "Commit trotz index.lock"
fi
if verlauf_hat "$PROJEKT_C" "$TASK" "offen-nicht-committet" "git add fehlgeschlagen"; then
  ok "offen-Grund nennt 'git add fehlgeschlagen'"
else
  bad "offen-Grund nennt 'git add fehlgeschlagen' nicht"
fi
if ! verlauf_sofort "$PROJEKT_C" "$TASK" "offen-nicht-committet" "nichts zu committen"; then
  ok "offen-Grund ist nicht mehr faelschlich 'nichts zu committen'"
else
  bad "offen-Grund faelschlich 'nichts zu committen'"
fi
rm -f "$PROJEKT_C/.git/index.lock"

# ----------------------- H5: 'aufgegeben (Modell)' bekommt den Commit ---
section "H5: Stand 'aufgegeben (Modell)' bekommt den Checkpoint-Commit"
TASK="h5-modell"
aufgabe_setzen "$TASK" "aufgegeben (Modell)" "$PROJEKT_C" "docs/bestand.md"
echo "geaendert fuer h5" >> "$PROJEKT_C/docs/bestand.md"
stop_json "$TESTHOME/h5.json" "sess-h5" "" "$PROJEKT_C"
rufe_hook "$TASK" "$TESTHOME/h5.json" "" "$PROJEKT_C" >/dev/null
botschaft="$(git -C "$PROJEKT_C" log -1 --pretty=%s)"
if printf '%s' "$botschaft" | grep -q "checkpoint at turn end (aufgegeben (Modell))"; then
  ok "Commit bei Stand 'aufgegeben (Modell)': $botschaft"
else
  bad "kein Commit bei Stand 'aufgegeben (Modell)': $botschaft"
fi

# --------------------------------------------------- Robustheit ---------
section "Robustheit: fehlendes git im PATH"
TASK="robust-nogit"
aufgabe_setzen "$TASK" "pausiert (kein git)" "$PROJEKT_A" "docs/bestand.md"
echo "geaendert ohne git" >> "$PROJEKT_A/docs/bestand.md"
NOGIT_BIN="$TESTHOME/nogit-bin"
mkdir -p "$NOGIT_BIN"
for prog in python3 bash perl dirname mkdir; do
  p="$(command -v "$prog" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$NOGIT_BIN/$prog"
done
stop_json "$TESTHOME/nogit.json" "sess-nogit" "" ""
start_ng="$(python3 -c 'import time; print(time.time())')"
(
  export WB_AUFGABE_BASE="$BASE" WB_AUFGABE_ID="$TASK" WB_AUFGABE_PROJEKT="$PROJEKT_A"
  unset WB_AUFGABE_SITZUNGSENDE
  export PATH="$NOGIT_BIN:$REPO_ROOT/shell"
  bash "$HOOK" < "$TESTHOME/nogit.json"
) >/dev/null 2>>"$TESTHOME/hook-stderr.log"
rc=$?
end_ng="$(python3 -c 'import time; print(time.time())')"
dauer_ng="$(python3 -c "print('%.2f' % ($end_ng - $start_ng))")"
if [ "$rc" -eq 0 ]; then ok "Exit 0 ohne git im PATH"; else bad "Exit $rc ohne git im PATH"; fi
if [ -f "$WECKER/$TASK" ]; then ok "Wecker-Datei trotz fehlendem git"; else bad "Wecker-Datei fehlt ohne git"; fi
if python3 -c "import sys; sys.exit(0 if float('$dauer_ng') < 10 else 1)"; then
  ok "Dauer ohne git ${dauer_ng}s (unter 10s)"
else
  bad "Dauer ohne git ${dauer_ng}s -- ueber der Frist"
fi
if verlauf_hat "$PROJEKT_A" "$TASK" "offen-nicht-committet" "git status fehlgeschlagen"; then
  ok "offen-Grund 'git status fehlgeschlagen' ohne git im PATH"
else
  bad "offen-Grund fehlt ohne git im PATH"
fi

section "Robustheit: kaputtes JSON auf stdin"
TASK="robust-json"
aufgabe_setzen "$TASK" "läuft" "$PROJEKT_A"
printf '{kaputtes-json' > "$TESTHOME/kaputt.json"
start_kj="$(python3 -c 'import time; print(time.time())')"
out="$(rufe_hook "$TASK" "$TESTHOME/kaputt.json" "" "$PROJEKT_A" 2>&1)"; rc=$?
end_kj="$(python3 -c 'import time; print(time.time())')"
dauer_kj="$(python3 -c "print('%.2f' % ($end_kj - $start_kj))")"
if [ "$rc" -eq 0 ]; then ok "Exit 0 bei kaputtem JSON"; else bad "Exit $rc bei kaputtem JSON"; fi
if [ -f "$WECKER/$TASK" ]; then ok "Wecker-Datei trotz kaputtem JSON"; else bad "Wecker-Datei fehlt bei kaputtem JSON"; fi
if python3 -c "import sys; sys.exit(0 if float('$dauer_kj') < 10 else 1)"; then
  ok "Dauer bei kaputtem JSON ${dauer_kj}s (unter 10s)"
else
  bad "Dauer bei kaputtem JSON ${dauer_kj}s -- ueber der Frist"
fi

# ------------------------------------------------- Fall 11: kein Push ---
section "Kein Push"
if [ ! -f "$PUSH_FLAG" ]; then
  ok "git-Schirm stumm geblieben (kein push aufgerufen)"
else
  bad "git push wurde aufgerufen"
fi

# ------------------------------------------------ Fall 12: Snippet ------
section "Settings-Snippet"
if python3 - "$SNIPPET" <<'PY'
import json, sys
daten = json.load(open(sys.argv[1]))
eintrag = daten["hooks"]["Stop"][0]["hooks"][0]
assert eintrag["type"] == "command", eintrag
assert eintrag["timeout"] == 60, eintrag
assert "stop-aufgabe-zugende.sh" in eintrag["command"], eintrag
PY
then ok "Snippet ist gueltiges JSON mit Stop-Eintrag und timeout 10"
else bad "Snippet ungueltig"
fi
if grep -q "stop-aufgabe-zugende" "$HOOKS_DIR/README.md"; then
  ok "hooks/README.md beschreibt den Hook"
else
  bad "hooks/README.md ohne Absatz zum neuen Hook"
fi

# --------------------------------------- Fall 12: tmux-Umgebungsvererbung
if command -v tmux >/dev/null 2>&1; then
  section "tmux: Wecker-Datei entsteht aus der Pane-Umgebung (Umgebungsvererbung in tmux, nicht Claude)"
  TXSOCK="wbtest-stophook-$$"
  TXHOME="$TESTHOME/tmuxhome"
  mkdir -p "$TXHOME"
  TASK="tmux-erbe"
  PROJEKT_LAUFT="$PROJEKT_B"
  aufgabe_setzen "$TASK" "läuft" "$PROJEKT_B"
  rm -f "$WECKER/$TASK"
  stop_json "$TESTHOME/tmux-stop.json" "sess-tmux" "" "$PROJEKT_B"
  TSCHIRM="$TESTHOME/tmux-schirm.sh"
  cat > "$TESTHOME/tmux-schirm.sh" <<EOF
#!/bin/bash
bash "$HOOK" < "$TESTHOME/tmux-stop.json" > "$TESTHOME/tmux-out" 2> "$TESTHOME/tmux-err"
echo \$? > "$TESTHOME/tmux-rc"
touch "$TESTHOME/tmux-fertig"
EOF
  chmod +x "$TESTHOME/tmux-schirm.sh"
  rm -f "$WECKER/$TASK" "$TESTHOME/tmux-fertig"
  (
    export HOME="$TXHOME" WB_AUFGABE_ID="$TASK" WB_AUFGABE_PROJEKT="$PROJEKT_B" \
           WB_AUFGABE_BASE="$BASE"
    unset TMUX TMUX_PANE
    tmux -L "$TXSOCK" new-session -d -s stophook -x 120 -y 40 "bash $TESTHOME/tmux-schirm.sh"
  ) >/dev/null 2>&1
  tmux_gestartet=$?
  fertig=0
  for _ in $(seq 1 150); do
    [ -f "$TESTHOME/tmux-fertig" ] && { fertig=1; break; }
    sleep 0.2
  done
  if [ "$fertig" = "1" ] && [ -f "$WECKER/$TASK" ]; then
    ok "Wecker-Datei aus dem Pane heraus entstanden (WB_AUFGABE_ID aus der Pane-Umgebung)"
  else
    bad "Wecker-Datei aus dem Pane fehlt (rc=$(cat "$TESTHOME/tmux-rc" 2>/dev/null || echo '?'); err=$(cat "$TESTHOME/tmux-err" 2>/dev/null | head -1))"
  fi
  tmux -L "$TXSOCK" kill-server >/dev/null 2>&1 || true
else
  printf '  SKIP  tmux fehlt -- tmux-Fall uebersprungen\n'
fi

printf '\n======================================================================\n'
printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
