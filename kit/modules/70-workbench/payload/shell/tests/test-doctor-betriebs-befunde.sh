#!/bin/bash
# Test fuer die sechs wb-doctor-Befunde aus dem Betriebslauf vom 2026-08-04
# (~/.pi-workers/results/betriebslauf/latest.md): B3/B7 (--fix meldet
# Reparaturen, die keine sind), B4 (--fix fasst fremde tmux-Sessions an),
# B5 (Punkt 4 verlangt unter workerLayout=split eine Sicht, die die Extension
# bewusst schliesst), B6/B8 (das Ueberlauf-Fenster 'workers-2' ist Punkt 4/6
# unbekannt), B9 (die Schlusszeile zaehlt Punkt 5/6 nicht mit).
#
# Eigener tmux-Socket, eigenes HOME (mktemp -d), trap raeumt auf. wb-grid wird
# hier durch einen STUB ersetzt statt den echten (symlinkten) Aufruf zu nutzen:
# an shell/wb-grid arbeitet parallel ein anderer Worker (B2, TABU fuer diese
# Datei), und dieser Test soll die HONESTITAET von wb-doctors --fix pruefen,
# nicht wb-grids tatsaechliches Verhalten. Der Stub tut genau das, was B2
# beschreibt: er endet mit 0, ohne irgendetwas zu bewegen -- exakt der Fall,
# den wb-doctor jetzt nicht mehr als Erfolg verkaufen darf.
#
# Auftrag falschrot (2026-08-09): der woechentliche Gesamtlauf meldete diese
# Suite wiederholt rot, obwohl sie einzeln (auch dreimal nachgestellt in
# einer launchd-Umgebung) 19/19 gruen lief. Ursache war run_doctor()/
# workers_window() unten: die Deadline lief unter Last ab, die Schleife
# brach STILL ab, und OUT enthielt den halbfertigen oder leeren Inhalt --
# die folgenden Zusagen verglichen dagegen und meldeten einen inhaltlichen
# Fehler, wo tatsaechlich nur die Zeit ausging. Fix: warte_auf_datei()
# (lib-testwerkzeuge.sh) meldet ein abgelaufenes Zeitlimit jetzt SELBST, als
# eigenen ZEITLIMIT-Fehlschlag mit Wartezeit und letzter Ausgabe -- der
# Beleg dafuer steht als eigener Pruefblock am Dateiende.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-doctor-bef-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib-testwerkzeuge.sh"
TOOL="${WB_DOCTOR:-$REPO_ROOT/shell/wb-doctor}"
STATE_BIN="$HOME/.local/bin/wb-state"
WORK="$(mktemp -d)"
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

# Geschwister-Werkzeuge einzeln verlinken (nicht das ganze Verzeichnis, siehe
# oben) -- wb-grid bekommt einen Stub statt eines Symlinks.
mkdir -p "$WORK/.local/bin"
for t in wb-state wb-workers-window wb-session-close; do
  ln -s "$HOME/.local/bin/$t" "$WORK/.local/bin/$t"
done
# wb-rolle kommt aus dem REPO und nicht aus ~/.local/bin: Pruefung 13 (unten)
# prueft die Fassung, an der gerade gearbeitet wird. Das Register liegt unter
# $HOME und ist damit schon isoliert; die Bibliothek dazu muss aber im Test-HOME
# liegen, sonst findet wb-rolle sie nicht und setzt grundsaetzlich nichts.
ln -s "$REPO_ROOT/shell/wb-rolle" "$WORK/.local/bin/wb-rolle"
mkdir -p "$WORK/.claude/hooks/lib"
cp "$REPO_ROOT/hooks/lib/rollen.py" "$WORK/.claude/hooks/lib/rollen.py"
cat > "$WORK/.local/bin/wb-grid" <<'STUB'
#!/bin/bash
# Stub fuer diesen Test: endet mit 0, bewegt nichts -- simuliert B2 (echtes
# wb-grid, TABU-Datei fuer diesen Worker) kontrolliert und ohne Abhaengigkeit
# von dessen aktuellem, gerade in Arbeit befindlichem Zustand.
exit 0
STUB
chmod +x "$WORK/.local/bin/wb-grid"

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp

