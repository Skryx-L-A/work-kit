#!/usr/bin/env bash
# Tests fuer wb-session-close — insbesondere die Eigen-Erkennung.
#
# Anlass (2026-08-03): Eine laufende Orchestrator-Session hat sich selbst
# geschlossen. Die alte Eigen-Pruefung fragte `tmux display -p '#{session_name}'`;
# haengt das eigene Fenster in einer Sessiongruppe ('<name>' + '<name>-view', wie
# die Workbench sie fuer das VS-Code-Fenster anlegt), antwortet tmux mit der
# SCHWESTER-Session. Der Vergleich ging damit ins Leere, und weil der Client am
# '-view' haengt, meldete die Basis-Session zusaetzlich `session_attached=0`.
#
# Alles laeuft auf einem EIGENEN Socket (Regel: Tests fassen die Live-Umgebung
# nie an), und JEDER Aufruf des Werkzeugs geschieht aus einem Pane dieses
# Servers — nie aus der Test-Shell selbst, die am Live-Server haengt.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-session-close-$$"
# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie: eine Reparatur,
# die nur im Repo steht und nie ausgerollt wurde, MUSS hier rot sein. Der Weg
# ueber die installierte Fassung bleibt moeglich (WB_SESSION_CLOSE), ist aber
# die Ausnahme und wird unten benannt.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
TOOL="${WB_SESSION_CLOSE:-$REPO/wb-session-close}"
WORK="$(mktemp -d)"
pass=0; fail=0
echo "Geprueft: $TOOL"

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  # Ein evtl. noch offener Control-Mode-Client (simulierter "angehaengter Client",
  # siehe Test 8) haengt sonst als verwaister Hintergrundprozess herum, wenn der
  # Test mittendrin abbricht.
  [ -n "${CTRL_PID:-}" ] && kill "$CTRL_PID" 2>/dev/null
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

ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Kommando in einem Pane des TESTSERVERS ausfuehren und Ausgabe + Rueckgabewert
# einsammeln. Innerhalb des Panes zeigt $TMUX auf den Testsocket, das Werkzeug
# redet also mit dem Testserver und nicht mit dem Live-Server.
pane_run() { # pane_run <session> <kommando> -> setzt OUT und RC
  local sess="$1" cmd="$2" f="$WORK/out.$RANDOM"
  tm send-keys -t "$sess:$WIN.$PANE" "{ $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 20 "pane_run: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

echo "== wb-session-close =="
# Nur einen liegengebliebenen Testserver abraeumen — NICHT cleanup aufrufen, das
# loescht auch $WORK, in das die Panes gleich schreiben sollen.
tm kill-server 2>/dev/null
tm new-session -d -s eigen  -c /tmp
tm new-session -d -t eigen  -s eigen-view      # gruppierte Sicht, wie die Extension sie anlegt
tm new-session -d -s fremd  -c /tmp
tm new-session -d -s steuer -c /tmp            # von hier wird "von aussen" geschlossen
WIN="$(tm show-options -gv base-index 2>/dev/null || echo 0)"
PANE="$(tm show-window-options -gv pane-base-index 2>/dev/null || echo 0)"

echo "-- Eigen-Erkennung in einer Sessiongruppe --"
pane_run eigen "$TOOL eigen"
case "$OUT" in *"EIGENE Session"*) ok "'eigen' aus 'eigen' heraus: verweigert" ;;
               *) bad "'eigen' aus 'eigen' heraus nicht als eigen erkannt (rc=$RC): $OUT" ;; esac
tm has-session -t '=eigen' 2>/dev/null && ok "'eigen' lebt noch" || bad "'eigen' wurde geschlossen"

pane_run eigen "$TOOL eigen-view"
case "$OUT" in *"EIGENE Session"*) ok "'eigen-view' aus 'eigen' heraus: verweigert" ;;
               *) bad "gruppierte Schwester 'eigen-view' nicht als eigen erkannt (rc=$RC): $OUT" ;; esac
tm has-session -t '=eigen-view' 2>/dev/null && ok "'eigen-view' lebt noch" || bad "'eigen-view' wurde geschlossen"

# Auch aus der Sicht-Session heraus: dieselbe Gruppe, dieselbe Verweigerung.
pane_run eigen-view "$TOOL eigen"
case "$OUT" in *"EIGENE Session"*) ok "'eigen' aus 'eigen-view' heraus: verweigert" ;;
               *) bad "'eigen' aus der Sicht-Session heraus nicht geschuetzt (rc=$RC): $OUT" ;; esac

