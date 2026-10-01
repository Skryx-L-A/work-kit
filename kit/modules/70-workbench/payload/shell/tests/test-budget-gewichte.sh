#!/bin/bash
# test-budget-gewichte.sh — wb-budget --limit-gewichte: ein Gewicht je Modell statt eines
# Faktors fuer alle.
#
# WARUM (Auftrag 2026-08-10, Folgeauftrag zu limitkosten): --limit-kalibrierung lieferte an
# zwei 5-Stunden-Abschnitten fast den doppelten USD/Punkt-Wert, weil sich der Modellmix drehte
# (80% sonnet-5 gegen 74% opus-5). --limit-gewichte loest stattdessen ein lineares
# Gleichungssystem je Modell. Diese Suite prueft:
#   1. ein exakt bestimmtes 2x2-System (2 Abschnitte, 2 Modelle) liefert die von Hand
#      nachgerechneten Gewichte, in allen drei Basen (USD, Tokens inkl./ohne cache_read)
#   2. ein einzelner belastbarer Abschnitt bleibt unterbestimmt statt eine Zahl zu erfinden
#   3. ein widerspruechliches System liefert ein negatives Gewicht UND die Warnung dazu
#   4. fehlt limits.jsonl ganz, bleibt die alte Meldung, Exit-Code 0
#
# ISOLATION: eigenes HOME je Fall in einem mktemp-Verzeichnis, nie die echte Konfiguration und
# nie die echten Transkripte. Kein tmux noetig.
#
# Run: shell/tests/test-budget-gewichte.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
TOOL="$REPO/wb-budget"
echo "Geprueft: $TOOL"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-budget-gewichte-test.XXXXXX")" && pwd)"
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

msg() {  # msg <ts> <model> <input_tokens> -> eine assistant-Zeile im Transkript-Format
  local ts="$1" model="$2" input="$3"
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"%s","usage":{"input_tokens":%s,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' \
    "$ts" "$model" "$input"
}

# =============================================================================================
# Fall 1: exakt bestimmtes 2x2-System -- von Hand nachgerechnet.
#
# Ziel: w(sonnet-5)=0.1 Punkte/USD, w(opus-5)=0.2 Punkte/USD.
#   Abschnitt A: sonnet 20.000.000 Tokens (60 USD @3/MTok), opus 5.000.000 Tokens (25 USD @5/MTok)
#     -> 0.1*60 + 0.2*25 = 6 + 5 = 11 Punkte
#   Abschnitt B: sonnet 10.000.000 Tokens (30 USD), opus 17.000.000 Tokens (85 USD)
#     -> 0.1*30 + 0.2*85 = 3 + 17 = 20 Punkte
# =============================================================================================
HOME1="$TESTHOME/h1"
mkdir -p "$HOME1/.claude/workbench" "$HOME1/.claude/projects/proj/"
cat > "$HOME1/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-01T00:20:00Z","session":"s","five_hour_pct":11,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-01T00:21:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"1"}
{"ts":"2026-01-01T00:41:00Z","session":"s","five_hour_pct":20,"seven_day_pct":null,"five_hour_resets_at":"1"}
EOF
TX1="$HOME1/.claude/projects/proj/session.jsonl"
{
  msg "2026-01-01T00:10:00Z" "claude-sonnet-5" 20000000
  msg "2026-01-01T00:10:01Z" "claude-opus-5"    5000000
  msg "2026-01-01T00:31:00Z" "claude-sonnet-5" 10000000
  msg "2026-01-01T00:31:01Z" "claude-opus-5"   17000000
} > "$TX1"

OUT1=$(HOME="$HOME1" "$TOOL" --limit-gewichte --tage 36500 2>&1)

echo "$OUT1" | grep -qF '2 Abschnitt(e) mit mindestens 3 Punkten Anstieg gefunden, davon 2 belastbar' \
  && ok "beide Abschnitte gefunden und als belastbar erkannt" \
  || bad "Abschnittszahl/Belastbarkeit stimmt nicht" "$OUT1"

USD_BLOCK=$(echo "$OUT1" | awk '/Punkte je USD-Aequivalent/{f=1} f{print} f && /Kreuzprobe/{exit}')
echo "$USD_BLOCK" | grep -qF 'claude-opus-5: 0.2000 Punkte je USD' \
  && ok "USD-Basis: opus-5 Gewicht 0.2000 (Handrechnung bestaetigt)" \
  || bad "opus-5-Gewicht (USD) stimmt nicht" "$USD_BLOCK"