# ~/.tmux.conf ist keine Isolationsgrenze -- ein neuer Server auf einem eigenen
# `-L`-Socket laedt sie trotzdem, und drei GLOBALE Hooks darin riefen bis hierher
# die ECHTEN Werkzeuge der lebenden Maschine auf (after-split-window/pane-exited
# das echte wb-grid, pane-died das echte wb-autorevive) -- unabhaengig vom
# Socket. Genau das hat B3/B7 unten sporadisch rot gemacht: der Stub in
# $WORK/.local/bin/wb-grid faengt nur wb-doctors EIGENEN Aufruf ab, der Hook lief
# daran vorbei. Ursache, Reproduktion und Kontrollexperiment stehen an
# tmux_live_hooks_kappen() in lib-testwerkzeuge.sh (Auftrag dienstprobe,
# 2026-08-20) -- seit dem Fund gemeinsamer Baustein statt Kopie je Testdatei.
tmux_live_hooks_kappen "$SOCKET"

# 20s war unter Last zu knapp (Nachtlauf 09.08., siehe Dateikopf). Direktmessung
# auf diesem Rechner (36 eigene Busy-Loops auf 18 Kernen) zeigte keine messbare
# Verzoegerung -- die tatsaechliche Nachtlast liess sich synthetisch nicht
# nachstellen, deshalb ist 45s ein grosszuegiger Puffer statt einer exakt
# gemessenen Zahl (siehe Ergebnis-Datei dieses Auftrags).
DOCTOR_DEADLINE=45

run_doctor() { # run_doctor [--fix] [deadline-sekunden] -> setzt OUT
  local extra="${1:-}" deadline_sek="${2:-$DOCTOR_DEADLINE}" f="$WORK/out.$RANDOM"
  tm send-keys -t steuer "HOME='$WORK' '$TOOL' $extra > '$f' 2>&1; touch '$f.done'" Enter
  warte_auf_datei "$f.done" "$deadline_sek" "wb-doctor $extra" "$f"
  OUT="$(cat "$f" 2>/dev/null)"
  rm -f "$f" "$f.done"
}

attach_watcher() { # attach_watcher <watcher-session> <ziel-session>
  tm new-session -d -s "$1" -c /tmp
  tm send-keys -t "$1" "unset TMUX; tmux -L $SOCKET attach -t '$2'" Enter
}

wait_attached() { # wait_attached <session> -> Rueckgabewert 0, wenn attached>0
  local target="$1" deadline=$((SECONDS+10)) n
  while [ $SECONDS -lt $deadline ]; do
    n="$(tm list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
         | awk -v s="$target" '$1==s{print $2+0}')"
    [ "${n:-0}" -gt 0 ] && return 0
    sleep 0.3
  done
  return 1
}

# wb-workers-window aus dem Testsocket heraus aufrufen (dasselbe Pane-Muster
# wie run_doctor), damit es auf den Testserver zeigt statt auf den Live-Server.
workers_window() { # workers_window <session> [fenstername]
  local extra="${2:-}" f="$WORK/ww.$RANDOM"
  tm send-keys -t steuer "HOME='$WORK' '$HOME/.local/bin/wb-workers-window' '$1' $extra > '$f' 2>&1; touch '$f.done'" Enter
  warte_auf_datei "$f.done" 30 "wb-workers-window $1 $extra" "$f"
  rm -f "$f" "$f.done"
}

HOME="$WORK" "$STATE_BIN" settings set workerLayout window >/dev/null

echo "== wb-doctor: Betriebslauf-Befunde 2026-08-04 =="