echo "-- warum die alte Pruefung versagte (Beleg, nicht Bedingung) --"
pane_run eigen "tmux display -p '#{session_name}'"
case "$OUT" in
  eigen-view) ok "tmux nennt aus 'eigen' heraus '$OUT' — genau diese Falle" ;;
  eigen)      ok "tmux nennt hier 'eigen' (versionsabhaengig; massgeblich sind die Tests darueber)" ;;
  *)          bad "unerwartete Antwort von tmux: '$OUT'" ;;
esac

# --- 2b. Der Weg des Knopfes: tmux startet das Werkzeug SELBST ----------------
# Prefix + S laeuft ueber `run-shell`. Dabei haengt der Prozess unter dem tmux-Server
# statt unter einem Pane, TMUX_PANE ist leer, und die Prozesskette findet nichts —
# der erste Anlauf des Knopfes verweigerte deshalb den Dienst. Seitdem nimmt das
# Werkzeug ersatzweise die Session-ID aus $TMUX. Dieser Fall haelt das fest.
echo "-- Knopfweg (run-shell) --"
tm new-session -d -s knopf -c /tmp
tm new-session -d -t knopf -s knopf-view
tm run-shell "WB_SESSION_CLOSE_CONFIRM=knopf $TOOL --self"
sleep 3
tm has-session -t '=knopf' 2>/dev/null && bad "'knopf' lebt noch — --self ueber run-shell wirkungslos" \
                                       || ok "--self schliesst die Basis-Session auch ueber run-shell"
tm has-session -t '=knopf-view' 2>/dev/null && bad "'knopf-view' lebt noch" \
                                            || ok "die gruppierte Sicht ist mit geschlossen"

# --- 2c. --self trifft nur GEMESSENE eigene Sessions -------------------------
# Befund 2026-08-15 (Bugjagd): WB_SESSION wanderte ungeprueft in die Liste der eigenen
# Sessions, und die Kill-Schleife von --self raeumt jeden Eintrag ausser der Basis ab —
# ohne Client- und ohne Worker-Pruefung. Ein geerbtes WB_SESSION (Worker-Pane, launchd,
# ssh) beendete damit eine FREMDE Session samt laufender Arbeit. Derselbe Fehlertyp wie
# der Selbstabschuss vom 2026-08-03: Eigenheit wird ueber die Prozesskette bewiesen,
# nie ueber einen Namen aus der Umgebung.
echo "-- --self mit geerbtem WB_SESSION: die fremde Session bleibt --"
tm new-session -d -s selbst -c /tmp
tm new-session -d -t selbst -s selbst-view
tm new-session -d -s opfer  -c /tmp
tm set-option -p -t "opfer:$WIN.$PANE" @wb_role worker 2>/dev/null   # laufende Arbeit
tm send-keys -t "selbst:$WIN.$PANE" \
   "WB_SESSION=opfer WB_SESSION_CLOSE_CONFIRM=selbst $TOOL --self > $WORK/self.out 2>&1" Enter
if warte_auf_bedingung 20 "--self schliesst die eigene Basis 'selbst'" \
     '! tmux -L "$SOCKET" has-session -t "=selbst" 2>/dev/null' "$WORK/self.out"; then
  ok "--self schliesst die eigene Basis-Session"
fi
tm has-session -t '=selbst-view' 2>/dev/null && bad "'selbst-view' lebt noch" \
                                             || ok "die eigene Sicht ist mitgeschlossen"
tm has-session -t '=opfer' 2>/dev/null \
  && ok "die fremde Session aus WB_SESSION lebt weiter" \
  || bad "WB_SESSION=opfer hat eine FREMDE Session mit laufendem Worker geschlossen"
tm kill-session -t '=opfer' 2>/dev/null

echo "-- WB_SESSION schuetzt weiterhin: benannt wird sie nicht geschlossen --"
tm new-session -d -s geerbt -c /tmp
pane_run steuer "WB_SESSION=geerbt $TOOL geerbt"
case "$OUT" in *"EIGENE Session"*) ok "WB_SESSION zaehlt weiter als 'nicht anfassen'" ;;
               *) bad "WB_SESSION schuetzt die genannte Session nicht mehr (rc=$RC): $OUT" ;; esac
tm has-session -t '=geerbt' 2>/dev/null && ok "'geerbt' lebt noch" || bad "'geerbt' wurde geschlossen"
tm kill-session -t '=geerbt' 2>/dev/null

