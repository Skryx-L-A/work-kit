#!/usr/bin/env bash
# test-guard-sessionende.sh -- prueft die neue Abbruchbedingung
# `--exit-when-session-gone` und dass `--ensure` sie jetzt benutzt.
#
# Anlass (2026-08-04): eine Orchestrator-Session lief bei 60% Kontext ohne
# einen einzigen Guard. Ursache: `--ensure` startete bisher immer mit
# `--exit-when-no-workers`, und der Guard beendete sich, sobald der letzte
# Worker-Pane verschwand -- fuer WORKER richtig, laesst aber den Orchestrator
# selbst unbewacht, sobald er wieder allein arbeitet. Diese Datei prueft die
# Reparatur: eine neue, unabhaengige Abbruchbedingung "Session existiert nicht
# mehr" statt "keine Worker mehr", die `--ensure` jetzt benutzt, ohne dass
# `--exit-when-no-workers` sich fuer bestehende Aufrufer aendert.
#
# SICHERHEIT (regeln/tests-und-eingriffe.md, Abschnitt vom 2026-08-04 07:10):
# der PRUEFLING wird an den Testsocket GEBUNDEN, nicht nur der Test selbst --
# eine Shell-Funktion `tm() { tmux -L ... }` gilt NICHT im Kindprozess, und
# context-guard ruft `tmux` an ueber 30 Stellen intern auf. Der Weg (Vorlage:
# shell/tests/betriebslauf.sh): ein `tmux`-Schirm ganz vorn im PATH der
# Testumgebung, der JEDEN Aufruf auf den Testsocket zwingt -- auch den, den
# context-guard selbst macht, ohne dass es davon weiss. context-guard selbst
# wird ausserdem ueber den ABSOLUTEN Pfad aufgerufen (nie ueber den bloßen
# Namen aus dem PATH): sein eigenes SELF_PATH-$0 waere sonst relativ zum
# aktuellen Arbeitsverzeichnis der Pane statt zum tatsaechlichen Skriptort --
# genau der Grund, warum pi-worker es in shell/pi-worker auch absolut aufruft.
#
# Eigener tmux-Socket 'wbtest-guardende-<pid>', eigenes HOME (mktemp -d),
# eigene Sessionnamen ('wb-GT-…'), nie ein Name aus laufenden des Nutzers
# Sessions. `trap` raeumt Server und Verzeichnis auf, auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_GUARD_SRC="${CONTEXT_GUARD:-$REPO/context-guard}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-guardende-$$"
TESTHOME="$(mktemp -d)"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"

pass=0; fail=0
GUARD_PIDS=()   # jede von diesem Test gestartete Guard-PID -- verifiziert beendet, nicht angenommen

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
  # Prozess-Hygiene, verifiziert statt angenommen: jeder Guard, den DIESER Test
  # gestartet hat, wird hier per PID beendet (eng gefasst, keine Musterjagd
  # ueber fremde Prozesse). Ohne Session findet er zwar mangels erreichbarem
  # tmux von selbst heraus, dass er weg ist (session_gone() faellt beim
  # Fehlschlagen von 'tmux has-session' auf "verschwunden"), aber das haengt
  # von einem eigenen Poll-Zyklus ab -- kein Ersatz fuer eine geprueften
  # Abraeumung, nur ein Netz darunter.
  local p noch_da=""
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    kill "$p" 2>/dev/null
  done
  sleep 0.5
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null && noch_da="$noch_da $p"
  done
  [ -n "$noch_da" ] && echo "WARNUNG: Guard-PID(s)$noch_da laufen nach dem Aufraeumen noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

