#!/usr/bin/env bash
# test-zustellung-eingabezeile.sh -- Auftrag "Aufträge kommen nicht zuverlässig im
# Pane an" (2026-08-20).
#
# DER BEFUND, DER DIESEN TEST AUSGELOEST HAT: heute Nacht blieb ein Auftragstext
# dreimal ungesendet in der Eingabezeile stehen -- Enter wirkte nicht, nur Escape
# loeste ein Neuzeichnen aus. Was live half: C-u (Eingabezeile loeschen), DANACH
# tippen. Die LAENGEN-Hypothese ist WIDERLEGT (Nachtrag zum Auftrag, gemessen): auch
# ein kurzer Zeigertext blieb beim ersten Versuch stehen. Die Spur, die geprueft
# wurde: schon VOR dem Einfuegen stand etwas in der Eingabezeile, und der neue Text
# wurde daran angehaengt statt in eine leere Zeile getippt.
#
# WAS HIER GEMESSEN WIRD, VIER FAELLE:
#   1  Liegengebliebener Text VOR dem Einfuegen wird durch das neue C-u entfernt --
#      der zweite Auftrag kommt WORTGLEICH an, ohne Vermischung mit dem Rest.
#   2  Ein Auftrag jenseits der Laengen-Schwelle (1200 Zeichen $TASK) landet NICHT
#      inline im Pane, sondern als kurzer Zeiger auf eine Datei -- und die Datei
#      traegt den Original-Auftrag WORTGLEICH (byte-fuer-byte).
#   3  Ein kurzer Auftrag (deutlich unter der Schwelle) bleibt weiterhin inline --
#      die neue Schwelle aendert am haeufigen Fall nichts.
#   4  Eine Zustellung, die scheitert (Pane bleibt nach C-u weiterhin belegt, oder
#      der Auftrag haengt spaeter fest), hinterlaesst KEINEN Platzhalter, der wie
#      ein arbeitender Worker aussieht -- latest.md zeigt sofort auf ein ehrliches
#      Fehlschlag-Ergebnis.
#
# GEZAEHLT WIRD, WIE IN test-absende-pruefung.sh, AN DER STELLE, WO DER TASTENDRUCK
# ANKOMMT: der Stellvertreter fake-tui.py schreibt bei jedem Enter jetzt zusaetzlich
# den WORTGLEICHEN Inhalt der Eingabezeile mit (TEXT-Zeile in agent.log, additiv,
# 2026-08-20) -- nur so laesst sich pruefen, OB und WAS sich vermischt hat, nicht
# nur, DASS irgendetwas abgeschickt wurde.
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
SOCKET="wbtest-zustell-$$"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-zustell-test.XXXXXX")" && pwd)"
SHIM="$TESTHOME/.shim"
MARKE="z$$$RANDOM"
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
  chmod -R u+w "$TESTHOME" 2>/dev/null || true
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

echo "== pi-worker: Zustellung ueber die Eingabezeile (Socket $SOCKET, HOME $TESTHOME) =="
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
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-mensch" "$TESTHOME/.local/bin/wb-rolle"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py" 2>/dev/null || true
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

# wb-pane-write: die ECHTE Fassung entscheidet weiter, wer tippen darf -- ein
# Schirm davor protokolliert nur zusaetzlich jeden Tastendruck (dasselbe Muster
# wie test-absende-pruefung.sh).
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write.echt"
chmod +x "$TESTHOME/.local/bin/wb-pane-write.echt"
TASTENLOG="$TESTHOME/tasten.log"
cat > "$TESTHOME/.local/bin/wb-pane-write" <<SHIMEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TASTENLOG"
exec "$TESTHOME/.local/bin/wb-pane-write.echt" "\$@"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/wb-pane-write"