echo "-- was weiterhin funktionieren muss --"
pane_run steuer "$TOOL fremd"
[ "$RC" = 0 ] && ok "fremde, unbeaufsichtigte Session laesst sich schliessen" \
              || bad "fremde Session liess sich nicht schliessen (rc=$RC): $OUT"
tm has-session -t '=fremd' 2>/dev/null && bad "'fremd' lebt noch" || ok "'fremd' ist geschlossen"

pane_run steuer "$TOOL gibtesnicht"
[ "$RC" != 0 ] && ok "nicht existierende Session: verweigert" \
               || bad "nicht existierende Session wurde nicht abgelehnt"

# Laufender Worker in der Zielsession -> verweigert.
tm new-session -d -s mitworker -c /tmp
tm set-option -p -t "mitworker:$WIN.$PANE" @wb_role worker 2>/dev/null
pane_run steuer "$TOOL mitworker"
case "$OUT" in *"laufende Worker"*) ok "Session mit laufendem Worker: verweigert" ;;
               *) bad "Worker-Pruefung griff nicht (rc=$RC): $OUT" ;; esac

# --- 5. Fremde Basis mit gruppierter Sicht: beide muessen weg -----------------
# Genau der Befund vom 2026-08-04: `wb-session-close ziel` liess `ziel-view` als
# Waise stehen. Der normale Weg (nicht --self) muss die Sicht jetzt mitschliessen.
echo "-- fremde Basis mit einer Sicht: beide weg --"
tm new-session -d -s ziel -c /tmp
tm new-session -d -t ziel -s ziel-view
pane_run steuer "$TOOL ziel"
[ "$RC" = 0 ] && ok "Basis mit Sicht: rc=0" || bad "Basis mit Sicht schlug fehl (rc=$RC): $OUT"
tm has-session -t '=ziel' 2>/dev/null      && bad "'ziel' lebt noch"      || ok "'ziel' (Basis) ist geschlossen"
tm has-session -t '=ziel-view' 2>/dev/null && bad "'ziel-view' lebt noch — verwaiste Sicht" || ok "'ziel-view' ist mitgeschlossen"

# --- 6. Fremde Basis mit ZWEI Sichten: alle drei weg ---------------------------
echo "-- fremde Basis mit zwei Sichten: alle weg --"
tm new-session -d -s mehr -c /tmp
tm new-session -d -t mehr -s mehr-view
tm new-session -d -t mehr -s mehr-view2
pane_run steuer "$TOOL mehr"
[ "$RC" = 0 ] && ok "Basis mit zwei Sichten: rc=0" || bad "Basis mit zwei Sichten schlug fehl (rc=$RC): $OUT"
tm has-session -t '=mehr'       2>/dev/null && bad "'mehr' lebt noch"       || ok "'mehr' (Basis) ist geschlossen"
tm has-session -t '=mehr-view'  2>/dev/null && bad "'mehr-view' lebt noch"  || ok "'mehr-view' ist mitgeschlossen"
tm has-session -t '=mehr-view2' 2>/dev/null && bad "'mehr-view2' lebt noch" || ok "'mehr-view2' ist mitgeschlossen"

# --- 7. Nur die Sicht allein genannt: Rettung fuer eine bereits verwaiste Sicht -
echo "-- Sicht allein genannt: geht weiterhin, Basis bleibt unberuehrt --"
tm new-session -d -s solo -c /tmp
tm new-session -d -t solo -s solo-view
pane_run steuer "$TOOL solo-view"
[ "$RC" = 0 ] && ok "Sicht allein: rc=0" || bad "Sicht allein schlug fehl (rc=$RC): $OUT"
tm has-session -t '=solo-view' 2>/dev/null && bad "'solo-view' lebt noch" || ok "'solo-view' ist geschlossen"
tm has-session -t '=solo'      2>/dev/null && ok "'solo' (Basis) lebt weiter, unberuehrt" || bad "'solo' (Basis) wurde faelschlich mitgeschlossen"
tm kill-session -t '=solo' 2>/dev/null