echo "$USD_BLOCK" | grep -qF 'claude-sonnet-5: 0.1000 Punkte je USD' \
  && ok "USD-Basis: sonnet-5 Gewicht 0.1000 (Handrechnung bestaetigt)" \
  || bad "sonnet-5-Gewicht (USD) stimmt nicht" "$USD_BLOCK"
echo "$USD_BLOCK" | grep -qF '5.00 USD/Punkt bei reinem Verbrauch dieses Modells' \
  && ok "Kehrwert opus-5: 5.00 USD/Punkt" \
  || bad "Kehrwert fuer opus-5 fehlt/falsch" "$USD_BLOCK"
echo "$USD_BLOCK" | grep -qF '10.00 USD/Punkt bei reinem Verbrauch dieses Modells' \
  && ok "Kehrwert sonnet-5: 10.00 USD/Punkt" \
  || bad "Kehrwert fuer sonnet-5 fehlt/falsch" "$USD_BLOCK"
echo "$USD_BLOCK" | grep -qF 'nach Entfernen eines Abschnitts blieben nur 1 Gleichung(en) fuer 2 Modell(e)' \
  && ok "Kreuzprobe bei nur 2 Abschnitten korrekt als unmoeglich gemeldet" \
  || bad "Kreuzprobe-Meldung fehlt/falsch" "$USD_BLOCK"

echo "$OUT1" | grep -qF 'Punkte je Million Tokens, inkl. cache_read' \
  && ok "Token-Basis inkl. cache_read wird berechnet" \
  || bad "Token-Basis inkl. cache_read fehlt" "$OUT1"
echo "$OUT1" | grep -qF 'Punkte je Million Tokens, ohne cache_read' \
  && ok "Token-Basis ohne cache_read wird berechnet" \
  || bad "Token-Basis ohne cache_read fehlt" "$OUT1"
echo "$OUT1" | grep -qF '2 Modell(e) x 4 Arten = 8 Unbekannte' \
  && ok "Aufteilung nach Tokenart korrekt als nicht tragfaehig ausgewiesen" \
  || bad "Hinweis zur Tokenart-Aufteilung fehlt" "$OUT1"

# =============================================================================================
# Fall 2: nur EIN belastbarer Abschnitt -- unterbestimmt, keine Zahl.
# =============================================================================================
HOME2="$TESTHOME/h2"
mkdir -p "$HOME2/.claude/workbench" "$HOME2/.claude/projects/proj/"
cat > "$HOME2/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-01-02T00:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-02T00:20:00Z","session":"s","five_hour_pct":11,"seven_day_pct":null,"five_hour_resets_at":"0"}
EOF
TX2="$HOME2/.claude/projects/proj/session.jsonl"
{
  msg "2026-01-02T00:10:00Z" "claude-sonnet-5" 20000000
  msg "2026-01-02T00:10:01Z" "claude-opus-5"    5000000
} > "$TX2"

OUT2=$(HOME="$HOME2" "$TOOL" --limit-gewichte --tage 36500 2>&1)
echo "$OUT2" | grep -qF 'davon 1 belastbar' \
  && ok "Fall 2: genau ein belastbarer Abschnitt erkannt" \
  || bad "Fall 2: Belastbarkeitszahl stimmt nicht" "$OUT2"
echo "$OUT2" | grep -qF 'nicht loesbar: unterbestimmt: 1 Gleichung(en) fuer 2 Modell(e)' \
  && ok "Fall 2: ein Abschnitt fuer zwei Modelle bleibt unterbestimmt, keine erfundene Zahl" \
  || bad "Fall 2: unterbestimmt-Meldung fehlt" "$OUT2"

