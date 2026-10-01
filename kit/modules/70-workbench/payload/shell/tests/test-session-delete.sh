#!/usr/bin/env bash
# Tests fuer wb-session-delete — vor allem der Nachweis, dass ein Loeschlauf
# NICHTS ausserhalb der einen Session anfasst.
#
# Alles laeuft unter einem WEGWERF-HOME (HOME=$(mktemp -d)). Das Werkzeug bildet
# jeden Pfad aus $HOME, damit sieht es ausschliesslich die hier angelegte
# Attrappe — die echten Zustandsdateien, der echte Kbase und die echten
# Transkripte unter dem richtigen $HOME bleiben unerreichbar. tmux wird in dieser
# Datei bewusst nicht benutzt: die tmux-Seite haengt an wb-session-close, das
# seine eigenen Tests auf eigenem Socket hat.
unset TMUX TMUX_PANE
set -uo pipefail

# Quelle der Wahrheit ist das Repo, nicht die installierte Kopie (siehe
# WB_SESSION_CLOSE-Regel in test-session-close.sh) — Override bleibt moeglich.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_SESSION_DELETE:-$REPO/wb-session-delete}"
[ -x "$TOOL" ] || { echo "  FAIL  $TOOL fehlt oder ist nicht ausfuehrbar"; exit 1; }
echo "Geprueft: $TOOL"

REAL_HOME="$HOME"
FAKE="$(mktemp -d)"
pass=0; fail=0
cleanup() { rm -rf "$FAKE"; }
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
da()      { [ -e "$1" ] && ok "$2" || bad "$2 — fehlt: $1"; }
weg()     { [ -e "$1" ] && bad "$2 — existiert noch: $1" || ok "$2"; }

# --- Attrappe aufbauen -------------------------------------------------------
PROJEKT="$FAKE/AI/Testprojekt"
SLUG="-$(printf '%s' "${PROJEKT#/}" | tr '/' '-')"
CSLUG="$(printf '%s' "$PROJEKT" | tr -c 'a-zA-Z0-9' '-')"
STATE="$FAKE/.claude/workbench/sessions"
PROJ="$FAKE/.claude/projects/$CSLUG"
KBASE="$FAKE/work/brain/20-projects/testprojekt"

mkdir -p "$PROJEKT" "$STATE" "$PROJ" "$KBASE" "$FAKE/.local/bin"
# wb-session-close wird vom Werkzeug unter $HOME/.local/bin erwartet; ohne
# laufende tmux-Session wird es hier nie aufgerufen, muss aber existieren duerfen.
# Quelle Repo, aus demselben Grund wie oben bei TOOL.
cp "$REPO/wb-session-close" "$FAKE/.local/bin/" 2>/dev/null || true

# Die Session, die geloescht werden soll.
cat > "$STATE/$SLUG.json" <<JSON
{ "dir": "$PROJEKT", "name": "Testprojekt", "tmuxSession": "wb-Testprojekt-aaaaaa",
  "claudeSessionId": "11111111-1111-1111-1111-111111111111",
  "workers": [ { "name": "w1" }, { "name": "w2" } ] }
JSON
echo '{"type":"user"}' > "$PROJ/11111111-1111-1111-1111-111111111111.jsonl"

# Eine ZWEITE Session desselben Ordners — sie muss unangetastet bleiben.
cat > "$STATE/${SLUG}__9f2a1c.json" <<JSON
{ "dir": "$PROJEKT", "sessionKey": "9f2a1c", "name": "Testprojekt2",
  "tmuxSession": "wb-Testprojekt-aaaaaa-9f2a1c",
  "claudeSessionId": "22222222-2222-2222-2222-222222222222", "workers": [] }
JSON
echo '{"type":"user"}' > "$PROJ/22222222-2222-2222-2222-222222222222.jsonl"

# Eine FREMDE Session eines anderen Ordners.
cat > "$STATE/-Users-fremd-Projekt.json" <<JSON
{ "dir": "/Users/fremd/Projekt", "name": "Fremd", "tmuxSession": "wb-Fremd-bbbbbb", "workers": [] }
JSON

# Kbase, Projektdateien, ein drittes Transkript ohne Bezug.
echo "# Kbase-Notiz, muss bleiben" > "$KBASE/notiz.md"
echo "# Projekt-README, muss bleiben" > "$PROJEKT/README.md"
echo "print('code')" > "$PROJEKT/main.py"
mkdir -p "$PROJEKT/docs"; echo "# doku" > "$PROJEKT/docs/plan.md"
echo '{"type":"user"}' > "$PROJ/33333333-3333-3333-3333-333333333333.jsonl"

lauf() { HOME="$FAKE" "$TOOL" "$@" 2>&1; }

echo "== wb-session-delete =="

# --- 1. Ohne --yes wird nichts geloescht -------------------------------------
echo "-- Bericht ohne --yes --"
OUT="$(lauf --dir "$PROJEKT")"; RC=$?
[ "$RC" = 0 ] && ok "Bericht laeuft durch (rc=0)" || bad "Bericht scheiterte (rc=$RC): $OUT"
case "$OUT" in *"Nichts geloescht"*) ok "sagt ausdruecklich, dass nichts geloescht wurde" ;;
               *) bad "kein Hinweis auf den Trockenlauf: $OUT" ;; esac
