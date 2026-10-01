#!/usr/bin/env bash
# test-revive.sh — die Liveness-Sperre von wb-revive und wb-autorevive.
#
# Anlass (2026-08-04): beide Werkzeuge riefen `tmux respawn-pane -k` ohne je
# `#{pane_dead}` zu pruefen. `-k` beendet den Prozess im Pane, auch einen
# arbeitenden Claude. Der Weg dorthin ist die Tastenbindung prefix + R, also ein
# einzelner Fehlgriff. Betriebslauf 2 hat es mit wechselnden PIDs reproduziert
# (Abschnitte 3b und 4b); diese Suite haelt die Reparatur fest.
#
# Geprueft wird:
#   1  toter claude-Pane wird wiederbelebt, mit '--continue' (der eigentliche Zweck)
#   2  LEBENDER claude-Pane bleibt unberuehrt, PID unveraendert, Rueckgabewert 3
#   3  '--force' ohne Terminal und ohne '--yes' fasst ihn ebenfalls nicht an
#   4  '--force --yes' startet ihn trotzdem neu (der ausdrueckliche Weg)
#   5  derselbe lebende Pane ueber wb-autorevive: unberuehrt, Rueckgabewert 3
#   6  wb-autorevive belebt einen toten claude-Pane weiterhin
#   7  Nicht-claude-Panes (tot wie lebendig) bleiben unberuehrt
#   8  der Weg der Tastenbindung selbst: tmux run-shell "wb-revive '#{pane_id}'"
#      gegen einen lebenden Pane laesst ihn stehen
#
# SICHERHEIT. Nichts hiervon beruehrt die Live-Umgebung:
#   * eigener tmux-Socket 'wbtest-revive-<pid>'. Der Prueflig laeuft NIE aus
#     dieser Shell heraus, sondern in einem PANE des Testservers — nur dort zeigt
#     sein geerbtes $TMUX auf den Testsocket, und nur so landen seine eigenen
#     `tmux`-Aufrufe dort statt auf 'default' (Regel vom 2026-08-04). Zusaetzlich
#     liegt ein `tmux`-Schirm vorn im PATH, der jeden Aufruf festnagelt.
#   * eigenes HOME (mktemp -d): Log- und Drossel-Dateien entstehen nur dort;
#     wb-autorevive startet ausserdem "$HOME/.local/bin/wb-revive", trifft damit
#     also die hierher kopierte Repo-Fassung und nicht die installierte.
#   * die installierte ~/.tmux.conf laedt auch auf einem frischen Testsocket und
#     bindet 'pane-died' per ABSOLUTEM Pfad an die installierte Fassung von
#     wb-autorevive. Dieser Hook wuerde bei jedem hier absichtlich herbeigefuehrten
#     Pane-Tod mitlaufen und mit der eigenen Messung um denselben Pane streiten —
#     er wird deshalb fuer den ganzen Lauf abgeschaltet (tmux_live_hooks_kappen,
#     lib-testwerkzeuge.sh -- derselbe Baustein, den test-doctor-betriebs-befunde.sh
#     nach einem sporadisch roten Lauf bekam, hier auf den bereits vorher erkannten
#     Fall gezogen).
#   * `trap` raeumt Server und Verzeichnis auf, auch bei Abbruch. Kein pkill.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-revive-$$"
TESTHOME="$(mktemp -d)"
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench"

