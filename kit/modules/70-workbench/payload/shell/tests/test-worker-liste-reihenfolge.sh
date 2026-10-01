#!/usr/bin/env bash
# test-worker-liste-reihenfolge.sh -- ein aktualisierter Worker bleibt an
# seinem Platz, statt ans Ende der Liste zu springen.
#
# BEFUND VOM 22.08. ~21:15 (der Nutzer: "die Worker-Tabs... springen auf und
# ab"), gemessen an 40 Sekunden byteweise verglichener Aufnahmen der rechten
# Leiste (drei Zustaende, monoton A->C->B, kein Flackern): zwischen zwei
# Aufnahmen wanderte ein bereits laufender Worker in der Liste nach unten,
# ein anderer nach oben -- ohne dass ein Worker verschwunden oder neu
# hinzugekommen waere.
#
# ROOT CAUSE: `wb-state add-worker` filterte den bestehenden Eintrag beim
# Aktualisieren heraus (z.B. der verzoegerte claudeSessionId-Fund aus
# shell/pi-worker, record_worker_conversation) und haengte den neuen Eintrag
# ans ENDE von workers[] an. app/src/renderer/renderer.ts (zeichneRechts)
# zeigt Worker exakt in Array-Reihenfolge, ohne eigene Sortierung -- jede
# Aktualisierung eines laufenden Workers schob ihn damit sichtbar ans Ende
# und alles dazwischen eine Position nach oben.
#
# Dieser Test ist die REALE Zusage, kein Existenz-Check: er ruft add-worker
# zweimal fuer denselben Namen (Registrierung, dann Aktualisierung wie beim
# claudeSessionId-Fund) und MISST die tatsaechliche Reihenfolge der
# workers[]-Namen danach -- nicht nur, dass der Worker noch irgendwo steht.
#
# ISOLATION: eigenes HOME (mktemp -d), kein tmux noetig (add-worker braucht
# nur eine bestehende Zustandsdatei, siehe wb-state touch), COPY des
# Repo-Skripts statt Symlink (M7-Lehre aus test-registry.sh: ein Edit
# waehrend des Laufs darf den laufenden Test nicht mitaendern).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
WBS="$BIN/wb-state"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== Worker-Reihenfolge bleibt stabil bei einer Aktualisierung (HOME $TESTHOME) =="

DIR="$TESTHOME/work"
SESS="wb-reihenfolgetest"
"$WBS" touch "$DIR" "$SESS" >/dev/null

# Vier Worker in bekannter Reihenfolge anlegen -- so wie ein Dutzend
# Agenten nacheinander gespawnt werden.
for n in erste zweite dritte vierte; do
  "$WBS" add-worker "$n" claude sonnet "$DIR" "$SESS" >/dev/null
done

STATEFILE="$(ls "$TESTHOME"/.claude/workbench/sessions/*.json 2>/dev/null | head -1)"
[ -n "$STATEFILE" ] || { bad "keine Zustandsdatei unter .claude/workbench/sessions/ angelegt -- Test kann nicht messen"; echo; echo "  bestanden: $pass, fehlgeschlagen: $fail"; exit 1; }

namen_in_reihenfolge() {
  python3 -c "import json,sys; print(','.join(w['name'] for w in json.load(open(sys.argv[1]))['workers']))" "$STATEFILE"
}

VOR="$(namen_in_reihenfolge)"
if [ "$VOR" = "erste,zweite,dritte,vierte" ]; then
  ok "vier neu angelegte Worker stehen in Anlegereihenfolge: $VOR"
else
  bad "Anlegereihenfolge schon falsch, bevor ueberhaupt aktualisiert wurde: $VOR"
fi

SPAWN_ZWEITE_VORHER="$(python3 -c "import json; w=[x for x in json.load(open('$STATEFILE'))['workers'] if x['name']=='zweite'][0]; print(w['spawnedAt'])")"
sleep 1.1   # spawnedAt hat Sekunden-Aufloesung -- ohne Abstand kann now==alt sein und der Test sagt nichts

# 'zweite' wird aktualisiert -- genau der Fall aus pi-worker's
# record_worker_conversation, das die claudeSessionId nachtraegt, nachdem
# das Transcript aufgetaucht ist. Der Worker selbst laeuft unveraendert
# weiter, nur ein Feld kommt hinzu.
"$WBS" add-worker zweite claude sonnet "$DIR" "$SESS" --claude-session "abc123" >/dev/null

NACH="$(namen_in_reihenfolge)"
if [ "$NACH" = "erste,zweite,dritte,vierte" ]; then
  ok "nach der Aktualisierung von 'zweite' bleibt die Reihenfolge unveraendert: $NACH"
else
  bad "Reihenfolge hat sich durch eine reine Aktualisierung veraendert -- $VOR wurde zu $NACH (die Leiste wuerde hier springen)"
fi

CSESS_NACH="$(python3 -c "import json; w=[x for x in json.load(open('$STATEFILE'))['workers'] if x['name']=='zweite'][0]; print(w.get('claudeSessionId',''))")"
if [ "$CSESS_NACH" = "abc123" ]; then
  ok "die neue claudeSessionId kam trotzdem an -- die Reihenfolge steht fest, der Inhalt wird weiter aktualisiert"
else
  bad "claudeSessionId wurde nicht uebernommen (erwartet abc123, war '$CSESS_NACH')"
fi

SPAWN_ZWEITE_NACHHER="$(python3 -c "import json; w=[x for x in json.load(open('$STATEFILE'))['workers'] if x['name']=='zweite'][0]; print(w['spawnedAt'])")"
if [ "$SPAWN_ZWEITE_NACHHER" = "$SPAWN_ZWEITE_VORHER" ]; then
  ok "spawnedAt von 'zweite' bleibt der urspruengliche Zeitpunkt, nicht der der Aktualisierung"
else
  bad "spawnedAt wurde auf den Aktualisierungszeitpunkt zurueckgesetzt ($SPAWN_ZWEITE_VORHER -> $SPAWN_ZWEITE_NACHHER) -- ein 'nach Startzeitpunkt sortieren' waere darauf keine stabile Reparatur"
fi

# Ein WIRKLICH neuer Worker haengt weiter unten an -- das ist kein Springen,
# sondern der einzige Fall, in dem sich die Reihenfolge aendern SOLL.
"$WBS" add-worker fuenfte claude sonnet "$DIR" "$SESS" >/dev/null
LETZTE="$(namen_in_reihenfolge)"
if [ "$LETZTE" = "erste,zweite,dritte,vierte,fuenfte" ]; then
  ok "ein echter Neuzugang haengt ans Ende an: $LETZTE"
else
  bad "ein echter Neuzugang landet nicht wie erwartet am Ende: $LETZTE"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
