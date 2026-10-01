#!/usr/bin/env bash
# Tests fuer wb-session-sweep — die Automatik hinter dem manuellen wb-session-close.
#
# Anlass (2026-08-03): 27 verwaiste tmux-Sessions mit 22 Claude-Prozessen und
# 7,5 GB im Speicher, weil ein geschlossenes VS-Code-Fenster die zugehoerige
# tmux-Session nicht mitbeendet. Dieser Test deckt genau die Bedingungen ab,
# unter denen der Sweep schliessen darf — und, wichtiger, wann er es NICHT tut.
#
# Alles laeuft auf einem EIGENEN Socket (Regel: Tests fassen die Live-Umgebung
# nie an), und JEDER Aufruf des Werkzeugs geschieht aus einem Pane dieses
# Servers — nie aus der Test-Shell selbst, die am Live-Server haengt. Der Sweep
# ruft intern wb-session-close auf; WB_SESSION_CLOSE zeigt beide Werkzeuge auf
# die Repo-Kopien, nicht auf ~/.local/bin, damit der Test ohne Installation
# gruen wird und keine Live-Datei anfasst.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-session-sweep-$$"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SELF/lib-testwerkzeuge.sh"
CLOSE_TOOL="${WB_SESSION_CLOSE:-$SELF/../wb-session-close}"
SWEEP_TOOL="${WB_SESSION_SWEEP:-$SELF/../wb-session-sweep}"
echo "Geprueft: $CLOSE_TOOL, $SWEEP_TOOL"
WORK="$(mktemp -d)"
LOG="$WORK/sweep.log"
ORPHAN_DIR="$WORK/orphans"
mkdir -p "$ORPHAN_DIR"
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

# Kommando in einem Pane des TESTSERVERS ausfuehren, Ausgabe + Rueckgabewert
# einsammeln — analog zu test-session-close.sh. $TMUX zeigt innerhalb des
# Panes auf den Testsocket, die Werkzeuge reden also nur mit dem Testserver.
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

sweep() { # sweep <steuersession> <weitere-args...> -> setzt OUT und RC, haengt Log an $LOG
  local steuer="$1"; shift
  pane_run "$steuer" "WB_SESSION_CLOSE='$CLOSE_TOOL' WB_SESSION_SWEEP_LOG='$LOG' WB_ORPHAN_DIR='$ORPHAN_DIR' '$SWEEP_TOOL' $*"
}

echo "== wb-session-sweep =="
tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp   # von hier aus wird gesteuert, nie selbst Ziel
WIN="$(tm show-options -gv base-index 2>/dev/null || echo 0)"
PANE="$(tm show-window-options -gv pane-base-index 2>/dev/null || echo 0)"

echo "-- alte, unbeaufsichtigte Session wird geschlossen --"
tm new-session -d -s wb-alt -c /tmp
sweep steuer --days 0
case "$OUT" in *"geschlossen: wb-alt"*) ok "wb-alt im Report als geschlossen genannt" ;;
               *) bad "wb-alt fehlt im Report (rc=$RC): $OUT" ;; esac
tm has-session -t '=wb-alt' 2>/dev/null && bad "'wb-alt' lebt noch" || ok "'wb-alt' ist geschlossen"
[ "$RC" = 0 ] && ok "Exit-Code 0 nach erfolgreichem Schluss" || bad "Exit-Code war $RC, erwartet 0"

echo "-- Gruppe mit Client an der -view-Schwester wird NICHT geschlossen --"
tm new-session -d -s wb-angesehen -c /tmp
tm new-session -d -t wb-angesehen -s wb-angesehen-view
# 'steuer' selbst haengt am Testserver an (new-session ohne -d liesse sich hier
# nicht sauber scripten) -- session_attached auf der -view-Schwester simulieren,
# indem ein zweiter Client sie attacht. Das 'waecher'-Pane hat selbst $TMUX auf
# diesen Testserver gesetzt (es ist ja ein Pane davon); tmux verweigert ein
# genestetes attach deshalb mit "sessions should be nested with care" -- also
# erst $TMUX im Zielpane loeschen, dann attachen (gemessen, 2026-08-03).
tm new-session -d -s waecher -c /tmp
tm send-keys -t waecher "unset TMUX; tmux -L $SOCKET attach -t wb-angesehen-view" Enter
sleep 1
sweep steuer --days 0
attached_now="$(tm list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null | awk '$1=="wb-angesehen-view"{print $2}')"
if [ "${attached_now:-0}" -gt 0 ]; then
  case "$OUT" in *"wb-angesehen"*) bad "angehaengte Gruppe trotzdem im Schliess-Report: $OUT" ;;
                 *) ok "angehaengte Gruppe nicht im Schliess-Report" ;; esac
  tm has-session -t '=wb-angesehen' 2>/dev/null && ok "'wb-angesehen' lebt noch (Client haengt an Schwester)" \
                                                 || bad "'wb-angesehen' wurde trotz Client geschlossen"
