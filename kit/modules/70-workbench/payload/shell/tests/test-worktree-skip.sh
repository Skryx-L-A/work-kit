#!/bin/bash
# test-worktree-skip.sh -- proves the is_worktree() check that betriebslauf.sh
# and betriebslauf2.sh now use to gate their deploy-vs-repo comparison
# actually tells a real git worktree apart from a real main tree, and that
# both files carry the right SKIP wording for it.
#
# Anlass (04.08., Abnahme des vorigen Auftrags): in einem Worker-Worktree ist
# ~/.local/bin niemals dasselbe wie der Arbeitsbaum -- Worker rollen dort
# seit dieser Aenderung nichts mehr aus. Die alte, unbedingte ABWEICHEND-
# Meldung war deshalb in jedem Worktree ein falscher Fund. is_worktree() muss
# das zuverlaessig erkennen, nicht nur "meistens".
#
# WARUM ECHTE GIT-FIXTUREN STATT EINER NACHBAUTEN FUNKTION: is_worktree()
# selbst wird nicht nachgeschrieben, sondern woertlich aus den beiden echten
# Dateien extrahiert (per sed zwischen 'is_worktree() {' und der zugehoerigen
# '}') und dann ausgefuehrt -- was hier laeuft, ist der tatsaechlich
# ausgelieferte Code, keine Kopie, die stillschweigend auseinanderlaufen
# koennte. Getestet wird er gegen einen WIRKLICH per 'git init' angelegten
# Baum und einen WIRKLICH per 'git worktree add' daraus abgeleiteten
# Worktree -- eine hergestellte Bedingung, keine angenommene.
#
# Was diese Suite NICHT tut: die vollen (rund 30s schweren) Suiten
# betriebslauf.sh/betriebslauf2.sh selbst zweimal laufen lassen (einmal "als
# Hauptbaum", einmal "als Worktree"), nur um eine Zeile zu pruefen. Der
# Hauptbaum-Fall wird hier absichtlich gegen einen EIGENEN, wegwerfbaren
# Fixture-Baum gemessen statt gegen den echten
# $HOME/AI/claude-workbench -- ein Test ruehrt die echte, vom Nutzer
# benutzte Arbeitskopie nicht an. Der echte Worktree-Fall ("im Worktree
# erscheint SKIP") ist ausserdem durch den echten, vollstaendigen
# run-all.sh-Lauf in diesem Arbeitsbaum belegt (siehe Bericht) -- diese Suite
# hier beweist die Erkennung selbst, in beide Richtungen.
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BETRIEB1="$SCRIPT_DIR/betriebslauf.sh"
BETRIEB2="$SCRIPT_DIR/betriebslauf2.sh"
[ -f "$BETRIEB1" ] || { echo "FAIL  $BETRIEB1 fehlt"; exit 1; }
[ -f "$BETRIEB2" ] || { echo "FAIL  $BETRIEB2 fehlt"; exit 1; }

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

# --- die echte is_worktree()-Funktion woertlich aus beiden Dateien ziehen --
extract_is_worktree() { # extract_is_worktree <datei>
  sed -n '/^is_worktree() {$/,/^}$/p' "$1"
}

FN1="$(extract_is_worktree "$BETRIEB1")"
FN2="$(extract_is_worktree "$BETRIEB2")"
[ -n "$FN1" ] && ok "betriebslauf.sh enthaelt eine is_worktree()-Funktion" \
              || bad "betriebslauf.sh: is_worktree() nicht gefunden (Extraktion leer)"
[ -n "$FN2" ] && ok "betriebslauf2.sh enthaelt eine is_worktree()-Funktion" \
              || bad "betriebslauf2.sh: is_worktree() nicht gefunden (Extraktion leer)"
[ "$FN1" = "$FN2" ] && ok "beide Dateien nutzen woertlich dieselbe is_worktree()-Logik" \
                      || bad "die beiden is_worktree()-Fassungen weichen voneinander ab" \
                             "das ist kein Fehler an sich, aber ein Hinweis, dass sie auseinanderlaufen koennten"

# --- echte Fixturen: ein Hauptbaum und ein davon abgeleiteter Worktree -----
FIXTURE="$TESTHOME/fixture-main"
mkdir -p "$FIXTURE/shell"
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email test@example.invalid
git -C "$FIXTURE" config user.name "Test"
echo x > "$FIXTURE/datei"
git -C "$FIXTURE" add datei
git -C "$FIXTURE" commit -q -m init

FIXTURE_WT="$TESTHOME/fixture-worktree"
git -C "$FIXTURE" worktree add -q "$FIXTURE_WT" -b wt-branch >/dev/null 2>&1
mkdir -p "$FIXTURE_WT/shell"

run_is_worktree() { # run_is_worktree <fn-source> <REPO-pfad> -> Exit 0=Worktree, 1=Hauptbaum
  ( REPO="$2"; eval "$1"; is_worktree )
}

if [ -d "$FIXTURE_WT/.git" ] || [ -f "$FIXTURE_WT/.git" ]; then
  ok "Fixtur: 'git worktree add' hat einen echten, verlinkten Worktree angelegt"
else
  bad "Fixtur: 'git worktree add' hat keinen erkennbaren Worktree angelegt -- Testaufbau fehlerhaft"
fi

for label_fn in "betriebslauf.sh:$FN1" "betriebslauf2.sh:$FN2"; do
  label="${label_fn%%:*}"
  fn="${label_fn#*:}"

  if run_is_worktree "$fn" "$FIXTURE/shell"; then
    bad "$label: is_worktree() haelt den echten HAUPTBAUM faelschlich fuer einen Worktree"
  else
    ok "$label: is_worktree() erkennt den echten Hauptbaum korrekt als Hauptbaum"
  fi

  if run_is_worktree "$fn" "$FIXTURE_WT/shell"; then
    ok "$label: is_worktree() erkennt den echten, verlinkten Worktree korrekt als Worktree"
  else
    bad "$label: is_worktree() haelt den echten Worktree faelschlich fuer den Hauptbaum"
  fi

  if run_is_worktree "$fn" "$TESTHOME/kein-git-hier"; then
    bad "$label: ohne git/Repo faellt die Pruefung faelschlich auf 'Worktree' -- sie muesste im Zweifel LAUFEN"
  else
    ok "$label: ohne git/Repo faellt die Pruefung sicher auf 'Hauptbaum' zurueck (die Pruefung LAEUFT im Zweifel)"
  fi
done

# --- die Meldung selbst traegt die geforderten Angaben ----------------------
for f in "$BETRIEB1" "$BETRIEB2"; do
  name="$(basename "$f")"
  grep -q '"SKIP"' "$f" && ok "$name: die Ausgabe nennt SKIP als eigenes Wort" \
                         || bad "$name: kein sichtbares 'SKIP' im Deploy-Vergleich"
  grep -q "Arbeitsbaum (git-Worktree" "$f" && ok "$name: die SKIP-Meldung nennt den Grund (git-Worktree)" \
                                            || bad "$name: die SKIP-Meldung nennt keinen erkennbaren Grund"
done

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