da "$STATE/$SLUG.json" "die Zustandsdatei lebt nach dem Bericht noch"
da "$PROJ/11111111-1111-1111-1111-111111111111.jsonl" "das Transkript lebt nach dem Bericht noch"

# --- 2. Falscher Ordner zur Datei -------------------------------------------
echo "-- Schutz gegen einen Fehlgriff --"
# Ein Ordner, zu dem es keine Zustandsdatei gibt. (Frueher stand hier
# '/Users/fremd/Projekt' — dazu GIBT es unten aber eine Attrappe, und das Werkzeug
# hat sie folgerichtig geloescht. Der Testfall war falsch gestellt, nicht das
# Werkzeug; die fremde Session bleibt jetzt das unberuehrte Vergleichsstueck.)
OUT="$(lauf --dir "$FAKE/AI/GibtsNicht" --yes)"; RC=$?
[ "$RC" != 0 ] && ok "Ordner ohne Zustandsdatei: verweigert" \
               || bad "Ordner ohne Zustandsdatei wurde nicht abgelehnt: $OUT"
OUT="$(lauf --dir "$PROJEKT" --key ZZZZZZ --yes)"; RC=$?
[ "$RC" != 0 ] && ok "unsinniger sessionKey: verweigert" || bad "unsinniger Schluessel akzeptiert: $OUT"
da "$STATE/-Users-fremd-Projekt.json" "die fremde Zustandsdatei ist unberuehrt"

# --- 3. Der eigentliche Loeschlauf ------------------------------------------
echo "-- Loeschlauf mit --yes --"
OUT="$(lauf --dir "$PROJEKT" --yes)"; RC=$?
[ "$RC" = 0 ] && ok "Loeschlauf endet mit rc=0" || bad "Loeschlauf scheiterte (rc=$RC): $OUT"
weg "$STATE/$SLUG.json" "die Zustandsdatei der Session ist weg"
weg "$PROJ/11111111-1111-1111-1111-111111111111.jsonl" "das Transkript dieser Session ist weg"

echo "-- was unberuehrt bleiben MUSS --"
da "$STATE/${SLUG}__9f2a1c.json" "die zweite Session desselben Ordners"
da "$PROJ/22222222-2222-2222-2222-222222222222.jsonl" "ihr Transkript"
da "$STATE/-Users-fremd-Projekt.json" "die Session eines fremden Ordners"
da "$PROJ/33333333-3333-3333-3333-333333333333.jsonl" "ein drittes, unbeteiligtes Transkript"
da "$KBASE/notiz.md" "die Kbase-Notiz"
da "$PROJEKT/README.md" "die README des Projekts"
da "$PROJEKT/main.py" "eine Quelldatei des Projekts"
da "$PROJEKT/docs/plan.md" "eine Markdown-Datei im Projekt"
da "$PROJEKT" "der Projektordner selbst"
da "$FAKE/work/brain" "der Kbase-Ordner"

# Zaehlen statt nur stichprobenartig schauen: ausser den beiden Dateien der
# geloeschten Session darf sich nichts veraendert haben.
uebrig_state="$(ls "$STATE" | wc -l | tr -d ' ')"
[ "$uebrig_state" = 2 ] && ok "im Sessionverzeichnis stehen noch genau die 2 anderen Zustandsdateien" \
                        || { bad "im Sessionverzeichnis stehen $uebrig_state Dateien (erwartet 2)"; ls "$STATE"; }
uebrig_proj="$(ls "$PROJ" | wc -l | tr -d ' ')"
[ "$uebrig_proj" = 2 ] && ok "im Projektverzeichnis stehen noch genau die 2 anderen Transkripte" \
                       || bad "im Projektverzeichnis stehen $uebrig_proj Transkripte (erwartet 2)"

