#!/bin/bash
# Prueft die Vormarkierung: ein Ergebnis, das lange vor dem Guard-Start geschrieben
# wurde, darf NICHT gemeldet werden; ein frisches schon.
unset TMUX TMUX_PANE
set -uo pipefail
# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override bleibt moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_SRC="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
STATE_SRC="${WB_STATE:-$REPO/wb-state}"
[ -x "$GUARD_SRC" ] || { echo "FAIL  $GUARD_SRC fehlt oder ist nicht ausfuehrbar"; exit 1; }
echo "Geprueft: $GUARD_SRC"
# Kennzeichen dieses Laufs (siehe test-context-guard-live-socket-unberuehrt.sh):
# haengt an Socket- und Worker-Namen, wenn LIVE_MARKER gesetzt ist -- leer und
# ohne Wirkung, wenn diese Suite einzeln laeuft.
MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCK="wbtest-backfill$MARK-$$"
# Der Guard laeuft mit eigenem HOME, muss aber denselben tmux-Server sehen wie
# dieser Test. Deshalb EIN Socketverzeichnis fuer beide Seiten, gesetzt statt
# geerbt. Frueher stand hier fest '/private/tmp' — auf dem Mac ist das dasselbe
# Verzeichnis wie /tmp, auf Linux existiert es nicht, dort sah der Guard einen
# leeren eigenen Server und meldete jedes Ergebnis als frisch.
TMUX_TMPDIR="${TMUX_TMPDIR:-/tmp}"; export TMUX_TMPDIR
# Das Kennzeichen geht auch in den Pfad: diese Suite KOPIERT context-guard
# hierhin, ein geleaktes context-guard traegt also keinen Repo-Pfad, sondern
# nur diesen mktemp-Pfad -- er muss deshalb selbst erkennbar sein.
FAKEHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-backfill${MARK}.XXXXXX")"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
# Worker-Namen, jeweils mit dem Kennzeichen dieses Laufs: sie werden
# woertlich in den echten Fertigmeldungstext eingebettet, den context-guard
# in eine Pane schreibt -- genau das macht sie als Nachweis brauchbar.
ALT="alt$MARK"; NEU="neu$MARK"; PANEWEG="paneweg$MARK"; AKTIVDONE="aktivdone$MARK"
pass=0; fail=0
GUARD_PID=""
SHIM=""
ok()  { pass=$((pass+1)); echo "  ok    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
cleanup() {
  [ -n "$GUARD_PID" ] && kill "$GUARD_PID" 2>/dev/null
  local gdl=$((SECONDS + 5))
  while [ -n "$GUARD_PID" ] && [ $SECONDS -lt $gdl ] && kill -0 "$GUARD_PID" 2>/dev/null; do
    kill "$GUARD_PID" 2>/dev/null; sleep 0.3
  done
  [ -n "$GUARD_PID" ] && kill -0 "$GUARD_PID" 2>/dev/null \
    && echo "WARNUNG: context-guard (PID $GUARD_PID) liess sich nicht beenden" >&2
  tmux_socket_beenden_ohne_reste "$SOCK"
  rm -f "$TMUX_TMPDIR/tmux-$(id -u)/$SOCK"
  rm -rf "$FAKEHOME" "$SHIM"
}
trap cleanup EXIT

mkdir -p "$FAKEHOME/.local/state" "$FAKEHOME/.local/bin" "$FAKEHOME/.pi-workers/results/$ALT" "$FAKEHOME/.pi-workers/results/$NEU" "$FAKEHOME/.pi-workers/results/$PANEWEG"
cp "$GUARD_SRC" "$FAKEHOME/.local/bin/"
ln -sf "$STATE_SRC" "$FAKEHOME/.local/bin/wb-state" 2>/dev/null || true

# Der PRUEFLING (context-guard) ruft selbst unflagged `tmux ...` auf -- ohne
# Bindung faellt das auf den DEFAULT-Socket zurueck, sobald diese beiden
# Aufrufe (anders als jede andere Suite hier) nie in einem Pane des Testservers
# laufen, sondern direkt aus dieser Shell heraus (Vorfall 2026-08-04: exakt
# dieser Prozess -- $FAKEHOME/.local/bin/context-guard --auto %0 -- tippte in
# LIVE-Orchestrator-Pane des Nutzers). Ein PATH-Schirm zwingt jeden bare-`tmux`-
# Aufruf jedes Kindprozesses auf den Testsocket, egal ob $TMUX gesetzt ist.
REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "FAIL  tmux nicht gefunden"; exit 1; }
SHIM="$(mktemp -d)"
cat > "$SHIM/tmux" <<EOF
#!/bin/sh
exec "$REALTMUX" -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

