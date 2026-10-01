#!/usr/bin/env bash
# test-absende-inhalt.sh -- die INHALTSPRUEFUNG in pi-workers Absende-Pruefung.
#
# ANLASS (2026-08-17): Ein Auftrag um 20:06 galt als "Submission verifiziert" --
# das Auftragsbuch trug ihn, die Auftragsdatei lag auf der Platte, pi-worker meldete
# Erfolg. Im Pane kam der Auftrag nie an; dort stand stattdessen eine
# Terminal-Escape-Folge (eine Device-Attributes-Antwort, `?1;2;4c>84;0;0c>|tmux
# 3.7b`). Die Absende-Pruefung in pi-worker (siehe test-absende-pruefung.sh) belegte
# bis dahin nur, dass die EINGABEZEILE leer wurde -- nicht, dass der Text, der sie
# geleert hat, der Auftragstext war. Ein Paste, in den sich eine Terminalantwort
# mischt, leert die Zeile genauso wie ein echtes Absenden und bestand die alte
# Pruefung unveraendert.
#
# GEPRUEFT WIRD HIER, ZUSAETZLICH zu test-absende-pruefung.sh:
#   1  Eine SAUBERE Zustellung meldet weiterhin Erfolg: der Auftragstext (genauer:
#      sein Marker -- derselbe Dateiname, den record_worker_conversation schon zur
#      Transkript-Zuordnung benutzt) taucht im Pane wieder auf, "Submission
#      verifiziert" steht in der Ausgabe, Exit-Code 0.
#   2  Eine VERFAELSCHTE Zustellung -- die Eingabezeile leert sich genauso, aber im
#      Pane erscheint etwas anderes als der Auftragstext -- wird jetzt als Fehler
#      erkannt: Exit-Code ungleich 0, eine Meldung, die sagt, was zu tun ist, und
#      AUSDRUECKLICH KEINE "Submission verifiziert"-Zeile. Das ist der Fall, an dem
#      die alte Pruefung hereingefallen ist.
#   3  Eine ZERFASERTE Zustellung (Nachtrag 2026-08-22, Anlass: ein 35B-aider-Spawn
#      galt als "Submission verifiziert", das Pane zeigte aber nur Bruchstuecke des
#      Auftragstextes, nie den Auftrag selbst) -- der MARKER (der Dateiname aus dem
#      Protokoll-Anhang) kommt sauber an, weil er in der LETZTEN eingefuegten Zeile
#      steht, aber die ERSTE Zeile -- der eigentliche Auftrag -- ist verstuemmelt.
#      Der alte, marker-only Beleg haette das faelschlich als verifiziert gemeldet;
#      die neue Pruefung verlangt zusaetzlich die unversehrte erste Zeile und muss
#      hier denselben Fehler wie bei Fall 2 melden.
#   4  Nachtrag 2026-09-09 (vierte Runde): Eine GEFLUTETE, aber echte Zustellung --
#      der Auftragstext kommt sauber an, die TUI flutet den Bildschirm danach mit
#      tausenden Zeilen echter Ausgabe (Harness pi, gemessen: ein Auftrag, der eine
#      groessere Datei liest oder ein Werkzeug mit viel Ausgabe aufruft, produziert
#      das in Sekundenbruchteilen). Das schiebt die Marker-Zeile aus einem zu
#      knappen Verlaufsfenster -- vier gemeldete Fehlalarme am selben Tag trugen
#      genau dieses Bild ("Eingabezeile ... ist leer, aber der Auftragstext ist
#      nicht wiederzufinden"), obwohl der Worker laengst arbeitete. Muss weiterhin
#      als Erfolg gelten (siehe KAPTUR_ZEILEN in pi-worker).
#
# Der Stellvertreter ist derselbe fake-tui.py wie in test-absende-pruefung.sh, um
# zwei neue Spielarten erweitert ('korrekt', 'verfaelscht') -- siehe dort fuer die
# Begruendung des raw-mode-Ansatzes.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME, eigene Registry.
# Keine Live-Session, kein ~/.pi-workers des Menschen, kein Netz, kein Modell.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"        # …/claude-workbench/shell
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-tui.py"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-absendeninhalt-$$"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-absendeninhalt-test.XXXXXX")" && pwd)"
SHIM="$TESTHOME/.shim"
MARKE="i$$$RANDOM"
ECHTHOME="$HOME"
export HOME="$TESTHOME"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

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
trap cleanup EXIT INT TERM

