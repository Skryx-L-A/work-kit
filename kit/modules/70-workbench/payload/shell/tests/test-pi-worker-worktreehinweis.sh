#!/usr/bin/env bash
# test-pi-worker-worktreehinweis.sh -- pi-worker stellt dem injizierten Auftrag
# einen kurzen Vorspann voran, wenn der Worker WIRKLICH in einem eigenen
# git-Worktree laeuft.
#
# ANLASS (11.08.): shell/pi-worker legt fuer jeden Worker einen eigenen
# git-Worktree an, sagt dem Auftragstext davon aber nichts. Ein Worker bekam
# beim Spawn den Projektordner ~/AI/claude-workbench genannt, sein Pane stand
# im Worktree, und er hat seine neuen Dateien trotzdem in den Projektordner
# geschrieben, weil er die Pfade aus dem Auftragstext gegen den Hauptbaum
# aufgeloest hat -- 'git merge' im Hauptbaum brach danach mit "Your local
# changes ... would be overwritten by merge" ab.
#
# DIE DREI AUSSAGEN:
#   A  Bei aktivem Worktree steht ein "[Working directory]"-Vorspann im
#      injizierten Text, VOR dem eigentlichen Auftragstext -- mit dem
#      absoluten Worktree-Pfad, dem Zweignamen und dem Hauptbaum-Pfad als
#      tabu. Der Auftragstext selbst bleibt vollstaendig erhalten.
#   B  Bei abgeschalteten Worktrees (workerWorktrees=false) fehlt der
#      Vorspann -- unveraendertes Verhalten.
#   C  Bei einem Zielverzeichnis ausserhalb jedes git-Arbeitsbaums fehlt der
#      Vorspann ebenfalls (wb-worktree faellt dort ohnehin auf das
#      uebergebene Verzeichnis zurueck).
#
# KEIN ECHTER AGENT LAEUFT HIER. Auf dem PATH liegt ein Schirm, der `claude`
# durch ein Skript ersetzt, das nur sein Bereitschaftszeichen zeigt und dann
# ALLES, was in den Pane getippt wird, in eine Datei umleitet (statt es wie im
# Auftragsbuch-Test wegzuwerfen) -- genau das ist hier der Pruefgegenstand:
# der TATSAECHLICH injizierte Text, nicht nur die Auftragsdatei auf der
# Platte (die traegt seit V18 nur $TASK, nicht den Vorspann).
#
# ISOLATION: eigener tmux-Socket, eigenes HOME (Registry, Worktrees, Ergebnisse
# und Zustand liegen alle darunter), eigene Modell-Registry, eigenes
# Fixture-Repo als "Hauptbaum" -- niemals der echte, gerade benutzte
# Arbeitsbaum. Keine Live-Session, kein ~/.pi-workers des Menschen, kein Netz.
# `trap` raeumt ab, auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-worktreehinweis-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="w$(date +%s)$$$RANDOM"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS + 5))
  while [ $SECONDS -lt $d ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== pi-worker: Worktree-Vorspann im injizierten Auftrag (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-worktree" ] || ueberspringen "shell/wb-worktree fehlt"
command -v git >/dev/null 2>&1 || ueberspringen "git nicht im PATH"

# --- Die Testumgebung, vollstaendig selbst hergestellt ---------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

# tmux des Prueflings auf den Testsocket nageln -- pi-worker ruft es ungeflaggt.
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent. Er zeigt das Bereitschaftszeichen des claude-Harness
# (readyPattern) und laesst danach eine leere Eingabezeile stehen (promptPattern
# '^❯'), damit pi-worker den Task ueberhaupt absendet -- und schreibt ALLES, was
# danach in den Pane kommt, fortlaufend in eine Datei. Das ist der eigentliche
# Pruefgegenstand dieser Suite: der Text, den pi-worker WIRKLICH einfuegt.
# `tee` statt `cat >>`, damit derselbe Text zusaetzlich im Pane selbst landet --
# die Absende-Pruefung belegt seit 2026-08-17 auch den Inhalt im Pane, nicht nur
# eine leere Eingabezeile, und eine Datei allein zeigt der Pruefung nichts.
cat > "$TESTHOME/.local/bin/claude" <<SHIMEOF
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec tee -a "$TESTHOME/capture.log"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"

# Zwei Werkzeuge, die pi-worker im Vorbeigehen ruft und die hier nichts zu tun
# haben.
for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done

# Die ECHTEN Werkzeuge, kein Platzhalter -- sie entscheiden hier mit.
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-worktree" "$TESTHOME/.local/bin/wb-worktree"
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
cp "$REPO/wb-rolle" "$TESTHOME/.local/bin/wb-rolle"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-worktree" \
         "$TESTHOME/.local/bin/wb-pane-write" "$TESTHOME/.local/bin/wb-mensch" \
         "$TESTHOME/.local/bin/wb-rolle"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

# Vorher-Stand der ECHTEN Register. Der Lauf darf sie nicht anfassen.
ECHT_ROLLEN="$HOME/.pi-workers/rollen"
ROLLEN_VORHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"

# Ein eigenes, wegwerfbares Fixture-Repo als "Hauptbaum" -- niemals der echte
# Arbeitsbaum dieser Session.
ARBEIT="$TESTHOME/arbeit"
git -C "$ARBEIT" init -q -b main
git -C "$ARBEIT" config user.email test@test.invalid
git -C "$ARBEIT" config user.name Test
echo hallo > "$ARBEIT/README.md"
git -C "$ARBEIT" add README.md
git -C "$ARBEIT" commit -q -m init
# Derselbe Weg, mit dem auch pi-worker den Hauptbaum-Pfad ermittelt (git
# worktree list, erster Eintrag) -- so ist die Erwartung gegen dieselbe Quelle
# gemessen, nicht gegen eine angenommene String-Gleichheit mit $ARBEIT.
HAUPTBAUM_ERWARTET="$(git -C "$ARBEIT" worktree list --porcelain 2>/dev/null \
  | awk '/^worktree /{sub(/^worktree /,""); print; exit}')"
[ -n "$HAUPTBAUM_ERWARTET" ] || ueberspringen "Hauptbaum-Pfad des Fixture-Repos nicht ermittelbar"

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

# Eine Workbench-Session, in die pi-worker seine Panes haengen kann.
tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

echo
echo "-- A: aktiver Worktree --"
WORKER_A="a$MARKE"
AUS_A="$(pi "$WORKER_A" claude-opus5 "$ARBEIT" "Testauftrag A $MARKE")"
RC_A=$?
if [ ! -s "$TESTHOME/capture.log" ]; then
  bad "A: nichts im Pane angekommen (rc=$RC_A)"
  printf '%s\n' "$AUS_A" | sed 's/^/      | /' | tail -12
else
  WTPFAD="$TESTHOME/.pi-workers/worktrees/$WORKER_A"
  [ -d "$WTPFAD" ] && ok "A: pi-worker hat wirklich einen Worktree angelegt ($WTPFAD)" \
                    || bad "A: kein Worktree unter $WTPFAD -- Testvoraussetzung verletzt"

  grep -qF "[Working directory]" "$TESTHOME/capture.log" \
    && ok "A: der Vorspann steht im injizierten Text" \
    || bad "A: kein '[Working directory]'-Vorspann im injizierten Text"
  grep -qF "$WTPFAD" "$TESTHOME/capture.log" \
    && ok "A: der Vorspann nennt den absoluten Worktree-Pfad" \
    || bad "A: der Vorspann nennt nicht den Worktree-Pfad $WTPFAD"
  grep -qF "wb/$WORKER_A" "$TESTHOME/capture.log" \
    && ok "A: der Vorspann nennt den Zweignamen wb/$WORKER_A" \
    || bad "A: der Vorspann nennt nicht den Zweignamen"
  grep -qF "$HAUPTBAUM_ERWARTET" "$TESTHOME/capture.log" \
    && ok "A: der Vorspann nennt den Hauptbaum-Pfad als tabu ($HAUPTBAUM_ERWARTET)" \
    || bad "A: der Vorspann nennt nicht den Hauptbaum-Pfad"
  grep -qF "Testauftrag A $MARKE" "$TESTHOME/capture.log" \
    && ok "A: der eigentliche Auftragstext ist weiterhin im injizierten Text" \
    || bad "A: der Auftragstext fehlt -- der Vorspann hat ihn verdraengt"

  ZEILE_VORSPANN="$(grep -n -F "[Working directory]" "$TESTHOME/capture.log" | head -1 | cut -d: -f1)"
  ZEILE_AUFTRAG="$(grep -n -F "Testauftrag A $MARKE" "$TESTHOME/capture.log" | head -1 | cut -d: -f1)"
  if [ -n "$ZEILE_VORSPANN" ] && [ -n "$ZEILE_AUFTRAG" ] && [ "$ZEILE_VORSPANN" -lt "$ZEILE_AUFTRAG" ]; then
    ok "A: der Vorspann steht VOR dem Auftragstext, nicht dazwischen oder danach"
  else
    bad "A: Reihenfolge Vorspann/Auftrag stimmt nicht (Vorspann Zeile ${ZEILE_VORSPANN:-?}, Auftrag Zeile ${ZEILE_AUFTRAG:-?})"
  fi
  grep -qF "[Protocol" "$TESTHOME/capture.log" \
    && ok "A: das Ergebnisdatei-Protokoll steht weiterhin (unverschoben) im Text" \
    || bad "A: das Ergebnisdatei-Protokoll fehlt im injizierten Text"
fi

: > "$TESTHOME/capture.log"

echo
echo "-- B: Worktrees abgeschaltet (workerWorktrees=false) --"
HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
  "$TESTHOME/.local/bin/wb-state" settings set workerWorktrees false >/dev/null 2>&1

WORKER_B="b$MARKE"
AUS_B="$(pi "$WORKER_B" claude-opus5 "$ARBEIT" "Testauftrag B $MARKE")"
RC_B=$?
if [ ! -s "$TESTHOME/capture.log" ]; then
  bad "B: nichts im Pane angekommen (rc=$RC_B)"
  printf '%s\n' "$AUS_B" | sed 's/^/      | /' | tail -12
else
  [ ! -e "$TESTHOME/.pi-workers/worktrees/$WORKER_B" ] \
    && ok "B: kein Worktree fuer '$WORKER_B' entstanden (workerWorktrees=false wirkt)" \
    || bad "B: trotz workerWorktrees=false ist ein Worktree fuer '$WORKER_B' entstanden"
  grep -qF "[Working directory]" "$TESTHOME/capture.log" \
    && bad "B: der Vorspann steht im Text, obwohl Worktrees abgeschaltet sind" \
    || ok "B: kein Vorspann im injizierten Text -- unveraendertes Verhalten"
  grep -qF "Testauftrag B $MARKE" "$TESTHOME/capture.log" \
    && ok "B: der Auftragstext ist unveraendert im injizierten Text" \
    || bad "B: der Auftragstext fehlt im injizierten Text"
fi

HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
  "$TESTHOME/.local/bin/wb-state" settings set workerWorktrees true >/dev/null 2>&1
: > "$TESTHOME/capture.log"

echo
echo "-- C: Zielverzeichnis liegt in keinem git-Arbeitsbaum --"
NICHTGIT="$TESTHOME/kein-git"
mkdir -p "$NICHTGIT"
WORKER_C="c$MARKE"
AUS_C="$(pi "$WORKER_C" claude-opus5 "$NICHTGIT" "Testauftrag C $MARKE")"
RC_C=$?
if [ ! -s "$TESTHOME/capture.log" ]; then
  bad "C: nichts im Pane angekommen (rc=$RC_C)"
  printf '%s\n' "$AUS_C" | sed 's/^/      | /' | tail -12
else
  grep -qF "[Working directory]" "$TESTHOME/capture.log" \
    && bad "C: der Vorspann steht im Text, obwohl das Zielverzeichnis in keinem git-Baum liegt" \
    || ok "C: kein Vorspann fuer ein Nicht-git-Verzeichnis"
  grep -qF "Testauftrag C $MARKE" "$TESTHOME/capture.log" \
    && ok "C: der Auftragstext ist unveraendert im injizierten Text" \
    || bad "C: der Auftragstext fehlt im injizierten Text"
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
if [ ! -e "$HOME/.pi-workers/results/$WORKER_A" ] \
   && [ ! -e "$HOME/.pi-workers/results/$WORKER_B" ] \
   && [ ! -e "$HOME/.pi-workers/results/$WORKER_C" ]; then
  ok "keine Ergebnisordner fuer die Testworker unter dem echten HOME"
else
  bad "es wurde ins ECHTE ~/.pi-workers geschrieben -- Testisolation gebrochen"
fi
ROLLEN_NACHHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"
[ "$ROLLEN_NACHHER" = "$ROLLEN_VORHER" ] \
  && ok "das ECHTE Rollenregister blieb unberuehrt ($ROLLEN_VORHER Eintraege wie vorher)" \
  || bad "der Lauf hat in das echte $ECHT_ROLLEN geschrieben ($ROLLEN_VORHER -> $ROLLEN_NACHHER)"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
