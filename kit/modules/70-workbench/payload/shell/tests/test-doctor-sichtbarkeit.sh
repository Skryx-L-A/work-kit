#!/bin/bash
# Test fuer wb-doctor Punkt 7 ("Sichtbarkeit") -- prueft, ob die Pruefung
# Orchestrator-Tab und Worker-Tab getrennt beurteilt statt sie zu verwechseln.
#
# Anlass (2026-08-04): der Nutzer mass 'wb-AI' clients=1, 'wb-AI-view' clients=0 --
# der Orchestrator-Tab hing, der Worker-Tab NICHT. wb-doctor meldete dazu
# nichts, weil die alte Pruefung session_attached ueber die GANZE Sessiongruppe
# summierte ('#{session_group}' + '#{session_name}'); ein einziger Client an
# der Basis liess die Gruppe als sichtbar gelten. Die neue Pruefung trennt
# Basis- und '-view'-Session und beruecksichtigt workerLayout: bei 'split'
# liegen die Worker im selben Fenster wie der Orchestrator, dort ist eine
# fehlende oder unbesuchte '-view' der korrekte Zustand.
#
# Alles laeuft auf einem EIGENEN Socket (Tests fassen die Live-Umgebung nie
# an) und mit einem EIGENEN HOME (wb-doctor liest workerLayout ueber
# wb-state, das ~/.claude/workbench/settings.json der echten Workbench sonst
# mitlesen wuerde). Ein Client wird simuliert, indem ein Watcher-Pane
# 'tmux attach' als Vordergrundprozess im eigenen Pty ausfuehrt -- dasselbe
# Muster wie in test-session-sweep.sh, dort ausfuehrlich begruendet.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-doctor-sicht-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Die REPO-Version testen, nicht die deployte Kopie unter ~/.local/bin: die
# beiden liefen zum Zeitpunkt dieses Tests auseinander (wb-doctor dort noch
# ohne die hier gepruefte Trennung von Orchestrator- und Worker-Tab), und ein
# Test, der ohne Deploy-Schritt gruen wird, hat nichts geprueft. Ueberschreibbar
# fuer den seltenen Fall, dass gezielt die deployte Kopie gemeint ist.
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib-testwerkzeuge.sh"
TOOL="${WB_DOCTOR:-$REPO_ROOT/shell/wb-doctor}"
STATE_BIN="$HOME/.local/bin/wb-state"
WORK="$(mktemp -d)"
# wb-doctor selbst leitet BIN="$HOME/.local/bin" ab, um Geschwister-Werkzeuge
# (wb-state, wb-workers-window) zu finden -- mit einem komplett leeren HOME
# wuerde das ins Leere laufen und wb-state fuer 'settings get' STILL scheitern
# und auf den eingebauten Default zurueckfallen, statt unser hier gesetztes
# workerLayout zu lesen (genau damit ist dieser Test zuerst hereingefallen: der
# Default 'window' hat den echten Fehlschlag verdeckt, weil er zufaellig mit
# Fall 2 uebereinstimmt). Der Symlink haengt die echten Werkzeuge unter das
# isolierte HOME, waehrend .claude/workbench/ (Settings, Zustandsdateien)
# darunter eigenstaendig bleibt.
mkdir -p "$WORK/.local"
ln -s "$HOME/.local/bin" "$WORK/.local/bin"
pass=0; fail=0

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$WORK"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
skip(){ printf '  skip  %s\n' "$1"; }

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp

# wb-doctor liest den default-Socket ueber $TMUX -- deshalb laeuft es aus
# einem Pane des Testservers heraus, nie aus der Test-Shell selbst.
#
# Auftrag falschrot (2026-08-09): 20s war unter Last zu knapp und lief STILL
# ab -- OUT enthielt dann Bruchstuecke, gegen die die Zusagen unten trotzdem
# verglichen (siehe test-doctor-betriebs-befunde.sh, dort ausfuehrlich
# begruendet und mit einem Beleg versehen). warte_auf_datei() meldet ein
# abgelaufenes Zeitlimit jetzt selbst, als eigenen ZEITLIMIT-Fehlschlag.
run_doctor() { # run_doctor [--fix] -> setzt OUT
  local extra="${1:-}" f="$WORK/out.$RANDOM"
  tm send-keys -t steuer "HOME='$WORK' '$TOOL' $extra > '$f' 2>&1; touch '$f.done'" Enter
  warte_auf_datei "$f.done" 45 "wb-doctor $extra" "$f"
  OUT="$(cat "$f" 2>/dev/null)"
  rm -f "$f" "$f.done"
}

