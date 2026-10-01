#!/usr/bin/env bash
# test-worktrees.sh — die Worktree-Isolierung je Worker (freigegeben 2026-08-04).
#
# Geprueft wird beides: das Werkzeug `wb-worktree` allein und die Kette, an der es
# haengt — `claude-worker` schickt den Worker in seinen Worktree, `wb-close` raeumt
# ihn hinterher auf oder verweigert es, wenn Arbeit darin steht.
#
# ISOLATION (Regeln 2026-07-25/28, beide nach echten Vorfaellen):
#   * `unset TMUX TMUX_PANE` als erste Zeile Code. Ein Skript, das nur den Socket
#     umbiegt, laesst jedes AUFGERUFENE Werkzeug weiter mit dem LIVE-Server reden.
#   * eigener tmux-Server, Socketname mit PID ('wbtest-worktrees-<pid>'), erreicht
#     ueber einen Wrapper auf PATH — auch pi-worker und wb-grid landen dort.
#   * eigenes HOME (mktemp -d): Einstellungen, Zustandsdateien, Worktrees und
#     Sicherungskopien entstehen ausschliesslich dort. Die echten Repos dieser
#     Maschine werden nie angefasst; jedes git-Repo in diesem Test wird selbst
#     angelegt.
#   * kein Netz, kein echter Agent — 'claude' ist eine Attrappe, die ihr
#     Arbeitsverzeichnis protokolliert und dann eine Eingabezeile zeigt.
#   * cleanup killt den Testserver ueber den SOCKET, nie per pkill-Muster.
#
# Run:  shell/tests/test-worktrees.sh
unset TMUX TMUX_PANE
set -uo pipefail

SOCK="wbtest-worktrees-$$"
SESS="wb-worktreetest-$$"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
# shellcheck source=/dev/null
. "$REPO_DIR/tests/lib-testwerkzeuge.sh"
PASS=0; FAIL=0

# `cd … && pwd -P` normalisiert den Pfad gleich zweifach: $TMPDIR endet auf macOS
# mit '/', mktemp liefert sonst einen doppelten Schraegstrich — und /var ist dort
# ein Symlink auf /private/var. tmux meldet in '#{pane_current_path}' immer den
# AUFGELOESTEN Pfad; ohne '-P' verglichen wir '/var/…' gegen '/private/var/…' und
# saehen einen Unterschied, der keiner ist.
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-worktree-test.XXXXXX")" && pwd -P)"
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench"
FAKELOG="$TESTHOME/fake.log"; export FAKELOG
echo "Geprueft: Repo-Stand aus $REPO_DIR"
echo "  Socket: $SOCK   HOME: $TESTHOME"

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCK" ls >/dev/null 2>&1; do
    tmux -L "$SOCK" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCK" ls >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch: tmux -L $SOCK ls" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK" "/tmp/tmux-$(id -u)/$SOCK"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }
have() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | tr '\n' ' ' | cut -c1-200)" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "'$3' steht in der Ausgabe, darf es aber nicht" ;; *) ok "$1" ;; esac; }

# --- Attrappen und Werkzeuge ------------------------------------------------
REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "tmux nicht gefunden — Test kann nicht laufen." >&2; exit 1; }
cat >"$BIN/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L $SOCK "\$@"
EOF
# Die Attrappe schreibt ihr ARBEITSVERZEICHNIS mit: das ist der Beleg dafuer, dass
# der Worker wirklich IM Worktree laeuft und nicht nur ein Pane daneben steht.
cat >"$BIN/claude" <<'EOF'
#!/bin/bash
{ echo "ARGV claude $*"; echo "PWD $(pwd)"; } >>"$FAKELOG"
while :; do printf '❯ '; IFS= read -r _line || sleep 1; done
EOF
chmod +x "$BIN/tmux" "$BIN/claude"
# KOPIEN, keine Symlinks: der Lauf prueft EINEN festen Stand des Repos. Mit
# Symlinks aendert eine Bearbeitung waehrend des Laufs den Code unter dem
# laufenden Test (Lehre aus test-registry.sh, M7).
for s in wb-worktree wb-state claude-worker pi-worker wb-grid wb-close; do
  [ -x "$REPO_DIR/$s" ] || { echo "FAIL  $REPO_DIR/$s fehlt oder ist nicht ausfuehrbar" >&2; exit 1; }
  cp "$REPO_DIR/$s" "$BIN/$s"; chmod +x "$BIN/$s"
