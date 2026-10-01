#!/usr/bin/env bash
# test-pi-worker-auftragsbuch.sh -- pi-worker fuehrt Buch darueber, WELCHER
# Auftrag gerade laeuft und welche Ergebnisdatei zu ihm gehoert.
#
# ANLASS (05.08.): "Fertig" ist eine Eigenschaft des AUFTRAGS, nicht der Datei.
# Der Worker `schrift` bekam seine zweite Aufgabe als Nachricht in den
# bestehenden Pane. Von aussen unterschied danach nichts mehr "Auftrag 2 fertig"
# von "Auftrag 1 nachgebessert" -- eine Fertigmeldung forderte dazu auf, einen
# arbeitenden Worker zu schliessen. Wer eine Aufgabe in einen Pane schickt, haelt
# seitdem fest, welcher Auftrag das ist.
#
# DIE VIER AUSSAGEN:
#   1  Ein Auftrag schreibt eine Zeile in `<results>/<name>/auftraege.tsv`, mit
#      Zeitpunkt, Ergebnisdatei, Pane, Harness und Modell.
#   2  Ein ZWEITER Auftrag an denselben Worker -- gleicher Name, gleicher, noch
#      lebender Pane, KEIN neuer Spawn -- schreibt eine zweite Zeile mit einem
#      EIGENEN Ergebnispfad. Genau das fehlte.
#   3  `latest.md` zeigt danach (ueber den Platzhalter, siehe unten) auf die Datei
#      des zweiten Auftrags.
#
# ANGEPASST 2026-08-16 (Symlink-Falle): `latest.md` zeigt waehrend der Laufzeit auf
# einen lesbaren Platzhalter (`.laufend.md`), nicht mehr direkt auf die (hier nie
# geschriebene) Ergebnisdatei -- sonst war ein haengender Symlink von "nie
# gespawnt" nicht zu unterscheiden. Aussage 3 prueft deshalb, dass der Platzhalter
# selbst den richtigen Zielpfad NENNT, nicht dass `latest.md` ihn direkt IST.
#   4  Die Spalte `spawned` unterscheidet den ersten Auftrag (neuer Pane) vom
#      zweiten (wiederverwendeter Pane).
#
# KEIN ECHTER AGENT LAEUFT HIER. Auf dem PATH liegt ein Schirm, der `claude`
# durch `cat` ersetzt: der Pane lebt, nimmt Text entgegen und fuehrt nichts aus.
# Geprueft wird die Buchfuehrung von pi-worker, nicht das Verhalten eines
# Modells -- und es werden keine Tokens verbrannt.
#
# ISOLATION: eigener tmux-Socket, eigenes HOME (Registry, Ergebnisse, Zustand
# liegen alle darunter), eigene Modell-Registry. Keine Live-Session, kein
# ~/.pi-workers des Menschen, kein Netz. `trap` raeumt ab, auch bei Abbruch.
# Alle Namen entstehen zur Laufzeit aus einer Kennung, die es vor dem Lauf
# nirgends gab -- ein Erkenner passt nicht auf seine eigene Beschreibung.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-auftragsbuch-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="a$(date +%s)$$$RANDOM"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

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
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== pi-worker fuehrt Auftragsbuch (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"

# --- Die Testumgebung, vollstaendig selbst hergestellt ---------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

# tmux des Prueflings auf den Testsocket nageln -- pi-worker ruft es ungeflaggt.
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent. Er muss zwei Dinge tun, damit pi-worker ueberhaupt bis zum
# Senden kommt: einmal das Bereitschaftszeichen des claude-Harness zeigen
# (readyPattern) und danach eine leere Eingabezeile stehen lassen, an der die
# Submissionspruefung sieht, dass der Task abgeschickt wurde (promptPattern
# '^❯'). `stty -echo`, damit der eingefuegte Text die Zeile nicht fuellt und
# faelschlich wie ein haengender Prompt aussieht. Er fuehrt NICHTS aus, gibt den
# empfangenen Text aber echoend weiter (2026-08-17: die Absende-Pruefung belegt
# inzwischen zusaetzlich den INHALT -- ein Schirm, der alles nach /dev/null
# schweigt, sieht fuer diese Pruefung genauso aus wie ein Pane, in dem etwas
# anderes als der Auftrag ankam).
# Der Harness ruft `~/.local/bin/claude` absolut auf -- der Schirm muss also
# dorthin, nicht nur auf den PATH.
cat > "$TESTHOME/.local/bin/claude" <<'SHIMEOF'
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec cat
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"

# Zwei Werkzeuge, die pi-worker im Vorbeigehen ruft und die hier nichts zu tun
# haben: das Umraeumen des Gitters und der Kontext-Waechter. Ohne sie meldet der
# Lauf Rauschen, das mit dem Prueffall nichts zu tun hat.
for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done

# wb-state liegt im Repo; pi-worker ruft es ueber $HOME/.local/bin.
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
chmod +x "$TESTHOME/.local/bin/wb-state"
# Ebenso wb-pane-write: seit dem 06.08. geht JEDER Tastendruck von pi-worker durch
# dieses Werkzeug, und ohne es tippt er nichts mehr -- absichtlich, ein Rueckfall auf
# `tmux send-keys` waere ein Loch. Die ECHTE Fassung, kein Platzhalter: sie entscheidet
# hier mit, und ein Platzhalter wuerde genau die Entscheidung wegnehmen, die zaehlt.
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
chmod +x "$TESTHOME/.local/bin/wb-pane-write" "$TESTHOME/.local/bin/wb-mensch"
# Und wb-rolle, aus demselben Grund die ECHTE Fassung: seit dem 07.08. markiert
# pi-worker den neuen Pane darueber, damit die Rolle nicht nur in der Pane-Option
# steht (die der Bewachte selbst umschreiben konnte), sondern auch im Register, das
# die Guards als zweite Quelle lesen. Ein Platzhalter wuerde genau den Teil
# wegnehmen, der hier gemessen werden soll. Das Modul dahinter liegt bei den Hooks.
cp "$REPO/wb-rolle" "$TESTHOME/.local/bin/wb-rolle"
chmod +x "$TESTHOME/.local/bin/wb-rolle"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

# Vorher-Stand des ECHTEN Rollenregisters. Der Lauf darf es nicht anfassen; ohne
# diese Zahl liesse sich das hinterher nur behaupten.
ECHT_ROLLEN="$HOME/.pi-workers/rollen"
ROLLEN_VORHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"

WORKER="w$MARKE"
ARBEIT="$TESTHOME/arbeit"
RESDIR="$TESTHOME/.pi-workers/results/$WORKER"
BUCH="$RESDIR/auftraege.tsv"

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

# Eine Workbench-Session, in die pi-worker seinen Pane haengen kann.
tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

echo
echo "-- Auftrag 1: neuer Pane --"
AUS1="$(pi "$WORKER" claude-opus5 "$ARBEIT" "Erste Aufgabe $MARKE")"
RC1=$?
if [ ! -s "$BUCH" ]; then
  bad "1: kein Auftragsbuch unter $BUCH (rc=$RC1)"
  printf '%s\n' "$AUS1" | sed 's/^/      | /' | tail -12
else
  ok "1: das Auftragsbuch ist entstanden"
  Z1="$(grep -cv '^#' "$BUCH")"
  [ "$Z1" = "1" ] && ok "1: genau eine Auftragszeile nach dem ersten Auftrag" \
                  || bad "1: $Z1 Auftragszeilen statt 1"
  RES1="$(grep -v '^#' "$BUCH" | tail -1 | cut -f2)"
  SP1="$(grep -v '^#' "$BUCH" | tail -1 | cut -f6)"
  PANE1="$(grep -v '^#' "$BUCH" | tail -1 | cut -f3)"
  case "$RES1" in
    "$RESDIR"/*.md) ok "1: die Zeile nennt die Ergebnisdatei dieses Auftrags ($(basename "$RES1"))" ;;
    *) bad "1: Ergebnisdatei der Zeile ist '$RES1'" ;;
  esac
  [ "$SP1" = "1" ] && ok "1: die Spalte spawned sagt, dass dieser Auftrag den Pane angelegt hat" \
                   || bad "1: spawned='$SP1' statt 1"
  case "$PANE1" in %*) ok "1: die Zeile nennt den Pane ($PANE1)" ;; *) bad "1: Pane der Zeile ist '$PANE1'" ;; esac
  PLATZHALTER1="$(readlink "$RESDIR/latest.md")"
  if [ "$PLATZHALTER1" = "$RESDIR/.laufend.md" ] && grep -qF "$RES1" "$PLATZHALTER1" 2>/dev/null; then
    ok "1: latest.md zeigt auf den Platzhalter, der die Ergebnisdatei dieses Auftrags nennt"
  else
    bad "1: latest.md ($PLATZHALTER1) nennt nicht $RES1"
  fi
  AUFTRAGSDATEI1="${RES1%.md}.auftrag.txt"
  if [ -f "$AUFTRAGSDATEI1" ] && grep -q "Erste Aufgabe $MARKE" "$AUFTRAGSDATEI1"; then
    ok "1: der Auftragstext liegt unter demselben Zeitstempel (V18)"
  else
    bad "1: kein Auftragstext unter '$AUFTRAGSDATEI1' mit dem gesendeten Text"
  fi
  # Die Rolle des neuen Panes -- in BEIDEN Quellen. Der Spawn ist der eine Weg, auf
  # dem eine Rolle legitim entsteht; alles andere lehnt die Hook-Kette ab. Deshalb
  # wird hier nicht nur die Pane-Option geprueft, sondern auch der Registereintrag:
  # ohne ihn faellt die zweite Quelle still aus, und die Sicherung haengt wieder an
  # der Option allein.
  ROLLE1="$(tmux -L "$SOCKET" display -p -t "$PANE1" '#{@wb_role}' 2>/dev/null)"
  [ "$ROLLE1" = worker ] \
    && ok "1: der neue Pane traegt @wb_role=worker" \
    || bad "1: der neue Pane traegt '$ROLLE1' statt worker"
  if HOME="$TESTHOME" "$TESTHOME/.local/bin/wb-rolle" -L "$SOCKET" lesen "$PANE1" 2>/dev/null \
       | grep -q '^register	worker$'; then
    ok "1: pi-worker hat den Pane auch im Rollenregister eingetragen"
  else
    bad "1: kein Registereintrag fuer $PANE1 — die zweite Rollenquelle fehlt"
  fi
  ROLLEN_NACHHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$ROLLEN_NACHHER" = "$ROLLEN_VORHER" ] \
    && ok "1: das ECHTE Rollenregister blieb unberuehrt ($ROLLEN_VORHER Eintraege wie vorher)" \
    || bad "1: der Lauf hat in das echte $ECHT_ROLLEN geschrieben ($ROLLEN_VORHER -> $ROLLEN_NACHHER)"
fi

echo
echo "-- Auftrag 2: DERSELBE Worker, derselbe lebende Pane, kein neuer Spawn --"
# Der Pane muss noch leben, sonst prueft der zweite Teil den Wiederverwendungs-
# weg gar nicht. Erst nachsehen, dann behaupten.
LEBT="$(tmux -L "$SOCKET" list-panes -a -F '#{@wb_worker}' 2>/dev/null | grep -cx "$WORKER")"
[ "$LEBT" -ge 1 ] \
  && ok "2: Voraussetzung: der Pane des Workers lebt noch ($LEBT gefunden)" \
  || bad "2: Voraussetzung verletzt -- kein lebender Pane fuer '$WORKER'"

sleep 1   # damit der Zeitstempel des zweiten Auftrags sicher ein anderer ist
AUS2="$(pi "$WORKER" claude-opus5 "$ARBEIT" "Zweite Aufgabe $MARKE")"
if [ -s "$BUCH" ]; then
  Z2="$(grep -cv '^#' "$BUCH")"
  [ "$Z2" = "2" ] && ok "2: zwei Auftragszeilen -- der zweite Auftrag steht im Buch" \
                  || bad "2: $Z2 Auftragszeilen statt 2"
  RES2="$(grep -v '^#' "$BUCH" | tail -1 | cut -f2)"
  SP2="$(grep -v '^#' "$BUCH" | tail -1 | cut -f6)"
  PANE2="$(grep -v '^#' "$BUCH" | tail -1 | cut -f3)"
  [ "$RES2" != "${RES1:-}" ] \
    && ok "3: der zweite Auftrag hat einen EIGENEN Ergebnispfad ($(basename "$RES2"))" \
    || bad "3: beide Auftraege zeigen auf dieselbe Datei ($RES2)"
  PLATZHALTER2="$(readlink "$RESDIR/latest.md")"
  if [ "$PLATZHALTER2" = "$RESDIR/.laufend.md" ] && grep -qF "$RES2" "$PLATZHALTER2" 2>/dev/null; then
    ok "3: latest.md zeigt jetzt auf den Platzhalter, der die Ergebnisdatei des ZWEITEN Auftrags nennt"
  else
    bad "3: latest.md ($PLATZHALTER2) nennt nicht $RES2"
  fi
  [ "$SP2" = "0" ] \
    && ok "4: die Spalte spawned sagt, dass der Pane wiederverwendet wurde" \
    || bad "4: spawned='$SP2' statt 0 -- es wurde offenbar ein neuer Pane angelegt"
  [ "$PANE2" = "${PANE1:-}" ] \
    && ok "4: beide Auftraege nennen denselben Pane" \
    || bad "4: Pane wechselte von '${PANE1:-}' auf '$PANE2'"
  AUFTRAGSDATEI2="${RES2%.md}.auftrag.txt"
  if [ -f "$AUFTRAGSDATEI2" ] && grep -q "Zweite Aufgabe $MARKE" "$AUFTRAGSDATEI2"; then
    ok "3: der zweite Auftragstext liegt unter dem EIGENEN Zeitstempel (V18)"
  else
    bad "3: kein Auftragstext unter '$AUFTRAGSDATEI2' mit dem gesendeten Text"
  fi
  [ "${AUFTRAGSDATEI1:-x}" != "$AUFTRAGSDATEI2" ] \
    && ok "3: beide Auftragstexte liegen in verschiedenen Dateien" \
    || bad "3: beide Auftraege teilen sich dieselbe Auftragsdatei"
else
  bad "2: das Auftragsbuch ist verschwunden"
  printf '%s\n' "$AUS2" | sed 's/^/      | /' | tail -12
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
[ ! -e "$HOME/.pi-workers/results/$WORKER" ] \
  && ok "kein Ergebnisordner fuer '$WORKER' unter dem echten HOME" \
  || bad "es wurde in das ECHTE ~/.pi-workers geschrieben -- Testisolation gebrochen"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
