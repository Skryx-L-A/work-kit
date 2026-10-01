#!/usr/bin/env bash
# test-harness-aider.sh — die Zusagen, die aider am 2026-08-08 bekommen hat.
#
# aider war der letzte Harness mit zwei ungemessenen Feldern: promptIgnore und
# contextPattern. Nachgemessen wurde am 2026-08-08 mit aider 0.86.2 und
# einem lokalen Modell, auf einem eigenen tmux-Socket und mit umgelenktem HOME:
#
#   * Die LEERE Eingabezeile ist genau '>' und bleibt es. Ueber 100 Sekunden alle
#     zwoelf Sekunden abgegriffen, auch mit Steuerzeichen: kein Platzhalter, kein
#     Vorschlag, nichts, was rotiert. Bei codex waren es vier wechselnde Texte —
#     hier gibt es nichts zu ignorieren, und darum steht promptIgnore auf null.
#   * Eine Kontextanzeige hat aider nicht. Die Statuszeile nennt nur die
#     schreibgeschuetzten Dateien, die Zeile nach einer Antwort nennt gesendete und
#     empfangene Token ohne Nenner, und '/tokens' liefert absolute Zahlen ohne
#     Prozentwert, die sofort wieder wegscrollen. Fuer den Vertrag der vierten
#     Quelle (erste Gruppe faengt die Auslastung in Prozent) gibt es nichts.
#   * promptPattern '^>' trennt die Eingabezeile NICHT vom Verlauf: aider wiederholt
#     die abgeschickte Nachricht mit demselben Zeichen, und waehrend das Modell
#     rechnet, ist gar keine Eingabezeile zu sehen. Der echte Spawn meldete deshalb
#     'FEHLER: Prompt haengt nach 3 Versuchen noch in der Inputbox', obwohl aider
#     geantwortet hatte. Das ist eine Zeitfrage, keine Musterfrage — festgehalten,
#     damit niemand sie mit einem erfundenen promptIgnore zuzukleben versucht.
#     NACHTRAG (08.08., spaeter am Tag): die Zeitfrage ist beantwortet. Die
#     Absende-Pruefung wartet jetzt, solange sich der Pane bewegt, und tippt dabei
#     kein weiteres Enter; die Meldung heisst nicht mehr 'nach 3 Versuchen'. Die
#     Zusagen dazu stehen in test-absende-pruefung.sh. Zusage 5 und 6 hier bleiben
#     unveraendert gueltig: sie halten den MESSWERT fest, an dem der Fehlschlag
#     entstand, und die Falle fuer den naechsten promptIgnore-Versuch.
#
# Geprueft wird der ausgelieferte Registry-Stand (shell/models.default.json) gegen
# aufgezeichnete Bildschirme — Fixtures, kein installiertes aider: ein Test haengt
# nie daran, was zufaellig auf der Maschine liegt.
#
#   1  readyPattern trifft alle drei gemessenen Zustaende (Start, beschaeftigt, fertig).
#   2  promptIgnore ist gesetzt und null — gemessen, nicht offen; und die leere
#      Eingabezeile traegt wirklich nichts ausser dem Prompt-Zeichen.
#   3  contextPattern ist null, und die aufgezeichneten Bildschirme geben auch nichts
#      her: keine Prozentzahl, kein Zaehler/Nenner-Paar, kein Balken.
#   4  Wird spaeter doch ein contextPattern nachgetragen, darf es die Token-Zeile und
#      die /tokens-Ausgabe NICHT treffen — das waere die codex-Falle (eine Zahl fangen,
#      die nicht die Auslastung ist).
#   5  Die Absende-Pruefung: das wiederholte Auftragsstueck trifft promptPattern, und
#      es ist die LETZTE Zeile, die es trifft. Genau daran scheitert die Verifikation.
#   6  Ein promptIgnore, das jemand nachtraegt, darf diese Zeile nicht treffen.
#   7  --yes-always ist tragend, nicht bequem: ohne das Flag steht aider bei der
#      gitignore-Frage, und readyPattern trifft diesen Bildschirm nicht.
#   8  Kein trustStore — aider stellt keine Vertrauensfrage (im Gegensatz zu agy/codex).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
REG="$REPO/models.default.json"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-aider-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== test-harness-aider =="
echo "Geprueft: Registry-Stand aus $REG"