echo "== pi-worker: Inhaltspruefung der Absendung (Socket $SOCKET, HOME $TESTHOME) =="
[ -n "$TMUX_REAL" ]      || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -f "$FAKE" ]           || ueberspringen "fake-tui.py fehlt neben diesem Test"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"
export WB_NO_DISCOVER=1

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
cp "$REPO/wb-rolle" "$TESTHOME/.local/bin/wb-rolle"
cp "$REPO/wb-harness-run" "$TESTHOME/.local/bin/wb-harness-run"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-mensch" \
         "$TESTHOME/.local/bin/wb-rolle" "$TESTHOME/.local/bin/wb-harness-run"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py" 2>/dev/null || true
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write"
chmod +x "$TESTHOME/.local/bin/wb-pane-write"

spielart() {  # spielart <dateiname> <kind> <prompt-zeichen>
  cat > "$TESTHOME/.local/bin/$1" <<SHIMEOF
#!/bin/sh
FAKE_KIND=$2 FAKE_PROMPT='$3' exec /usr/bin/python3 "$FAKE"
SHIMEOF
  chmod +x "$TESTHOME/.local/bin/$1"
}
spielart tui-korrekt     korrekt     '❯'
spielart tui-verfaelscht verfaelscht '❯'
spielart tui-zerfallen   zerfallen   '❯'
spielart tui-ueberflutet ueberflutet '❯'
spielart tui-umgebrochen umgebrochen '❯'
# Fall 6: derselbe Stellvertreter, aber mit hartem Wortbruch. Der Schalter steht IN der
# Datei, weil tmux die Attrappe mit der Umgebung des Test-Servers startet -- eine
# exportierte Variable des Aufrufers erreicht sie nicht (gemessen 2026-09-10).
cat > "$TESTHOME/.local/bin/tui-umgebrochen-hart" <<SHIMEOF
FAKE_KIND=umgebrochen FAKE_UMBRUCH_HART=1 FAKE_PROMPT='❯' exec /usr/bin/python3 "$FAKE"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/tui-umgebrochen-hart"

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 60
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator
# Ohne eigene tmux.conf (-f /dev/null) traegt dieser Socket tmux' eingebaute
# Vorgabe fuer history-limit -- gemessen 2000, nicht die 20000, die auf der
# echten Maschine gelten (wb-speicher VERLAUF_EMPFOHLEN). Fall 4 unten braucht
# echten Verlauf JENSEITS von 2000 Zeilen, um den behobenen Fehler ueberhaupt
# nachstellen zu koennen -- sonst wirft der Test-eigene Socket den Ueberschuss
# laengst weg, bevor KAPTUR_ZEILEN in pi-worker ueberhaupt zum Zug kommt.
tmux -L "$SOCKET" set-option -g history-limit 20000

aufraeumen() {
  local p
  for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk '$2!=""{print $1}'); do
    tmux -L "$SOCKET" kill-pane -t "$p" 2>/dev/null
  done
}

# ── 1: saubere Zustellung -- der Marker taucht im Pane auf, Erfolg bleibt Erfolg ──
echo
echo "-- 1: saubere Zustellung (Auftragstext erscheint im Pane) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-korrekt" "$TESTHOME/.local/bin/claude"
T0=$SECONDS
AUS="$(pi "s1$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Erste Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "1: die saubere Zustellung gilt weiterhin als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "1: keine Verifikation trotz sauberer Zustellung, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
[ "$RC" -eq 0 ] && ok "1: Exit-Code 0" || bad "1: Exit-Code $RC statt 0"
PANE1="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s1$MARKE" '$2==n{print $1; exit}')"
RES1="$(printf '%s\n' "$AUS" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1)"
if [ -n "$PANE1" ] && [ -n "$RES1" ] \
   && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE1" 2>/dev/null | grep -qF -- "$(basename "$RES1")"; then
  ok "1: der Marker (Ergebnisdatei-Name) steht wirklich im Pane -- der Test misst am echten Bildschirm, nicht nur an pi-workers eigener Meldung"
else
  bad "1: der Marker steht NICHT im Pane (Pane=$PANE1, Ergebnisdatei=$RES1) -- die Positivprobe des Tests selbst ist kaputt"