done
# context-guard wird BEWUSST nicht mitkopiert: pi-worker ruft es mit `|| true` auf,
# und ein Guard-Prozess, der diesen Lauf ueberlebt, waere genau die Art Rueckstand,
# die diese Suite vermeiden soll.
export PATH="$BIN:$PATH"
W="$BIN/wb-worktree"

# --- Testrepo ---------------------------------------------------------------
mkrepo() { # mkrepo <pfad>
  mkdir -p "$1"
  git -c init.defaultBranch=main init -q "$1"
  git -C "$1" config user.email "test@example.invalid"
  git -C "$1" config user.name  "Worktree Test"
  git -C "$1" config commit.gpgsign false
  printf 'hallo\n' > "$1/a.txt"
  mkdir -p "$1/unterordner"; printf 'x\n' > "$1/unterordner/b.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m "init"
}
REPO="$TESTHOME/projekt"; mkrepo "$REPO"
PLAIN="$TESTHOME/kein-repo"; mkdir -p "$PLAIN"
WTROOT="$TESTHOME/.pi-workers/worktrees"

echo
echo "== 1. ensure: Worktree entsteht, ist idempotent und faellt sauber zurueck =="
out="$("$W" ensure w1 "$REPO" 2>"$TESTHOME/err1")"
eq  "ensure druckt den Worktree-Pfad" "$out" "$WTROOT/w1"
[ -d "$WTROOT/w1" ] && ok "Worktree-Verzeichnis existiert" || bad "Worktree-Verzeichnis existiert" "$WTROOT/w1 fehlt"
[ -f "$WTROOT/w1/a.txt" ] && ok "Worktree traegt den Inhalt des Repos" || bad "Worktree traegt den Inhalt des Repos"
have "Zweig wb/w1 angelegt" "$(git -C "$REPO" branch --list 'wb/w1')" "wb/w1"
have "git kennt den Worktree" "$(git -C "$REPO" worktree list)" "$WTROOT/w1"
have "Hinweis nennt Pfad und Zweig" "$(cat "$TESTHOME/err1")" "Zweig wb/w1"

out="$("$W" ensure w1 "$REPO" 2>"$TESTHOME/err1b")"
eq   "zweiter Aufruf liefert denselben Pfad" "$out" "$WTROOT/w1"
have "zweiter Aufruf meldet Wiederverwendung" "$(cat "$TESTHOME/err1b")" "bestehender Baum $WTROOT/w1"
have "und meldet: kein Rueckstand (Baum ist auf main-Stand)" "$(cat "$TESTHOME/err1b")" "kein Rueckstand zu main"

out="$("$W" ensure w1 "$WTROOT/w1" 2>"$TESTHOME/err1c")"
eq "ensure IM Worktree gibt ihn unveraendert zurueck" "$out" "$WTROOT/w1"
eq "und sagt dazu nichts (kein doppelter Hinweis)" "$(cat "$TESTHOME/err1c")" ""

out="$("$W" ensure wsub "$REPO/unterordner" 2>/dev/null)"
eq "Unterordner bleibt Unterordner" "$out" "$WTROOT/wsub/unterordner"

echo
echo "== 2. Der Normalfall bricht nicht =="
out="$("$W" ensure wplain "$PLAIN" 2>"$TESTHOME/err2")"
eq   "kein git-Repo: unveraendertes Verzeichnis" "$out" "$PLAIN"
have "und ein Hinweis, warum" "$(cat "$TESTHOME/err2")" "liegt in keinem git-Arbeitsbaum"
[ -e "$WTROOT/wplain" ] && bad "kein Worktree fuer ein Nicht-Repo" "$WTROOT/wplain existiert" \
                        || ok  "kein Worktree fuer ein Nicht-Repo"