# KOPIE, kein Symlink (wie in test-harness-opencode.sh): die Suite prueft einen festen Stand.
cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
cp "$REG" "$TESTHOME/.claude/workbench/models.json"
WBS="$BIN/wb-state"
# Kit: 'models resolve' needs the aider binary; a stand-in, so the suite does not depend on
# an aider installed on the machine that runs it.
printf '#!/bin/sh\nexit 0\n' > "$BIN/aider"; chmod +x "$BIN/aider"; export PATH="$BIN:$PATH"

feld() { /usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "aider")
cur = h
for k in sys.argv[2].split("."):
    cur = (cur or {}).get(k) if isinstance(cur, dict) else None
print("" if cur is None else (json.dumps(cur) if not isinstance(cur, str) else cur))
' "$REG" "$1"; }

# Ob ein Feld ueberhaupt DASTEHT, ist eine andere Frage als sein Wert: ein fehlendes
# Feld heisst "nie gemessen", ein ausdrueckliches null heisst "gemessen, es gibt nichts".
hat_feld() { /usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "aider")
sys.exit(0 if sys.argv[2] in h else 1)
' "$REG" "$1"; }

READY="$(feld readyPattern)"
[ -n "$READY" ] && ok "readyPattern ist gesetzt: $READY" || bad "readyPattern fehlt"

# ── Die aufgezeichneten Bildschirme ──────────────────────────────────────────────────
# Aufgenommen 2026-08-08 mit aider 0.86.2 in tmux-Panes auf eigenem Socket, Wegwerf-HOME,
# einem lokalen Modell (Kit: Name durch openai/qwen3.5-4b ersetzt). Gekuerzt auf die Zeilen, die zur Frage etwas beitragen; die
# Trennlinien sind gestutzt und die Wegwerf-Pfade durch kurze ersetzt — beides aendert an
# keiner der geprueften Eigenschaften etwas.
FIX="$TESTHOME/fix"; mkdir -p "$FIX"

# Zustand 1: frisch gestartet, Eingabezeile leer.
cat >"$FIX/start.txt" <<'EOF'
────────────────────────────────────────────────────────────────────────
Aider v0.86.2
Model: openai/qwen3.5-4b with whole edit format
Git repo: .git with 0 files
Repo-map: using 4096 tokens, auto refresh
Added ../.claude/roles/agent.md to the chat (read-only).
────────────────────────────────────────────────────────────────────────
Readonly: ../.claude/roles/agent.md
>
EOF

# Zustand 2: Auftrag abgeschickt, Modell rechnet. Die vier '>'-Zeilen sind der
# WIEDERHOLTE Auftragstext, keine Eingabezeile — die gibt es hier gerade nicht.
# Darunter drei aufgezeichnete Frames des Spinners.
cat >"$FIX/beschaeftigt.txt" <<'EOF'
────────────────────────────────────────────────────────────────────────
Readonly: ../.claude/roles/agent.md
> Antworte in genau einem Satz mit dem Wort HALLOAIDER. Nichts aendern, keine Datei anlegen.
>
> [Protokoll — immer befolgen] Schreibe dein vollstaendiges Endergebnis als Markdown in die Datei /tmp/w/results/aidertest/20
> 260808-184302.md (WHAT/HOW-verified/OPEN). Antworte danach im Chat, letzte Zeile exakt: DONE

       ░█  Waiting for openai/qwen3.5-4b
    █░     Waiting for openai/qwen3.5-4b
   ░█      Waiting for openai/qwen3.5-4b
EOF