# =============================================================================================
# Fall 3: widerspruechliches System -- negatives Gewicht, mit Warnung.
#
# Ziel: w(sonnet-5)=-2, w(opus-5)=6.
#   Abschnitt A: sonnet 3.000.000 Tokens (9 USD), opus 2.000.000 Tokens (10 USD)
#     -> -2*9 + 6*10 = -18+60 = 42 Punkte
#   Abschnitt B: sonnet 1.000.000 Tokens (3 USD), opus 1.000.000 Tokens (5 USD)
#     -> -2*3 + 6*5 = -6+30 = 24 Punkte
# =============================================================================================
HOME3="$TESTHOME/h3"
mkdir -p "$HOME3/.claude/workbench" "$HOME3/.claude/projects/proj/"
cat > "$HOME3/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-01-03T00:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-03T00:20:00Z","session":"s","five_hour_pct":42,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-03T00:21:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"1"}
{"ts":"2026-01-03T00:41:00Z","session":"s","five_hour_pct":24,"seven_day_pct":null,"five_hour_resets_at":"1"}
EOF
TX3="$HOME3/.claude/projects/proj/session.jsonl"
{
  msg "2026-01-03T00:10:00Z" "claude-sonnet-5" 3000000
  msg "2026-01-03T00:10:01Z" "claude-opus-5"   2000000
  msg "2026-01-03T00:31:00Z" "claude-sonnet-5" 1000000
  msg "2026-01-03T00:31:01Z" "claude-opus-5"   1000000
} > "$TX3"

OUT3=$(HOME="$HOME3" "$TOOL" --limit-gewichte --tage 36500 2>&1)
USD_BLOCK3=$(echo "$OUT3" | awk '/Punkte je USD-Aequivalent/{f=1} f{print} f && /Kreuzprobe/{exit}')
echo "$USD_BLOCK3" | grep -qF 'claude-sonnet-5: -2.0000 Punkte je USD' \
  && ok "Fall 3: negatives Gewicht -2.0000 fuer sonnet-5 korrekt berechnet" \
  || bad "Fall 3: erwartetes negatives Gewicht fehlt" "$USD_BLOCK3"
echo "$USD_BLOCK3" | grep -qF 'claude-opus-5: 6.0000 Punkte je USD' \
  && ok "Fall 3: Gegengewicht 6.0000 fuer opus-5 korrekt berechnet" \
  || bad "Fall 3: erwartetes Gewicht fuer opus-5 fehlt" "$USD_BLOCK3"
echo "$USD_BLOCK3" | grep -qF 'WARNUNG negatives Gewicht bei claude-sonnet-5' \
  && ok "Fall 3: negatives Gewicht wird als Warnsignal ausgegeben, nicht verschwiegen" \
  || bad "Fall 3: Warnung zum negativen Gewicht fehlt" "$USD_BLOCK3"
echo "$USD_BLOCK3" | grep -qF 'die Datenlage reicht nicht' \
  && ok "Fall 3: Warnung sagt explizit, dass die Datenlage nicht reicht" \
  || bad "Fall 3: Einordnung 'Datenlage reicht nicht' fehlt" "$USD_BLOCK3"

# =============================================================================================
# Fall 4: limits.jsonl fehlt ganz -> alte Meldung, Exit 0.
# =============================================================================================
HOME4="$TESTHOME/h4"
mkdir -p "$HOME4/.claude/projects"
OUT4=$(HOME="$HOME4" "$TOOL" --limit-gewichte 2>&1); RC4=$?
[ "$RC4" -eq 0 ] \
  && ok "Fall 4: kein limits.jsonl -- Exit-Code 0" \
  || bad "Fall 4: Exit-Code $RC4 statt 0"
echo "$OUT4" | grep -qF 'nicht verfuegbar — kein Log unter' \
  && ok "Fall 4: klare Fallback-Meldung bei fehlendem Log" \
  || bad "Fall 4: Fallback-Meldung fehlt" "$OUT4"

# =============================================================================================
# Fall 5: ein externer Anker (limit-anker.json) tritt als eigene Gleichung neben einen
# automatisch erkannten Abschnitt (Nachtrag 2026-08-10, Wochenfenster-Anker des Nutzers).
#
# Ziel: w(sonnet-5)=0,05, w(opus-5)=0,15 Punkte/USD.
#   Automatischer Abschnitt: sonnet 20.000.000 Tokens (60 USD), opus 4.000.000 Tokens (20 USD)
#     -> 0,05*60 + 0,15*20 = 3+3 = 6 Punkte
#   Anker (keine Token-Daten, nur USD): sonnet 100 USD, opus 200 USD
#     -> 0,05*100 + 0,15*200 = 5+30 = 35 Punkte
# =============================================================================================
HOME5="$TESTHOME/h5"
mkdir -p "$HOME5/.claude/workbench" "$HOME5/.claude/projects/proj/"
cat > "$HOME5/.claude/workbench/plan-historie.json" <<'EOF'
{ "plaene": [ { "plan": "P", "von": "2026-01-01T00:00:00Z", "bis": null } ] }
EOF
cat > "$HOME5/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-01-05T00:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-05T00:10:00Z","session":"s","five_hour_pct":6,"seven_day_pct":null,"five_hour_resets_at":"0"}
EOF
cat > "$HOME5/.claude/workbench/limit-anker.json" <<'EOF'
{
  "anker": [
    {
      "feld": "five_hour_pct",
      "von": "2026-01-04T00:00:00Z",
      "bis": "2026-01-04T01:00:00Z",
      "punkte": 35,
      "usd": { "claude-sonnet-5": 100, "claude-opus-5": 200 },
      "quelle": "Testanker"
    }
  ]
}
EOF
TX5="$HOME5/.claude/projects/proj/session.jsonl"
msg "2026-01-05T00:05:00Z" "claude-sonnet-5" 20000000 > "$TX5"
msg "2026-01-05T00:05:01Z" "claude-opus-5"    4000000 >> "$TX5"