out="$("$W" ensure wfehlt "$TESTHOME/gibtsnicht" 2>/dev/null)"
eq "nicht existierendes Verzeichnis: unveraendert durchgereicht" "$out" "$TESTHOME/gibtsnicht"

# Ein unzulaessiger Name wird zu einem PFAD und zu einem ZWEIGNAMEN — beides muss
# er nicht werden duerfen (Stress-Befund B05, hier fuer den Worktree wiederholt).
out="$("$W" ensure "../evil" "$REPO" 2>"$TESTHOME/err2b")"
eq   "unzulaessiger Name: Rueckfall auf das Verzeichnis" "$out" "$REPO"
have "und eine Meldung dazu" "$(cat "$TESTHOME/err2b")" "unzulaessiger Worker-Name"
[ -e "$TESTHOME/.pi-workers/evil" ] && bad "nichts ausserhalb von worktrees/ angelegt" "~/.pi-workers/evil existiert" \
                                    || ok  "nichts ausserhalb von worktrees/ angelegt"

# Unbeachtete Aenderungen im HAUPTbaum: der Worktree steht auf HEAD, das muss
# gesagt werden — scheitern darf es nicht.
printf 'noch nicht committet\n' >> "$REPO/schmutz.txt"
out="$("$W" ensure wdirty "$REPO" 2>"$TESTHOME/err2c")"
eq   "schmutziger Hauptbaum: Worktree entsteht trotzdem" "$out" "$WTROOT/wdirty"
have "mit Hinweis auf den nicht enthaltenen Stand" "$(cat "$TESTHOME/err2c")" "unbeachtete Aenderung"
rm -f "$REPO/schmutz.txt"

echo
echo "== 3. Abschaltbar (workerWorktrees) =="
"$BIN/wb-state" settings set workerWorktrees false >/dev/null 2>&1
eq   "Einstellung steht auf false" "$("$BIN/wb-state" settings get workerWorktrees)" "false"
out="$("$W" ensure waus "$REPO" 2>"$TESTHOME/err3")"
eq   "abgeschaltet: Verzeichnis unveraendert" "$out" "$REPO"
eq   "abgeschaltet: keine Meldung (verhaelt sich wie frueher)" "$(cat "$TESTHOME/err3")" ""
[ -e "$WTROOT/waus" ] && bad "abgeschaltet: kein Worktree angelegt" "$WTROOT/waus existiert" \
                      || ok  "abgeschaltet: kein Worktree angelegt"
"$BIN/wb-state" settings set workerWorktrees true >/dev/null 2>&1
eq   "Vorgabe ohne Eintrag ist an" "$(printf '{}' > "$TESTHOME/.claude/workbench/settings.json"; "$BIN/wb-state" settings get workerWorktrees)" "true"

echo
echo "== 4. Aufraeumen: sauber ja, schmutzig nie =="
"$W" ensure wclean "$REPO" >/dev/null 2>&1
"$W" check wclean >/dev/null 2>&1; eq "sauberer Baum: check sagt ja" "$?" "0"
out="$("$W" remove wclean 2>&1)"; rc=$?
eq   "remove endet mit 0" "$rc" "0"
[ -e "$WTROOT/wclean" ] && bad "sauberer Baum wird entfernt" "$WTROOT/wclean steht noch" || ok "sauberer Baum wird entfernt"
hasnt "Zweig wb/wclean ist mit weg" "$(git -C "$REPO" branch --list 'wb/wclean')" "wb/wclean"

WTD="$("$W" ensure wdreck "$REPO" 2>/dev/null)"
printf 'unfertige Arbeit\n' >> "$WTD/neu.txt"
"$W" check wdreck >/dev/null 2>&1; eq "schmutziger Baum: check sagt NEIN (3)" "$?" "3"
out="$("$W" remove wdreck 2>&1)"; rc=$?
eq   "remove verweigert mit 3" "$rc" "3"
have "und sagt, was zu tun ist" "$out" "wb-worktree adopt wdreck"
[ -d "$WTD" ] && ok "schmutziger Baum bleibt stehen" || bad "schmutziger Baum bleibt stehen" "$WTD ist weg"
[ -f "$WTD/neu.txt" ] && ok "die Arbeit darin ist unangetastet" || bad "die Arbeit darin ist unangetastet"