echo "-- Sicherung --"
SNAP="$(printf '%s\n' "$OUT" | sed -n 's/^Gesichert in: //p')"
[ -n "$SNAP" ] && ok "der Lauf nennt den Sicherungsort" || bad "kein Sicherungsort genannt: $OUT"
da "$SNAP/$SLUG.json" "die Zustandsdatei liegt in der Sicherung"
da "$SNAP/11111111-1111-1111-1111-111111111111.jsonl" "das Transkript liegt in der Sicherung"
da "$SNAP/README.md" "die Sicherung erklaert, wie man zurueckkommt"

# --- 4. Eine Session ohne claudeSessionId loescht kein Transkript ------------
echo "-- Session ohne Transkript-Id --"
cat > "$STATE/$SLUG.json" <<JSON
{ "dir": "$PROJEKT", "name": "OhneId", "tmuxSession": "wb-x-cccccc", "workers": [] }
JSON
OUT="$(lauf --dir "$PROJEKT" --yes)"
case "$OUT" in *"KEIN Transkript"*) ok "sagt, dass ohne Id kein Transkript geloescht wird" ;;
               *) bad "keine Aussage zur fehlenden Id: $OUT" ;; esac
uebrig_proj="$(ls "$PROJ" | wc -l | tr -d ' ')"
[ "$uebrig_proj" = 2 ] && ok "ohne Id bleibt jedes Transkript stehen" \
                       || bad "ohne Id wurden Transkripte angefasst ($uebrig_proj statt 2)"

# --- 4b. Mit LEBENDER tmux-Session, ohne --force ----------------------------
# Bis zum 2026-08-16 lief dieser Weg auf der Bash des Shebangs (macOS 3.2.57)
# ueberhaupt nicht: `CLOSE_ARGS=()` ist dort unter `set -u` beim Entfalten ein
# Fehler ("unbound variable"), und der Abbruch kam VOR jedem Loeschen. Die
# Suite hat es nie gemerkt, weil ihre Faelle keine lebende tmux-Session haben
# und der Zweig deshalb nie erreicht wurde. Eigener Socket, eigener HOME.
echo "-- lebende tmux-Session, ohne --force --"
# Attrappen statt echter Server: das Werkzeug fragt `tmux has-session` OHNE
# `-L`, landet also auf dem Standard-Socket. Ein echter Testsocket wuerde
# deshalb nie gefunden und der ganze Zweig uebersprungen — genau daran ist eine
# erste Fassung dieses Falls stillschweigend vorbeigelaufen.
BIN="$FAKE/.local/bin"; mkdir -p "$BIN"
cat > "$BIN/tmux" <<'STUB'
#!/bin/bash
# Nur so viel tmux, wie dieser Weg braucht: die Basis-Session lebt, ihre Sicht
# nicht. Alles andere meldet Erfolg und schweigt.
case "$1 $2" in
  "has-session -t")
    case "$3" in
      *-view) exit 1 ;;
      *)      exit 0 ;;
    esac ;;
esac
exit 0
STUB
chmod 755 "$BIN/tmux"
cat > "$BIN/wb-session-close" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/close-args.log"
exit 0
STUB
chmod 755 "$BIN/wb-session-close"
cat > "$STATE/$SLUG.json" <<JSON
{ "dir": "$PROJEKT", "name": "MitTmux", "tmuxSession": "wb-x-dddddd", "claudeSessionId": "44444444-4444-4444-4444-444444444444", "workers": [] }
JSON
: > "$PROJ/44444444-4444-4444-4444-444444444444.jsonl"
OUT="$(PATH="$BIN:$PATH" HOME="$FAKE" "$TOOL" --dir "$PROJEKT" --yes 2>&1)"; RC=$?
case "$OUT" in
  *"unbound variable"*) bad "4b: bricht mit 'unbound variable' ab (leeres CLOSE_ARGS unter set -u)" ;;
  *) ok "4b: kein 'unbound variable' auf dem Weg ohne --force" ;;
esac
[ -s "$FAKE/close-args.log" ] && ok "4b: wb-session-close wurde ueberhaupt aufgerufen (der Zweig wird erreicht)" \
                              || bad "4b: wb-session-close nie aufgerufen — der Zweig wurde uebersprungen, die Zusage prueft nichts"
[ "$RC" = 0 ] && ok "4b: der Lauf endet mit rc=0" || bad "4b: unerwarteter Rueckgabewert rc=$RC — $OUT"
rm -f "$BIN/tmux" "$BIN/wb-session-close" "$FAKE/close-args.log"

# --- 5. Der echte $HOME wurde nie beruehrt ----------------------------------
echo "-- Live-Umgebung --"
[ -d "$REAL_HOME/.claude/workbench/sessions" ] && ok "das echte Sessionverzeichnis existiert unveraendert weiter" \
                                               || bad "das echte Sessionverzeichnis fehlt"

echo
echo "wb-session-delete: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
