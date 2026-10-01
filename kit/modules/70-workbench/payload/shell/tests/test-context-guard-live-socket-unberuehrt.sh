#!/usr/bin/env bash
# Beweis, keine Behauptung: waehrend die context-guard-Testsuiten laufen, darf
# KEIN Prozess DIESES LAUFS den Live-/Default-tmux-Socket beruehren.
#
# Anlass (2026-08-04): test-context-guard-backfill.sh startete den PRUEFLING
# (context-guard) als Hintergrundjob DIESER Test-Shell, mit `unset TMUX` am
# Kopf der Datei und ohne jede Bindung an den eigenen Testsocket -- der
# Pruefling ruft selbst unflagged `tmux ...` auf, das faellt ohne `$TMUX` und
# ohne `-L` auf den DEFAULT-Socket zurueck. Gemessen: genau dieser Prozess
# (".../tmp.AzXGVYiXii/.local/bin/context-guard --auto %0") tippte die
# Fertigmeldung eines nicht existierenden Workers in echtes des Nutzers
# Orchestrator-Pane und forderte `wb-close neu` -- eine Testsuite, die dem
# Orchestrator Befehle unterschiebt. Ursache und Reparatur (PATH-Schirm nach
# dem Muster aus betriebslauf.sh/test-registry.sh) stehen in der Result-Datei
# dieser Aufgabe.
#
# ZWEITER ANLASS (04.08., Abnahme der ersten Reparatur dieser Datei): fester
# MARKER_REGEX und ein blosser Vorher/Nachher-Zaehlvergleich pruefen die
# FALSCHE Behauptung. Drei gemessene Fehlalarme, alle ohne echtes Leck:
#   1. Der Erkenner passte auf seine eigene Beschreibung -- die Marker-Literale
#      standen woertlich in dieser Datei, und jede Live-Pane, die die Datei,
#      ihren Diff oder ein Gespraech UEBER sie zeigte, loeste den Fund aus
#      (dieselbe Familie wie ein `pgrep -f`, das auf den eigenen Prompt passt).
#      Bestaetigt: der Marker-Fund am 04.08. war eigener des Nutzers Bildschirm.
#   2. Nachweis 3 zaehlte jeden `context-guard`-Prozess als eigenes Leck,
#      unabhaengig davon, aus welchem Arbeitsbaum er stammte -- dreimal
#      gemessen ein `context-guard` aus `worktrees/geruest`, nicht aus diesem
#      Lauf.
#   3. Nachweis 1 verlangte Session-/Pane-Menge unveraendert -- auf einer
#      Maschine, auf der der Nutzer waehrend des Laufs tatsaechlich arbeitet,
#      aendert sich die Pane-Menge aus Gruenden, die nichts mit dieser Suite
#      zu tun haben.
# BEWIESEN WERDEN SOLL: dass die vier gepruefte Suiten den Live-Socket nicht
# anfassen. NICHT: dass am Live-Socket waehrenddessen ueberhaupt nichts
# passiert -- das ist auf einer Maschine, an der ein Mensch und andere Worker
# gleichzeitig arbeiten, weder pruefbar noch das, was ein Vorfall wie oben
# bedeuten wuerde.
#
# DIE REPARATUR, dreiteilig, ein Mechanismus fuer alle drei Punkte:
#   * Ein KENNZEICHEN, das es vor diesem Lauf nirgends gab (Zeitstempel + PID +
#     Zufallszahl dieses Prozesses), geht per LIVE_MARKER an die vier Suiten.
#     Jede haengt es an ihre Socket- UND Worker-/Ergebnisnamen -- alles, was
#     ein Pruefling ueber diese Namen in eine Pane oder eine Prozesszeile
#     schreibt, traegt es zwangslaeufig mit. Nachweis 2 sucht NUR noch danach,
#     nicht mehr nach generischen, in dieser Datei selbst stehenden Literalen.
#     Kein Mensch bringt eine elf Stellen lange Zufallszeichenkette aus einem
#     Prozess, den es vor Sekunden noch nicht gab, versehentlich auf den
#     Bildschirm.
#   * Nachweis 3 zaehlt einen neu entstandenen `context-guard`-Prozess nur als
#     Leck DIESES LAUFS, wenn er diesem Lauf zuzuordnen ist (Suiten, die das
#     Werkzeug in ein `mktemp`-Verzeichnis kopieren, tragen das Kennzeichen
#     dafuer im Pfad dieses Verzeichnisses). Ein Prozess, der nicht zuzuordnen
#     ist, erscheint als Hinweis, nicht als Fehlschlag.
#
# DRITTER ANLASS (20.09.2026, im vollen Lauf mit --jobs 6 gemessen, vierter
# Fehlalarm ohne echtes Leck): Nachweis 3 zaehlte jeden neuen Prozess, dessen
# Kommandozeile den Pfad DIESES ARBEITSBAUMS enthielt, als Leck dieses Laufs.
# Im Parallellauf laufen aber weitere Suiten desselben Arbeitsbaums
# gleichzeitig, und mindestens fuenf davon starten ebenfalls
# `$REPO/context-guard` (test-guard-nur-worker.sh, -postfach, -statuszeile-tief,
# -haengender-schreibvorgang, -slug-stabil). Gemeldet wurde konkret
# `.../shell/context-guard --auto --workers-only --exit-when-session-gone %0` --
# `--workers-only` gibt es in keiner der vier hier gepruefte Suiten; der Prozess
# gehoerte test-guard-nur-worker.sh. Der Pfad des Arbeitsbaums ist also KEINE
# Zuordnung, er ist nur die Auskunft "aus diesem Repo".
#   Die Zuordnung haengt jetzt an dem, was diesen Lauf wirklich auszeichnet:
#   jede der vier Suiten arbeitet auf einem tmux-Socket, dessen NAME das
#   Kennzeichen traegt. Der Beobachter schreibt waehrend des Laufs alle
#   `context-guard`-Prozesse mit, die unter einer Pane eines solchen Servers
#   haengen -- das faengt auch die beiden Suiten, die das Werkzeug direkt aus
#   dem Arbeitsbaum starten (blockiert, fertigmeldung) und deren
#   Kommandozeile das Kennzeichen darum nicht enthaelt. Ein Prozess, den
#   weder diese Mitschrift noch seine Kommandozeile diesem Lauf zuordnet,
#   ist ein Hinweis.
#   * Nachweis 1 (Session-/Pane-Menge) ist ein HINWEIS, kein Fehlschlag mehr --
#     eine Aenderung am Live-Socket, die nichts mit dieser Suite zu tun hat,
#     ist kein Befund. Was zaehlt, ist weiterhin Nachweis 2 (das Kennzeichen)
#     und Nachweis 3 (der zuordenbare Prozess).
#
# Diese Datei ruehrt den Live-/Default-Socket NUR LESEND an: list-sessions,
# list-panes, capture-pane. Niemals send-keys/kill/set/new-session dagegen --
# das waere derselbe Fehler, den sie beweisen soll, dass er nicht mehr passiert.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