# Zwei Ergebnisse: eines alt (zwei Stunden), eines frisch.
echo "altes Ergebnis"  > "$FAKEHOME/.pi-workers/results/$ALT/20260804-000000.md"
ln -sf "$FAKEHOME/.pi-workers/results/$ALT/20260804-000000.md" "$FAKEHOME/.pi-workers/results/$ALT/latest.md"
touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$FAKEHOME/.pi-workers/results/$ALT/20260804-000000.md"
echo "frisches Ergebnis" > "$FAKEHOME/.pi-workers/results/$NEU/20260804-060000.md"
ln -sf "$FAKEHOME/.pi-workers/results/$NEU/20260804-060000.md" "$FAKEHOME/.pi-workers/results/$NEU/latest.md"

# Dritter Fall (2026-08-04, der real gemessene): ein Ergebnis aelter als die Karenz,
# dessen WORKER-PANE selbst schon existiert HAT und wieder verschwunden ist -- nicht
# nur nie einen hatte, wie "alt" oben. Muss GENAUSO still vorgemerkt werden.
echo "altes Ergebnis, Pane weg" > "$FAKEHOME/.pi-workers/results/$PANEWEG/20260804-000000.md"
ln -sf "$FAKEHOME/.pi-workers/results/$PANEWEG/20260804-000000.md" "$FAKEHOME/.pi-workers/results/$PANEWEG/latest.md"
touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$FAKEHOME/.pi-workers/results/$PANEWEG/20260804-000000.md"

tmux -L "$SOCK" new-session -d -s wb-backfilltest -c /tmp "cat > $FAKEHOME/orch.txt"
ORCH=$(tmux -L "$SOCK" list-panes -t wb-backfilltest -F '#{pane_id}' | head -1)
tmux -L "$SOCK" set -p -t "$ORCH" @wb_role orchestrator

# Ein frischer Testsocket laedt trotzdem die installierte ~/.tmux.conf mit, samt
# ihrer GLOBAL gebundenen Hooks (siehe regeln/tests-und-eingriffe.md, 2026-08-04:
# "Ein eigener Socket erbt trotzdem ~/.tmux.conf"). Gemessen genau HIER: der
# `after-split-window`-Hook (startet wb-grid) liess die Session zwischen dem
# Bootstrap-Lauf und dem echten Testlauf unter dem Namen 'wb-backfilltest-view'
# statt 'wb-backfilltest' erscheinen -- der Guard berechnete beim zweiten Aufruf
# einen ANDEREN Slug als beim Bootstrap und schrieb/las eine ANDERE
# Zustandsdatei, dadurch verschwanden alt/neu/paneweg spurlos aus der Buchfuehrung
# (siehe Ergebnis-Datei fuer den vollen Befund). Vorlage: betriebslauf2.sh /
# test-revive.sh.
tmux_live_hooks_kappen "$SOCK"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

# paneweg bekommt kurz einen echten Pane, der noch VOR dem Guard-Start wieder
# geschlossen wird -- "existiert NICHT mehr" statt "hat nie existiert".
tmux -L "$SOCK" split-window -t wb-backfilltest -c /tmp "cat"
PANEWEG_PANE=$(tmux -L "$SOCK" display -p -t wb-backfilltest '#{pane_id}')
tmux -L "$SOCK" set -p -t "$PANEWEG_PANE" @wb_role worker
tmux -L "$SOCK" set -p -t "$PANEWEG_PANE" @wb_worker "$PANEWEG"
tmux -L "$SOCK" kill-pane -t "$PANEWEG_PANE"

# aktivdone: schon einmal markiert (done-notified existiert), aber sein Pane LEBT
# noch die ganze Testdauer -- Bereinigung braucht BEIDE Bedingungen, eine allein
# reicht nicht. Bleibt bis zum Testende am Leben (kein kill-pane hier).
tmux -L "$SOCK" split-window -t wb-backfilltest -c /tmp "cat"
AKTIVDONE_PANE=$(tmux -L "$SOCK" display -p -t wb-backfilltest '#{pane_id}')
tmux -L "$SOCK" set -p -t "$AKTIVDONE_PANE" @wb_role worker
tmux -L "$SOCK" set -p -t "$AKTIVDONE_PANE" @wb_worker "$AKTIVDONE"

# Den Slug NICHT raten: den Guard kurz laufen lassen, damit er seine eigenen
# Zustandsdateien anlegt, und den Namen danach ablesen.
mkdir -p "$FAKEHOME/.local/state/wb-context-guard"
HOME="$FAKEHOME" POLL=2 \
  timeout 4 "$FAKEHOME/.local/bin/context-guard" --auto "$ORCH" >/dev/null 2>&1 || true