# Zaehlt NUR die Guards, die DIESER Lauf gestartet hat. Bis zum 2026-08-06 stand hier
# `ps -ax -o args= | grep ... | grep -c "$PANE"`, also eine Zaehlung ueber ALLE Prozesse
# der Maschine. Pane-Namen sind kein eindeutiger Schluessel: ein frischer Testsocket
# faengt bei %0 an und vergibt damit zwangslaeufig dieselben Namen wie die laufende
# Werkbank. Ein Test, der die Umgebung mitzaehlt, ist nicht flackerig -- er misst etwas
# anderes, als er behauptet.
# Der Pane-Name wird ausserdem an einer Wortgrenze verglichen: '%4' steht sonst auch in
# '%41'.
guard_gemerkt() {   # <pid> -> merkt eine Guard-PID genau einmal
  local neu="$1" p
  [ -n "$neu" ] || return 0
  for p in "${GUARD_PIDS[@]:-}"; do [ "$p" = "$neu" ] && return 0; done
  GUARD_PIDS+=("$neu")
}
eigene_guards_fuer() {   # <pane> -> Zahl der lebenden Guards DIESES Laufs fuer diesen Pane
  local pane="$1" p n=0 args
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    args="$(ps -p "$p" -o args= 2>/dev/null)"
    case "$args" in
      *--auto*" $pane"|*--auto*" $pane "*) n=$((n+1)) ;;
    esac
  done
  printf '%s' "$n"
}
# Die alte, globale Zaehlung -- steht nur noch hier, damit Punkt 3c zeigen kann, dass
# sie einen fremden Prozess mitzaehlt und die neue nicht.
alte_globale_zaehlung() {   # <pane> -> wie frueher gezaehlt wurde
  ps -ax -o args= 2>/dev/null | grep -F "$GUARD --auto" | grep -cF "$1"
}

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '  hinweis %s\n' "$1"; }

[ -x "$CONTEXT_GUARD_SRC" ] || { echo "FAIL  context-guard nicht gefunden/ausfuehrbar: $CONTEXT_GUARD_SRC"; exit 1; }

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.local/state"
cp "$CONTEXT_GUARD_SRC" "$BIN/context-guard"
chmod +x "$BIN/context-guard"
# wb-state wird von context-guard intern ueber den HARTKODIERTEN Pfad
# $HOME/.local/bin/wb-state aufgerufen (nicht ueber PATH) -- die echte,
# unveraenderte Kopie reicht, sie liest nur guardWorkerWarnPct/guardOrchWarnPct/
# minWorkerPaneWidth, die hier ohnehin auf ihren eingebauten Defaults bleiben.
cp "$HOME/.local/bin/wb-state" "$BIN/wb-state"
chmod +x "$BIN/wb-state"

# Der Schirm: JEDER `tmux`-Aufruf aus einer Pane dieser Testumgebung heraus --
# auch der, den context-guard selbst staendig macht -- landet zwingend auf
# dem Testsocket. Ohne ihn liefe ein interner `tmux display -p -t ...` von
# context-guard gegen 'default', mit unabsehbaren Folgen fuer eine echte,
# laufende Session (genau der Vorfall vom 2026-08-04 07:05).
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
GUARD="$BIN/context-guard"   # IMMER absolut aufrufen, siehe Kopfkommentar

tm kill-server 2>/dev/null
tm new-session -d -s ctrl -c /tmp

# Kommando in der STEUER-Pane des Testservers ausfuehren (nie aus dieser Shell
# heraus): nur dort zeigt $TMUX auf den Testsocket, und context-guards eigene
# Aufrufe laufen ueber den PATH-Schirm.
lauf() { # lauf <kommando> -> setzt OUT und RC
  local cmd="$1" f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t ctrl \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 30 "lauf: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

neue_orch_session() { # name -> setzt PANE
  local name="$1"
  tm new-session -d -s "$name" -c /tmp
  PANE="$(tm list-panes -t "=$name" -F '#{pane_id}' | head -1)"
  tm set -p -t "$PANE" @wb_role orchestrator
}

wait_gone() { # pid timeout -> Rueckgabe 0 wenn der Prozess verschwindet, sonst 1; setzt ELAPSED
  local pid="$1" timeout="$2" start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - start >= timeout )); then ELAPSED=$((SECONDS-start)); return 1; fi
    sleep 0.5
  done
  ELAPSED=$((SECONDS-start))
  return 0
}