# Committete, aber nicht uebernommene Arbeit ist genauso schuetzenswert wie
# unbeachtete: ein sauberer Baum allein ist kein Freibrief.
git -C "$WTD" add -A >/dev/null 2>&1
git -C "$WTD" commit -q -m "Arbeit von wdreck" >/dev/null 2>&1
eq "Baum ist jetzt sauber" "$(git -C "$WTD" status --porcelain | wc -l | tr -d ' ')" "0"
"$W" check wdreck >/dev/null 2>&1; eq "nicht uebernommene Commits: check sagt NEIN (3)" "$?" "3"
out="$("$W" remove wdreck 2>&1)"; rc=$?
eq   "remove verweigert auch hier" "$rc" "3"
have "Meldung nennt die Commits" "$out" "Commit(s) auf wb/wdreck"

# Ist das Verzeichnis von Hand geloescht worden, traegt der ZWEIG die Arbeit
# weiter — auch dann darf nichts stillschweigend verschwinden.
WTG="$("$W" ensure wweg "$REPO" 2>/dev/null)"
printf 'nur im Zweig\n' >> "$WTG/nur-zweig.txt"
git -C "$WTG" add -A >/dev/null 2>&1; git -C "$WTG" commit -q -m "Arbeit von wweg"
rm -rf "$WTG"
"$W" check wweg >/dev/null 2>&1; eq "Verzeichnis weg, Commits da: check sagt NEIN (3)" "$?" "3"
"$W" remove wweg >/dev/null 2>&1; eq "remove verweigert auch das" "$?" "3"
have "der Zweig steht noch" "$(git -C "$REPO" branch --list 'wb/wweg')" "wb/wweg"
"$W" remove wweg --force >/dev/null 2>&1

echo
echo "== 5. --force wirft nichts weg, es sichert vorher =="
out="$("$W" remove wdreck --force 2>&1)"; rc=$?
eq   "remove --force endet mit 0" "$rc" "0"
have "Sicherungskopie wird gemeldet" "$out" "Sicherungskopie"
SNAP="$TESTHOME/.local/trash-snapshots/$(date +%F)-worktree-wdreck/wdreck"
[ -f "$SNAP/neu.txt" ] && ok "Kopie enthaelt die Datei des Workers" || bad "Kopie enthaelt die Datei des Workers" "$SNAP/neu.txt fehlt"
[ -e "$WTD" ] && bad "Worktree ist entfernt" "$WTD steht noch" || ok "Worktree ist entfernt"
have "Zweig bleibt stehen (traegt die Commits)" "$(git -C "$REPO" branch --list 'wb/wdreck')" "wb/wdreck"

echo
echo "== 6. adopt: Arbeit in den Hauptbaum holen =="
WTA="$("$W" ensure wnehm "$REPO" 2>/dev/null)"
printf 'ergebnis des workers\n' >> "$WTA/ergebnis.txt"
out="$("$W" adopt wnehm 2>&1)"; rc=$?
eq   "adopt endet mit 0" "$rc" "0"
have "adopt sichert den Arbeitsstand zuerst" "$out" "Arbeitsstand von 'wnehm' auf wb/wnehm gesichert"
have "adopt committet NICHT selbst" "$out" "NICHT committet"
[ -f "$REPO/ergebnis.txt" ] && ok "die Datei liegt im Hauptbaum" || bad "die Datei liegt im Hauptbaum"
have "und ist vorgemerkt" "$(git -C "$REPO" status --porcelain ergebnis.txt)" "A"
"$W" check wnehm >/dev/null 2>&1; eq "vor dem Commit gilt sie als nicht uebernommen" "$?" "3"
git -C "$REPO" commit -q -m "Arbeit von wnehm uebernommen"
"$W" check wnehm >/dev/null 2>&1; eq "nach dem Commit darf der Baum weg" "$?" "0"
"$W" remove wnehm >/dev/null 2>&1; eq "und wird entfernt" "$?" "0"