# ---------------------------------------------------------------------------
# B4 -- --fix fasst fremde, nicht-wb-*-Sessions nicht an
# ---------------------------------------------------------------------------
echo "-- B4: fremde Session bleibt nach --fix unveraendert --"
tm new-session -d -s beliebig -c /tmp
# automatic-rename (tmux-Default: an) benennt das Fenster um, sobald die
# Schale im neuen Pane durchstartet -- ein Wettlauf zwischen diesem Hochlauf
# und der Momentaufnahme direkt nach new-session. Ohne Last ist die Schale
# meist schon da, wenn list-windows greift (Fenstername zeigt 'zsh'); unter
# Last kann new-session zurueckkommen, bevor der Fork/Exec durch ist, dann
# steht hier noch 'tmux' -- und die zweite Momentaufnahme (nach run_doctor,
# mehrere Sekunden spaeter) faengt die Umbenennung ein. Das haette nichts
# mit wb-doctor zu tun und faellt trotzdem als Befund auf: reproduziert unter
# fuenffacher Parallellast, 1 von 30 Laeufen (par-r2-p3.log). Fester Name
# schaltet den Wettlauf ab, ohne die eigentliche Pruefung (aendert --fix
# etwas an einer fremden Session?) zu veraendern.
tm set-option -w -t '=beliebig' automatic-rename off
tm rename-window -t '=beliebig' fremde-schale
vorher_fenster="$(tm list-windows -t '=beliebig' -F '#{window_name}' 2>/dev/null | sort | tr '\n' ' ')"
run_doctor "--fix"
nachher_fenster="$(tm list-windows -t '=beliebig' -F '#{window_name}' 2>/dev/null | sort | tr '\n' ' ')"
[ "$vorher_fenster" = "$nachher_fenster" ] \
  && ok "'beliebig' hat nach --fix dieselben Fenster wie vorher ($nachher_fenster)" \
  || bad "'beliebig' wurde umgebaut: vorher='$vorher_fenster' nachher='$nachher_fenster'"
tm list-windows -t '=beliebig' -F '#{window_name}' 2>/dev/null | grep -qx workers \
  && bad "'beliebig' hat ein 'workers'-Fenster bekommen" \
  || ok "kein 'workers'-Fenster bei 'beliebig'"
tm has-session -t '=beliebig-view' 2>/dev/null \
  && bad "'beliebig-view' wurde angelegt" \
  || ok "keine gruppierte Sicht 'beliebig-view' angelegt"
# 'beliebig' darf in der informativen Sessions-Uebersicht am Kopf der Ausgabe
# stehen (die zeigt jede laufende Session) -- gepruefte wird nur, dass keine
# der PRUEFUNGEN (BEFUND/REPARIERT/hinweis) sie erwaehnt.
printf '%s\n' "$OUT" | grep -E '^  (BEFUND|REPARIERT|hinweis)' | grep -qF "beliebig" \
  && bad "'beliebig' taucht in einer Pruefzeile auf: $(printf '%s\n' "$OUT" | grep -E '^  (BEFUND|REPARIERT|hinweis)' | grep -F beliebig)" \
  || ok "'beliebig' kommt in keiner Pruefzeile vor (nur in der informativen Sessions-Uebersicht)"

