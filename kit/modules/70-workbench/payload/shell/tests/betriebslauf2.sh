#!/usr/bin/env bash
# betriebslauf2.sh — der zweite Betriebslauf, fuer die Rettungs- und
# Aufraeumwerkzeuge, die betriebslauf.sh selbst als offen benennt (siehe dessen
# eigener OPEN-Abschnitt, 2026-08-04): `wb-session-sweep`, `wb-autorevive`,
# `wb-revive`, `wb-close` (auch `--all-workers`) und der Tastendruck-Weg
# `wb-session-close --self`.
#
# Diese fuenf laufen selten, greifen dann aber tief ein — `wb-revive` startet
# einen Claude neu, `wb-session-sweep` schliesst Sessions taeglich um 04:30
# unbeaufsichtigt, `wb-close` beendet Worker. Ein Fehler darin faellt erst auf,
# wenn er Schaden angerichtet hat: am 2026-08-03 hat `wb-revive` um ein Haar
# anderthalb Stunden Arbeit getoetet, weil ein leerer Pane fuer einen toten
# Prozess gehalten wurde. Der wichtigste einzelne Fall dieses Laufs ist deshalb
# Schritt 3b: ein Pane, dessen Prozess NOCH LEBT, darf `wb-revive` nicht anfassen.
#
# SICHERHEIT. Nichts hiervon beruehrt die Live-Umgebung:
#   * eigener tmux-Socket 'wbtest-betrieb2-<pid>', kein einziger Aufruf gegen
#     'default'. Jedes Werkzeug laeuft ueber einen PATH-Schirm, der `tmux`
#     unabaenderlich auf diesen Socket festnagelt.
#   * eigenes HOME (mktemp -d): Zustandsdateien, Marken und Logs entstehen
#     ausschliesslich dort.
#   * Sessionnamen mit eigenem Praefix ('wb-Betrieb2-…'), nie ein Name aus
#     laufenden des Nutzers Sessions.
#   * `trap` raeumt Server und Verzeichnisse auf, auch bei Abbruch. Kein pkill,
#     kein killall, kein Muster ueber fremde Prozesse — Prozesse werden nur
#     ueber den eigenen isolierten tmux-Server beendet (kill-server dieses
#     Sockets), nie per Name/Signal gegen den Rest des Systems.
#
# WICHTIG zu ~/.tmux.conf: ein frischer tmux-Server auf einem NEUEN Socket laedt
# automatisch die installierte ~/.tmux.conf (gemessen vor diesem Lauf: die
# Hooks 'after-split-window'/'pane-exited' -> wb-grid und 'pane-died' ->
# wb-autorevive sowie die Tastenbindung 'S' sind auf einem frischen Testsocket
# ohne '-f' sofort aktiv). Diese Hooks/Bindings tragen aber ABSOLUTE, fest
# einprogrammierte Pfade nach $HOME/.local/bin/... — sie rufen also
# IMMER die INSTALLIERTE Fassung, nicht die Kopie dieses Laufs unter $BIN,
# selbst wenn $PATH auf den Testsocket zeigt. Fuer Schritt 5 (der echte
# Tastendruck) wird deshalb eine EIGENE, minimale Tastenbindung gesetzt, die
# auf die Kopie dieses Laufs zeigt — sonst wuerde der Tastendruck-Test nicht
# den Repo-Stand pruefen, sondern zufaellig das, was gerade ausgerollt ist.
# Wo die Hooks (wb-grid/wb-autorevive) unvermeidlich die installierte Fassung
# nebenbei mitlaufen lassen, wird das im Ergebnis ausdruecklich vermerkt statt
# verschwiegen.
unset TMUX TMUX_PANE
set -uo pipefail

REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

WERKZEUGE="wb-session-sweep wb-session-close wb-close wb-revive wb-autorevive
           wb-workers-window wb-grid wb-state"

SOCKET="wbtest-betrieb2-$$"
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

pass=0; fail=0; skip=0
FUNDE=()

# Ist $REPO ein git-Worktree (statt des Hauptbaums)? In einem Worktree hat
# `git rev-parse --git-dir` einen eigenen Pfad unter der HAUPT-.git/worktrees/,
# waehrend `--git-common-dir` immer auf die eine geteilte .git des Hauptbaums
# zeigt -- im Hauptbaum selbst sind beide identisch. Ungueltig/leer (kein
# git, kein Repo) faellt auf "Hauptbaum" zurueck, damit die Pruefung im
# Zweifel LAEUFT statt sich selbst grundlos zu uebergehen.
is_worktree() {
  local gd cd
  gd="$(git -C "$REPO" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cd="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$gd" ] && [ -n "$cd" ] && [ "$gd" != "$cd" ]
}

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
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

fund() { # fund <schritt> <erwartet> <beobachtet> <reproduktion>
  FUNDE+=("$(printf 'Schritt:      %s\nErwartet:     %s\nBeobachtet:   %s\nReproduktion: %s' "$1" "$2" "$3" "$4")")
}

# --- Vorbereitung -----------------------------------------------------------
mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.claude/workbench/orphans" "$TESTHOME/.local/state"
ABWEICHEND=""
for w in $WERKZEUGE; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
  if [ -x "$REPO/$w" ] && [ -x "$REAL_BIN/$w" ] && ! cmp -s "$REPO/$w" "$REAL_BIN/$w"; then
    ABWEICHEND="$ABWEICHEND $w"
  fi