echo "== context-guard: Session-Lebenszyklus statt Worker-Lebenszyklus =="

# ---------------------------------------------------------------------------
# Punkt 1: --exit-when-no-workers bleibt unveraendert; --exit-when-session-gone
# ist eine eigene, neue Option, die den Orchestrator OHNE Worker weiter bewacht.
# ---------------------------------------------------------------------------
echo "-- Punkt 1: beide Abbruchbedingungen nebeneinander, keine Worker vorhanden --"
neue_orch_session "wb-GT-noworkers-A"
PANE_A="$PANE"
lauf "POLL=1 EXIT_GRACE=1 EXIT_EMPTY_POLLS=1 nohup '$GUARD' --auto --exit-when-no-workers '$PANE_A' >'$TESTHOME/a.log' 2>&1 & echo PID=\$!"
PID_A="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_A"
[ -n "$PID_A" ] && kill -0 "$PID_A" 2>/dev/null \
  && ok "Guard A (--exit-when-no-workers) gestartet (PID $PID_A)" \
  || bad "Guard A nicht gestartet: $OUT"

neue_orch_session "wb-GT-noworkers-B"
PANE_B="$PANE"
lauf "POLL=1 nohup '$GUARD' --auto --exit-when-session-gone '$PANE_B' >'$TESTHOME/b.log' 2>&1 & echo PID=\$!"
PID_B="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_B"
[ -n "$PID_B" ] && kill -0 "$PID_B" 2>/dev/null \
  && ok "Guard B (--exit-when-session-gone) gestartet (PID $PID_B)" \
  || bad "Guard B nicht gestartet: $OUT"

if [ -n "$PID_A" ]; then
  if wait_gone "$PID_A" 15; then
    ok "Guard A beendet sich ohne Worker von selbst (nach ${ELAPSED}s, --exit-when-no-workers unveraendert)"
  else
    bad "Guard A (--exit-when-no-workers) haette sich ohne Worker beenden muessen, laeuft nach ${ELAPSED}s noch"
  fi
fi
if [ -n "$PID_B" ]; then
  if kill -0 "$PID_B" 2>/dev/null; then
    ok "Guard B (--exit-when-session-gone) laeuft trotz fehlender Worker weiter -- bewacht den Orchestrator allein"
  else
    bad "Guard B (--exit-when-session-gone) hat sich beendet, obwohl nur die Session, nicht die Worker fehlen"
  fi
fi

# Aufraeumen: Guard B beenden, indem seine Session verschwindet (testet
# nebenbei schon einen Teil von Punkt 4).
if [ -n "$PID_B" ] && kill -0 "$PID_B" 2>/dev/null; then
  tm kill-session -t "=wb-GT-noworkers-B" 2>/dev/null
  if wait_gone "$PID_B" 10; then
    ok "Guard B beendet sich, sobald seine Session weg ist (nach ${ELAPSED}s)"
  else
    bad "Guard B laeuft ${ELAPSED}s nach dem Session-Ende noch"
  fi
fi
tm kill-session -t "=wb-GT-noworkers-A" 2>/dev/null

# ---------------------------------------------------------------------------
# Punkt 2: --ensure startet jetzt mit --exit-when-session-gone
# ---------------------------------------------------------------------------
echo "-- Punkt 2: --ensure bewacht den Orchestrator auch ohne Worker --"
neue_orch_session "wb-GT-ensure"
PANE_E="$PANE"
lauf "POLL=2 '$GUARD' --ensure '$PANE_E'"
printf '%s\n' "$OUT" | grep -qF "gestartet fuer" \
  && ok "--ensure hat einen Guard gestartet, obwohl kein Worker existiert" \
  || bad "--ensure hat keinen Guard gestartet: $OUT"
printf '%s\n' "$OUT" | grep -qF "endet automatisch mit der Session" \
  && ok "--ensure kuendigt das neue Lebensende an (mit der Session, nicht mit den Workern)" \
  || bad "--ensure-Meldung nennt nicht mehr das Session-Ende: $OUT"