# ---------------------------------------------------------------------------
# B9 -- die Schlusszeile zaehlt Punkt 6 mit (Pipeline-Subshell-Bug)
# ---------------------------------------------------------------------------
echo "-- B9: Schlusszeile zaehlt einen reinen Punkt-6-Befund mit --"
tm new-session -d -s wb-B9 -c /tmp
workers_window wb-B9
attach_watcher watch-b9-base wb-B9
attach_watcher watch-b9-view wb-B9-view
base_ok=0; wait_attached wb-B9 && base_ok=1
view_ok=0; wait_attached wb-B9-view && view_ok=1
if [ "$base_ok" -eq 1 ] && [ "$view_ok" -eq 1 ]; then
  # Ein Worker-Pane im FALSCHEN Fenster (Orchestrator-Fenster statt 'workers')
  # anlegen -- das ist ausschliesslich ein Punkt-6-Befund, wenn sonst alles in
  # Ordnung ist (workers-Fenster+Sicht vorhanden, beide Tabs angehaengt, alle
  # anderen Panes eine Rolle haben).
  base_win="$(tm list-windows -t '=wb-B9' -F '#{window_index} #{window_name}' 2>/dev/null | awk '$2!="workers"{print $1; exit}')"
  tm split-window -t "=wb-B9:$base_win" -c /tmp
  fehl_pane="$(tm list-panes -t "=wb-B9:$base_win" -F '#{pane_id}' 2>/dev/null | tail -1)"
  tm set -p -t "$fehl_pane" @wb_role worker 2>/dev/null

  run_doctor ""   # Trockenlauf
  gedruckt="$(printf '%s\n' "$OUT" | grep -c '^  BEFUND')"
  gezaehlt="$(printf '%s\n' "$OUT" | sed -n 's/^wb-doctor: \([0-9][0-9]*\) Befunde\..*/\1/p')"
  keine_befunde="$(printf '%s\n' "$OUT" | grep -c '^wb-doctor: keine Befunde\.$')"
  [ "$gedruckt" -gt 0 ] \
    && ok "der Punkt-6-Befund wurde gedruckt ($gedruckt BEFUND-Zeile(n))" \
    || bad "kein BEFUND gedruckt -- Testaufbau selbst fehlerhaft: $OUT"
  [ "$keine_befunde" -eq 0 ] \
    && ok "die Schlusszeile behauptet NICHT 'keine Befunde' trotz gedruckter Befunde" \
    || bad "die Schlusszeile sagt 'keine Befunde', obwohl $gedruckt BEFUND-Zeile(n) gedruckt wurden -- B9 lebt noch"
  if [ -n "$gezaehlt" ]; then
    [ "$gezaehlt" -eq "$gedruckt" ] \
      && ok "Schlusszeile zaehlt $gezaehlt, gedruckt wurden $gedruckt -- stimmt ueberein" \
      || bad "Schlusszeile zaehlt $gezaehlt, gedruckt wurden $gedruckt -- B9 lebt noch"
  else
    bad "konnte die Zahl aus der Schlusszeile nicht lesen: $OUT"
  fi
else
  echo "  skip  konnte keinen Client an 'wb-B9'/'wb-B9-view' anhaengen -- Umgebung ohne echtes Terminal"
fi

# ---------------------------------------------------------------------------
# B10 -- Punkt 9: dieselbe Unterhaltung in zwei Zustandsdateien
# Seit dem 05.08. nimmt wb-revive die claudeSessionId DIESER Session. Steht
# dieselbe Kennung in zwei Dateien, laufen zwei Wiederbelebungen auf derselben
# Unterhaltung -- der Doktor soll das benennen. Die Kennung wird zur Laufzeit
# gebildet und steht vor dem Lauf nirgends im Baum.
# ---------------------------------------------------------------------------
echo "-- B10: Punkt 9 findet eine doppelt vergebene Unterhaltung --"
DOPPEL_ID="unterhaltung-doppelt-$$-$RANDOM"
mkdir -p "$WORK/.claude/workbench/sessions"
cat > "$WORK/.claude/workbench/sessions/-tmp-b10-eins.json" <<JSON
{"dir": "/tmp/b10", "tmuxSession": "wb-b10-eins", "claudeSessionId": "$DOPPEL_ID"}
JSON
cat > "$WORK/.claude/workbench/sessions/-tmp-b10-zwei.json" <<JSON
{"dir": "/tmp/b10", "tmuxSession": "wb-b10-zwei", "claudeSessionId": "$DOPPEL_ID"}
JSON
# Eine dritte Datei mit EIGENER Kennung darf NICHT gemeldet werden -- sonst
# meldete der Punkt jede Session statt nur die doppelten.
cat > "$WORK/.claude/workbench/sessions/-tmp-b10-drei.json" <<JSON
{"dir": "/tmp/b10", "tmuxSession": "wb-b10-drei", "claudeSessionId": "einzeln-$$-$RANDOM"}
JSON
run_doctor ""
printf '%s\n' "$OUT" | grep -q "Unterhaltung $DOPPEL_ID steht in mehreren Zustandsdateien" \
  && ok "Punkt 9 benennt die doppelt vergebene Unterhaltung" \
  || bad "Punkt 9 hat die doppelt vergebene Unterhaltung nicht gemeldet: $OUT"