# Zustand 3: Antwort fertig. Die Token-Zeile ist alles, was aider von sich aus ueber
# Verbrauch sagt — gesendet und empfangen, ohne Nenner.
cat >"$FIX/fertig.txt" <<'EOF'
Tokens: 3.0k sent, 243 received.
────────────────────────────────────────────────────────────────────────
Readonly: ../.claude/roles/agent.md
>
EOF

# Die Ausgabe von '/tokens' — die einzige Stelle, an der aider ueberhaupt Zahlen zum
# Kontextfenster nennt. Absolut, ohne Prozentwert, und einmalig auf Zuruf.
cat >"$FIX/tokens.txt" <<'EOF'
> /tokens

Approximate context window usage for openai/qwen3.5-4b, in tokens:

$ 0.0000      450 system messages
$ 0.0000    2,258 ../.claude/roles/agent.md (read-only) /drop to remove
==================
$ 0.0000    2,708 tokens total
          259,436 tokens remaining in context window
          262,144 tokens max context window size
────────────────────────────────────────────────────────────────────────
Readonly: ../.claude/roles/agent.md
>
EOF

# Der Start OHNE --yes-always: aider bleibt bei seiner einzigen Erstfrage stehen.
cat >"$FIX/gitignore-frage.txt" <<'EOF'
────────────────────────────────────────────────────────────────────────
Update git name with: git config user.name "Your Name"
Update git email with: git config user.email "you@example.com"
You can skip this check with --no-gitignore
Add .aider* to .gitignore (recommended)? (Y)es/(N)o [Yes]:
EOF

# 1 — die Bereitschaft. Der Ready-Wait in pi-worker fragt genau so: grep -qE auf den
# gerenderten Pane.
for z in start beschaeftigt fertig; do
  if grep -qE "$READY" "$FIX/$z.txt"; then
    ok "1: readyPattern trifft den Zustand '$z'"
  else
    bad "1: readyPattern '$READY' trifft den Zustand '$z' NICHT"
  fi
done
printf '\n\n   \n\n' >"$FIX/leerer-bildschirm.txt"
grep -qE "$READY" "$FIX/leerer-bildschirm.txt" \
  && bad "1: readyPattern trifft schon den leeren Startbildschirm" \
  || ok "1: readyPattern trifft den leeren Startbildschirm nicht"

# 2 — promptIgnore. Gemessen ist: es gibt nichts zu ignorieren. Das Feld steht deshalb
# ausdruecklich da und ist null; fehlte es, hiesse das "nie gemessen", und die Frage
# wuerde ein drittes Mal gestellt.
if hat_feld promptIgnore; then
  ok "2: promptIgnore steht in der Registry (Frage beantwortet, nicht offen)"
else
  bad "2: promptIgnore fehlt — das liest sich wie 'ungemessen'"
fi
PIGN="$(feld promptIgnore)"
[ -z "$PIGN" ] \
  && ok "2: promptIgnore ist null — aider zeigt keinen Platzhalter" \
  || ok "2: promptIgnore ist gesetzt ($PIGN) — Zusage 6 prueft ihn gegen die Messung"
# Und der Messwert selbst: die leere Eingabezeile traegt NUR das Prompt-Zeichen.
LEER="$(grep -E '^>' "$FIX/start.txt" | tail -1)"
[ "$LEER" = ">" ] \
  && ok "2: die leere Eingabezeile ist genau '>' (Messwert)" \
  || bad "2: Fixture: leere Eingabezeile ist '$LEER' statt '>' — Fixture kaputt"

# 3 — die Kontextanzeige, die es nicht gibt. Geprueft wird mit den EXAKTEN Suchen der
# Kontextwache: Zaehler/Nenner-Paar und Zehnerbalken, beide nur in den letzten fuenf
# Zeilen. Findet dort etwas, waere aider nicht blind — dann waere dieser Test der Ort,
# an dem das auffaellt.
CTX="$(feld contextPattern)"
[ -z "$CTX" ] \
  && ok "3: contextPattern ist null" \
  || ok "3: contextPattern ist gesetzt ($CTX) — Zusage 4 prueft ihn gegen die Messung"