PID_E="$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"
guard_gemerkt "$PID_E"
[ -n "$PID_E" ] && kill -0 "$PID_E" 2>/dev/null \
  && ok "der von --ensure gestartete Guard laeuft (PID $PID_E)" \
  || bad "kein lebender Guard-Prozess nach --ensure gefunden"

sleep 5
if [ -n "$PID_E" ]; then
  kill -0 "$PID_E" 2>/dev/null \
    && ok "der --ensure-Guard laeuft nach 5s ohne Worker weiterhin (waere unter der alten Fassung schon weg)" \
    || bad "der --ensure-Guard hat sich trotz --exit-when-session-gone ohne Worker beendet"
fi

# ---------------------------------------------------------------------------
# Punkt 3: kein zweiter Guard fuer dieselbe Session -- auch fuer den neuen Fall
# ---------------------------------------------------------------------------
echo "-- Punkt 3: --ensure startet keinen zweiten Guard --"
VOR_ANZAHL=$(eigene_guards_fuer "$PANE_E")
lauf "POLL=2 '$GUARD' --ensure '$PANE_E'"
printf '%s\n' "$OUT" | grep -qF "laeuft bereits fuer $PANE_E" \
  && ok "zweiter --ensure-Aufruf fuer denselben Pane erkennt den laufenden Guard" \
  || bad "zweiter --ensure-Aufruf hat den laufenden Guard nicht erkannt: $OUT"
# Haette der zweite --ensure-Aufruf doch einen Guard gestartet, stuende seine PID in
# seiner Ausgabe ("gestartet fuer ... (PID n"). Sie wird gemerkt, damit die Zaehlung
# unten sie SIEHT -- ohne das waere die Gegenprobe blind.
printf '%s\n' "$OUT" | grep -qF "gestartet fuer" \
  && guard_gemerkt "$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"
NACH_ANZAHL=$(eigene_guards_fuer "$PANE_E")
[ "$NACH_ANZAHL" -eq "$VOR_ANZAHL" ] \
  && ok "Prozesszahl unveraendert ($NACH_ANZAHL) -- kein zweiter Guard-Prozess entstanden" \
  || bad "Prozesszahl vorher=$VOR_ANZAHL nachher=$NACH_ANZAHL -- ein zweiter Guard ist entstanden"

echo "-- Punkt 3b: dieselbe Sperre greift, wenn der laufende Guard von Hand mit --exit-when-session-gone gestartet wurde (nicht ueber --ensure) --"
neue_orch_session "wb-GT-manuell"
PANE_M="$PANE"
lauf "POLL=5 nohup '$GUARD' --auto --exit-when-session-gone '$PANE_M' >'$TESTHOME/m.log' 2>&1 & echo PID=\$!"
PID_M="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_M"
[ -n "$PID_M" ] && kill -0 "$PID_M" 2>/dev/null || bad "Vorbereitung fuer Punkt 3b fehlgeschlagen: kein manueller Guard gestartet"
lauf "'$GUARD' --ensure '$PANE_M'"
printf '%s\n' "$OUT" | grep -qF "laeuft bereits fuer $PANE_M" \
  && ok "--ensure erkennt einen von Hand mit --exit-when-session-gone gestarteten Guard" \
  || bad "--ensure hat den manuell gestarteten --exit-when-session-gone-Guard NICHT erkannt und haette einen zweiten gestartet: $OUT"