AGENTLOG="$TESTHOME/agent.log"
cat > "$TESTHOME/.local/bin/claude" <<SHIMEOF
#!/bin/sh
FAKE_KIND=korrekt FAKE_PROMPT='❯' FAKE_BUSY=0 FAKE_LOG='$AGENTLOG' exec /usr/bin/python3 "$FAKE"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"
cat > "$TESTHOME/.local/bin/claude-hart" <<SHIMEOF
#!/bin/sh
FAKE_KIND=hart FAKE_PROMPT='❯' FAKE_BUSY=0 FAKE_LOG='$AGENTLOG' exec /usr/bin/python3 "$FAKE"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude-hart"
cat > "$TESTHOME/.local/bin/claude-taub" <<SHIMEOF
#!/bin/sh
FAKE_KIND=taub FAKE_PROMPT='❯' FAKE_BUSY=0 FAKE_LOG='$AGENTLOG' exec /usr/bin/python3 "$FAKE"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude-taub"

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}
zaehler_zuruecksetzen() { : > "$TASTENLOG"; : > "$AGENTLOG"; }
c_u_gesendet() { grep -c 'taste .* C-u' "$TASTENLOG" 2>/dev/null | tr -d ' '; }
# Der letzte TEXT-Eintrag im agent.log: was WIRKLICH bei Enter in der Box stand.
letzter_text() {
  awk -F'\t' '$1=="TEXT"{v=$2} END{print v}' "$AGENTLOG" 2>/dev/null \
    | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\\\/\\/g'
}

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 60
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

aufraeumen() {
  local p
  for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk '$2!=""{print $1}'); do
    tmux -L "$SOCKET" kill-pane -t "$p" 2>/dev/null
  done
}

# ── 1: liegengebliebener Text vor dem Einfuegen wird per C-u entfernt ───────────
echo
echo "-- 1: Text steht schon vor dem zweiten Auftrag in der Box -- C-u raeumt auf --"
aufraeumen
zaehler_zuruecksetzen
W1="w1$MARKE"
ERSTE="Erste Aufgabe $MARKE"
AUS="$(pi "$W1" claude-haiku45 "$TESTHOME/arbeit" "$ERSTE")"; RC=$?
case "$AUS" in
  *"Submission verifiziert"*) ok "1: die erste Zustellung kam an" ;;
  *) bad "1: erste Zustellung nicht verifiziert, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
PANE1="$(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk -v w="$W1" '$2==w{print $1}')"
if [ -z "$PANE1" ]; then
  bad "1: kein Pane fuer '$W1' gefunden -- der Rest von Fall 1 wird uebersprungen"
else
  # Liegengebliebener Text, wie er heute Nacht vor einem zweiten Versuch stand --
  # getippt, nicht eingefuegt (tmux send-keys ohne -p), kein Enter danach.
  MUELL="REST-VOM-ERSTEN-VERSUCH-$MARKE"
  tmux -L "$SOCKET" send-keys -l -t "$PANE1" "$MUELL"
  sleep 1
  VOR="$(tmux -L "$SOCKET" capture-pane -p -t "$PANE1" | grep -F "$MUELL" || true)"
  if [ -z "$VOR" ]; then
    bad "1: der liegengebliebene Text steht nicht mal VOR dem Test in der Box -- Vorbedingung nicht hergestellt"
  else
    ok "1: Vorbedingung hergestellt -- '$MUELL' steht vor dem zweiten Auftrag in der Eingabezeile"
  fi
  zaehler_zuruecksetzen
  ZWEITE="Zweite Aufgabe $MARKE"
  AUS="$(pi "$W1" claude-haiku45 "$TESTHOME/arbeit" "$ZWEITE")"; RC=$?
  case "$AUS" in
    *"Submission verifiziert"*) ok "1: der zweite Auftrag gilt trotz liegengebliebenem Text als abgeschickt" ;;
    *) bad "1: zweite Zustellung nicht verifiziert, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
  esac
  [ "$(c_u_gesendet)" -ge 1 ] \
    && ok "1: C-u wurde vor dem Einfuegen gesendet" \
    || bad "1: kein C-u in der Tastenreihe gefunden"
  LETZT="$(letzter_text)"
  case "$LETZT" in
    *"$MUELL"*)
      bad "1: der liegengebliebene Text ('$MUELL') ist in den zweiten Auftrag hineingerutscht -- genau die Vermischung, die C-u verhindern soll"
      ;;
    *)
      ok "1: der liegengebliebene Text ist NICHT in den zweiten Auftrag hineingerutscht"
      ;;
  esac
  case "$LETZT" in
    *"$ZWEITE"*) ok "1: der zweite Auftragstext kam wortgleich an" ;;
    *) bad "1: der zweite Auftragstext fehlt oder ist veraendert im tatsaechlich abgeschickten Text"; printf '      | %s\n' "$LETZT" ;;
  esac