pass=0; fail=0; hinweise=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { hinweise=$((hinweise+1)); printf '  hinw  %s\n' "$1"; }

SUITEN="test-context-guard-backfill.sh test-context-guard-blockiert.sh test-context-guard-fertigmeldung.sh test-worker-tab-capacity.sh"

# Das Kennzeichen dieses Laufs -- siehe Kopfkommentar. $RANDOM zweimal + Zeit +
# eigene PID, rein alphanumerisch (sicher als Socket-/Worker-/Verzeichnisname
# ueberall, wo diese vier Suiten Namen bilden).
export LIVE_MARKER="lsu$(date +%s)x$$x${RANDOM}${RANDOM}"
echo "== Kennzeichen dieses Laufs: $LIVE_MARKER =="
MARKER_REGEX="$LIVE_MARKER"

if ! tmux list-sessions >/dev/null 2>&1; then
  echo "== kein Live-/Default-tmux-Socket erreichbar -- nichts zu gefaehrden, Pruefung trivial erfuellt =="
  ok "kein Live-Socket vorhanden (nichts, das eine Suite haette beruehren koennen)"
  echo
  echo "context-guard-live-socket-unberuehrt: $pass ok, $fail fehlgeschlagen"
  exit 0
fi

WORK="$(mktemp -d)"
MONITOR_PID=""
cleanup() {
  [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
  wait "$MONITOR_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "== Vorher: Bestand auf dem Live-Socket =="
tmux list-sessions -F '#{session_name}' 2>/dev/null | sort > "$WORK/sessions.vorher"
tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null | sort > "$WORK/panes.vorher"
echo "   Sessions: $(wc -l < "$WORK/sessions.vorher" | tr -d ' ')   Panes: $(wc -l < "$WORK/panes.vorher" | tr -d ' ')"
# Baseline der context-guard-PIDs: es laeuft LEGITIM mindestens ein echter Guard
# fuer laufende des Nutzers Orchestrator-Sessions (Dauerbetrieb, nicht Teil dieses
# Laufs) -- Nachweis 3 darf nur PIDs melden, die WAEHREND dieses Laufs neu
# entstanden UND danach nicht wieder verschwunden sind, nie den Dauerbetrieb.
pgrep -f 'context-guard --auto' 2>/dev/null | sort > "$WORK/guardpids.vorher"
echo "   bereits laufende context-guard-Prozesse (Dauerbetrieb, nicht Teil des Nachweises): $(tr '\n' ' ' < "$WORK/guardpids.vorher")"

# --- Beobachter: tastet waehrend des GESAMTEN Laufs alle 2s jede Live-Pane
# auf die Vorfalls-Marker ab, rein lesend (capture-pane -p). ---
cat > "$WORK/monitor.sh" <<MONEOF
#!/usr/bin/env bash
FUND="$WORK/fund.log"
EIGENE="$WORK/eigene-guards"
SOCKDIR="\${TMUX_TMPDIR:-/tmp}/tmux-\$(id -u)"
while :; do
  for p in \$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null); do
    tmux capture-pane -p -t "\$p" 2>/dev/null | grep -EnH "$MARKER_REGEX" \
      | sed "s|^|\$(date '+%H:%M:%S') pane=\$p |" >> "\$FUND"
  done
  # Zuordnung fuer Nachweis 3 (siehe Kopfkommentar, dritter Anlass): jede der
  # vier gepruefte Suiten arbeitet auf einem tmux-Socket, dessen Name das
  # Kennzeichen traegt. Ein context-guard, den eine von ihnen startet, haengt
  # unter einer Pane genau dieses Servers. Solange er lebt, wird er hier
  # mitgeschrieben -- danach ist er auch dann noch zuzuordnen, wenn der Server
  # laengst weg ist und die Kommandozeile das Kennzeichen nicht enthaelt.
  for sock in "\$SOCKDIR"/*"$LIVE_MARKER"*; do
    [ -S "\$sock" ] || continue
    for pp in \$(tmux -L "\$(basename "\$sock")" list-panes -a -F '#{pane_pid}' 2>/dev/null); do
      nachkommen="\$(pgrep -P "\$pp" 2>/dev/null)"
      for kind in \$nachkommen; do nachkommen="\$nachkommen \$(pgrep -P "\$kind" 2>/dev/null)"; done
      for kind in \$nachkommen; do
        case "\$(ps -p "\$kind" -o command= 2>/dev/null)" in
          *context-guard*) echo "\$kind" >> "\$EIGENE" ;;
        esac
      done
    done
  done
  sleep 2
done
MONEOF
chmod +x "$WORK/monitor.sh"
"$WORK/monitor.sh" &
MONITOR_PID=$!
echo "   Beobachter laeuft (PID $MONITOR_PID), tastet alle 2s ab"
echo

echo "== Lauf der gepruefte Suiten =="
GESAMT_RC=0
for s in $SUITEN; do
  echo "-- $s --"
  if bash "$SCRIPT_DIR/$s"; then
    ok "$s: gruen"
  else
    bad "$s: FAIL (rc=$?) -- siehe Ausgabe oben"
    GESAMT_RC=1
  fi
  echo
done

echo "== Beobachter stoppen =="
kill "$MONITOR_PID" 2>/dev/null
wait "$MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""
sleep 1

echo "== Nachher: Bestand auf dem Live-Socket =="
tmux list-sessions -F '#{session_name}' 2>/dev/null | sort > "$WORK/sessions.nachher"
tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null | sort > "$WORK/panes.nachher"
echo "   Sessions: $(wc -l < "$WORK/sessions.nachher" | tr -d ' ')   Panes: $(wc -l < "$WORK/panes.nachher" | tr -d ' ')"

echo
echo "== Nachweis 1 (Hinweis, kein Fehlschlag): Session-/Pane-Menge =="
# Nur noch informativ (siehe Kopfkommentar, zweiter Anlass): auf einer
# Maschine, an der der Nutzer oder andere Worker waehrend des Laufs tatsaechlich
# arbeiten, aendert sich die Pane-Menge aus Gruenden, die nichts mit dieser
# Suite zu tun haben -- das ist kein Befund. Was wirklich zaehlt, ob DIESER
# Lauf etwas angefasst hat, steht in Nachweis 2 und 3.
if diff -q "$WORK/sessions.vorher" "$WORK/sessions.nachher" >/dev/null; then
  ok "Session-Menge auf dem Live-Socket unveraendert"
else
  note "Session-Menge hat sich geaendert (moeglicherweise fremde Aktivitaet waehrend des Laufs, kein Fehlschlag):"
  diff "$WORK/sessions.vorher" "$WORK/sessions.nachher" | sed 's/^/       /'
fi
if diff -q "$WORK/panes.vorher" "$WORK/panes.nachher" >/dev/null; then
  ok "Pane-Menge auf dem Live-Socket unveraendert"
else
  note "Pane-Menge hat sich geaendert (moeglicherweise fremde Aktivitaet waehrend des Laufs, kein Fehlschlag):"
  diff "$WORK/panes.vorher" "$WORK/panes.nachher" | sed 's/^/       /'
fi

echo
echo "== Nachweis 2: das Kennzeichen dieses Laufs ist in keiner Live-Pane aufgetaucht (waehrend des gesamten Laufs abgetastet) =="
if [ -s "$WORK/fund.log" ]; then
  bad "Kennzeichen $LIVE_MARKER in einer Live-Pane gefunden -- dieser Lauf hat den Live-Socket beruehrt:"
  sed 's/^/       /' "$WORK/fund.log"
else
  ok "das Kennzeichen $LIVE_MARKER ist in keiner Live-Pane aufgetaucht"
fi

echo
echo "== Nachweis 3: kein NEUER context-guard-Prozess DIESES LAUFS uebrig (kein Leck) =="
# Ein neu entstandener Prozess zaehlt nur als Leck DIESES Laufs, wenn der
# Beobachter ihn unter einer Pane eines Kennzeichen-Servers mitgeschrieben hat
# oder seine Kommandozeile das Kennzeichen traegt (siehe Kopfkommentar).
# Weder der Pfad des Arbeitsbaums noch der blosse Name `context-guard` ordnen
# zu: im Parallellauf starten Nachbarsuiten desselben Arbeitsbaums ihre
# eigenen Wachen (gemessen 20.09.), und ein context-guard aus einem ANDEREN
# Arbeitsbaum (gemessen: worktrees/geruest, dreimal) gehoert ohnehin zu dessen
# eigenem Lauf.
pgrep -f 'context-guard --auto' 2>/dev/null | sort > "$WORK/guardpids.nachher"
NEU="$(comm -13 "$WORK/guardpids.vorher" "$WORK/guardpids.nachher")"
if [ -z "$NEU" ]; then
  ok "keine neuen context-guard-Prozesse uebrig (Dauerbetrieb unveraendert: $(tr '\n' ' ' < "$WORK/guardpids.nachher"))"
else
  EIGENE=""
  FREMDE=""
  for p in $NEU; do
    cmd="$(ps -p "$p" -o command= 2>/dev/null)"
    if grep -qx -- "$p" "$WORK/eigene-guards" 2>/dev/null; then
      EIGENE="$EIGENE $p"
    else
      case "$cmd" in
        *"$LIVE_MARKER"*) EIGENE="$EIGENE $p" ;;
        *) FREMDE="$FREMDE $p" ;;
      esac
    fi
  done
  if [ -n "$FREMDE" ]; then
    note "neue context-guard-Prozesse laufen noch, die NICHT zu diesem Lauf gehoeren (anderer Arbeitsbaum oder eine Nachbarsuite dieses Arbeitsbaums im Parallellauf, PID(s):$FREMDE):"
    for p in $FREMDE; do ps -p "$p" -o pid,ppid,lstart,command 2>/dev/null | sed 's/^/       /'; done
  fi
  if [ -n "$EIGENE" ]; then
    bad "aus DIESEM Lauf entstandene context-guard-Prozesse laufen noch (PID(s):$EIGENE) -- Leck"
    for p in $EIGENE; do ps -p "$p" -o pid,ppid,lstart,command 2>/dev/null | sed 's/^/       /'; done
  else
    ok "keine neuen context-guard-Prozesse DIESES Laufs uebrig${FREMDE:+ (die oben genannten gehoeren nicht zu diesem Lauf)}"
  fi
fi

echo
echo "== gepruefte Suiten =="
if [ "$GESAMT_RC" -eq 0 ]; then ok "alle gepruefte Suiten liefen gruen durch"
else bad "mindestens eine gepruefte Suite ist rot (siehe oben)"; fi

echo
echo "context-guard-live-socket-unberuehrt: $pass ok, $fail fehlgeschlagen, $hinweise Hinweis(e)"
[ "$fail" -eq 0 ] && [ "$GESAMT_RC" -eq 0 ]