done
chmod +x "$BIN"/*

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Fake-'claude' fuer Schritt 3/4: schreibt sein komplettes argv in eine Marke
# und laeuft dann endlos weiter, WENN '--continue' dabei ist (simuliert eine
# fortgesetzte, laufende Session) — sonst beendet es sich sofort mit Code 9
# (simuliert den urspruenglichen Absturz/Exit). Kein echter 'claude'-Prozess
# noetig, nur das Verhalten, auf das wb-revive/wb-autorevive tatsaechlich
# reagieren: die Zeichenkette 'claude' in @wb_cmd, und ob der Pane danach lebt.
CLAUDE_MARKER="$TESTHOME/claude-argv.log"
cat > "$SHIM/claude" <<CLAUDEEOF
#!/bin/sh
echo "ARGV: \$*" >> "$CLAUDE_MARKER"
case " \$* " in
  *" --continue "*) while :; do sleep 1; done ;;
  *) exit 9 ;;
esac
CLAUDEEOF
chmod +x "$SHIM/claude"

# Speicherwaechter von wb-autorevive festnageln (Schritt 4), wie in test-revive.sh.
# Anlass (2026-09-25, vierter Gesamtlauf auf 1b24d375): unter der Last von
# `run-all.sh --jobs 6` fiel die Maschine unter 20 % freien Speicher, wb-autorevive
# liess den Pane korrekt tot liegen (Exit 4, "memory low") -- 4b sah "Pane lebt
# nicht", und weil nach dem Ueberspringer keine Drossel-Datei entsteht, fehlte in 4c
# "throttled". Einzeln war die Suite gruen. Geprueft werden soll der Code, nicht der
# freie Speicher des Rechners; der Waechter selbst hat seine Faelle in test-revive.sh.
# WB_TEST_FREIMEM erlaubt, den Ausfall gezielt nachzustellen (z. B. 10).
FREIMEM="$TESTHOME/freimem"
echo "${WB_TEST_FREIMEM:-90}" > "$FREIMEM"
cat > "$SHIM/memory_pressure" <<MEMEOF
#!/bin/sh
echo "System-wide memory free percentage: \$(cat "$FREIMEM")%"
MEMEOF
chmod +x "$SHIM/memory_pressure"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== Betriebslauf 2: Rettungs- und Aufraeumwerkzeuge =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo "   Geprueft wird der Repo-Stand aus $REPO"
if is_worktree; then
  # Der Vergleich ist in einem Worktree bedeutungslos: ~/.local/bin gehoert
  # zum HAUPTBAUM, nicht zu diesem Arbeitsbaum, und Worker rollen dort seit
  # 04.08. (Regelaenderung nach Abnahme des vorigen Auftrags) grundsaetzlich
  # nichts mehr aus -- ein Auseinanderlaufen ist hier der Normalfall, kein
  # Fund. Sichtbar uebersprungen statt stillschweigend weggelassen oder als
  # falscher Fehlschlag/Erfolg gezaehlt.
  printf '  %-5s %s\n' "SKIP" "Deploy-Vergleich uebersprungen -- $REPO ist ein Arbeitsbaum (git-Worktree, nicht der Hauptbaum). ~/.local/bin gehoert zum Hauptbaum; Worker rollen dorthin nichts mehr aus."
  skip=$((skip+1))
elif [ -n "$ABWEICHEND" ]; then
  bad "Ausgerollt und Repo gehen auseinander:$ABWEICHEND"
  fund "0 (vor dem ersten Schritt)" \
       "die Fassung unter ~/.local/bin ist dieselbe wie im Repo" \
       "diese Werkzeuge weichen ab:$ABWEICHEND" \
       "for f in$ABWEICHEND; do cmp -s shell/\$f ~/.local/bin/\$f || echo \"\$f abweichend\"; done"
else
  ok "ausgerollte Fassung und Repo-Stand sind identisch"
fi
echo

lauf() { # lauf <pane> <kommando> -> setzt OUT und RC
  local ziel="$1" cmd="$2" f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t "$ziel" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 30 "lauf: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}
steuer() { lauf "$CTRL" "$1"; }
lebt() { tm has-session -t "=$1" 2>/dev/null; }

tm kill-server 2>/dev/null
tm new-session -d -s steuer2 -c /tmp -x 200 -y 50
CTRL="$(tm list-panes -t steuer2 -F '#{pane_id}' | head -1)"

# Die installierte ~/.tmux.conf laedt automatisch auch auf DIESEM frischen
# Testsocket (gemessen vor diesem Lauf) und bindet 'pane-died' fest an
# $HOME/.local/bin/wb-autorevive sowie 'pane-exited'/'after-split-window'
# an .../wb-grid -- beides absolute Pfade, die IMMER die INSTALLIERTE Fassung
# treffen, egal was $PATH hier sagt. Fuer Schritt 3/4 (wb-revive/wb-autorevive)
# ist das doppelt schaedlich: der Hook wuerde parallel zu jedem hier bewusst
# herbeigefuehrten Pane-Tod ebenfalls automatisch zuschlagen und mit der
# eigenen, gezielten Messung um denselben Pane konkurrieren (Drossel-Dateien,
# Marker-Zeilen, Timing -- nicht mehr reproduzierbar). Diese beiden globalen
# Hooks werden deshalb fuer den GESAMTEN Lauf abgeschaltet; Schritt 2
# (wb-close) prueft dessen Wirkung dadurch ausschliesslich isoliert, ohne vom
# Hook verdeckt oder verdoppelt zu werden -- was hier beobachtet wird, ist
# wirklich nur das, was das jeweils getestete Werkzeug selbst tut.
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

# `tmux respawn-pane` (wb-revive/wb-autorevive, Schritt 3/4) startet die neue
# Shell OHNE das inline 'PATH=... claude' der ERSTEN Erzeugung -- sie bekommt
# nur das ererbte PATH. zsh (der Default-Shell dieser Maschine) sourced dabei
# IMMER, auch nicht-interaktiv, das systemweite /etc/zshenv, und das setzt
# hier 'PATH=$HOME/.local/bin:$PATH' -- genau der Pfad des ECHTEN
# installierten claude. Ohne diese Zeile laeuft nach jedem Respawn also der
# ECHTE claude statt des Fake-CLI aus $SHIM (gemessen 2026-08-09: Pane bleibt
# leben, aber $CLAUDE_MARKER bekommt nie eine neue Zeile -- die vier
# Fehlschlaege in Schritt 3, die genau daran haengen). bash sourced fuer
# 'sh -c' keine vergleichbare Datei, bleibt beim ererbten PATH.
tm set-option -g default-shell /bin/bash

# ═════════════════════════════════════════════════════════════════════════
# Schritt 1: wb-session-sweep
# ═════════════════════════════════════════════════════════════════════════
echo "-- Schritt 1: wb-session-sweep --"
ORPHANS="$TESTHOME/.claude/workbench/orphans"
SWEEPLOG="$TESTHOME/.local/state/wb-session-sweep.log"

marke() { # marke <session> <alter_s>
  local alt_ms=$(( ($(date +%s) - $2) * 1000 ))
  printf '{"session":"%s","folder":"/tmp","token":"t","at":%s}\n' "$1" "$alt_ms" > "$ORPHANS/$1.json"
}

# 1a: alt genug (Marke 700s alt, Default-Schwelle 600s) -> wird geschlossen
S_OLD="wb-Betrieb2-alt-$$"
tm new-session -d -s "$S_OLD" -c /tmp
marke "$S_OLD" 700

# 1b: jung, keine Marke -> bleibt (Default-Schwelle 3 Tage, Session gerade erst entstanden)
S_YOUNG="wb-Betrieb2-jung-$$"
tm new-session -d -s "$S_YOUNG" -c /tmp

# 1c: alt genug, aber ein Client haengt -> muss trotzdem bleiben
S_CLIENT="wb-Betrieb2-klient-$$"
tm new-session -d -s "$S_CLIENT" -c /tmp
marke "$S_CLIENT" 700
KL_C="$(tm split-window -d -t steuer2 -P -F '#{pane_id}' \
  "TMUX= TMUX_PANE= PATH='$PANE_PATH' HOME='$TESTHOME' tmux attach -t '=$S_CLIENT'")"
deadline=$((SECONDS+10))
until [ "$(tm list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null | awk -v n="$S_CLIENT" '$1==n{print $2}')" = "1" ] || [ $SECONDS -ge $deadline ]; do sleep 0.3; done

# 1d: alt genug, aber ein LEBENDER Worker-Pane -> muss bleiben
S_WORKER="wb-Betrieb2-worker-$$"
tm new-session -d -s "$S_WORKER" -c /tmp
marke "$S_WORKER" 700
WP="$(tm split-window -d -t "=$S_WORKER:" -P -F '#{pane_id}')"
tm set -p -t "$WP" @wb_role worker

steuer "wb-session-sweep"
[ "$RC" -eq 0 ] && ok "1: wb-session-sweep laeuft durch (rc=0)" || bad "1: wb-session-sweep scheitert (rc=$RC): $OUT"

lebt "$S_OLD" && bad "1a: die verwaiste, alte Session '$S_OLD' lebt noch" \
             || ok "1a: die verwaiste, alte Session wurde geschlossen"
grep -q "GESCHLOSSEN gruppe=$S_OLD" "$SWEEPLOG" 2>/dev/null \
  && ok "1a: das Log nennt GESCHLOSSEN fuer '$S_OLD'" || bad "1a: kein GESCHLOSSEN-Eintrag fuer '$S_OLD' im Log"

lebt "$S_YOUNG" && ok "1b: die zu junge Session '$S_YOUNG' lebt weiter" \
                || bad "1b: die zu junge Session wurde faelschlich geschlossen"
grep -q "UEBERSPRUNGEN gruppe=$S_YOUNG .*grund=zu-jung" "$SWEEPLOG" 2>/dev/null \
  && ok "1b: das Log nennt grund=zu-jung fuer '$S_YOUNG'" || bad "1b: falscher/fehlender Grund fuer '$S_YOUNG' im Log"

lebt "$S_CLIENT" && ok "1c: die Session mit haengendem Client lebt weiter" \
                 || bad "1c: die Session mit Client wurde trotzdem geschlossen"
grep -q "UEBERSPRUNGEN gruppe=$S_CLIENT .*grund=client-haengt-an" "$SWEEPLOG" 2>/dev/null \
  && ok "1c: das Log nennt grund=client-haengt-an fuer '$S_CLIENT'" || bad "1c: falscher/fehlender Grund fuer '$S_CLIENT' im Log"

lebt "$S_WORKER" && ok "1d: die Session mit laufendem Worker lebt weiter" \
                 || bad "1d: die Session mit laufendem Worker wurde trotzdem geschlossen"
grep -q "UEBERSPRUNGEN gruppe=$S_WORKER .*grund=laufender-worker" "$SWEEPLOG" 2>/dev/null \
  && ok "1d: das Log nennt grund=laufender-worker fuer '$S_WORKER'" || bad "1d: falscher/fehlender Grund fuer '$S_WORKER' im Log"

tm kill-pane -t "$KL_C" 2>/dev/null

# 1e: die EIGENE Session -- Sweep wird AUS dieser Session heraus aufgerufen,
# die Marke ist alt genug, dass die Alters-Pruefung allein sie schliessen wollte.
S_OWN="wb-Betrieb2-eigen-$$"
tm new-session -d -s "$S_OWN" -c /tmp
OWNPANE="$(tm list-panes -t "=$S_OWN" -F '#{pane_id}' | head -1)"
marke "$S_OWN" 700
lauf "$OWNPANE" "wb-session-sweep"
[ "$RC" -eq 0 ] && ok "1e: wb-session-sweep (aus der eigenen Session heraus) laeuft durch" \
                || bad "1e: scheitert (rc=$RC): $OUT"
lebt "$S_OWN" && ok "1e: die eigene Session bleibt trotz alter Marke bestehen" \
              || bad "1e: die eigene Session wurde geschlossen — h\xC3\xA4tte sich selbst abgesaegt"
grep -q "UEBERSPRUNGEN gruppe=$S_OWN .*grund=eigene-session" "$SWEEPLOG" 2>/dev/null \
  && ok "1e: das Log nennt grund=eigene-session fuer '$S_OWN'" || bad "1e: falscher/fehlender Grund fuer '$S_OWN' im Log"
tm kill-session -t "=$S_OWN" 2>/dev/null

# 1f: Trockenlauf aendert nichts
S_DRY="wb-Betrieb2-dry-$$"
tm new-session -d -s "$S_DRY" -c /tmp
marke "$S_DRY" 700
steuer "wb-session-sweep --dry-run"
[ "$RC" -eq 0 ] && ok "1f: --dry-run laeuft durch (rc=0)" || bad "1f: --dry-run scheitert (rc=$RC): $OUT"
lebt "$S_DRY" && ok "1f: --dry-run hat die Session NICHT geschlossen" \
              || bad "1f: --dry-run hat die Session trotzdem geschlossen"
grep -q "WUERDE-SCHLIESSEN gruppe=$S_DRY" "$SWEEPLOG" 2>/dev/null \
  && ok "1f: das Log nennt WUERDE-SCHLIESSEN fuer '$S_DRY'" || bad "1f: kein WUERDE-SCHLIESSEN-Eintrag fuer '$S_DRY'"
tm kill-session -t "=$S_DRY" 2>/dev/null
tm kill-session -t "=$S_YOUNG" 2>/dev/null
tm kill-session -t "=$S_CLIENT" 2>/dev/null
tm kill-session -t "=$S_WORKER" 2>/dev/null

echo

# ═════════════════════════════════════════════════════════════════════════
# Schritt 2: wb-close
# ═════════════════════════════════════════════════════════════════════════
echo "-- Schritt 2: wb-close --"
SESS="wb-Betrieb2-close-$$"
tm new-session -d -s "$SESS" -n main -c /tmp -x 197 -y 54
ORCH="$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)"
tm set -p -t "$ORCH" @wb_role orchestrator

# 2a: einzelner Worker
W1="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"
tm set -p -t "$W1" @wb_role worker
tm set -p -t "$W1" @wb_worker w1
lauf "$ORCH" "wb-close w1"
sleep 0.3
tm list-panes -t "$ORCH" -F '#{pane_id}' | grep -qx "$W1" \
  && bad "2a: 'wb-close w1' hat den Worker nicht geschlossen" \
  || ok "2a: 'wb-close w1' hat genau diesen Worker geschlossen"

# 2b: --all-workers, mehrere Worker, Orchestrator bleibt
W2="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"; tm set -p -t "$W2" @wb_role worker; tm set -p -t "$W2" @wb_worker w2
W3="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"; tm set -p -t "$W3" @wb_role worker; tm set -p -t "$W3" @wb_worker w3
lauf "$ORCH" "wb-close --all-workers"
sleep 0.3
uebrig="$(tm list-panes -t "=$SESS" -F '#{@wb_role}' | grep -c '^worker$' | tr -d ' ')"
[ "$uebrig" = 0 ] && ok "2b: --all-workers hat alle Worker geschlossen" \
                   || bad "2b: nach --all-workers laufen noch $uebrig Worker-Panes"
tm list-panes -t "=$SESS" -F '#{pane_id}' | grep -qx "$ORCH" \
  && ok "2b: der Orchestrator-Pane lebt weiter" \
  || bad "2b: der Orchestrator-Pane ist mitgegangen"

# 2c: ein Pane mit "laufender Arbeit" (Dauerschleife statt Leerlauf-Shell) --
# wb-close prueft nicht auf Aktivitaet, es schliesst sofort. Das ist der
# dokumentierte Vertrag ("die ONLY sanctioned way ... to close a pane"), Ziel
# dieses Schritts ist zu zeigen, dass genau das auch wirklich passiert.
WB="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"
tm set -p -t "$WB" @wb_role worker
tm set -p -t "$WB" @wb_worker wbusy
tm send-keys -t "$WB" "i=0; while :; do i=\$((i+1)); done" Enter
sleep 0.5
lauf "$ORCH" "wb-close wbusy"
sleep 0.3
tm list-panes -t "=$SESS" -F '#{pane_id}' | grep -qx "$WB" \
  && bad "2c: ein busy-loop-Worker liess sich NICHT schliessen (haengt weiter)" \
  || ok "2c: ein busy-loop-Worker wird trotz laufender Arbeit sofort geschlossen"

# 2d: was passiert mit dem 'workers'-Fenster, wenn der letzte Worker geht?
lauf "$ORCH" "wb-state settings set workerLayout window"
lauf "$ORCH" "wb-workers-window '$SESS'"
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qx workers \
  && ok "2d: 'workers'-Fenster mit Platzhalter angelegt" || bad "2d: kein 'workers'-Fenster"
WW1="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"; tm set -p -t "$WW1" @wb_role worker; tm set -p -t "$WW1" @wb_worker ww1
WW2="$(tm split-window -d -t "$ORCH" -P -F '#{pane_id}')"; tm set -p -t "$WW2" @wb_role worker; tm set -p -t "$WW2" @wb_worker ww2
lauf "$ORCH" "wb-grid $ORCH"
# GEZAEHLT WIRD UEBER ALLE WORKER-FENSTER (umgestellt 03.09.2026, Stufe A):
# seither bekommt jeder Worker sein eigenes, der zweite liegt also in
# 'workers-2'. Die Zusage bleibt, dass beide in einem Worker-Fenster landen und
# der Platzhalter dabei weicht.
im_fenster="$(tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' | awk -F'|' -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="worker"' | wc -l | tr -d ' ')"
[ "$im_fenster" = 2 ] && ok "2d: beide Worker liegen in eigenen Worker-Fenstern (Platzhalter gewichen)" \
                       || bad "2d: nur $im_fenster von 2 Workern in einem Worker-Fenster"
platzhalter="$(tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' | awk -F'|' -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="placeholder"' | wc -l | tr -d ' ')"
[ "$platzhalter" = 0 ] && ok "2d: kein Platzhalter steht mehr neben einem Worker" \
                        || bad "2d: $platzhalter Platzhalter stehen neben echten Workern"

lauf "$ORCH" "wb-close --all-workers"
sleep 0.3   # kein Hook mehr aktiv (oben abgeschaltet) -- das ist der endgueltige Zustand
if tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qE '^workers(-[0-9]+)?$'; then
  bad "2d: ein Worker-Fenster besteht nach wb-close --all-workers unerwartet weiter"
else
  ok "2d: wb-close selbst legt keinen Platzhalter nach — das 'workers'-Fenster verschwindet mit seinem letzten Pane (tmux-Standardverhalten: ein Fenster ohne Panes existiert nicht. Im echten Betrieb faengt das der 'pane-exited'-Hook durch einen automatischen wb-grid-Lauf ab, wb-close selbst tut es bewusst nicht -- das ist wb-grids Aufgabe, siehe dessen Kopfkommentar)"
fi
lauf "$ORCH" "wb-workers-window '$SESS'"
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qx workers \
  && ok "2d: die Repo-Fassung von wb-workers-window legt das 'workers'-Fenster (mit Platzhalter) zuverlaessig neu an" \
  || bad "2d: selbst ein expliziter wb-workers-window-Aufruf bringt das Fenster nicht zurueck"

echo

# ═════════════════════════════════════════════════════════════════════════
# Schritt 3: wb-revive
# ═════════════════════════════════════════════════════════════════════════
# Fake-'claude' fuer Schritt 3/4: schreibt sein komplettes argv in eine Marke
# und laeuft dann endlos weiter, WENN '--continue' dabei ist (simuliert eine
# fortgesetzte, laufende Session) -- sonst beendet es sich sofort mit Code 9
# (simuliert den urspruenglichen Absturz/Exit). Kein echter 'claude'-Prozess
# noetig, nur das Verhalten, auf das wb-revive/wb-autorevive tatsaechlich
# reagieren: die Zeichenkette 'claude' in @wb_cmd, und ob der Pane danach lebt.
#
# WICHTIG: der Pane bekommt das Fake-'claude' direkt als sein EIGENES
# Kommando (split-window "...claude...", nicht send-keys in eine interaktive
# Shell hinein). #{pane_dead} gehoert zum Kommando, das der Pane SELBST
# ausfuehrt -- laeuft claude nur als Kindprozess EINER interaktiven Shell,
# bleibt die Shell (und damit der Pane) nach dessen Ende einfach am Leben,
# und #{pane_dead} wird nie 1 (erster Testaufbau dieses Laufs, verworfen:
# maskierte 3a/3b/4b-4d hinter einem falschen 'lebt noch'). Aus demselben
# Grund steht 'remain-on-exit on' auf der SESSION, bevor der erste Pane mit
# dem Fake-claude entsteht -- sonst gewinnt das Wettrennen zwischen einem
# sehr schnell endenden Kommando (kein Sleep im Fake-claude) und dem
# nachtraeglichen Setzen der Option manchmal das Kommando, und tmux
# zerlegt den frisch entstandenen Pane wieder, bevor er ueberhaupt geprueft
# werden kann ("can't find pane"). Deshalb startet die Session zuerst mit
# einem harmlosen Leerlauf-Pane, bekommt DANN 'remain-on-exit', und erst
# danach ersetzt 'respawn-pane -k' dessen Kommando durch das Fake-claude --
# nie umgekehrt.
echo "-- Schritt 3: wb-revive --"
RSESS="wb-Betrieb2-revive-$$"
CLAUDE_MARKER="$TESTHOME/claude-argv.log"
: > "$CLAUDE_MARKER"
tm new-session -d -s "$RSESS" -c /tmp -x 100 -y 30
# ':' nach dem Sessionnamen zielt auf deren aktuelles FENSTER -- remain-on-exit
# ist eine FENSTER-Option; 'set-option -t "=<session>"' ohne das ':' sucht ein
# WINDOW namens '=<session>' und scheitert mit "no such window" (gemessen: mit
# der ueberall sonst in diesem Repo blich exakten '='-Verankerung schlaegt der
# Aufruf fehl, ohne '=' waere es ein Praefix-Treffer -- das ':' loest beides).
tm set-option -t "=$RSESS:" remain-on-exit on

# 3a: toter Pane wird neu gestartet UND fortgesetzt (--continue injiziert)
RP="$(tm list-panes -t "=$RSESS" -F '#{pane_id}' | head -1)"
tm set -p -t "$RP" @wb_cmd "claude --model fake-modell"
tm respawn-pane -k -t "$RP" "PATH='$PANE_PATH' claude --model fake-modell"
sleep 1
dead_vorher="$(tm display -p -t "$RP" '#{pane_dead}')"
[ "$dead_vorher" = 1 ] && ok "3a: der simulierte Absturz-Pane ist tot (pane_dead=1)" \
                       || bad "3a: der Pane ist nicht tot (pane_dead=$dead_vorher) -- Testaufbau fehlerhaft"

lauf "$CTRL" "PATH='$PANE_PATH' wb-revive '$RP'"
sleep 1.5
dead_nachher="$(tm display -p -t "$RP" '#{pane_dead}' 2>/dev/null)"
letzte_argv="$(tail -1 "$CLAUDE_MARKER" 2>/dev/null)"
[ "$dead_nachher" = 0 ] && ok "3a: nach wb-revive lebt der Pane wieder (pane_dead=0)" \
                        || bad "3a: der Pane lebt nach wb-revive nicht (pane_dead=$dead_nachher)"
case "$letzte_argv" in
  *--continue*) ok "3a: der neue Lauf traegt '--continue' (fortgesetzt): $letzte_argv" ;;
  *) bad "3a: '--continue' fehlt im neuen Lauf: '$letzte_argv'" ;;
esac
wb_cmd_nachher="$(tm show-options -pqv -t "$RP" @wb_cmd 2>/dev/null)"
[ "$wb_cmd_nachher" = "claude --model fake-modell" ] \
  && ok "3a: @wb_cmd bleibt der SAUBERE Originalbefehl (ohne --continue) fuer den naechsten Revive" \
  || bad "3a: @wb_cmd nach dem Revive ist '$wb_cmd_nachher', erwartet 'claude --model fake-modell'"

# 3b: DER WICHTIGSTE FALL -- ein Pane, dessen Prozess NOCH LEBT, darf nicht
# angefasst werden. Simuliert: eine 'claude'-aehnliche Dauerschleife (bereits
# mit --continue, also der laengst laufende, fortgesetzte Zustand), am Leben,
# bevor wb-revive ueberhaupt aufgerufen wird.
RP2="$(tm split-window -d -t "=$RSESS:" -P -F '#{pane_id}' "PATH='$PANE_PATH' claude --continue --model fake-modell")"
tm set -p -t "$RP2" @wb_cmd "claude --continue --model fake-modell"
sleep 1
dead_vorher2="$(tm display -p -t "$RP2" '#{pane_dead}')"
pid_vorher="$(tm display -p -t "$RP2" '#{pane_pid}')"
argv_zeilen_vorher="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
[ "$dead_vorher2" = 0 ] && ok "3b: der simulierte LEBENDE Claude-Pane laeuft (pane_dead=0) -- Testaufbau korrekt" \
                        || bad "3b: der Pane ist bereits tot -- Testaufbau fehlerhaft (pane_dead=$dead_vorher2)"

lauf "$CTRL" "PATH='$PANE_PATH' wb-revive '$RP2'"
sleep 1.5
pid_nachher="$(tm display -p -t "$RP2" '#{pane_pid}' 2>/dev/null)"
argv_zeilen_nachher="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
if [ "$pid_nachher" = "$pid_vorher" ] && [ "$argv_zeilen_nachher" = "$argv_zeilen_vorher" ]; then
  ok "3b: wb-revive hat den lebenden Pane in Ruhe gelassen (PID unveraendert: $pid_vorher, keine neue ARGV-Zeile)"
else
  bad "3b: wb-revive hat den LEBENDEN Pane angefasst -- PID $pid_vorher -> $pid_nachher, ARGV-Zeilen $argv_zeilen_vorher -> $argv_zeilen_nachher"
  fund "3b (wb-revive gegen einen lebenden Pane)" \
       "ein Pane, dessen Prozess noch laeuft (pane_dead=0), bleibt unangetastet -- Revive ist fuer TOTE Panes da" \
       "wb-revive prueft #{pane_dead} an keiner Stelle. Es liest nur @wb_cmd/#{pane_start_command}, filtert auf die Zeichenkette 'claude' und ruft danach unbedingt 'tmux respawn-pane -k' -- '-k' killt den laufenden Prozess im Pane, egal ob er noch lebt. Ergebnis hier: PID $pid_vorher -> $pid_nachher, die laufende Dauerschleife wurde beendet und durch einen neuen 'claude --continue'-Start ersetzt, obwohl der alte Prozess quicklebendig war." \
       "in einem lebenden Claude-Pane: tmux set -p @wb_cmd 'claude --foo'; wb-revive \$(tmux display -p '#{pane_id}'); Pane-PID davor/danach vergleichen"
fi

# 3c: DIE URSPRUNGSFRAGE DIESES AUFTRAGS -- zwei Zustandsdateien fuer denselben
# Ordner mit verschiedenen Kennungen (tmuxSession + claudeSessionId). Der
# wiederbelebte Befehl muss die Kennung SEINER EIGENEN tmux-Session tragen --
# nicht die der anderen Datei, und nicht raten (`--continue`). Beide
# Kennungen sind erst durch DIESEN Test angelegt und stehen nirgends sonst im
# Testbaum -- ein Treffer beweist also die Zuordnung, kein Zufall.
RSESS3="wb-Betrieb2-revive-resume-$$"
tm new-session -d -s "$RSESS3" -c /tmp -x 100 -y 30
tm set-option -t "=$RSESS3:" remain-on-exit on
RP3="$(tm list-panes -t "=$RSESS3" -F '#{pane_id}' | head -1)"
tm set -p -t "$RP3" @wb_cmd "claude --model fake-modell"
tm respawn-pane -k -t "$RP3" "PATH='$PANE_PATH' claude --model fake-modell"
sleep 1
dead_vorher3c="$(tm display -p -t "$RP3" '#{pane_dead}')"
[ "$dead_vorher3c" = 1 ] && ok "3c: der simulierte Absturz-Pane fuer die Kennungs-Probe ist tot" \
                         || bad "3c: der Pane ist nicht tot -- Testaufbau fehlerhaft (pane_dead=$dead_vorher3c)"

EIGENE_ID="eigene-unterhaltung-$$"
FREMDE_ID="fremde-unterhaltung-$$"
cat > "$TESTHOME/.claude/workbench/sessions/-tmp-fake-eigene.json" <<JSONEOF
{"tmuxSession": "$RSESS3", "claudeSessionId": "$EIGENE_ID", "dir": "/tmp/fake-eigene"}
JSONEOF
cat > "$TESTHOME/.claude/workbench/sessions/-tmp-fake-fremde.json" <<JSONEOF
{"tmuxSession": "wb-Betrieb2-irgendeine-andere-session-$$", "claudeSessionId": "$FREMDE_ID", "dir": "/tmp/fake-fremde"}
JSONEOF

lauf "$CTRL" "PATH='$PANE_PATH' wb-revive '$RP3'"
sleep 1.5
argv_3c="$(tail -1 "$CLAUDE_MARKER" 2>/dev/null)"
case "$argv_3c" in
  *"--resume $EIGENE_ID"*)
    ok "3c: der wiederbelebte Befehl traegt die Kennung SEINER EIGENEN Session ($EIGENE_ID), nicht die der anderen Datei: $argv_3c" ;;
  *"$FREMDE_ID"*)
    bad "3c: der wiederbelebte Befehl traegt die FREMDE Kennung statt der eigenen: $argv_3c"
    fund "3c (Kennungsverwechslung bei mehreren Sessions im selben Ordner)" \
         "wb-revive findet die Zustandsdatei, deren tmuxSession zum Pane passt, und resumt GENAU deren claudeSessionId" \
         "der neue Lauf traegt die fremde Kennung '$FREMDE_ID' statt der eigenen '$EIGENE_ID': $argv_3c" \
         "zwei Zustandsdateien fuer denselben Ordner mit verschiedenem tmuxSession/claudeSessionId anlegen, einen Pane mit passendem Sessionnamen absterben lassen, wb-revive aufrufen, argv pruefen"
    ;;
  *)
    bad "3c: weder die eigene noch die fremde Kennung im neuen Lauf gefunden (vermutlich '--continue' statt '--resume'): $argv_3c"
    fund "3c (Kennungsverwechslung bei mehreren Sessions im selben Ordner)" \
         "wb-revive findet die Zustandsdatei, deren tmuxSession zum Pane passt, und resumt GENAU deren claudeSessionId statt zu raten" \
         "der neue Lauf traegt weder '--resume' noch die erwartete Kennung: $argv_3c" \
         "zwei Zustandsdateien fuer denselben Ordner mit verschiedenem tmuxSession/claudeSessionId anlegen, einen Pane mit passendem Sessionnamen absterben lassen, wb-revive aufrufen, argv pruefen"
    ;;
esac

# 3d: der Rueckfall -- eine Zustandsdatei, deren tmuxSession zum Pane passt,
# aber OHNE claudeSessionId, aendert nichts am Ergebnis: weiter wie bisher
# mit '--continue'. Kein Abbruch, kein Fehler -- der Rueckfall ist gewollt.
RSESS4="wb-Betrieb2-revive-rueckfall-$$"
tm new-session -d -s "$RSESS4" -c /tmp -x 100 -y 30
tm set-option -t "=$RSESS4:" remain-on-exit on
RP4="$(tm list-panes -t "=$RSESS4" -F '#{pane_id}' | head -1)"
tm set -p -t "$RP4" @wb_cmd "claude --model fake-modell"
tm respawn-pane -k -t "$RP4" "PATH='$PANE_PATH' claude --model fake-modell"
sleep 1
cat > "$TESTHOME/.claude/workbench/sessions/-tmp-fake-ohne-id.json" <<JSONEOF
{"tmuxSession": "$RSESS4", "dir": "/tmp/fake-ohne-id"}
JSONEOF
lauf "$CTRL" "PATH='$PANE_PATH' wb-revive '$RP4'"
sleep 1.5
argv_3d="$(tail -1 "$CLAUDE_MARKER" 2>/dev/null)"
case "$argv_3d" in
  *--continue*) ok "3d: passende tmuxSession aber ohne claudeSessionId -- Rueckfall auf '--continue' bleibt erhalten: $argv_3d" ;;
  *)
    bad "3d: der Rueckfall auf '--continue' ist ausgeblieben: $argv_3d"
    fund "3d (Rueckfall ohne claudeSessionId)" \
         "eine Zustandsdatei mit passender tmuxSession aber ohne claudeSessionId aendert nichts -- weiter mit '--continue'" \
         "der neue Lauf traegt kein '--continue': $argv_3d" \
         "eine Zustandsdatei ohne claudeSessionId-Feld anlegen, deren tmuxSession zu einem toten Pane passt, wb-revive aufrufen, argv pruefen"
    ;;
esac

# 3e: die Kennung landet in einer Befehlszeile, die tmux an eine SCHALE gibt.
# Eine Zustandsdatei mit Schalen-Sonderzeichen darin darf deshalb nicht
# durchgereicht werden -- sie faellt auf '--continue' zurueck. Das Kennzeichen
# wird zur Laufzeit gebildet und steht vor dem Lauf nirgends im Baum.
RSESS5="wb-Betrieb2-revive-metazeichen-$$"
GIFT_DATEI="$TESTHOME/.local/state/wb-betrieb2-gift-$$.beleg"
tm new-session -d -s "$RSESS5" -c /tmp -x 100 -y 30
tm set-option -t "=$RSESS5:" remain-on-exit on
RP5="$(tm list-panes -t "=$RSESS5" -F '#{pane_id}' | head -1)"
tm set -p -t "$RP5" @wb_cmd "claude --model fake-modell"
tm respawn-pane -k -t "$RP5" "PATH='$PANE_PATH' claude --model fake-modell"
sleep 1
python3 - "$TESTHOME/.claude/workbench/sessions/-tmp-fake-metazeichen.json" "$RSESS5" "$GIFT_DATEI" <<'PY'
import json, sys
ziel, sess, gift = sys.argv[1], sys.argv[2], sys.argv[3]
# Die Kennung traegt einen Befehl in Rueckwaertsanfuehrung: wird sie ungeprueft
# in die Befehlszeile gesetzt, legt die Schale die Beleg-Datei an.
with open(ziel, 'w') as fh:
    json.dump({'tmuxSession': sess, 'dir': '/tmp/fake-metazeichen',
               'claudeSessionId': f'x`touch {gift}`x'}, fh)
PY
lauf "$CTRL" "PATH='$PANE_PATH' wb-revive '$RP5'"
sleep 1.5
argv_3e="$(tail -1 "$CLAUDE_MARKER" 2>/dev/null)"
if [ -e "$GIFT_DATEI" ]; then
  bad "3e: die Kennung aus der Zustandsdatei wurde von der Schale AUSGEFUEHRT: $argv_3e"
  fund "3e (Schalen-Sonderzeichen in der Kennung)" \
       "eine Kennung mit Sonderzeichen wird verworfen, nicht ausgefuehrt" \
       "die Beleg-Datei $GIFT_DATEI ist entstanden, die Kennung lief also als Befehl" \
       "eine Zustandsdatei mit einer claudeSessionId in Rueckwaertsanfuehrung anlegen, wb-revive aufrufen, auf die Beleg-Datei sehen"
else
  case "$argv_3e" in
    *--continue*) ok "3e: unplausible Kennung verworfen, Rueckfall auf '--continue': $argv_3e" ;;
    *) bad "3e: weder ausgefuehrt noch '--continue' -- unerwartetes Ergebnis: $argv_3e" ;;
  esac
fi

echo

# ═════════════════════════════════════════════════════════════════════════
# Schritt 4: wb-autorevive
# ═════════════════════════════════════════════════════════════════════════
echo "-- Schritt 4: wb-autorevive --"
ARSESS="wb-Betrieb2-autorevive-$$"
tm new-session -d -s "$ARSESS" -c /tmp -x 100 -y 30
tm set-option -t "=$ARSESS:" remain-on-exit on   # siehe Begruendung bei RSESS oben

AUTOLOG="$TESTHOME/.local/state/wb-autorevive.log"

# 4a: ueberwacht nur claude-Panes -- ein toter NICHT-claude-Pane bleibt liegen
NP="$(tm split-window -d -t "=$ARSESS:" -P -F '#{pane_id}' "true")"
tm set -p -t "$NP" @wb_cmd "bash -c true"
sleep 1
lauf "$CTRL" "PATH='$PANE_PATH' HOME='$TESTHOME' wb-autorevive '$NP'"
sleep 0.5
dead="$(tm display -p -t "$NP" '#{pane_dead}' 2>/dev/null)"
[ "$dead" = 1 ] && ok "4a: ein toter Nicht-claude-Pane bleibt unangetastet (pane_dead=1)" \
                 || bad "4a: ein Nicht-claude-Pane wurde trotzdem angefasst (pane_dead=$dead)"
# Seit dem groben *claude*-Substring-Match nicht mehr entscheidet (2026-08-16), reicht
# wb-autorevive diesen Pane (hat @wb_cmd, aber weder claude- noch pi-Kommando, kein
# @wb_role) an wb-revive weiter -- dessen eigene Begruendung, nicht mehr die alte
# "not a claude pane, skip"-Zeile, landet jetzt im Log (kein `exec` mehr, siehe dort).
grep -q "gehoert zu keinem registrierten Harness" "$AUTOLOG" 2>/dev/null \
  && ok "4a: das Log begruendet den Ueberspringer korrekt" || bad "4a: keine Begruendungszeile fuer den Ueberspringer im Log"

# 4b: toter claude-Pane -- wird revived (delegiert an wb-revive)
AP="$(tm split-window -d -t "=$ARSESS:" -P -F '#{pane_id}' "PATH='$PANE_PATH' claude --model autorevive-test")"
tm set -p -t "$AP" @wb_cmd "claude --model autorevive-test"
sleep 1
dead_vorher="$(tm display -p -t "$AP" '#{pane_dead}')"
[ "$dead_vorher" = 1 ] && ok "4b: der simulierte tote claude-Pane steht bereit" || bad "4b: Testaufbau fehlerhaft (pane_dead=$dead_vorher)"
lauf "$CTRL" "PATH='$PANE_PATH' HOME='$TESTHOME' wb-autorevive '$AP'"
sleep 2
dead_nachher="$(tm display -p -t "$AP" '#{pane_dead}' 2>/dev/null)"
[ "$dead_nachher" = 0 ] && ok "4b: wb-autorevive hat den toten claude-Pane wiederbelebt" \
                         || bad "4b: der Pane lebt nach wb-autorevive nicht (pane_dead=$dead_nachher)"
grep -q "reviving" "$AUTOLOG" 2>/dev/null && ok "4b: das Log nennt 'reviving'" || bad "4b: kein 'reviving' im Log"

# 4c: Crash-loop-Drosselung -- zweiter Tod desselben Panes kurz danach wird
# NICHT sofort wieder revived (THROTTLE_S=90s, Zustand liegt in einer Datei,
# kein Warten auf echte 90s noetig -- zwei echte Aufrufe kurz hintereinander
# reichen). Der zweite "Tod" wird ueber respawn-pane simuliert (derselbe
# Pane stirbt ein zweites Mal, ohne --continue, also erneut sofort tot).
tm respawn-pane -k -t "$AP" "PATH='$PANE_PATH' claude --model autorevive-test"
sleep 1
dead_2t="$(tm display -p -t "$AP" '#{pane_dead}')"
if [ "$dead_2t" = 1 ]; then
  argv_vor_drossel="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
  lauf "$CTRL" "PATH='$PANE_PATH' HOME='$TESTHOME' wb-autorevive '$AP'"
  sleep 1
  argv_nach_drossel="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
  dead_nach_drossel="$(tm display -p -t "$AP" '#{pane_dead}' 2>/dev/null)"
  if [ "$dead_nach_drossel" = 1 ] && [ "$argv_nach_drossel" = "$argv_vor_drossel" ]; then
    ok "4c: der zweite Tod desselben Panes < 90s spaeter wird gedrosselt (Pane bleibt tot, kein neuer Lauf)"
  else
    bad "4c: die Drosselung hat NICHT gegriffen (dead=$dead_nach_drossel, argv-Zeilen $argv_vor_drossel -> $argv_nach_drossel)"
  fi
  grep -q "throttled" "$AUTOLOG" 2>/dev/null && ok "4c: das Log nennt 'throttled'" || bad "4c: kein 'throttled' im Log"
else
  bad "4c: der Pane liess sich fuer den zweiten Tod nicht praeparieren (dead=$dead_2t) -- Testaufbau fehlerhaft, Drosselung nicht geprueft"
fi

# 4d: ein LEBENDER Pane bleibt auch ueber wb-autorevive in Ruhe (derselbe
# Beinahe-Unfall-Fall wie 3b, aber ueber den Einstiegspunkt, den der echte
# pane-died-Hook tatsaechlich aufruft).
AP2="$(tm split-window -d -t "=$ARSESS:" -P -F '#{pane_id}' "PATH='$PANE_PATH' claude --continue --model autorevive-live")"
tm set -p -t "$AP2" @wb_cmd "claude --continue --model autorevive-live"
sleep 1
dead_vorher3="$(tm display -p -t "$AP2" '#{pane_dead}')"
pid_vorher3="$(tm display -p -t "$AP2" '#{pane_pid}')"
argv_vorher3="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
[ "$dead_vorher3" = 0 ] && ok "4d: der simulierte lebende Pane laeuft -- Testaufbau korrekt" \
                        || bad "4d: Testaufbau fehlerhaft (pane_dead=$dead_vorher3)"
lauf "$CTRL" "PATH='$PANE_PATH' HOME='$TESTHOME' wb-autorevive '$AP2'"
sleep 1.5
pid_nachher3="$(tm display -p -t "$AP2" '#{pane_pid}' 2>/dev/null)"
argv_nachher3="$(grep -c . "$CLAUDE_MARKER" 2>/dev/null || echo 0)"
if [ "$pid_nachher3" = "$pid_vorher3" ] && [ "$argv_nachher3" = "$argv_vorher3" ]; then
  ok "4d: wb-autorevive hat den lebenden Pane in Ruhe gelassen"
else
  bad "4d: wb-autorevive hat einen LEBENDEN Pane angefasst -- PID $pid_vorher3 -> $pid_nachher3"
  fund "4d (wb-autorevive gegen einen lebenden Pane)" \
       "wb-autorevive wird laut Kopfkommentar nur vom pane-died-Hook aufgerufen, der Pane ist zu diesem Zeitpunkt also immer schon tot -- als zusaetzliche Absicherung sollte ein direkter Aufruf gegen einen lebenden Pane trotzdem folgenlos bleiben" \
       "wb-autorevive hat selbst keine #{pane_dead}-Pruefung (nur @wb_cmd/Drossel/Speicher) und ruft am Ende unbedingt 'exec wb-revive \$pane' -- dieselbe Luecke wie in 3b, nur ueber den anderen Einstiegspunkt erreicht. PID $pid_vorher3 -> $pid_nachher3." \
       "in einem lebenden Claude-Pane: tmux set -p @wb_cmd 'claude --foo'; wb-autorevive \$(tmux display -p '#{pane_id}'); Pane-PID davor/danach vergleichen"
fi

echo

# ═════════════════════════════════════════════════════════════════════════
# Schritt 5: wb-session-close --self ueber einen ECHTEN Tastendruck
# ═════════════════════════════════════════════════════════════════════════
echo "-- Schritt 5: wb-session-close --self --"

# 5a: die Logik direkt (ohne Tastendruck) -- Verweigerung bei laufendem
# Worker, Erfolg mit --with-workers, Anforderung von WB_SESSION_CLOSE_CONFIRM.
DSESS="wb-Betrieb2-direkt-$$"
tm new-session -d -s "$DSESS" -c /tmp -x 100 -y 30
DORCH="$(tm list-panes -t "=$DSESS" -F '#{pane_id}' | head -1)"
tm set -p -t "$DORCH" @wb_role orchestrator
DW="$(tm split-window -d -t "$DORCH" -P -F '#{pane_id}')"
tm set -p -t "$DW" @wb_role worker

lauf "$DORCH" "WB_SESSION_CLOSE_CONFIRM='$DSESS' wb-session-close --self"
[ "$RC" -ne 0 ] && ok "5a: verweigert mit laufendem Worker ohne --with-workers (rc=$RC)" \
                 || bad "5a: hat trotz laufendem Worker geschlossen"
lebt "$DSESS" || bad "5a: die Session ist trotz Verweigerung weg"

lauf "$DORCH" "wb-session-close --self"    # ohne WB_SESSION_CLOSE_CONFIRM
[ "$RC" -ne 0 ] && ok "5a: verweigert ohne WB_SESSION_CLOSE_CONFIRM (rc=$RC)" \
                 || bad "5a: hat auch ohne Bestaetigung geschlossen"

# Fuer den ERFOLGREICHEN Schliessvorgang taugt `lauf` (wartet auf eine
# Fertig-Markierung, geschrieben von genau dem Pane, der gerade geschlossen
# wird) nicht: der Befehl toetet seine EIGENE Session, bevor die Markierung
# geschrieben werden kann -- `lauf` liefe bis zum eigenen Timeout. Stattdessen
# per send-keys schicken und von AUSSEN (Kontroll-Pane) darauf warten, dass
# die Session verschwindet.
tm send-keys -t "$DORCH" "WB_SESSION_CLOSE_CONFIRM='$DSESS' wb-session-close --self --with-workers" Enter
warte_auf_bedingung 15 "5a: '$DSESS' verschwindet nach --with-workers" "! lebt '$DSESS'" \
  && ok "5a: --with-workers erzwingt das Schliessen"

# 5b: der echte Tastendruck. `tmux send-keys` scheidet aus (siehe Kopf) -- ein
# echter Client haengt sich per Pseudo-Terminal an, wie
# test-knopf-tastendruck.py es vormacht. Eigene, minimale Tastenbindung auf
# DIESEM Testserver, die auf die Repo-Kopie ($BIN/wb-session-close) zeigt --
# die installierte ~/.tmux.conf-Bindung ruft fest den absoluten Pfad
# $HOME/.local/bin/wb-session-close auf und wuerde damit NICHT den
# Repo-Stand pruefen, egal was $PATH auf diesem Testserver sagt.
KSESS="wb-Betrieb2-knopf-$$"
tm new-session -d -s "$KSESS" -c /tmp -x 100 -y 30
tm new-session -d -t "$KSESS" -s "$KSESS-view"
tm bind-key K confirm-before -p "Eigene Session '#{?session_group,#{session_group},#{session_name}}' schliessen (inkl. Sicht)? (y/n)" \
  "run-shell 'WB_SESSION_CLOSE_CONFIRM=#{?session_group,#{session_group},#{session_name}} $BIN/wb-session-close --self'"

PYOUT="$TESTHOME/knopf.out"
python3 - "$SOCKET" "$KSESS" "$PYOUT" > "$PYOUT" 2>&1 <<'PYEOF'
import os, pty, signal, subprocess, sys, time
sock, base, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

def tm(*args):
    return subprocess.run(["tmux", "-L", sock, *args], capture_output=True, text=True)

view = base + "-view"
# Ohne brauchbares $TERM bricht `tmux attach` sofort mit "open terminal failed:
# terminal does not support clear" ab -- der Client haengt sich nie an, der
# Tastendruck landet nirgends. Gemessen auf host2: ueber ssh steht TERM auf
# 'dumb', unter systemd/launchd fehlt es ganz; nur weil auf dem Mac von Hand aus
# einem echten Terminal gestartet wurde, war es bisher gesetzt. Der Wert wird
# hier gesetzt statt geerbt, damit der Schritt in jeder Umgebung dasselbe misst.
if os.environ.get("TERM", "") in ("", "dumb", "unknown"):
    os.environ["TERM"] = "xterm-256color"
pid, fd = pty.fork()
if pid == 0:
    os.execvp("tmux", ["tmux", "-L", sock, "attach", "-t", view])
    os._exit(1)

time.sleep(2)
clients = tm("list-clients", "-F", "#{client_session}").stdout.strip()
print("client haengt an:", clients or "(keiner)")

os.write(fd, b"\x02")   # Prefix Ctrl+B
time.sleep(0.7)
os.write(fd, b"K")      # die Testbindung
time.sleep(1.5)
os.write(fd, b"y")      # confirm-before bestaetigen
time.sleep(3)

def sessions():
    r = tm("list-sessions", "-F", "#{session_name}")
    return sorted(s for s in r.stdout.split() if s)

danach = sessions()
print("nachher:", danach)
ok = base not in danach and view not in danach
print("ERGEBNIS:", "OK" if ok else "FEHLGESCHLAGEN")

try:
    os.kill(pid, signal.SIGTERM)
except ProcessLookupError:
    pass
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
try:
    os.close(fd)
except OSError:
    pass

sys.exit(0 if ok else 1)
PYEOF
PYRC=$?
cat "$PYOUT" | sed 's/^/  [knopf] /'
if [ "$PYRC" -eq 0 ]; then
  ok "5b: echter Tastendruck (Prefix Ctrl+B, K, y) schliesst die eigene Session samt Sicht"
else
  bad "5b: der echte Tastendruck hat die Session nicht (vollstaendig) geschlossen"
  fund "5b (wb-session-close --self ueber echten Tastendruck)" \
       "Prefix+Tastenbindung -> confirm-before -> run-shell WB_SESSION_CLOSE_CONFIRM=... wb-session-close --self schliesst Basis UND Sicht" \
       "siehe Ausgabe oben (Zeile 'nachher:')" \
       "shell/tests/betriebslauf2.sh, Schritt 5b (eingebettetes Python, gleiche Pty-Technik wie test-knopf-tastendruck.py)"
fi
lebt "$KSESS" 2>/dev/null && tm kill-session -t "=$KSESS" 2>/dev/null
lebt "$KSESS-view" 2>/dev/null && tm kill-session -t "=$KSESS-view" 2>/dev/null

echo
echo "== Befunde =="
if [ "${#FUNDE[@]}" -eq 0 ]; then
  echo "  keine"
else
  for f in "${FUNDE[@]}"; do printf '%s\n\n' "$f" | sed 's/^/  /'; done
fi

echo "== Ergebnis: $pass ok, $fail FAIL, $skip SKIP, ${#FUNDE[@]} Befund(e) =="
[ "$fail" -eq 0 ]