fi

# ── 2: ein langer Auftrag wird zur Datei mit kurzem Zeiger ──────────────────────
echo
echo "-- 2: Auftrag jenseits der Schwelle (1200 Zeichen) -- Datei statt Inline-Text --"
aufraeumen
zaehler_zuruecksetzen
LANGTEXT="$(python3 -c "print(('Ein Satz mit Pfaden wie $HOME/AI/projekt und Befehlen wie \`wb-state settings get x\`. ' * 30).strip())")"
LAENGE=${#LANGTEXT}
if [ "$LAENGE" -le 1200 ]; then
  bad "2: Testtext ist nur $LAENGE Zeichen lang -- unter der Schwelle, kein aussagekraeftiger Fall"
else
  ok "2: Testtext ist $LAENGE Zeichen lang -- ueber der 1200-Zeichen-Schwelle"
fi
W2="w2$MARKE"
AUS="$(pi "$W2" claude-haiku45 "$TESTHOME/arbeit" "$LANGTEXT")"; RC=$?
case "$AUS" in
  *"in eine Datei geschrieben"*) ok "2: pi-worker meldet die Umleitung in eine Datei" ;;
  *) bad "2: keine Meldung ueber eine Dateiumleitung"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
case "$AUS" in
  *"Submission verifiziert"*) ok "2: die Zustellung (des Zeigers) gilt als abgeschickt" ;;
  *) bad "2: keine Verifikation, rc=$RC" ;;
esac
LETZT="$(letzter_text)"
case "$LETZT" in
  *"Read "*"and work through it."*) ok "2: im Pane stand nur der kurze Zeigersatz" ;;
  *) bad "2: im Pane stand kein Zeigersatz"; printf '      | %s\n' "$LETZT" ;;
esac
if printf '%s' "$LETZT" | grep -qF "$LANGTEXT"; then
  bad "2: der lange Auftragstext stand trotzdem inline im Pane -- die Schwelle griff nicht"
else
  ok "2: der lange Auftragstext stand NICHT inline im Pane"
fi
AUFTRAGSDATEI="$(ls -t "$TESTHOME/.pi-workers/results/$W2/"*.auftrag.txt 2>/dev/null | head -1)"
if [ -z "$AUFTRAGSDATEI" ]; then
  bad "2: keine .auftrag.txt-Datei fuer '$W2' gefunden"
elif diff -q <(printf '%s' "$LANGTEXT") "$AUFTRAGSDATEI" >/dev/null 2>&1; then
  ok "2: die Datei traegt den Original-Auftrag wortgleich (byte-fuer-byte)"
else
  bad "2: die Datei weicht vom Original-Auftragstext ab"
fi

# ── 3: ein kurzer Auftrag bleibt weiterhin inline (Gegenprobe zu Fall 2) ────────
echo
echo "-- 3: kurzer Auftrag (deutlich unter der Schwelle) bleibt inline --"
aufraeumen
zaehler_zuruecksetzen
KURZ="Pruefe die Logdatei und melde den letzten Fehler. $MARKE"
W3="w3$MARKE"
AUS="$(pi "$W3" claude-haiku45 "$TESTHOME/arbeit" "$KURZ")"; RC=$?
case "$AUS" in
  *"in eine Datei geschrieben"*) bad "3: ein kurzer Auftrag wurde faelschlich in eine Datei umgeleitet" ;;
  *) ok "3: kein Umweg ueber eine Datei fuer einen kurzen Auftrag" ;;
esac
LETZT="$(letzter_text)"
case "$LETZT" in
  *"$KURZ"*) ok "3: der kurze Auftragstext kam weiterhin direkt (inline) an" ;;
  *) bad "3: der kurze Auftragstext fehlt im tatsaechlich abgeschickten Text"; printf '      | %s\n' "$LETZT" ;;
esac