attach_watcher() { # attach_watcher <watcher-session> <ziel-session>
  tm new-session -d -s "$1" -c /tmp
  tm send-keys -t "$1" "unset TMUX; tmux -L $SOCKET attach -t '$2'" Enter
}

wait_attached() { # wait_attached <session> -> Rueckgabewert 0, wenn attached>0; setzt N
  local target="$1" deadline=$((SECONDS+10))
  N=0
  while [ $SECONDS -lt $deadline ]; do
    N="$(tm list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
         | awk -v s="$target" '$1==s{print $2+0}')"
    [ "${N:-0}" -gt 0 ] && return 0
    sleep 0.3
  done
  N=0
  return 1
}

echo "== wb-doctor Punkt 7: Sichtbarkeit =="

# ---------------------------------------------------------------------------
# workerLayout=window: Faelle 1, 2, 4, 5
# ---------------------------------------------------------------------------
HOME="$WORK" "$STATE_BIN" settings set workerLayout window >/dev/null

# Fall 1: Basis + Sicht beide angehaengt -> kein Befund.
tm new-session -d -s wb-Both -c /tmp
tm new-session -d -t wb-Both -s wb-Both-view
attach_watcher watch-both-base wb-Both
# Der Name darf NICHT auf '-view' enden -- sonst faellt der Watcher selbst unter
# den '*-view'-Filter von wb-doctor und wird in Abschnitt 7 stillschweigend
# uebersprungen (genau damit hereingefallen, beim ersten Anlauf dieses Tests).
attach_watcher watch-both-sicht wb-Both-view

# Fall 2: nur Basis angehaengt, Sicht existiert -> Befund Worker-Tab.
tm new-session -d -s wb-OnlyBase -c /tmp
tm new-session -d -t wb-OnlyBase -s wb-OnlyBase-view
attach_watcher watch-only-base wb-OnlyBase

# Fall 4: kein Client irgendwo -> bestehender Befund, wortgleich.
tm new-session -d -s wb-NoClient -c /tmp
tm new-session -d -t wb-NoClient -s wb-NoClient-view

# Fall 5: Sicht fehlt ganz, Basis angehaengt -> Befund + --fix legt sie an.
tm new-session -d -s wb-NoView -c /tmp
attach_watcher watch-noview-base wb-NoView

both_base_ok=0; wait_attached wb-Both && both_base_ok=1
both_view_ok=0; wait_attached wb-Both-view && both_view_ok=1
only_base_ok=0; wait_attached wb-OnlyBase && only_base_ok=1
noview_base_ok=0; wait_attached wb-NoView && noview_base_ok=1

run_doctor ""   # Trockenlauf, layout=window

echo "-- Fall 1: Basis + Sicht beide angehaengt --"
if [ "$both_base_ok" -eq 1 ] && [ "$both_view_ok" -eq 1 ]; then
  # Zeilenweise pruefen, nicht per Glob ueber das ganze $OUT: ein Glob wie
  # *"'wb-Both'"*"kein Client"* matcht schon, wenn beide Teilstrings IRGENDWO
  # im mehrzeiligen Text vorkommen (etwa 'wb-Both' in Abschnitt 4 und ein
  # unabhaengiges "kein Client" bei einer ganz anderen Session in Abschnitt 7)
  # -- ein falscher Treffer, kein echter Befund fuer 'wb-Both'.
  fund="$(printf '%s\n' "$OUT" | grep -F "'wb-Both'" | grep -E "kein Client|hat keine Sicht")"
  if [ -n "$fund" ]; then
    bad "'wb-Both' hat trotz zweier Clients einen Sichtbarkeits-Befund: $fund"
  else
    ok "'wb-Both': kein Sichtbarkeits-Befund"
  fi
else
  skip "konnte keinen Client an 'wb-Both'/'wb-Both-view' anhaengen -- Umgebung ohne echtes Terminal"
fi

echo "-- Fall 2: nur Basis angehaengt, workerLayout=window --"
if [ "$only_base_ok" -eq 1 ]; then
  printf '%s\n' "$OUT" | grep -qF "'wb-OnlyBase': kein Client am Worker-Tab ('wb-OnlyBase-view')" \
    && ok "Befund nennt den fehlenden Client am Worker-Tab" \
    || bad "kein Befund fuer den leeren Worker-Tab von 'wb-OnlyBase': $OUT"
  printf '%s\n' "$OUT" | grep -qF "'wb-OnlyBase': kein Client am Orchestrator-Tab" \
    && bad "faelschlich auch ein Orchestrator-Tab-Befund fuer 'wb-OnlyBase'" \
    || ok "kein falscher Orchestrator-Tab-Befund fuer 'wb-OnlyBase'"
  printf '%s\n' "$OUT" | grep -qF "'wb-OnlyBase' laeuft, aber KEIN Client" \
    && bad "'wb-OnlyBase' faelschlich als komplett unsichtbar gemeldet" \
    || ok "'wb-OnlyBase' nicht als komplett unsichtbar gemeldet"