echo
echo "== 7. Ein vorhandener Zweig wird wiederverwendet, nie ueberschrieben =="
WTR="$("$W" ensure wieder "$REPO" 2>/dev/null)"
printf 'alte arbeit\n' >> "$WTR/alt.txt"
git -C "$WTR" add -A >/dev/null 2>&1; git -C "$WTR" commit -q -m "alte Arbeit"
ALT="$(git -C "$REPO" rev-parse 'wb/wieder')"
git -C "$REPO" worktree remove --force "$WTR" >/dev/null 2>&1   # Baum weg, Zweig bleibt
rm -f "$TESTHOME/.pi-workers/worktrees/.meta/wieder"
out="$("$W" ensure wieder "$REPO" 2>/dev/null)"
eq   "ensure legt den Baum neu an" "$out" "$WTROOT/wieder"
eq   "auf demselben Commit wie vorher" "$(git -C "$out" rev-parse HEAD)" "$ALT"
[ -f "$out/alt.txt" ] && ok "die alte Arbeit ist wieder da" || bad "die alte Arbeit ist wieder da"
"$W" remove wieder --force >/dev/null 2>&1

echo
echo "== 8. Spawn: der Worker laeuft wirklich im Worktree =="
mkses() {
  local try err
  for try in 1 2 3; do
    err="$(tmux -L "$SOCK" new-session -d -s "$SESS" -x 200 -y 50 \
             "bash -c 'while :; do sleep 5; done'" 2>&1)"
    tmux -L "$SOCK" has-session -t "=$SESS" 2>/dev/null && return 0
    echo "  (Testsession-Start $try/3 fehlgeschlagen: ${err:-keine Meldung})" >&2
    sleep 2
  done
  echo "ABBRUCH: Testsession '$SESS' laesst sich auf Socket '$SOCK' nicht anlegen." >&2
  exit 1
}
mkses
tmux -L "$SOCK" set -p -t "$SESS" @wb_role orchestrator
export WB_SESSION="$SESS"