# --- 7b. Sichtnamen werden nicht von der Shell umgedeutet ---------------------
# Befund 2026-08-15: `for v in $views` ungequotet. Traegt eine Session ein '*' im
# Namen und liegt im Arbeitsverzeichnis eine passende Datei, expandiert die Shell das
# Muster — gemessen wurde dabei eine FREMDE Session geschlossen und die echte Sicht
# blieb stehen, waehrend die Ausgabe "geschlossen" meldete.
echo "-- Sichtname mit Sonderzeichen: es stirbt genau die Sicht --"
mkdir -p "$WORK/globcwd"
: > "$WORK/globcwd/globX-view"          # Datei, auf die 'glob*-view' passt
tm new-session -d -s 'glob*'      -c "$WORK/globcwd"
tm new-session -d -t 'glob*' -s 'glob*-view'
tm new-session -d -s 'globX-view' -c /tmp   # fremde Session, die den Glob-Treffer traegt
pane_run steuer "cd $WORK/globcwd && $TOOL 'glob*'"
[ "$RC" = 0 ] && ok "Basis mit Sonderzeichen: rc=0" || bad "rc=$RC: $OUT"
tm has-session -t '=glob*-view'  2>/dev/null && bad "'glob*-view' lebt noch — die echte Sicht wurde nicht getroffen" \
                                             || ok "'glob*-view' (die echte Sicht) ist geschlossen"
tm has-session -t '=globX-view'  2>/dev/null && ok "die fremde 'globX-view' lebt weiter" \
                                             || bad "die fremde 'globX-view' wurde durch die Glob-Expansion geschlossen"
tm kill-session -t '=globX-view' 2>/dev/null

# --- 8. Client haengt an der Sicht: Basis+Sicht-Schliessen wird verweigert ----
# group_attached() summiert ueber die ganze Gruppe, ein Client an der Sicht muss
# also auch das Schliessen der BASIS blockieren — beide bleiben stehen.
#
# Ein echter interaktiver Client braucht eine Pty; hier (Testlauf ohne Terminal)
# gibt es keine. tmux zaehlt aber auch einen CONTROL-MODE-Client (`-C`) als
# angehaengt, und der kommt ohne Pty aus — er redet ueber stdin/stdout im
# Kontrollprotokoll. Eine FIFO haelt seine Standardeingabe offen (sonst sieht er
# sofort EOF und beendet sich), ein offener Schreib-Filedeskriptor haelt die FIFO
# ihrerseits offen.
echo "-- Client an der Sicht: verweigert, beide bleiben --"
tm new-session -d -s bewacht -c /tmp
tm new-session -d -t bewacht -s bewacht-view
CTRLFIFO="$WORK/ctrlfifo"
mkfifo "$CTRLFIFO"
tmux -L "$SOCKET" -C attach-session -t bewacht-view < "$CTRLFIFO" > "$WORK/ctrl.out" 2>&1 &
CTRL_PID=$!
exec 8>"$CTRLFIFO"
sleep 1
pane_run steuer "$TOOL bewacht"
case "$OUT" in *"haengt ein Client"*) ok "Client an der Sicht blockiert das Basis-Schliessen" ;;
               *) bad "Client-Pruefung griff nicht ueber die Sicht (rc=$RC): $OUT" ;; esac
tm has-session -t '=bewacht'      2>/dev/null && ok "'bewacht' (Basis) lebt weiter"      || bad "'bewacht' (Basis) wurde trotz Client geschlossen"
tm has-session -t '=bewacht-view' 2>/dev/null && ok "'bewacht-view' lebt weiter"          || bad "'bewacht-view' wurde trotz Client geschlossen"
exec 8>&-
kill "$CTRL_PID" 2>/dev/null
CTRL_PID=""
tm kill-session -t '=bewacht-view' 2>/dev/null
tm kill-session -t '=bewacht' 2>/dev/null

# --- 9. Worker laeuft in der Basis: Basis+Sicht-Schliessen wird verweigert ----
echo "-- Worker in der Basis: verweigert, beide bleiben --"
tm new-session -d -s arbeit -c /tmp
tm new-session -d -t arbeit -s arbeit-view
tm set-option -p -t "arbeit:$WIN.$PANE" @wb_role worker 2>/dev/null
pane_run steuer "$TOOL arbeit"
case "$OUT" in *"laufende Worker"*) ok "Worker in der Basis blockiert das Schliessen mit Sicht" ;;
               *) bad "Worker-Pruefung griff nicht bei Basis+Sicht (rc=$RC): $OUT" ;; esac
tm has-session -t '=arbeit'      2>/dev/null && ok "'arbeit' (Basis) lebt weiter"      || bad "'arbeit' (Basis) wurde trotz Worker geschlossen"
tm has-session -t '=arbeit-view' 2>/dev/null && ok "'arbeit-view' lebt weiter"          || bad "'arbeit-view' wurde trotz Worker geschlossen"

echo
echo "wb-session-close: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