else
  echo "  (uebersprungen: konnte keinen Client an 'wb-angesehen-view' anhaengen -- Umgebung ohne echtes Terminal)"
fi
tm kill-session -t waecher 2>/dev/null
tm kill-session -t wb-angesehen 2>/dev/null
tm kill-session -t wb-angesehen-view 2>/dev/null

echo "-- Session mit lebendem Worker wird NICHT geschlossen --"
tm new-session -d -s wb-mitworker -c /tmp
PANEID="$(tm list-panes -t wb-mitworker -F '#{pane_id}' | head -1)"
tm set-option -p -t "$PANEID" @wb_role worker
sweep steuer --days 0
case "$OUT" in *"wb-mitworker"*"geschlossen"*) bad "Session mit Worker trotzdem geschlossen: $OUT" ;;
               *) ok "Session mit laufendem Worker nicht im Schliess-Report" ;; esac
tm has-session -t '=wb-mitworker' 2>/dev/null && ok "'wb-mitworker' lebt noch" || bad "'wb-mitworker' wurde trotz Worker geschlossen"
grep -q "grund=laufender-worker" "$LOG" && ok "Log nennt 'laufender-worker' als Grund" || bad "Log nennt den Worker-Grund nicht"

echo "-- umbenannte Gruppen-Basis mit lebendem Worker wird NICHT geschlossen --"
# Anlass (2026-08-16, bugjagd shell/mittel, wb-session-sweep:238): der Gruppen-
# Schluessel ($key = session_group) ist der Name, unter dem die Gruppe einmal
# ENTSTANDEN ist -- er folgt einer spaeteren Umbenennung der Basis-Session NICHT.
# Ueberlebt nur die umbenannte Basis (die '-view'-Schwester ist zu, wie beim
# Schliessen eines Editor-Fensters), zeigt `session_group` weiterhin auf den
# alten Namen, unter dem laengst keine Session mehr laeuft -- eine Abfrage nur
# gegen "=$key" findet dann "can't find window" und haelt einen lebenden Worker
# faelschlich fuer nicht vorhanden.
tm new-session -d -s wb-umbenennbar -c /tmp
tm new-session -d -t wb-umbenennbar -s wb-umbenennbar-view
tm kill-session -t wb-umbenennbar-view
tm rename-session -t wb-umbenennbar wb-nachbenannt
GRUPPE_JETZT="$(tm list-sessions -F '#{session_name} #{session_group}' 2>/dev/null | awk '$1=="wb-nachbenannt"{print $2}')"
[ "$GRUPPE_JETZT" = "wb-umbenennbar" ] \
  && ok "Testaufbau: session_group blieb 'wb-umbenennbar', der Name ist jetzt 'wb-nachbenannt'" \
  || bad "Testaufbau fehlerhaft: session_group='$GRUPPE_JETZT' statt 'wb-umbenennbar' -- tmux-Verhalten unerwartet"
PANEID="$(tm list-panes -t wb-nachbenannt -F '#{pane_id}' | head -1)"
tm set-option -p -t "$PANEID" @wb_role worker
sweep steuer --days 0
case "$OUT" in *"wb-nachbenannt"*"geschlossen"*|*"geschlossen: wb-umbenennbar"*)
  bad "umbenannte Gruppe mit Worker trotzdem geschlossen: $OUT" ;;
*) ok "umbenannte Gruppe mit laufendem Worker nicht im Schliess-Report" ;; esac
# Nicht nur, ob wb-session-close den Versuch am Ende ablehnt (das ist DESSEN
# eigene, zweite Sperre) -- sweep selbst darf den Versuch gar nicht erst
# starten, sonst zaehlt es in seinem eigenen Bericht als Fehler statt als
# korrekt erkannter laufender Worker.
case "$OUT" in *"FEHLER beim Schliessen von wb-umbenennbar"*)
  bad "sweep hat den Schliess-Versuch ueberhaupt erst gestartet: $OUT" ;;
*) ok "sweep hat gar nicht erst versucht zu schliessen" ;; esac
tm has-session -t '=wb-nachbenannt' 2>/dev/null \
  && ok "'wb-nachbenannt' lebt noch (Worker sitzt hinter dem umbenannten Basis-Namen)" \
  || bad "'wb-nachbenannt' wurde trotz laufendem Worker geschlossen"
grep -q "gruppe=wb-umbenennbar.*grund=laufender-worker" "$LOG" \
  && ok "Log nennt 'laufender-worker' fuer GENAU diese (umbenannte) Gruppe" \
  || bad "Log nennt den Worker-Grund fuer die umbenannte Gruppe nicht: $(tail -3 "$LOG")"