fi

# ── 2: verfaelschte Zustellung -- Eingabezeile leer, aber falscher Inhalt ────────
echo
echo "-- 2: verfaelschte Zustellung (Eingabezeile leer, Pane zeigt etwas anderes) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-verfaelscht" "$TESTHOME/.local/bin/claude"
T0=$SECONDS
AUS="$(pi "s2$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Zweite Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) bad "2: es wird trotz verfaelschter Zustellung Erfolg behauptet -- genau der gemessene Fehler" ;;
  *) ok "2: keine Erfolgsbehauptung (nach ${DAUER}s)" ;;
esac
case "$AUS" in
  *"nicht wiederzufinden"*) ok "2: die neue Meldung nennt den Grund (Auftragstext im Pane nicht wiederzufinden)" ;;
  *) bad "2: die erwartete Fehlermeldung fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
[ "$RC" -ne 0 ] && ok "2: Exit-Code ungleich 0 ($RC)" || bad "2: Exit-Code 0 trotz verfaelschter Zustellung"
PANE2="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s2$MARKE" '$2==n{print $1; exit}')"
RES2="$(printf '%s\n' "$AUS" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1)"
if [ -n "$PANE2" ] && [ -n "$RES2" ] \
   && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE2" 2>/dev/null | grep -qF -- "$(basename "$RES2")"; then
  bad "2: der Marker steht entgegen der Absicht des Testfalls doch im Pane -- die Gegenprobe des Tests selbst ist kaputt"
else
  ok "2: der Marker steht wirklich NICHT im Pane -- der nachgestellte Fehlerfall trifft zu"
fi

# ── 3: zerfaserte Zustellung -- der MARKER kommt an, der Auftrag selbst nicht ───
# Anlass (2026-08-22): ein 35B-aider-Spawn galt als "Submission verifiziert",
# das Pane zeigte aber nur Bruchstuecke des Auftragstextes. Anders als Fall 2
# (wo der Marker komplett fehlt) landet hier der Marker sauber -- er steht in
# der LETZTEN eingefuegten Zeile (dem Protokoll-Anhang) -- waehrend die ERSTE
# Zeile, der eigentliche Auftrag, verstuemmelt ankommt. Genau diese Luecke hat
# der alte, marker-only Beleg nicht gesehen.
echo
echo "-- 3: zerfaserte Zustellung (Marker kommt an, die erste Zeile nicht) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-zerfallen" "$TESTHOME/.local/bin/claude"
T0=$SECONDS
AUS="$(pi "s3$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Dritte Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) bad "3: es wird trotz zerfaserter Zustellung Erfolg behauptet -- genau der gemessene Fehler" ;;
  *) ok "3: keine Erfolgsbehauptung (nach ${DAUER}s)" ;;
esac
case "$AUS" in
  *"nicht wiederzufinden"*) ok "3: die neue Meldung nennt den Grund (Auftragstext im Pane nicht wiederzufinden)" ;;
  *) bad "3: die erwartete Fehlermeldung fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
[ "$RC" -ne 0 ] && ok "3: Exit-Code ungleich 0 ($RC)" || bad "3: Exit-Code 0 trotz zerfaserter Zustellung"
PANE3="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s3$MARKE" '$2==n{print $1; exit}')"
# pi-worker druckt "Ergebnis-Datei: ..." nur im ERFOLGSpfad -- ein Fehlschlag (der
# hier ausdruecklich erwartet wird) schreibt den erwarteten Pfad stattdessen in die
# Fehlschlag-Datei selbst ("- Erwartete Ergebnisdatei: ..."), siehe
# zustellung_fehlgeschlagen() in pi-worker.
FEHLDATEI3="$(ls -t "$TESTHOME/.pi-workers/results/s3$MARKE/"*.zustellung-fehlgeschlagen.md 2>/dev/null | head -1)"
RES3="$(sed -n 's/^- Erwartete Ergebnisdatei: \([^ ]*\).*/\1/p' "$FEHLDATEI3" 2>/dev/null | head -1)"
BILD3="$(tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE3" 2>/dev/null)"
if [ -n "$PANE3" ] && [ -n "$RES3" ] && printf '%s' "$BILD3" | grep -qF -- "$(basename "$RES3")"; then
  ok "3: der Marker steht WIRKLICH im Pane -- die alte, marker-only Pruefung waere genau hier hereingefallen"