# ── 4: eine gescheiterte Zustellung hinterlaesst keinen "laeuft"-Platzhalter ────
echo
echo "-- 4: Zustellung scheitert -- kein Platzhalter, der wie Arbeit aussieht --"
aufraeumen
zaehler_zuruecksetzen
cp "$TESTHOME/.local/bin/claude-hart" "$TESTHOME/.local/bin/claude"
W4="w4$MARKE"
AUS="$(pi "$W4" claude-haiku45 "$TESTHOME/arbeit" "Vierte Aufgabe $MARKE")"; RC=$?
case "$AUS" in
  *"FEHLER: Prompt haengt"*) ok "4: der Fehlschlag wird gemeldet" ;;
  *) bad "4: kein Fehlschlag gemeldet"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
[ "$RC" -ne 0 ] && ok "4: Exit-Code ungleich 0 ($RC)" || bad "4: Exit-Code 0 trotz gescheiterter Zustellung"
RESDIR4="$TESTHOME/.pi-workers/results/$W4"
RES4="$(readlink -f "$RESDIR4/latest.md" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$RESDIR4/latest.md")"
if [ -z "$RES4" ] || [ ! -s "$RES4" ]; then
  bad "4: latest.md zeigt auf keine gefuellte Datei -- ein Aufrufer wuerde bis zur eigenen Deadline auf ein Ergebnis warten, das nie kommt"
else
  ok "4: latest.md zeigt auf eine gefuellte Datei -- eine Warteschleife (\"until [ -s \$RES ]\") bekaeme sofort ihr Ergebnis"
fi
case "$(basename "${RES4:-}")" in
  .laufend.md) bad "4: latest.md zeigt IMMER NOCH auf den Platzhalter '.laufend.md'" ;;
  *) ok "4: latest.md zeigt nicht mehr auf den '.laufend.md'-Platzhalter, sondern auf ein echtes Ergebnis" ;;
esac
if [ -n "${RES4:-}" ] && grep -q "Zustellung an .* fehlgeschlagen" "$RES4" 2>/dev/null; then
  ok "4: das Ergebnis benennt sich selbst ehrlich als fehlgeschlagene Zustellung"
else
  bad "4: das Ergebnis nennt keinen Zustellungs-Fehlschlag"
fi
if [ -n "${RES4:-}" ] && grep -q 'laeuft' "$RES4" 2>/dev/null; then
  bad "4: das Ergebnis behauptet trotzdem irgendwo 'laeuft' -- sieht wie ein arbeitender Worker aus"
else
  ok "4: das Ergebnis behauptet nirgends, ein Worker 'laeuft'"
fi
if [ -e "$RESDIR4/.laufend.md" ]; then
  bad "4: .laufend.md liegt trotz gescheiterter Zustellung immer noch da (Nachtrag: nicht nur latest.md muss umgebogen sein, die Datei selbst muss weg)"
else
  ok "4: .laufend.md ist entfernt, nicht nur latest.md umgebogen"
fi

# ── 5: eine TAUBE TUI (nimmt ueberhaupt keine Taste an) wird ehrlich gemeldet ───
echo
echo "-- 5: TUI nimmt gar keine Taste mehr an (haerterer Fall als 4) -- ehrlicher Fehlschlag --"
aufraeumen
zaehler_zuruecksetzen
cp "$TESTHOME/.local/bin/claude-taub" "$TESTHOME/.local/bin/claude"
W5="w5$MARKE"
AUS="$(pi "$W5" claude-haiku45 "$TESTHOME/arbeit" "Fuenfte Aufgabe $MARKE")"; RC=$?
[ "$RC" -ne 0 ] && ok "5: Exit-Code ungleich 0 ($RC) -- kein falscher Erfolg trotz taubem Pane" || bad "5: Exit-Code 0 trotz taubem Pane"
case "$AUS" in
  *"Submission verifiziert"*) bad "5: es wird trotzdem eine Verifikation behauptet" ;;
  *) ok "5: keine Erfolgsbehauptung" ;;
esac
RESDIR5="$TESTHOME/.pi-workers/results/$W5"
RES5="$(readlink -f "$RESDIR5/latest.md" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$RESDIR5/latest.md")"
if [ -n "${RES5:-}" ] && grep -q "Zustellung an .* fehlgeschlagen" "$RES5" 2>/dev/null; then
  ok "5: auch der taube Fall endet in einem ehrlichen, sofort sichtbaren Ergebnis"
else
  bad "5: kein ehrliches Ergebnis fuer den tauben Fall"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8