# WELCHE PID --ensure dabei nennt, war bis zum 2026-08-07 keine Zusage dieser Suite,
# sondern eine Eigenschaft der Umgebung: `running_guard_pid()` in context-guard suchte
# ueber ALLE Prozesse und verglich den Pane-Namen, ohne Socket oder HOME zu
# beruecksichtigen. Lief auf der Maschine ein echter Guard fuer denselben Pane-Namen --
# und Pane-Namen fangen auf jedem Socket bei %0 an --, meldete --ensure DESSEN PID.
# Seit dem 2026-08-07 findet die Erkennung ueber eine Merkdatei je Instanz statt
# (socket_path + Basis-Session, siehe context-guard und test-context-guard-waise.sh),
# ein fremder Socket kann also nicht mehr gemeint sein. Der Hinweis bleibt trotzdem
# stehen: er kostet nichts und faellt sofort auf, sollte die Trennung je wieder
# verlorengehen. Weiterhin wird er berichtet, nicht bewertet -- der Test soll es nicht
# verdecken und nicht daran scheitern.
GEMELDETE_PID="$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"
IST_EIGEN=nein
for p in "${GUARD_PIDS[@]:-}"; do [ "$p" = "$GEMELDETE_PID" ] && IST_EIGEN=ja; done
if [ "$IST_EIGEN" = ja ]; then
  note "--ensure nennt einen Guard DIESES Laufs (PID $GEMELDETE_PID)"
else
  note "--ensure nennt PID $GEMELDETE_PID, die NICHT zu diesem Lauf gehoert — auf dieser Maschine laeuft ein echter Guard fuer denselben Pane-Namen ($PANE_M). Befund am Werkzeug, nicht am Test: $(ps -p "${GEMELDETE_PID:-0}" -o args= 2>/dev/null | head -1)"
fi
NACH_MANUELL=$(eigene_guards_fuer "$PANE_M")
[ "$NACH_MANUELL" -eq 1 ] \
  && ok "weiterhin genau EIN Guard-Prozess fuer $PANE_M" \
  || bad "es laufen jetzt $NACH_MANUELL Guard-Prozesse fuer $PANE_M (erwartet 1)"

echo "-- Punkt 3c: ein FREMDER Prozess mit derselben Befehlszeile wird nicht mitgezaehlt --"
# Der Fall, an dem diese Suite im Gesamtlauf gescheitert ist: auf der Maschine laeuft
# ein Guard, der nicht zu diesem Lauf gehoert, und sein Pane traegt denselben Namen --
# Pane-Namen fangen auf jedem Socket bei %0 an. Statt darauf zu warten, wird er hier
# selbst hergestellt: ein Wegwerf-Prozess mit genau der Befehlszeile, nach der frueher
# gesucht wurde. Er ist KEIN Guard und steht in keiner PID-Liste dieses Laufs.
/bin/sh -c 'while :; do sleep 1; done' "$GUARD" --auto --exit-when-session-gone "$PANE_M" &
FREMD_PID=$!
sleep 1
ALT_MIT_FREMD="$(alte_globale_zaehlung "$PANE_M")"
NEU_MIT_FREMD="$(eigene_guards_fuer "$PANE_M")"
[ "$ALT_MIT_FREMD" -gt 1 ] \
  && ok "die alte, globale Zaehlung sieht den fremden Prozess mit ($ALT_MIT_FREMD) -- der Befund ist hergestellt" \
  || bad "der fremde Prozess wurde nicht einmal von der alten Zaehlung gesehen ($ALT_MIT_FREMD) -- Testaufbau fehlerhaft"
[ "$NEU_MIT_FREMD" -eq 1 ] \
  && ok "die eigene Zaehlung bleibt bei 1, obwohl der fremde Prozess laeuft" \
  || bad "die eigene Zaehlung meldet $NEU_MIT_FREMD statt 1 -- sie zaehlt Fremdes mit"
kill "$FREMD_PID" 2>/dev/null
wait "$FREMD_PID" 2>/dev/null
kill -0 "$FREMD_PID" 2>/dev/null \
  && bad "der Wegwerf-Prozess $FREMD_PID laeuft noch" \
  || ok "der Wegwerf-Prozess ist beendet"