tm kill-session -t wb-nachbenannt 2>/dev/null

echo "-- zu junge Session wird NICHT geschlossen --"
tm new-session -d -s wb-frisch -c /tmp
sweep steuer --days 3650
case "$OUT" in *"wb-frisch"*"geschlossen"*) bad "zu junge Session trotzdem geschlossen: $OUT" ;;
               *) ok "zu junge Session nicht im Schliess-Report" ;; esac
tm has-session -t '=wb-frisch' 2>/dev/null && ok "'wb-frisch' lebt noch" || bad "'wb-frisch' wurde trotz Alters-Schwelle geschlossen"
grep -q "grund=zu-jung" "$LOG" && ok "Log nennt 'zu-jung' als Grund" || bad "Log nennt den Alters-Grund nicht"
tm kill-session -t wb-frisch 2>/dev/null

echo "-- eigene Session wird NICHT geschlossen --"
# 'steuer' ist hier die aufrufende (= eigene) Session des Sweep-Prozesses.
sweep steuer --days 0
case "$OUT" in *"steuer"*"geschlossen"*) bad "eigene Session 'steuer' trotzdem geschlossen: $OUT" ;;
               *) ok "eigene Session 'steuer' nicht im Schliess-Report" ;; esac
tm has-session -t '=steuer' 2>/dev/null && ok "'steuer' lebt noch" || bad "'steuer' (eigene Session) wurde geschlossen"

echo "-- --dry-run schliesst nichts --"
tm new-session -d -s wb-trocken -c /tmp
sweep steuer --dry-run --days 0
case "$OUT" in *"wuerde schliessen"*"wb-trocken"*) ok "'wb-trocken' als 'wuerde schliessen' gemeldet" ;;
               *) bad "--dry-run-Meldung fuer 'wb-trocken' fehlt: $OUT" ;; esac
tm has-session -t '=wb-trocken' 2>/dev/null && ok "'wb-trocken' lebt nach --dry-run noch" || bad "--dry-run hat 'wb-trocken' trotzdem geschlossen"
tm kill-session -t wb-trocken 2>/dev/null

echo "-- als verwaist markierte Session braucht die Drei-Tage-Frist nicht --"
# Die Marke legt die Extension beim Schliessen des Fensters ab (2026-08-04). Sie
# beweist, dass hinter der Session kein Fenster mehr steht — auf drei Tage
# Untaetigkeit zu warten waere hier die falsche Frist, denn der Speicher ist
# sofort belegt. Ohne Marke bleibt eine frische Session unangetastet.
tm new-session -d -s wb-ohnemarke -c /tmp
sweep steuer --days 3
tm has-session -t '=wb-ohnemarke' 2>/dev/null \
  && ok "frische Session ohne Marke bleibt bei --days 3 offen" \
  || bad "frische Session ohne Marke wurde geschlossen"
tm kill-session -t wb-ohnemarke 2>/dev/null

tm new-session -d -s wb-markiert -c /tmp
printf '{"session":"wb-markiert","folder":"/tmp/projekt","token":"t","at":%s}\n' \
  "$(( ($(date +%s) - 600) * 1000 ))" > "$ORPHAN_DIR/wb-markiert.json"
sweep steuer --days 3 --orphan-minutes 5
if ! tm has-session -t '=wb-markiert' 2>/dev/null; then
  ok "markierte Session wird trotz --days 3 geschlossen"
else
  bad "markierte Session blieb offen: $OUT"
fi
[ -f "$ORPHAN_DIR/wb-markiert.json" ] \
  && bad "Marke haette nach dem Schliessen entfernt werden muessen" \
  || ok "Marke ist nach dem Schliessen weg"

echo "-- eine noch frische Marke reicht nicht --"
tm new-session -d -s wb-jungemarke -c /tmp
printf '{"session":"wb-jungemarke","folder":"/tmp/projekt","token":"t","at":%s}\n' \
  "$(( $(date +%s) * 1000 ))" > "$ORPHAN_DIR/wb-jungemarke.json"
sweep steuer --days 3 --orphan-minutes 10
tm has-session -t '=wb-jungemarke' 2>/dev/null \
  && ok "Marke unter der Frist schliesst nichts" \
  || bad "zu junge Marke hat trotzdem geschlossen"
tm kill-session -t wb-jungemarke 2>/dev/null
rm -f "$ORPHAN_DIR/wb-jungemarke.json"

echo "-- Exit 0 auch ohne Kandidaten --"
sweep steuer --days 0
[ "$RC" = 0 ] && ok "Exit 0, obwohl nichts mehr zu schliessen war" || bad "Exit-Code war $RC, erwartet 0"

echo
echo "wb-session-sweep: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