fi
if [ -e "$RESDIR5/.laufend.md" ]; then
  bad "5: .laufend.md liegt auch im tauben Fall noch da"
else
  ok "5: .laufend.md ist auch im tauben Fall entfernt"
fi

# ── 6: Erfolgspfad -- .laufend.md verschwindet, sobald das Ergebnis steht ──────
echo
echo "-- 6: Erfolgspfad -- .laufend.md verschwindet, sobald ein echtes Ergebnis dasteht --"
aufraeumen
zaehler_zuruecksetzen
# claude auf 'korrekt' zurueckstellen -- Fall 5 hat es zuletzt auf 'taub' gesetzt.
cat > "$TESTHOME/.local/bin/claude" <<SHIMEOF
#!/bin/sh
FAKE_KIND=korrekt FAKE_PROMPT='❯' FAKE_BUSY=0 FAKE_LOG='$AGENTLOG' exec /usr/bin/python3 "$FAKE"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"
W6="w6$MARKE"
AUS="$(pi "$W6" claude-haiku45 "$TESTHOME/arbeit" "Sechste Aufgabe $MARKE")"; RC=$?
case "$AUS" in
  *"Submission verifiziert"*) ok "6: die Zustellung kam an" ;;
  *) bad "6: keine Verifikation, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
RESDIR6="$TESTHOME/.pi-workers/results/$W6"
if [ ! -e "$RESDIR6/.laufend.md" ]; then
  bad "6: .laufend.md fehlt schon VOR der eigentlichen Fertigstellung -- Vorbedingung nicht hergestellt"
else
  ok "6: Vorbedingung -- .laufend.md steht, solange der (simulierte) Worker noch arbeitet"
fi
# pi-worker LEGT $RES nie selbst an (das tut erst der wirkliche Worker in der
# Pane) -- ein Glob auf existierende Dateien faende hier nichts. Der Pfad steht
# stattdessen in pi-workers eigener Meldung ("Ergebnis-Datei: <Pfad> (...)").
RES6="$(printf '%s\n' "$AUS" | sed -n 's/^Ergebnis-Datei: \([^ ]*\) .*/\1/p' | head -1)"
if [ -z "$RES6" ]; then
  bad "6: keine Ergebnis-Datei-Meldung von pi-worker fuer '$W6' gefunden"
else
  # Simuliert, was der ECHTE Worker irgendwann selbst tut: sein Ergebnis schreiben.
  printf '# Ergebnis\n\nWHAT: erledigt.\n' > "$RES6"
  ok "6: simuliertes Ergebnis geschrieben ($RES6)"
  d=$((SECONDS + 20))
  while [ $SECONDS -lt $d ] && [ -e "$RESDIR6/.laufend.md" ]; do sleep 1; done
  if [ -e "$RESDIR6/.laufend.md" ]; then
    bad "6: .laufend.md steht auch 20s nach dem fertigen Ergebnis noch da -- der Sechs-Stunden-Beobachter hat es nicht entfernt"
  else
    ok "6: .laufend.md ist verschwunden, sobald das echte Ergebnis stand"
  fi
  # -ef statt Zeichenkettenvergleich: /var vs /private/var (macOS-Symlink) waere
  # sonst ein falscher Fehlschlag trotz identischer Datei.
  if [ "$RESDIR6/latest.md" -ef "$RES6" ]; then
    ok "6: latest.md zeigt auf das echte Ergebnis"
  else
    ZIEL6="$(readlink -f "$RESDIR6/latest.md" 2>/dev/null)"
    bad "6: latest.md zeigt nicht auf das echte Ergebnis (zeigt auf '$ZIEL6')"
  fi
fi

# ── die echte Umgebung blieb unberuehrt ─────────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
UEBRIG=0
for n in "w1$MARKE" "w2$MARKE" "w3$MARKE" "w4$MARKE" "w5$MARKE" "w6$MARKE"; do
  [ -e "$ECHTHOME/.pi-workers/results/$n" ] && UEBRIG=$((UEBRIG+1))
done
[ "$UEBRIG" -eq 0 ] \
  && ok "kein Ergebnisordner unter dem echten HOME" \
  || bad "$UEBRIG Ergebnisordner im ECHTEN ~/.pi-workers -- Testisolation gebrochen"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