echo "-- Punkt 3d: ein ZWEITER eigener Guard wird weiterhin gefunden (Gegenprobe) --"
# Ohne diese Richtung waere die neue Zaehlung wertlos: sie darf Fremdes weglassen, aber
# nichts Eigenes uebersehen. Der zweite Guard wird hier absichtlich VORBEI an --ensure
# gestartet, weil geprueft wird, ob die ZAEHLUNG ihn sieht, nicht ob --ensure ihn baut.
#
# Seit 2026-08-08 verweigert der Guard diesen Start allerdings SELBST, sobald die Merkdatei
# seiner Instanz eine lebende Guard-PID traegt (siehe test-context-guard-doppelstart.sh) -- der
# Schutz sitzt nicht mehr nur in --ensure. Fuer diesen Punkt wird die verhinderte Lage deshalb
# von Hand hergestellt: die Merkdatei wandert fuer die Dauer des Starts zur Seite. Das ist
# Testkulisse, keine Aussage ueber das Werkzeug -- die Zusage "kein zweiter Guard" steht in der
# Doppelstart-Suite, hier geht es allein um die Zaehlung.
PIDDATEI_M="$(ls "$TESTHOME/.local/state/wb-context-guard/"*wb-GT-manuell.pid 2>/dev/null | head -1)"
[ -n "$PIDDATEI_M" ] && mv "$PIDDATEI_M" "$PIDDATEI_M.beiseite" 2>/dev/null
lauf "POLL=5 nohup '$GUARD' --auto --exit-when-session-gone '$PANE_M' >'$TESTHOME/m2.log' 2>&1 & echo PID=\$!"
PID_M2="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_M2"
sleep 1
ZWEI="$(eigene_guards_fuer "$PANE_M")"
[ "$ZWEI" -eq 2 ] \
  && ok "zwei eigene Guards fuer $PANE_M werden auch als zwei gezaehlt" \
  || bad "zwei eigene Guards, aber gezaehlt wurden $ZWEI"
kill "$PID_M2" 2>/dev/null
sleep 1
WIEDER_EINS="$(eigene_guards_fuer "$PANE_M")"
[ "$WIEDER_EINS" -eq 1 ] \
  && ok "nach dem Beenden des zweiten sind es wieder eins" \
  || bad "nach dem Beenden werden $WIEDER_EINS gezaehlt"

# ---------------------------------------------------------------------------
# Punkt 4: maximale Zeit bis zum Ende, auch aus dem Poll-Schlaf heraus
# ---------------------------------------------------------------------------
echo "-- Punkt 4: der Guard beendet sich spaetestens ein Poll-Intervall nach dem Session-Ende --"
neue_orch_session "wb-GT-timing"
PANE_T="$PANE"
POLL_T=3
lauf "POLL=$POLL_T nohup '$GUARD' --auto --exit-when-session-gone '$PANE_T' >'$TESTHOME/t.log' 2>&1 & echo PID=\$!"
PID_T="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_T"
if [ -n "$PID_T" ] && kill -0 "$PID_T" 2>/dev/null; then
  sleep 1   # sicherstellen, dass der Guard im Poll-Schlaf steckt (POLL=3), nicht mitten im Start
  TOLERANZ=$(( POLL_T + 5 ))
  START_KILL=$SECONDS
  tm kill-session -t "=wb-GT-timing" 2>/dev/null
  if wait_gone "$PID_T" $(( POLL_T + 15 )); then
    GEMESSEN=$((SECONDS - START_KILL))
    ok "Guard beendet sich ${GEMESSEN}s nach dem Session-Ende (POLL=${POLL_T}s)"
    if [ "$GEMESSEN" -le "$TOLERANZ" ]; then
      ok "gemessene Zeit (${GEMESSEN}s) liegt innerhalb POLL+5s (${TOLERANZ}s Toleranz fuer Testrechner-Last)"
    else
      bad "gemessene Zeit (${GEMESSEN}s) liegt UEBER POLL+5s (${TOLERANZ}s) -- Bound verletzt"
    fi
  else
    GEMESSEN=$((SECONDS - START_KILL))
    bad "Guard laeuft ${GEMESSEN}s nach dem Session-Ende noch (POLL=${POLL_T}s, Toleranz ${TOLERANZ}s)"
  fi
else
  bad "Vorbereitung fuer Punkt 4 fehlgeschlagen: kein Guard gestartet"
fi

echo
echo "wb-guard-sessionende: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