for z in start beschaeftigt fertig tokens; do
  tail5="$(tail -5 "$FIX/$z.txt")"
  paar="$(printf '%s\n' "$tail5" | grep -oE '[0-9]+(\.[0-9]+)?[kKmM]?/[0-9]+(\.[0-9]+)?[kKmM]' | tail -1)"
  [ -z "$paar" ] \
    && ok "3: '$z' — kein Zaehler/Nenner-Paar in den letzten fuenf Zeilen" \
    || bad "3: '$z' — die Kontextwache faende hier '$paar' und wuerde daraus eine Auslastung rechnen"
  balken="$(printf '%s\n' "$tail5" | grep -oE '[▓░]{6,12}' | tail -1)"
  [ -z "$balken" ] \
    && ok "3: '$z' — kein Zehnerbalken in den letzten fuenf Zeilen" \
    || bad "3: '$z' — Balken '$balken' gefunden, die Kontextwache laese daraus einen Prozentwert"
done
# Der Spinner von aider benutzt ein Blockzeichen ('░█') — nah genug am Balkenmuster, dass
# es einer Pruefung wert ist. Gemessen: die Blockzeichen stehen nie in einer Reihe.
grep -qE '[▓░]{6,12}' "$FIX/beschaeftigt.txt" \
  && bad "3: der Spinner bildet doch eine Balken-Reihe — die Kontextwache wuerde ihn ablesen" \
  || ok "3: der Spinner bildet keine Balken-Reihe (░ und █ wechseln sich ab)"
# Und ueberhaupt: nirgends steht eine Prozentzahl.
if grep -qE '[0-9]{1,3}[[:space:]]*%' "$FIX/start.txt" "$FIX/beschaeftigt.txt" "$FIX/fertig.txt" "$FIX/tokens.txt"; then
  bad "3: es gibt doch eine Prozentzahl auf dem Bildschirm — dann ist contextPattern moeglich"
else
  ok "3: keine Prozentzahl auf irgendeinem der vier Bildschirme"
fi

# 4 — die codex-Falle, vorbeugend. Wer spaeter ein contextPattern nachtraegt, muss den
# Vertrag einhalten: die erste Gruppe ist die AUSLASTUNG in Prozent. Auf aiders
# Bildschirmen gibt es nur Zahlen, die etwas anderes bedeuten (empfangene Token, freier
# Rest, Fenstergroesse). Ein Muster, das eine davon faengt, ist schlimmer als keins.
if [ -n "$CTX" ]; then
  for z in fertig tokens; do
    sedx="$(printf 's\001.*%s.*\001\\1\001p' "$CTX")"
    t="$(tail -5 "$FIX/$z.txt" | sed -nE "$sedx" 2>/dev/null | tail -1)"
    if [ -n "$t" ]; then
      bad "4: contextPattern faengt auf '$z' den Wert '$t' — das ist keine Auslastung"
    else
      ok "4: contextPattern faengt auf '$z' nichts"
    fi
  done
else
  ok "4: kein contextPattern gesetzt — es gibt nichts, das die falsche Zahl fangen koennte"
fi

# 5 — der gemessene Befund zur Absendung. Die Verifikation in pi-worker nimmt die LETZTE
# Zeile, die promptPattern trifft. Waehrend aider rechnet, ist das die letzte Zeile des
# wiederholten AUFTRAGS — sie sieht aus wie haengender Text und ist das Gegenteil.
PROMPT="$(feld promptPattern)"
[ -n "$PROMPT" ] && ok "5: promptPattern ist gesetzt: $PROMPT" || bad "5: promptPattern fehlt"
INBOX_BUSY="$(grep -E "$PROMPT" "$FIX/beschaeftigt.txt" | tail -1)"
case "$INBOX_BUSY" in
  *"letzte Zeile exakt: DONE"*)
    ok "5: waehrend der Antwort ist die letzte Treffer-Zeile der Auftragstext (Messwert)" ;;
  *)
    bad "5: Fixture: letzte Treffer-Zeile waehrend der Antwort ist '$INBOX_BUSY'" ;;