SLUG="$(basename "$(ls "$FAKEHOME/.local/state/wb-context-guard/"*.known-workers 2>/dev/null | head -1)" .known-workers)"
[ -n "$SLUG" ] || { echo "  FAIL  Guard hat keine Zustandsdatei angelegt"; exit 1; }
printf '%s\n%s\n%s\n%s\n' "$ALT" "$NEU" "$PANEWEG" "$AKTIVDONE" > "$FAKEHOME/.local/state/wb-context-guard/$SLUG.known-workers"
rm -rf "$FAKEHOME/.local/state/wb-context-guard/$SLUG.done-notified"
mkdir -p "$FAKEHOME/.local/state/wb-context-guard/$SLUG.done-notified"
touch "$FAKEHOME/.local/state/wb-context-guard/$SLUG.done-notified/$AKTIVDONE"

HOME="$FAKEHOME" POLL=2 \
  timeout 22 "$FAKEHOME/.local/bin/context-guard" --auto "$ORCH" \
  > "$FAKEHOME/guard.log" 2>&1 &
GUARD_PID=$!
sleep 19
tmux_socket_beenden_ohne_reste "$SOCK"
sleep 1
kill "$GUARD_PID" 2>/dev/null
wait "$GUARD_PID" 2>/dev/null
GUARD_PID=""

out="$(cat "$FAKEHOME/orch.txt" 2>/dev/null)$(cat "$FAKEHOME/guard.log" 2>/dev/null)"
case "$out" in *"worker $ALT war schon vor dem Guard-Start fertig"*) ok "altes Ergebnis still vorgemerkt" ;;
               *) bad "altes Ergebnis nicht vorgemerkt: $(printf '%s' "$out" | tail -3)" ;; esac
case "$out" in *"Worker $ALT is done"*) bad "altes Ergebnis wurde trotzdem gemeldet" ;;
               *) ok "keine Meldung fuer das alte Ergebnis" ;; esac
# Dass ein FRISCHES Ergebnis gemeldet wird, prueft die bestehende Suite
# `test-context-guard-fertigmeldung.sh` in elf Faellen mit dem dafuer gebauten
# Aufbau. Hier wird bewusst nur die Vormarkierung geprueft: der Orchestrator-Pane
# dieses Tests ist ein blosser `cat`-Sink, und die Nudge-Zustellung haengt an der
# BUSY-Erkennung, die auf einem echten Prompt beruht — ein Fehlschlag hier wuerde
# den Aufbau messen, nicht die Sache.
case "$out" in *"Worker $NEU is done"*|*"worker $NEU fertig"*)
                 ok "frisches Ergebnis wurde gemeldet" ;;
               *) echo "  hinweis  frisches Ergebnis hier nicht zugestellt (cat-Sink; deckt test-context-guard-fertigmeldung.sh ab)" ;; esac

case "$out" in *"worker $PANEWEG war schon vor dem Guard-Start fertig"*)
                 ok "altes Ergebnis mit inzwischen geschlossenem Pane still vorgemerkt" ;;
               *) bad "paneweg (Pane existierte, ist weg) nicht vorgemerkt: $(printf '%s' "$out" | tail -3)" ;; esac
case "$out" in *"Worker $PANEWEG is done"*) bad "paneweg wurde trotzdem gemeldet" ;;
               *) ok "keine Meldung fuer paneweg" ;; esac

echo "-- Bereinigung der known-workers-Liste (kein Pane UND schon markiert -> raus) --"
KW_AFTER="$FAKEHOME/.local/state/wb-context-guard/$SLUG.known-workers"
kw_content="$(cat "$KW_AFTER" 2>/dev/null)"
case "$out" in *"known-workers bereinigt:"*) ok "Bereinigung lief und meldete sich: $(printf '%s' "$out" | grep -o 'known-workers bereinigt:.*' | head -1)" ;;
               *) bad "keine Bereinigungs-Meldung im Log" ;; esac
if printf '%s' "$kw_content" | grep -qxF "$ALT"; then bad "alt (kein Pane, vorgemerkt) haette entfernt werden muessen"
else ok "alt aus known-workers entfernt (kein Pane, schon markiert)"; fi
if printf '%s' "$kw_content" | grep -qxF "$PANEWEG"; then bad "paneweg (kein Pane, vorgemerkt) haette entfernt werden muessen"
else ok "paneweg aus known-workers entfernt (kein Pane, schon markiert)"; fi
if printf '%s' "$kw_content" | grep -qxF "$AKTIVDONE"; then ok "aktivdone bleibt (Pane lebt trotz Markierung -- eine Bedingung allein reicht nicht)"
else bad "aktivdone haette NICHT entfernt werden duerfen (sein Pane lebt noch)"; fi
if printf '%s' "$kw_content" | grep -qxF "$NEU"; then ok "neu bleibt (kein Pane, aber noch keine Markierung -- eine Bedingung allein reicht nicht)"
else bad "neu haette NICHT entfernt werden duerfen (noch nicht markiert)"; fi

echo "backfill: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