printf '%s\n' "$OUT" | grep -q 'einzeln-' \
  && bad "Punkt 9 meldet auch eine Unterhaltung, die nur EINMAL vorkommt" \
  || ok "eine einmal vergebene Unterhaltung wird nicht gemeldet"
punkt9_befunde="$(printf '%s\n' "$OUT" | sed -n 's/^wb-doctor: \([0-9][0-9]*\) Befunde\..*/\1/p')"
if [ -n "$punkt9_befunde" ] && [ "$punkt9_befunde" -gt 0 ]; then
  ok "die Schlusszeile zaehlt den Punkt-9-Befund mit ($punkt9_befunde)"
else
  bad "die Schlusszeile zaehlt den Punkt-9-Befund nicht mit -- Unterschalen-Falle wie B9: $OUT"
fi
rm -f "$WORK/.claude/workbench/sessions/-tmp-b10-"*.json

# ---------------------------------------------------------------------------
# B3/B7 -- --fix meldet nur dann REPARIERT, wenn wb-grid tatsaechlich etwas
# bewegt hat (hier: der Stub bewegt NIE etwas, wie B2 es beobachtet hat)
# ---------------------------------------------------------------------------
echo "-- B3/B7: --fix glaubt wb-grids Rueckgabewert nicht --"
tm new-session -d -s wb-B37 -c /tmp
workers_window wb-B37
attach_watcher watch-b37-base wb-B37
attach_watcher watch-b37-view wb-B37-view
base_ok=0; wait_attached wb-B37 && base_ok=1
view_ok=0; wait_attached wb-B37-view && view_ok=1
if [ "$base_ok" -eq 1 ] && [ "$view_ok" -eq 1 ]; then
  base_win="$(tm list-windows -t '=wb-B37' -F '#{window_index} #{window_name}' 2>/dev/null | awk '$2!="workers"{print $1; exit}')"
  tm split-window -t "=wb-B37:$base_win" -c /tmp
  fehl_pane="$(tm list-panes -t "=wb-B37:$base_win" -F '#{pane_id}' 2>/dev/null | tail -1)"
  tm set -p -t "$fehl_pane" @wb_role worker 2>/dev/null

  run_doctor "--fix"
  printf '%s\n' "$OUT" | grep -qF "$fehl_pane (wb-B37) ist ein Worker im Fenster" \
    && ok "--fix meldet den Befund (der Stub bewegt den Pane nicht)" \
    || bad "kein Befund fuer den falsch platzierten Worker: $OUT"
  printf '%s\n' "$OUT" | grep -F "REPARIERT" | grep -qF "wb-B37 neu geordnet" \
    && bad "--fix behauptet REPARIERT fuer wb-B37, obwohl der Stub nichts bewegt hat" \
    || ok "--fix behauptet KEIN REPARIERT fuer wb-B37 (ehrlich: nichts hat sich bewegt)"
  aktuelles_fenster="$(tm display -p -t "$fehl_pane" '#{window_name}' 2>/dev/null)"
  [ "$aktuelles_fenster" != workers ] \
    && ok "der Pane liegt tatsaechlich immer noch nicht im workers-Fenster ('$aktuelles_fenster')" \
    || bad "der Pane liegt jetzt doch im workers-Fenster -- Testaufbau widerspricht sich selbst"
  # Zweiter Lauf ohne --fix: derselbe Befund kommt unveraendert wieder.
  run_doctor ""
  printf '%s\n' "$OUT" | grep -qF "$fehl_pane (wb-B37) ist ein Worker im Fenster" \
    && ok "der Befund kommt beim naechsten Lauf unveraendert wieder" \
    || bad "der Befund ist verschwunden, obwohl nichts repariert wurde: $OUT"
else
  echo "  skip  konnte keinen Client an 'wb-B37'/'wb-B37-view' anhaengen -- Umgebung ohne echtes Terminal"
fi

# ---------------------------------------------------------------------------
# B5 -- workerLayout=split: Punkt 4 verlangt keine Sicht mehr
# ---------------------------------------------------------------------------
echo "-- B5: workerLayout=split verlangt keine Sicht --"
HOME="$WORK" "$STATE_BIN" settings set workerLayout split >/dev/null
tm new-session -d -s wb-B5 -c /tmp
workers_window wb-B5
tm kill-session -t '=wb-B5-view' 2>/dev/null   # killViewSession-Aequivalent