esac
# Und genau deshalb schlaegt die Pruefung an: sie sieht Prompt-Zeichen, Abstand, Text.
printf '%s' "$INBOX_BUSY" | grep -qE "${PROMPT}[[:space:]]+[^[:space:]]" \
  && ok "5: die Pruefung haelt diese Zeile fuer haengenden Text — der gemessene Fehlschlag" \
  || bad "5: Fixture bildet den gemessenen Fehlschlag nicht mehr ab"
# Was traegt, ist der Vergleich ohne Wortlaut: ist aider fertig, steht dort wieder das,
# was vor dem Einfuegen dort stand.
VORHER="$(grep -E "$PROMPT" "$FIX/start.txt" | tail -1)"
NACHHER="$(grep -E "$PROMPT" "$FIX/fertig.txt" | tail -1)"
[ "$VORHER" = "$NACHHER" ] \
  && ok "5: nach der Antwort sieht die Eingabezeile wieder aus wie vorher ('$NACHHER')" \
  || bad "5: nach der Antwort steht '$NACHHER' statt '$VORHER' — der Vergleich traegt nicht"

# 6 — die Falle fuer den naechsten, der den Fehlschlag aus Zusage 5 mit einem
# promptIgnore heilen will. Traefe es die Auftragszeile, hiesse jeder beliebige Text
# 'abgeschickt' — auch dann, wenn er wirklich haengt.
if [ -n "$PIGN" ]; then
  if printf '%s' "$INBOX_BUSY" | grep -qE "$PIGN"; then
    bad "6: promptIgnore '$PIGN' trifft den wiederholten Auftragstext — jeder Text hiesse dann 'abgeschickt'"
  else
    ok "6: promptIgnore laesst den wiederholten Auftragstext aus"
  fi
else
  ok "6: kein promptIgnore — nichts, das eine Absendung faelschlich bestaetigt"
fi

# 7 — die Autonomie-Flags sind tragend. Ohne --yes-always steht aider bei seiner einzigen
# Erstfrage, und der Ready-Wait laeuft in seine Frist, weil auf diesem Bildschirm keine
# Zeile mit dem Prompt-Zeichen beginnt.
grep -qE "$READY" "$FIX/gitignore-frage.txt" \
  && bad "7: readyPattern trifft die gitignore-Frage — ein blockierter Start hiesse 'bereit'" \
  || ok "7: readyPattern trifft die gitignore-Frage nicht (Start ohne --yes-always bleibt stehen)"
OUT="$("$WBS" models resolve aider-qwen3.5-4b --role worker --dir "$TESTHOME/work" --name w1 2>/dev/null)"
CMD="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="cmd"{print $2}')"
case "$CMD" in
  *--yes-always*) ok "7: resolve baut --yes-always in die Startzeile" ;;
  *) bad "7: resolve ohne --yes-always: ${CMD:-<leer>}" ;;
esac
case "$CMD" in
  *"--model openai/qwen3.5-4b"*) ok "7: resolve bestellt das Modell: openai/qwen3.5-4b" ;;
  *) bad "7: resolve baut keine Modellwahl: ${CMD:-<leer>}" ;;
esac
READY_OUT="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="ready"{print $2}')"
[ "$READY_OUT" = "$READY" ] \
  && ok "7: resolve reicht dasselbe readyPattern durch" \
  || bad "7: resolve meldet ready '$READY_OUT' statt '$READY'"

# 8 — keine Vertrauensfrage. agy und codex fragen beim ersten Start in einem neuen
# Verzeichnis; aider nicht (gemessen ohne --yes-always: die gitignore-Frage ist die
# einzige). Ein trustStore-Block waere hier also eine Behauptung ohne Messung.
if hat_feld trustStore; then
  bad "8: aider hat einen trustStore-Block — gemessen wurde keine Vertrauensfrage"
else
  ok "8: kein trustStore — aider stellt keine Vertrauensfrage"
fi

echo
echo "  $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