# Die Zustandsdatei der Workbench, wie wb-code sie fuer eine Session anlegt. Ohne
# sie meldet `wb-state add-worker` gar nichts (es findet keine Session) — und dann
# koennte dieser Test nicht sehen, ob der Worker mit dem RICHTIGEN Verzeichnis in
# der Sidebar landet. Gefunden wird sie ueber den tmux-Sessionnamen, nicht ueber
# den Verzeichnis-Slug; genau deshalb faellt der Worker auch mit Worktree nicht aus
# der Sidebar heraus.
STATEDIR="$TESTHOME/.claude/workbench/sessions"; mkdir -p "$STATEDIR"
STATEFILE="$STATEDIR/-$(printf '%s' "${REPO#/}" | tr '/' '-').json"
cat > "$STATEFILE" <<JSON
{ "dir": "$REPO", "name": "projekt", "tmuxSession": "$SESS", "workers": [] }
JSON

pane_of() { tmux -L "$SOCK" list-panes -s -t "=$SESS" -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="$1" '$2==n{print $1; exit}'; }
cwd_of()  { tmux -L "$SOCK" display -p -t "$1" '#{pane_current_path}' 2>/dev/null; }
# Der Pane wechselt sein Arbeitsverzeichnis erst, wenn `cd` im Startbefehl gelaufen
# ist — nie sofort nach dem split. Mit Frist warten, nie unbegrenzt.
warte_auf_cwd() { # warte_auf_cwd <pane> <soll>
  local pane="$1" soll="$2"
  warte_auf_bedingung 15 "cwd von $pane wird '$soll'" "[ \"\$(cwd_of '$pane')\" = '$soll' ]"
}

"$BIN/claude-worker" spawn1 sonnet5:high "$REPO" >"$TESTHOME/spawn1.log" 2>&1
P1="$(pane_of spawn1)"
[ -n "$P1" ] && ok "Pane fuer 'spawn1' entstanden" || bad "Pane fuer 'spawn1' entstanden" "$(tail -3 "$TESTHOME/spawn1.log")"
warte_auf_cwd "$P1" "$WTROOT/spawn1"
eq  "der Pane steht im Worktree" "$(cwd_of "$P1")" "$WTROOT/spawn1"
have "die Attrappe lief im Worktree" "$(cat "$FAKELOG" 2>/dev/null)" "PWD $WTROOT/spawn1"
have "der Worker steht mit dem Worktree in der Zustandsdatei" \
     "$(cat "$STATEFILE" 2>/dev/null | tr -d ' \n')" "\"dir\":\"$WTROOT/spawn1\""

echo
echo "== 9. wb-close raeumt auf — aber nur, wenn nichts verlorengeht =="
out="$("$BIN/wb-close" spawn1 2>&1)"; rc=$?
eq   "wb-close endet mit 0" "$rc" "0"
have "wb-close meldet den geschlossenen Pane" "$out" "geschlossen"
have "und das entfernte Verzeichnis" "$out" "entfernt: $WTROOT/spawn1"
[ -e "$WTROOT/spawn1" ] && bad "Worktree ist weg" "$WTROOT/spawn1 steht noch" || ok "Worktree ist weg"
eq   "Pane ist zu" "$(pane_of spawn1)" ""

"$BIN/claude-worker" spawn2 sonnet5:high "$REPO" >"$TESTHOME/spawn2.log" 2>&1
P2="$(pane_of spawn2)"
warte_auf_cwd "$P2" "$WTROOT/spawn2"
printf 'halbfertig\n' >> "$WTROOT/spawn2/wip.txt"
out="$("$BIN/wb-close" spawn2 2>&1)"; rc=$?
eq   "wb-close endet auch hier mit 0 (der Pane geht immer zu)" "$rc" "0"
eq   "Pane ist zu" "$(pane_of spawn2)" ""
have "aber der Worktree wird GEMELDET, nicht entfernt" "$out" "bleibt stehen"
[ -f "$WTROOT/spawn2/wip.txt" ] && ok "die unfertige Arbeit steht noch da" || bad "die unfertige Arbeit steht noch da"
"$W" remove spawn2 --force >/dev/null 2>&1

echo
echo "== 10. Ohne git und mit abgeschaltetem Schalter bleibt alles wie frueher =="
: > "$FAKELOG"
"$BIN/claude-worker" spawn3 sonnet5:high "$PLAIN" >"$TESTHOME/spawn3.log" 2>&1
P3="$(pane_of spawn3)"
warte_auf_cwd "$P3" "$PLAIN"
eq   "Nicht-Repo: der Pane steht im uebergebenen Verzeichnis" "$(cwd_of "$P3")" "$PLAIN"
have "die Attrappe lief dort" "$(cat "$FAKELOG" 2>/dev/null)" "PWD $PLAIN"
out="$("$BIN/wb-close" spawn3 2>&1)"
hasnt "wb-close meldet keinen Worktree" "$out" "bleibt stehen"

"$BIN/wb-state" settings set workerWorktrees false >/dev/null 2>&1
: > "$FAKELOG"
"$BIN/claude-worker" spawn4 sonnet5:high "$REPO" >"$TESTHOME/spawn4.log" 2>&1
P4="$(pane_of spawn4)"
warte_auf_cwd "$P4" "$REPO"
eq   "abgeschaltet: der Pane steht im Repo selbst" "$(cwd_of "$P4")" "$REPO"
[ -e "$WTROOT/spawn4" ] && bad "abgeschaltet: kein Worktree entstanden" "$WTROOT/spawn4 existiert" \
                        || ok  "abgeschaltet: kein Worktree entstanden"
"$BIN/wb-close" spawn4 >/dev/null 2>&1
"$BIN/wb-state" settings set workerWorktrees true >/dev/null 2>&1

echo
echo "Worktree-Isolierung: $PASS ok, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