else
  skip "konnte keinen Client an 'wb-OnlyBase' anhaengen -- Umgebung ohne echtes Terminal"
fi

echo "-- Fall 4: kein Client irgendwo -- bestehender Befund bleibt wortgleich --"
printf '%s\n' "$OUT" | grep -qF "'wb-NoClient' laeuft, aber KEIN Client sieht sie — weder Orchestrator- noch Worker-Tab." \
  && ok "der alte Befund-Wortlaut steht unveraendert" \
  || bad "der bestehende Befund fuer 'wb-NoClient' fehlt oder wurde umformuliert: $OUT"
printf '%s\n' "$OUT" | grep -qF "'wb-NoClient': kein Client am Worker-Tab" \
  && bad "'wb-NoClient' bekam zusaetzlich einen Worker-Tab-Befund (sollte bei 'continue' stehen bleiben)" \
  || ok "kein doppelter Worker-Tab-Befund fuer 'wb-NoClient'"

echo "-- Fall 5: Sicht fehlt ganz, Basis angehaengt, workerLayout=window --"
if [ "$noview_base_ok" -eq 1 ]; then
  printf '%s\n' "$OUT" | grep -qF "'wb-NoView' hat keine Sicht 'wb-NoView-view' — der Worker-Tab kann an nichts haengen." \
    && ok "Befund nennt die fehlende Sicht" \
    || bad "kein Befund fuer die fehlende Sicht von 'wb-NoView': $OUT"
  tm has-session -t '=wb-NoView-view' 2>/dev/null \
    && bad "'wb-NoView-view' existiert schon vor --fix" \
    || ok "'wb-NoView-view' existiert im Trockenlauf noch nicht"
else
  skip "konnte keinen Client an 'wb-NoView' anhaengen -- Umgebung ohne echtes Terminal"
fi

echo "-- Fall 5 (Fortsetzung): --fix legt die fehlende Sicht an --"
run_doctor "--fix"
tm has-session -t '=wb-NoView-view' 2>/dev/null \
  && ok "'wb-NoView-view' existiert nach --fix" \
  || bad "--fix hat 'wb-NoView-view' nicht angelegt"

# ---------------------------------------------------------------------------
# workerLayout=split: Fall 3
# ---------------------------------------------------------------------------
HOME="$WORK" "$STATE_BIN" settings set workerLayout split >/dev/null

tm new-session -d -s wb-SplitOnlyBase -c /tmp
tm new-session -d -t wb-SplitOnlyBase -s wb-SplitOnlyBase-view
attach_watcher watch-split-base wb-SplitOnlyBase
split_base_ok=0; wait_attached wb-SplitOnlyBase && split_base_ok=1

run_doctor ""   # Trockenlauf, layout=split

echo "-- Fall 3: nur Basis angehaengt, workerLayout=split --"
if [ "$split_base_ok" -eq 1 ]; then
  printf '%s\n' "$OUT" | grep -qF "'wb-SplitOnlyBase': kein Client am Worker-Tab" \
    && bad "Worker-Tab-Befund trotz workerLayout=split (Worker liegen im selben Fenster)" \
    || ok "kein Worker-Tab-Befund bei workerLayout=split"
  printf '%s\n' "$OUT" | grep -qF "'wb-SplitOnlyBase' hat keine Sicht" \
    && bad "fehlende-Sicht-Befund trotz workerLayout=split" \
    || ok "kein fehlende-Sicht-Befund bei workerLayout=split"
  printf '%s\n' "$OUT" | grep -qF "'wb-SplitOnlyBase' laeuft, aber KEIN Client" \
    && bad "'wb-SplitOnlyBase' faelschlich als komplett unsichtbar gemeldet" \
    || ok "'wb-SplitOnlyBase' nicht als komplett unsichtbar gemeldet"
else
  skip "konnte keinen Client an 'wb-SplitOnlyBase' anhaengen -- Umgebung ohne echtes Terminal"
fi

echo
echo "wb-doctor-sichtbarkeit: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