else
  bad "3: der Marker fehlt im Pane -- die Gegenprobe des Testfalls selbst trifft nicht zu (Pane=$PANE3, Ergebnisdatei=$RES3)"
fi
if printf '%s' "$BILD3" | grep -qF -- "Dritte Aufgabe $MARKE"; then
  bad "3: die unversehrte erste Zeile steht entgegen der Absicht des Testfalls doch im Pane -- die Gegenprobe ist kaputt"
else
  ok "3: die erste Zeile ('Dritte Aufgabe $MARKE') steht wirklich NICHT unversehrt im Pane"
fi

# ── 4: geflutete, aber echte Zustellung -- der Marker steht, wird aber verscrollt ──
# Anlass (2026-09-09, vierte Runde): vier Fehlalarme in derselben Nacht bei
# Harness pi, alle mit derselben Meldung wie Fall 2 ("Eingabezeile ... ist leer,
# aber der Auftragstext ist nicht wiederzufinden"), obwohl der jeweilige Worker
# nachweislich arbeitete und ein echtes Ergebnis schrieb. Anders als Fall 2 (der
# Marker fehlt WIRKLICH) steht der Marker hier im Pane -- nur nicht mehr in den
# letzten 2000 ROH-Zeilen, die die alte, feste Suchtiefe abdeckte.
echo
echo "-- 4: geflutete Zustellung (Marker steht, aber weit oberhalb einer zu knappen Suchtiefe) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-ueberflutet" "$TESTHOME/.local/bin/claude"
T0=$SECONDS
AUS="$(pi "s4$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Vierte Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "4: die geflutete, aber echte Zustellung gilt weiterhin als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "4: keine Verifikation trotz echter Zustellung -- der Fehlalarm vom 2026-09-09, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
[ "$RC" -eq 0 ] && ok "4: Exit-Code 0" || bad "4: Exit-Code $RC statt 0"
PANE4="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s4$MARKE" '$2==n{print $1; exit}')"
RES4="$(printf '%s\n' "$AUS" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1)"
if [ -n "$PANE4" ] && [ -n "$RES4" ] \
   && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE4" 2>/dev/null | grep -qF -- "$(basename "$RES4")"; then
  bad "4: der Marker steht noch in den letzten 2000 Rohzeilen -- die gestellte Flut war zu schwach, um den behobenen Fehler ueberhaupt nachzustellen (Testfall ohne Aussagekraft)"
else
  ok "4: der Marker steht NICHT mehr in den letzten 2000 Rohzeilen -- genau die Lage, die vier Fehlalarme am 2026-09-09 ausgeloest hat; mit dem ALTEN, festen -2000 waere das hier als Fehlschlag gemeldet worden"
fi
if [ -n "$PANE4" ] && [ -n "$RES4" ] \
   && tmux -L "$SOCKET" capture-pane -p -J -S -20000 -t "$PANE4" 2>/dev/null | grep -qF -- "$(basename "$RES4")"; then
  ok "4: der Marker steht in der vollen Suchtiefe (KAPTUR_ZEILEN) -- die Positivprobe des Testfalls selbst ist intakt"
else
  bad "4: der Marker fehlt sogar in der vollen Suchtiefe -- die Positivprobe des Testfalls selbst ist kaputt (Pane=$PANE4, Ergebnisdatei=$RES4)"
fi