# Seit dem 2026-08-06 holt wb-revive die Fortsetzen-Flags aus der Registry statt sie
# im Code zu tragen. Diese Suite bekommt deshalb ihre EIGENE, winzige Registry — die
# ausgelieferte oder gar die echte zu benutzen hiesse, den Zustand der Maschine zu
# pruefen statt den Code. `fallbackArgs` steht hier auf '--continue', weil genau das
# die Faelle 1 bis 8 unten erwarten: ohne gemerkte Sitzungskennung faellt wb-revive
# darauf zurueck, und das ist das Verhalten, das diese Suite seit jeher festhaelt.
cat > "$TESTHOME/.claude/workbench/models.json" <<'REGEOF'
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "claude", "label": "Pruef-Claude", "command": "claude",
      "args": ["--model", "{model}"], "cwdMode": "cd",
      "resume": {"args": ["--resume", "{resumeId}"], "fallbackArgs": ["--continue"],
                 "probe": "revive-only"},
      "readyPattern": "❯", "promptPattern": "^❯", "compactCommand": "/compact",
      "contextPattern": null
    }
  ],
  "models": []
}
REGEOF
for w in wb-revive wb-autorevive wb-state; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/*

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Fake-'claude': schreibt sein argv in eine Marke und laeuft dann endlos weiter,
# WENN '--continue' dabei ist (die fortgesetzte, laufende Session) — sonst endet
# es sofort mit Code 9 (der urspruengliche Absturz). Mehr braucht es nicht: die
# Werkzeuge reagieren nur auf die Zeichenkette 'claude' in @wb_cmd und darauf, ob
# der Pane danach lebt.
MARKER="$TESTHOME/claude-argv.log"
cat > "$SHIM/claude" <<CLAUDEEOF
#!/bin/sh
echo "ARGV: \$*" >> "$MARKER"
case " \$* " in
  *" --continue "*) while :; do sleep 1; done ;;
  *) exit 9 ;;
esac
CLAUDEEOF
chmod +x "$SHIM/claude"
: > "$MARKER"

# Der Speicher-Waechter von wb-autorevive wird GESCHIRMT, nicht dem Zufall ueberlassen.
#
# Anlass (Bugjagd 2026-08-15): Diese Suite flatterte — 5 von 6 Laeufen rot, immer an
# Fall 6 ("der Pane lebt nicht"). Die Ursache lag nicht im Code, sondern in der Kopplung
# an die Maschine: `wb-autorevive` ueberspringt die Wiederbelebung unter 20 % freiem
# Speicher, und die Maschine stand waehrend der Messung bei 24 % — mit einer parallelen
# Modellsitzung fiel sie darunter. Die Suite prueft seither den Zustand des Rechners
# statt den Code. Mit dem Schirm steht der Messwert fest; wieviel Speicher gerade frei
# ist, spielt keine Rolle mehr. `wb-autorevive` fragt `memory_pressure` VOR /proc/meminfo,
# darum wirkt der Schirm auf beiden Maschinen.
FREIMEM="$TESTHOME/freimem"
echo 90 > "$FREIMEM"          # reichlich frei — der Waechter darf nicht dazwischenfunken
cat > "$SHIM/memory_pressure" <<MEMEOF
#!/bin/sh
# Wortlaut wie das echte macOS-Werkzeug; wb-autorevive liest daraus die Prozentzahl.
echo "System-wide memory free percentage: \$(cat "$FREIMEM")%"
MEMEOF
chmod +x "$SHIM/memory_pressure"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
AUTOLOG="$TESTHOME/.local/state/wb-autorevive.log"

echo "== test-revive: die Liveness-Sperre von wb-revive / wb-autorevive =="
echo "   Socket: $SOCKET   HOME: $TESTHOME   Repo-Stand: $REPO"
echo

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp -x 100 -y 30
CTRL="$(tm list-panes -t steuer -F '#{pane_id}' | head -1)"
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh
# `tmux respawn-pane` (wb-revive/wb-autorevive) startet die neue Shell OHNE
# das inline 'PATH=... claude' der ERSTEN Erzeugung -- sie bekommt nur das
# ererbte PATH. zsh (der Default-Shell dieser Maschine) sourced dabei IMMER,
# auch nicht-interaktiv, das systemweite /etc/zshenv, und das setzt hier
# 'PATH=$HOME/.local/bin:$PATH' -- genau der Pfad des ECHTEN installierten
# claude. Ohne diese Zeile laeuft nach jedem Respawn also der ECHTE claude
# statt des Fake-CLI aus $SHIM (gemessen 2026-08-09: Pane bleibt leben, aber
# $MARKER bekommt nie eine neue Zeile). bash sourced fuer 'sh -c' keine
# vergleichbare Datei, bleibt beim ererbten PATH.
tm set-option -g default-shell /bin/bash

# Der Prueflig laeuft in einem Pane des TESTSERVERS, nie aus dieser Shell heraus.
lauf() { # lauf <kommando> -> setzt OUT und RC
  local f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t "$CTRL" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; $1 ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 30 "lauf: $1" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

SESS="wb-Revivetest-$$"
# remain-on-exit ist eine FENSTER-Option und steht als GLOBALE Vorgabe, bevor der
# erste Pane entsteht — sonst zerlegt tmux einen sofort endenden Pane, ehe er
# geprueft werden kann. Global, weil jeder Testfall sein EIGENES Fenster bekommt:
# acht Panes in einem 30 Zeilen hohen Fenster laufen aus dem Platz ("no space for
# a new pane", gemessen), und ein Fall, dessen Pane gar nicht erst entsteht,
# prueft nichts mehr.
tm set-option -wg remain-on-exit on
tm new-session -d -s "$SESS" -c /tmp -x 100 -y 30

pane_mit() { # pane_mit <kommando> -> Pane-Id in einem eigenen Fenster
  local p
  p="$(tm new-window -d -t "=$SESS:" -P -F '#{pane_id}' "$1" 2>/dev/null)"
  [ -n "$p" ] || { bad "Testaufbau: Pane fuer '$1' liess sich nicht anlegen"; return 1; }
  printf '%s' "$p"
}
toter_pane() { # toter_pane <modell> -> Pane-Id eines toten claude-Panes
  # ACHTUNG: das Stdout dieser Funktion ist die Rueckgabe (Aufrufer nutzen
  # 'P="$(toter_pane ...)"') -- jede Diagnose von warte_auf_bedingung/bad()
  # geht deshalb ausdruecklich nach stderr, sonst landet die FAIL-Zeile IM
  # zurueckgegebenen Pane-Namen und jede spaetere Zusage bricht daran.
  local p vorher
  p="$(pane_mit "PATH='$PANE_PATH' claude --model $1")" || return 1
  tm set -p -t "$p" @wb_cmd "claude --model $1"
  vorher="$(zeilen)"
  warte_auf_bedingung 15 "toter_pane($1): Fake-claude schreibt sein argv und endet" \
    '[ "$(zeilen)" -gt "$vorher" ] && [ "$(dead_of "$p")" = "1" ]' "$MARKER" 1>&2 || true
  printf '%s' "$p"
}
lebender_pane() { # lebender_pane <modell> -> Pane-Id eines laufenden claude-Panes
  # Dieselbe Regel wie in toter_pane(): Diagnose nach stderr, nie nach stdout.
  local p vorher
  p="$(pane_mit "PATH='$PANE_PATH' claude --continue --model $1")" || return 1
  tm set -p -t "$p" @wb_cmd "claude --continue --model $1"
  vorher="$(zeilen)"
  warte_auf_bedingung 15 "lebender_pane($1): Fake-claude schreibt sein argv" \
    '[ "$(zeilen)" -gt "$vorher" ]' "$MARKER" 1>&2 || true
  printf '%s' "$p"
}
dead_of() { tm display -p -t "$1" '#{pane_dead}' 2>/dev/null; }
pid_of()  { tm display -p -t "$1" '#{pane_pid}' 2>/dev/null; }
zeilen()  {
  # `grep -c` druckt bei null Treffern selbst schon "0" UND scheitert mit rc=1
  # (2026-08-20 gefunden, derselbe Fehler wie bei B1: Rueckgabewert und Ausgabe
  # sind hier nicht dasselbe). Das alte `grep -c . "$MARKER" || echo 0` liess
  # dann BEIDE feuern, "0\n0" statt "0" -- folgenlos nur, weil jede Verwendung
  # unten zwei Aufrufe auf Stringgleichheit vergleicht statt eine Zahl zu lesen.
  # Erst einsammeln, dann entscheiden: leer heisst "Datei fehlt", "0" bleibt "0".
  local n; n="$(grep -c . "$MARKER" 2>/dev/null)"
  printf '%s\n' "${n:-0}"
}

# ── 1: der eigentliche Zweck — ein toter Pane kommt zurueck ─────────────────
echo "-- 1: toter claude-Pane wird wiederbelebt --"
P1="$(toter_pane fall1)"
[ "$(dead_of "$P1")" = 1 ] && ok "1: der simulierte Absturz-Pane ist tot (pane_dead=1)" \
                           || bad "1: Testaufbau fehlerhaft (pane_dead=$(dead_of "$P1"))"
lauf "wb-revive '$P1'"
warte_auf_bedingung 15 "1: der Pane lebt nach wb-revive wieder" '[ "$(dead_of "$P1")" = "0" ]' || true
[ "$RC" -eq 0 ] && ok "1: wb-revive meldet Erfolg (rc=0)" || bad "1: rc=$RC statt 0 ($OUT)"
[ "$(dead_of "$P1")" = 0 ] && ok "1: der Pane lebt wieder (pane_dead=0)" \
                           || bad "1: der Pane lebt nicht (pane_dead=$(dead_of "$P1"))"
case "$(tail -1 "$MARKER")" in
  *--continue*) ok "1: der neue Lauf traegt '--continue' (fortgesetzt)" ;;
  *) bad "1: '--continue' fehlt im neuen Lauf: '$(tail -1 "$MARKER")'" ;;
esac

# ── 2: der Fall, um den es geht ─────────────────────────────────────────────
echo
echo "-- 2: LEBENDER claude-Pane bleibt unberuehrt --"
P2="$(lebender_pane fall2)"
[ "$(dead_of "$P2")" = 0 ] && ok "2: der Pane laeuft (pane_dead=0) -- Testaufbau korrekt" \
                           || bad "2: Testaufbau fehlerhaft (pane_dead=$(dead_of "$P2"))"
pid_vor="$(pid_of "$P2")"; zeilen_vor="$(zeilen)"
lauf "wb-revive '$P2'"
sleep 1.5
pid_nach="$(pid_of "$P2")"; zeilen_nach="$(zeilen)"
if [ "$pid_nach" = "$pid_vor" ] && [ "$zeilen_nach" = "$zeilen_vor" ]; then
  ok "2: PID unveraendert ($pid_vor), kein neuer claude-Start"
else
  bad "2: der lebende Pane wurde angefasst -- PID $pid_vor -> $pid_nach, ARGV-Zeilen $zeilen_vor -> $zeilen_nach"
fi
[ "$RC" -eq 3 ] && ok "2: Rueckgabewert 3 unterscheidet das vom Erfolg" \
                || bad "2: rc=$RC statt 3 -- ununterscheidbar von einem echten Revive"
printf '%s\n' "$OUT" | grep -q 'still running' \
  && ok "2: die Meldung sagt, warum nichts geschah" || bad "2: keine Meldung: '$OUT'"

# ── 3: '--force' allein reicht ohne Terminal nicht ──────────────────────────
echo
echo "-- 3: '--force' ohne Terminal und ohne '--yes' --"
pid_vor="$(pid_of "$P2")"; zeilen_vor="$(zeilen)"
lauf "wb-revive --force '$P2' < /dev/null"
sleep 1
[ "$(pid_of "$P2")" = "$pid_vor" ] && [ "$(zeilen)" = "$zeilen_vor" ] \
  && ok "3: der Pane bleibt stehen (PID $pid_vor)" \
  || bad "3: '--force' allein hat den lebenden Pane beendet -- PID $pid_vor -> $(pid_of "$P2")"
[ "$RC" -eq 3 ] && ok "3: Rueckgabewert 3" || bad "3: rc=$RC statt 3"
printf '%s\n' "$OUT" | grep -q -- '--yes' \
  && ok "3: die Meldung nennt den ausdruecklichen Weg ('--yes')" || bad "3: keine '--yes'-Meldung: '$OUT'"

# ── 4: der ausdrueckliche Weg tut es trotzdem ──────────────────────────────
echo
echo "-- 4: '--force --yes' startet den lebenden Pane neu --"
pid_vor="$(pid_of "$P2")"; zeilen_vor="$(zeilen)"
lauf "wb-revive --force --yes '$P2' < /dev/null"
warte_auf_bedingung 15 "4: der Prozess wird nach '--force --yes' ersetzt" '[ "$(pid_of "$P2")" != "$pid_vor" ]' || true
pid_nach="$(pid_of "$P2")"; zeilen_nach="$(zeilen)"
[ "$RC" -eq 0 ] && ok "4: wb-revive meldet Erfolg (rc=0)" || bad "4: rc=$RC statt 0 ($OUT)"
[ "$pid_nach" != "$pid_vor" ] && ok "4: der Prozess wurde ersetzt (PID $pid_vor -> $pid_nach)" \
                              || bad "4: PID unveraendert ($pid_vor) -- '--force --yes' hat nichts getan"
[ "$zeilen_nach" -gt "$zeilen_vor" ] && ok "4: ein neuer claude-Start ist belegt" \
                                     || bad "4: keine neue ARGV-Zeile ($zeilen_vor -> $zeilen_nach)"
[ "$(dead_of "$P2")" = 0 ] && ok "4: der Pane laeuft danach wieder" \
                           || bad "4: der Pane ist tot (pane_dead=$(dead_of "$P2"))"

# ── 5: derselbe Fall ueber den zweiten Einstiegspunkt ──────────────────────
echo
echo "-- 5: LEBENDER Pane ueber wb-autorevive --"
P5="$(lebender_pane fall5)"
[ "$(dead_of "$P5")" = 0 ] && ok "5: der Pane laeuft -- Testaufbau korrekt" \
                           || bad "5: Testaufbau fehlerhaft (pane_dead=$(dead_of "$P5"))"
pid_vor="$(pid_of "$P5")"; zeilen_vor="$(zeilen)"
lauf "wb-autorevive '$P5'"
sleep 1.5
if [ "$(pid_of "$P5")" = "$pid_vor" ] && [ "$(zeilen)" = "$zeilen_vor" ]; then
  ok "5: PID unveraendert ($pid_vor), kein neuer claude-Start"
else
  bad "5: wb-autorevive hat den lebenden Pane angefasst -- PID $pid_vor -> $(pid_of "$P5")"
fi
[ "$RC" -eq 3 ] && ok "5: Rueckgabewert 3" || bad "5: rc=$RC statt 3"
grep -q 'still running' "$AUTOLOG" 2>/dev/null \
  && ok "5: das Log begruendet den Ueberspringer" || bad "5: keine Begruendung im Log"
# Ein uebersprungener lebender Pane darf keine Drossel-Marke hinterlassen, sonst
# wuerde ein spaeterer ECHTER Tod desselben Panes faelschlich gedrosselt.
[ -e "$TESTHOME/.local/state/wb-autorevive/${P5//[^A-Za-z0-9]/_}" ] \
  && bad "5: der Ueberspringer hat eine Drossel-Marke hinterlassen" \
  || ok "5: keine Drossel-Marke -- ein spaeterer echter Tod wird nicht gedrosselt"

# ── 6: wb-autorevive belebt weiterhin, was wirklich tot ist ────────────────
echo
echo "-- 6: toter claude-Pane ueber wb-autorevive --"
P6="$(toter_pane fall6)"
[ "$(dead_of "$P6")" = 1 ] && ok "6: der Pane ist tot -- Testaufbau korrekt" \
                           || bad "6: Testaufbau fehlerhaft (pane_dead=$(dead_of "$P6"))"
lauf "wb-autorevive '$P6'"
warte_auf_bedingung 15 "6: der tote Pane wird von wb-autorevive wiederbelebt" '[ "$(dead_of "$P6")" = "0" ]' || true
[ "$RC" -eq 0 ] && ok "6: wb-autorevive laeuft durch (rc=0)" || bad "6: rc=$RC statt 0 ($OUT)"
[ "$(dead_of "$P6")" = 0 ] && ok "6: der tote Pane wurde wiederbelebt" \
                           || bad "6: der Pane lebt nicht (pane_dead=$(dead_of "$P6"))"

# ── 7: Nicht-claude-Panes gehen niemanden etwas an ────────────────────────
echo
echo "-- 7: Nicht-claude-Panes, tot wie lebendig --"
P7T="$(pane_mit "true")"
tm set -p -t "$P7T" @wb_cmd "bash -c true"
warte_auf_bedingung 15 "7: der Nicht-claude-Pane (true) endet" '[ "$(dead_of "$P7T")" = "1" ]' || true
[ "$(dead_of "$P7T")" = 1 ] && ok "7: der Nicht-claude-Pane ist tot -- Testaufbau korrekt" \
                            || bad "7: Testaufbau fehlerhaft, der Nicht-claude-Pane lebt noch"
lauf "wb-revive '$P7T'"
sleep 0.5
[ "$(dead_of "$P7T")" = 1 ] && ok "7: der tote Nicht-claude-Pane bleibt liegen" \
                            || bad "7: ein Nicht-claude-Pane wurde wiederbelebt"
[ "$RC" -eq 0 ] && ok "7: wb-revive endet ohne Fehler (rc=0)" || bad "7: rc=$RC statt 0 ($OUT)"

P7L="$(pane_mit "sleep 300")"
tm set -p -t "$P7L" @wb_cmd "sleep 300"
sleep 0.5
pid_vor="$(pid_of "$P7L")"
lauf "wb-revive '$P7L'"
sleep 0.5
[ "$(pid_of "$P7L")" = "$pid_vor" ] && ok "7: der lebende Nicht-claude-Pane bleibt unberuehrt (PID $pid_vor)" \
                                    || bad "7: ein lebender Nicht-claude-Pane wurde angefasst"

# ── 8: der Weg der Tastenbindung selbst ───────────────────────────────────
# ~/.tmux.conf bindet: bind-key R run-shell "wb-revive '#{pane_id}'". Geprueft
# wird genau diese Form — run-shell mit Format-Ersetzung, ohne Terminal — nur
# ohne den Tastendruck davor, der einen angehefteten Client braeuchte.
echo
echo "-- 8: der Weg der Tastenbindung (run-shell mit #{pane_id}) --"
P8="$(lebender_pane fall8)"
pid_vor="$(pid_of "$P8")"; zeilen_vor="$(zeilen)"
tm run-shell -t "$P8" "PATH='$PANE_PATH' HOME='$TESTHOME' '$BIN/wb-revive' '#{pane_id}'" >/dev/null 2>&1
rc8=$?
sleep 1.5
if [ "$(pid_of "$P8")" = "$pid_vor" ] && [ "$(zeilen)" = "$zeilen_vor" ]; then
  ok "8: prefix+R gegen einen lebenden Pane laesst ihn stehen (PID $pid_vor, rc=$rc8)"
else
  bad "8: der Weg der Tastenbindung hat den lebenden Pane beendet -- PID $pid_vor -> $(pid_of "$P8")"
fi

# ── 9: der Speicher-Waechter ist sichtbar und unterscheidbar ──────────────
# Zwei Zusagen in einem Fall: der Waechter greift bei wenig Speicher UND sein
# Ueberspringer ist am Rueckgabewert vom Erfolg zu unterscheiden. Frueher endeten
# "wiederbelebt" und "wegen Speicher uebersprungen" beide mit 0 — fuer den
# pane-died-Hook egal, fuer jeden anderen Aufrufer eine stille Luege, und fuer diese
# Suite der Grund, dass sie den Maschinenzustand fuer den Code hielt.
echo
echo "-- 9: wenig Speicher: uebersprungen, mit eigenem Rueckgabewert --"
echo 5 > "$FREIMEM"
P9="$(toter_pane fall9)"
zeilen_vor="$(zeilen)"
lauf "wb-autorevive '$P9'"
sleep 1
[ "$RC" -eq 4 ] && ok "9: Rueckgabewert 4 sagt 'wegen Speicher uebersprungen'" \
                || bad "9: rc=$RC statt 4 — ununterscheidbar von einer echten Wiederbelebung ($OUT)"
[ "$(dead_of "$P9")" = 1 ] && ok "9: der Pane bleibt tot (Handbetrieb, wie vorgesehen)" \
                           || bad "9: der Pane wurde trotz Speichermangel wiederbelebt"
[ "$(zeilen)" = "$zeilen_vor" ] && ok "9: kein neuer claude-Start" \
                                || bad "9: es lief doch ein claude an"
grep -q 'memory low' "$AUTOLOG" 2>/dev/null \
  && ok "9: das Log nennt den Grund" || bad "9: keine Begruendung im Log"
echo 90 > "$FREIMEM"
lauf "wb-autorevive '$P9'"
warte_auf_bedingung 15 "9: mit freiem Speicher wird der Pane wiederbelebt" '[ "$(dead_of "$P9")" = "0" ]' || true
[ "$RC" -eq 0 ] && ok "9: mit freiem Speicher belebt derselbe Aufruf wieder (rc=0)" \
                || bad "9: rc=$RC statt 0 nach Entspannung ($OUT)"
[ "$(dead_of "$P9")" = 0 ] && ok "9: der Pane lebt wieder" \
                           || bad "9: der Pane lebt nicht (pane_dead=$(dead_of "$P9"))"

# ── 10: zwei Reviver, ein Pane, EIN Respawn ───────────────────────────────
# Der pane-died-Hook und prefix + R sehen denselben toten Pane. Ohne Sperre respawnen
# beide, und der zweite `-k` beendet die Unterhaltung, die der erste gerade
# fortgesetzt hat.
echo
echo "-- 10: zwei gleichzeitige Reviver beleben genau einmal --"
P10="$(toter_pane fall10)"
zeilen_vor="$(zeilen)"
lauf "wb-revive '$P10' & wb-revive '$P10' & wait"
warte_auf_bedingung 15 "10: der Pane lebt nach den zwei gleichzeitigen Revivern" '[ "$(dead_of "$P10")" = "0" ]' || true
zeilen_nach="$(zeilen)"
[ "$(dead_of "$P10")" = 0 ] && ok "10: der Pane lebt" \
                            || bad "10: der Pane lebt nicht (pane_dead=$(dead_of "$P10"))"
if [ $((zeilen_nach - zeilen_vor)) -eq 1 ]; then
  ok "10: genau EIN claude-Start ($zeilen_vor -> $zeilen_nach)"
else
  bad "10: $((zeilen_nach - zeilen_vor)) claude-Starts statt einem ($zeilen_vor -> $zeilen_nach) — der zweite Respawn hat die fortgesetzte Unterhaltung beendet"
fi
printf '%s\n' "$OUT" | grep -qE 'andere Wiederbelebung|still running' \
  && ok "10: der zweite Reviver sagt, warum er nichts tat" \
  || bad "10: der zweite Reviver blieb still: '$OUT'"

# ── 11: wb-autorevive erkennt Workbench-Panes, nicht das Wort "claude" ────
# Frueher entschied ein Teilzeichenketten-Vergleich auf *claude*: tote pi-Worker blieben
# mit "not a claude pane" liegen, und jedes Kommando mit "claude" irgendwo im Pfad galt
# als Treffer. Gefragt wird jetzt, ob der Pane uns gehoert (@wb_cmd / @wb_role /
# @wb_worker); welcher Harness darin steckt, entscheidet wb-revive.
echo
echo "-- 11: ein toter pi-Worker wird ebenfalls wiederbelebt --"
cat > "$SHIM/pi" <<'PIEOF'
#!/bin/sh
case " $* " in
  *" --continue "*) while :; do sleep 1; done ;;
  *) exit 9 ;;
esac
PIEOF
chmod +x "$SHIM/pi"
P11="$(pane_mit "PATH='$PANE_PATH' pi --provider pruef")" || true
tm set -p -t "$P11" @wb_cmd "pi --provider pruef"
tm set -p -t "$P11" @wb_worker pruefling
warte_auf_bedingung 15 "11: der pi-Pane (ohne --continue) endet" '[ "$(dead_of "$P11")" = "1" ]' || true
[ "$(dead_of "$P11")" = 1 ] && ok "11: der pi-Pane ist tot -- Testaufbau korrekt" \
                            || bad "11: Testaufbau fehlerhaft (pane_dead=$(dead_of "$P11"))"
lauf "wb-autorevive '$P11'"
warte_auf_bedingung 15 "11: der pi-Pane wird von wb-autorevive wiederbelebt" '[ "$(dead_of "$P11")" = "0" ]' || true
[ "$RC" -ne 6 ] && ok "11: wb-autorevive haelt ihn fuer einen Workbench-Pane (rc=$RC)" \
                || bad "11: 'kein Workbench-Pane' (rc=6) -- pi-Worker bleiben liegen"
[ "$(dead_of "$P11")" = 0 ] && ok "11: der pi-Pane lebt wieder" \
                            || bad "11: der pi-Pane blieb tot (pane_dead=$(dead_of "$P11"))"

echo
echo "-- 11b: ein fremder Pane ohne Workbench-Markierung bleibt liegen --"
P11B="$(pane_mit "true")"          # weder @wb_cmd noch @wb_role/@wb_worker
warte_auf_bedingung 15 "11b: der fremde Pane (true) endet" '[ "$(dead_of "$P11B")" = "1" ]' || true
lauf "wb-autorevive '$P11B'"
[ "$RC" -eq 6 ] && ok "11b: Rueckgabewert 6 sagt 'kein Workbench-Pane'" \
                || bad "11b: rc=$RC statt 6 ($OUT)"
[ "$(dead_of "$P11B")" = 1 ] && ok "11b: der fremde Pane bleibt liegen" \
                             || bad "11b: ein fremder Pane wurde angefasst"

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