run_doctor ""   # Trockenlauf, layout=split
printf '%s\n' "$OUT" | grep -qF "'wb-B5' hat keine Sicht" \
  && bad "Punkt 4 verlangt trotz workerLayout=split eine Sicht" \
  || ok "Punkt 4 verlangt bei workerLayout=split keine Sicht"

run_doctor "--fix"
tm has-session -t '=wb-B5-view' 2>/dev/null \
  && bad "--fix hat unter workerLayout=split trotzdem eine Sicht angelegt" \
  || ok "--fix legt unter workerLayout=split keine Sicht an"

HOME="$WORK" "$STATE_BIN" settings set workerLayout window >/dev/null

# ---------------------------------------------------------------------------
# B6/B8 -- das Ueberlauf-Fenster 'workers-2' ist gueltig
# ---------------------------------------------------------------------------
echo "-- B6/B8: 'workers-2' ist kein Strukturfehler --"
tm new-session -d -s wb-B68 -c /tmp
workers_window wb-B68
attach_watcher watch-b68-base wb-B68
attach_watcher watch-b68-view wb-B68-view
base_ok=0; wait_attached wb-B68 && base_ok=1
view_ok=0; wait_attached wb-B68-view && view_ok=1
if [ "$base_ok" -eq 1 ] && [ "$view_ok" -eq 1 ]; then
  tm new-window -t '=wb-B68:' -n workers-2 -c /tmp
  ueberlauf_pane="$(tm list-panes -t '=wb-B68:workers-2' -F '#{pane_id}' 2>/dev/null | tail -1)"
  tm set -p -t "$ueberlauf_pane" @wb_role worker 2>/dev/null
  # Sicht auf den Ueberlauf-Tab zeigen, wie 'wb-worker-tab --window workers-2'
  # es taete (B8: genau dieser Zustand wurde bisher zurueckgestellt).
  tm select-window -t '=wb-B68-view:workers-2' 2>/dev/null

  run_doctor ""   # Trockenlauf
  printf '%s\n' "$OUT" | grep -qF "ist ein Worker im Fenster 'workers-2'" \
    && bad "Punkt 6 meldet den Worker im Ueberlauf-Fenster als falsch platziert" \
    || ok "Punkt 6 schweigt zum Worker in 'workers-2'"
  printf '%s\n' "$OUT" | grep -qF "steht auf 'workers-2' statt auf" \
    && bad "Punkt 4 meldet die Sicht auf 'workers-2' als falsch" \
    || ok "Punkt 4 schweigt zur Sicht auf 'workers-2'"

  run_doctor "--fix"
  aktiv_nach_fix="$(tm list-windows -t '=wb-B68-view' -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1}')"
  [ "$aktiv_nach_fix" = "workers-2" ] \
    && ok "--fix laesst die Sicht auf 'workers-2' stehen (der Tab springt nicht weg)" \
    || bad "--fix hat die Sicht auf '$aktiv_nach_fix' umgestellt, sollte 'workers-2' bleiben"
else
  echo "  skip  konnte keinen Client an 'wb-B68'/'wb-B68-view' anhaengen -- Umgebung ohne echtes Terminal"
fi