# ── 5: von der TUI selbst umgebrochene erste Zeile ──────────────────────────────
# Anlass (2026-09-09, Spawn 'browserbase', pi v0.84, Pane 170 Spalten): der Auftrag
# war angekommen, der Worker lief, und pi-worker meldete trotzdem "Auftragstext
# nicht wiederzufinden". pi bricht Verlaufszeilen an seiner EIGENEN Breite um
# (wortweise, Folgezeile mit fuehrendem Leerzeichen); `capture-pane -J` setzt
# das nicht zusammen. Die erste Zeile hier ist laenger als die Umbruchbreite des
# Stellvertreters (FAKE_UMBRUCH, Vorgabe 60), genau wie ein Zeiger-Satz auf eine
# Auftragsdatei im Betrieb.
echo
echo "-- 5: die TUI bricht die erste Zeile selbst um (Marker und Auftrag kommen an) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-umgebrochen" "$TESTHOME/.local/bin/claude"
LANG5="Fuenfte Aufgabe $MARKE: lies die Auftragsdatei unter einem langen Pfad vollstaendig und erfuelle sie Punkt fuer Punkt in deinem Worktree"
T0=$SECONDS
AUS="$(pi "s5$MARKE" claude-haiku45 "$TESTHOME/arbeit" "$LANG5")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "5: die umgebrochene, aber vollstaendige Zustellung gilt als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "5: keine Verifikation trotz vollstaendiger Zustellung -- der Fehlalarm vom 2026-09-09 (Spawn browserbase), rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
[ "$RC" -eq 0 ] && ok "5: Exit-Code 0" || bad "5: Exit-Code $RC statt 0"
PANE5="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s5$MARKE" '$2==n{print $1; exit}')"
if [ -n "$PANE5" ] && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE5" 2>/dev/null | grep -qF -- "$LANG5"; then
  bad "5: die erste Zeile steht am Stueck im Pane -- der Stellvertreter hat nicht umgebrochen, der Testfall stellt den Fehler nicht nach"
else
  ok "5: die erste Zeile steht NICHT am Stueck im Pane -- genau die Lage des Fehlalarms; der alte Vergleich am Stueck waere hier durchgefallen"
fi
if [ -n "$PANE5" ] && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE5" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | grep -qF -- "$LANG5"; then
  ok "5: mit eingeebnetem Weissraum steht die erste Zeile vollstaendig im Pane -- die Positivprobe des Testfalls ist intakt"
else
  bad "5: die erste Zeile fehlt auch mit eingeebnetem Weissraum -- die Positivprobe des Testfalls selbst ist kaputt (Pane=$PANE5)"
fi

# ── 6: die TUI bricht einen ueberlangen Pfad MITTEN IM WORT um ─────────────────
# Anlass (2026-09-10, Spawn 'ausrollen', Pane 80x23): erste Zeile mit einem 110
# Zeichen langen Auftragsdatei-Pfad; pi bricht das Wort selbst um, die Bruchstelle
# bekommt beim Weissraum-Einebnen ein Leerzeichen, das im Auftrag nie stand.
echo
echo "-- 6: die TUI bricht einen ueberlangen Pfad mitten im Wort um --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-umgebrochen-hart" "$TESTHOME/.local/bin/claude"
LANG6="Lies /private/tmp/sehr/langer/pfad/der/laenger/ist/als/die/zeile/$MARKE/auftrag-mit-vielen-ordnern-und-noch-mehr-zeichen.md und erfuelle ihn"
T0=$SECONDS
AUS="$(pi "s6$MARKE" claude-haiku45 "$TESTHOME/arbeit" "$LANG6")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "6: Zustellung mit hart umgebrochenem Pfad gilt als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "6: keine Verifikation trotz vollstaendiger Zustellung -- der Fehlalarm vom 2026-09-10 (Spawn ausrollen), rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -10 ;;
esac
PANE6="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v n="s6$MARKE" '$2==n{print $1; exit}')"
if [ -n "$PANE6" ] && tmux -L "$SOCKET" capture-pane -p -J -S -2000 -t "$PANE6" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | grep -qF -- "$LANG6"; then
  bad "6: die erste Zeile steht mit eingeebnetem Weissraum am Stueck -- der Stellvertreter hat nicht im Wort gebrochen, der Testfall stellt den Fehler nicht nach"
else
  ok "6: mit eingeebnetem Weissraum steht die Zeile NICHT am Stueck -- genau die Lage des Fehlalarms (Bruch mitten im Pfad)"
fi

# ── die echte Umgebung blieb unberuehrt ─────────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
UEBRIG=0
for n in "s1$MARKE" "s2$MARKE" "s3$MARKE" "s4$MARKE" "s5$MARKE" "s6$MARKE"; do
  [ -e "$ECHTHOME/.pi-workers/results/$n" ] && UEBRIG=$((UEBRIG+1))
done
[ "$UEBRIG" -eq 0 ] \
  && ok "kein Ergebnisordner unter dem echten HOME" \
  || bad "$UEBRIG Ergebnisordner im ECHTEN ~/.pi-workers -- Testisolation gebrochen"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