OUT5=$(HOME="$HOME5" "$TOOL" --limit-gewichte --tage 36500 2>&1)
echo "$OUT5" | grep -qF 'dazu 1 externe(r) Anker' \
  && ok "Fall 5: der externe Anker wird gezaehlt" \
  || bad "Fall 5: Anker-Zaehlung fehlt/falsch" "$OUT5"
echo "$OUT5" | grep -qF 'E1. extern 2026-01-04T00:00:00Z -> 2026-01-04T01:00:00Z, +35 Punkte, Plan: P (durchgehend bestaetigt)' \
  && ok "Fall 5: der Anker wird mit Plan-Bestaetigung gelistet" \
  || bad "Fall 5: Anker-Listenzeile fehlt/falsch" "$OUT5"
USD_BLOCK5=$(echo "$OUT5" | awk '/Punkte je USD-Aequivalent \(2/{f=1} f{print} f && /Aufteilung je Modell/{exit}')
echo "$USD_BLOCK5" | grep -qF 'claude-sonnet-5: 0.0500 Punkte je USD' \
  && ok "Fall 5: sonnet-5-Gewicht 0.0500 mit Anker korrekt geloest" \
  || bad "Fall 5: sonnet-5-Gewicht falsch" "$USD_BLOCK5"
echo "$USD_BLOCK5" | grep -qF 'claude-opus-5: 0.1500 Punkte je USD' \
  && ok "Fall 5: opus-5-Gewicht 0.1500 mit Anker korrekt geloest" \
  || bad "Fall 5: opus-5-Gewicht falsch" "$USD_BLOCK5"
echo "$OUT5" | grep -qF 'bei 1 Abschnitt(en) mit Token-Daten' \
  && ok "Fall 5: der Anker liefert keine Token-Basis (nur die USD-Basis)" \
  || bad "Fall 5: Token-Basis-Zaehlung beruecksichtigt den Anker faelschlich" "$OUT5"

# =============================================================================================
# Fall 6: ein Anker, dessen Zeitraum eine Plangrenze ueberspannt, wird NICHT verwendet.
# =============================================================================================
HOME6="$TESTHOME/h6"
mkdir -p "$HOME6/.claude/workbench" "$HOME6/.claude/projects"
cat > "$HOME6/.claude/workbench/plan-historie.json" <<'EOF'
{
  "plaene": [
    { "plan": "Alt", "von": "2026-01-01T00:00:00Z", "bis": "2026-01-04T12:00:00Z" },
    { "plan": "Neu", "von": "2026-01-04T12:00:00Z", "bis": null }
  ]
}
EOF
cat > "$HOME6/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-01-05T00:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
EOF
cat > "$HOME6/.claude/workbench/limit-anker.json" <<'EOF'
{
  "anker": [
    {
      "feld": "five_hour_pct",
      "von": "2026-01-04T00:00:00Z",
      "bis": "2026-01-04T23:00:00Z",
      "punkte": 35,
      "usd": { "claude-sonnet-5": 100, "claude-opus-5": 200 },
      "quelle": "Testanker ueber eine Plangrenze"
    }
  ]
}
EOF
OUT6=$(HOME="$HOME6" "$TOOL" --limit-gewichte --tage 36500 2>&1)
echo "$OUT6" | grep -qF 'NICHT verwendet (mischt Plaene: Alt, Neu)' \
  && ok "Fall 6: ein Anker ueber eine Plangrenze wird ausgeschlossen, mit Begruendung" \
  || bad "Fall 6: Ausschluss-Meldung fuer den plangrenzueberspannenden Anker fehlt" "$OUT6"

echo
echo "wb-budget-gewichte: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