# ---------------------------------------------------------------------------
# Pruefung 13 (2026-09-05) -- 'placeholder' auf einem Pane, in dem gearbeitet wird
#
# Der gemessene Zustand aus der Companion-Sitzung, nachgestellt: das erste Pane
# des ersten Fensters traegt 'placeholder', darin laeuft aber ein Prozess, der
# keine Schale ist. Genau daran ist der Umschalter der Werkbank haengen
# geblieben, und Pruefung 5 hat es nicht gesehen -- sie sucht Panes OHNE Rolle.
# Die Gegenprobe steht daneben: ein ECHTER Platzhalter bleibt unangetastet.
# ---------------------------------------------------------------------------
echo "-- 13: Platzhalter-Rolle auf einem arbeitenden Pane --"
tm new-session -d -s wb-P13 -c /tmp 'exec cat'
p13_orch="$(tm list-panes -t '=wb-P13' -F '#{pane_id}' 2>/dev/null | head -1)"
tm set -p -t "$p13_orch" @wb_role placeholder
# Der echte Platzhalter zum Vergleich: eigenes Fenster, Rolle placeholder,
# und darin nichts als eine schlafende Schale -- so legt wb-workers-window ihn an.
tm new-window -d -t '=wb-P13:' -n workers -c /tmp 'exec sleep 3600'
p13_echt="$(tm list-panes -t '=wb-P13:workers' -F '#{pane_id}' 2>/dev/null | head -1)"
tm set -p -t "$p13_echt" @wb_role placeholder

run_doctor ""   # Trockenlauf
printf '%s\n' "$OUT" | grep -qF "$p13_orch traegt die Rolle 'placeholder'" \
  && ok "Punkt 13 meldet das arbeitende Pane mit Platzhalter-Rolle" \
  || bad "Punkt 13 hat $p13_orch nicht gemeldet -- Ausgabe: $(printf '%s\n' "$OUT" | sed -n '/== 13/,$p')"
printf '%s\n' "$OUT" | grep -qF "$p13_echt traegt die Rolle 'placeholder'" \
  && bad "Punkt 13 meldet auch den echten Platzhalter $p13_echt" \
  || ok "Punkt 13 schweigt zum echten Platzhalter"

run_doctor "--fix"
p13_rolle="$(tm display -p -t "$p13_orch" '#{@wb_role}' 2>/dev/null)"
[ "$p13_rolle" = orchestrator ] \
  && ok "--fix hat $p13_orch auf 'orchestrator' berichtigt" \
  || bad "--fix liess $p13_orch auf '$p13_rolle' stehen"
p13_echt_rolle="$(tm display -p -t "$p13_echt" '#{@wb_role}' 2>/dev/null)"
[ "$p13_echt_rolle" = placeholder ] \
  && ok "--fix laesst den echten Platzhalter auf 'placeholder'" \
  || bad "--fix hat den echten Platzhalter auf '$p13_echt_rolle' gesetzt"

# ---------------------------------------------------------------------------
# Beleg (Auftrag falschrot, Auflage 4): eine kuenstlich ueberschrittene
# Deadline wird als ZEITLIMIT gemeldet, nicht als inhaltlicher Fehler.
# deadline_sek=0 heisst: warte_auf_datei prueft "$f.done" genau einmal --
# das kann unmittelbar nach send-keys nicht schon existieren, die Deadline
# ist also GARANTIERT abgelaufen, ganz ohne synthetische Last. Der Aufruf
# laeuft in einer Subshell mit eigenem pass/fail/ok/bad, damit der erwartete
# interne Fehlschlag nicht in die Zaehlung dieser Suite durchschlaegt --
# geprueft wird NUR der Wortlaut, den er erzeugt.
# ---------------------------------------------------------------------------
echo "-- Beleg: eine kuenstlich abgelaufene Deadline meldet sich als ZEITLIMIT --"
BELEG_LOG="$(mktemp)"
(
  pass=0; fail=0
  ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
  bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
  run_doctor "" 0
) > "$BELEG_LOG" 2>&1
if grep -qE '^  FAIL  ZEITLIMIT: wb-doctor .* abgelaufen \(Deadline 0s\)' "$BELEG_LOG" \
   && ! grep -qE '^  FAIL  (kein BEFUND|Punkt|Schlusszeile|--fix|der Befund|Unterhaltung)' "$BELEG_LOG"; then
  ok "deadline_sek=0 meldet ZEITLIMIT, keinen Inhaltsfehler: $(grep '^  FAIL' "$BELEG_LOG")"
else
  bad "deadline_sek=0 hat NICHT wie erwartet als ZEITLIMIT gemeldet: $(cat "$BELEG_LOG")"
fi
rm -f "$BELEG_LOG"

echo
echo "wb-doctor-betriebs-befunde: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
