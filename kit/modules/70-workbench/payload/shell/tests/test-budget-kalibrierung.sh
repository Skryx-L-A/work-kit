#!/bin/bash
# test-budget-kalibrierung.sh — wb-budget --limit-kalibrierung und der Plan-Limit-Fallback.
#
# WARUM (Auftrag 2026-08-10): wb-budget rechnet ab jetzt Limit-Prozentpunkte gegen Tokens/USD
# um, empirisch aus ~/.claude/workbench/limits.jsonl + den Session-Transkripten -- nie aus einer
# festen Zahl im Code. Diese Suite prueft die vier im Auftrag genannten Faelle:
#   1. ein Reset in limits.jsonl ergibt zwei getrennte Abschnitte, nie ueber ihn hinweg gerechnet
#   2. ein Abschnitt unter 3 Prozentpunkten wird verworfen, nicht zu einer Zahl gemacht
#   3. ein Modell ohne Preiseintrag erscheint als "ohne Preis", faellt aber nicht unter den Tisch
#   4. fehlt limits.jsonl ganz, bleibt beim normalen Aufruf die alte Meldung, Exit-Code 0
#
# ISOLATION: eigenes HOME in einem mktemp-Verzeichnis, nie die echte Konfiguration und nie die
# echten Transkripte -- alle Fixture-Dateien werden hier frisch angelegt. Kein tmux noetig,
# wb-budget liest nur Dateien unter $HOME.
#
# Run: shell/tests/test-budget-kalibrierung.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
TOOL="$REPO/wb-budget"
echo "Geprueft: $TOOL"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-budget-kalib-test.XXXXXX")" && pwd)"
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

msg() {  # msg <ts> <model> <input_tokens> -> eine assistant-Zeile im Transkript-Format
  local ts="$1" model="$2" input="$3"
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"%s","usage":{"input_tokens":%s,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n' \
    "$ts" "$model" "$input"
}

# =============================================================================================
# Fall 1 + 2: Reset trennt zwei Abschnitte (nie darueber hinweg gerechnet), <3 Punkte verworfen.
# =============================================================================================
HOME1="$TESTHOME/h1"
mkdir -p "$HOME1/.claude/workbench" "$HOME1/.claude/projects/proj/"
LOG1="$HOME1/.claude/workbench/limits.jsonl"
cat > "$LOG1" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","session":"s","five_hour_pct":10,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-01T00:10:00Z","session":"s","five_hour_pct":20,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-01T00:20:00Z","session":"s","five_hour_pct":30,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-01-01T00:21:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"1"}
{"ts":"2026-01-01T00:30:00Z","session":"s","five_hour_pct":15,"seven_day_pct":null,"five_hour_resets_at":"1"}
{"ts":"2026-01-01T00:40:00Z","session":"s","five_hour_pct":45,"seven_day_pct":null,"five_hour_resets_at":"1"}
{"ts":"2026-01-01T00:41:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"2"}
{"ts":"2026-01-01T00:45:00Z","session":"s","five_hour_pct":1,"seven_day_pct":null,"five_hour_resets_at":"2"}
{"ts":"2026-01-01T00:50:00Z","session":"s","five_hour_pct":2,"seven_day_pct":null,"five_hour_resets_at":"2"}
EOF

TX1="$HOME1/.claude/projects/proj/session.jsonl"
{
  # Abschnitt 1 (10%->30%): 2.000.000 sonnet-5-Input-Tokens -> 6.00 USD.
  msg "2026-01-01T00:10:00Z" "claude-sonnet-5" 2000000
  # GIFT zwischen den Abschnitten (00:20:30, ausserhalb beider Fenster): 50.000.000
  # opus-5-Tokens -> 250 USD. Taucht dieser Betrag in EINEM der beiden Abschnitte auf,
  # rechnet die Kalibrierung faelschlich ueber die Fenstergrenze hinweg.
  msg "2026-01-01T00:20:30Z" "claude-opus-5" 50000000
  # Abschnitt 2 (0%->45%): 4.500.000 sonnet-5-Input-Tokens -> 13.50 USD.
  msg "2026-01-01T00:35:00Z" "claude-sonnet-5" 4500000
} > "$TX1"

OUT1=$(HOME="$HOME1" "$TOOL" --limit-kalibrierung --tage 36500 2>&1)

echo "$OUT1" | grep -qF '10%) -> 2026-01-01T00:20:00Z (30%), +20 Punkte' \
  && ok "Abschnitt 1 (10%->30%) erkannt" \
  || bad "Abschnitt 1 fehlt in der Ausgabe" "$OUT1"
echo "$OUT1" | grep -qF '0%) -> 2026-01-01T00:40:00Z (45%), +45 Punkte' \
  && ok "Abschnitt 2 (0%->45%) erkannt" \
  || bad "Abschnitt 2 fehlt in der Ausgabe" "$OUT1"

SEG1_USD=$(echo "$OUT1" | awk '/10%\) -> .*\(30%\)/{f=1} f && /Summe im Abschnitt/{print; exit}')
SEG2_USD=$(echo "$OUT1" | awk '/0%\) -> .*\(45%\)/{f=1} f && /Summe im Abschnitt/{print; exit}')
echo "$SEG1_USD" | grep -qF '6.00 USD' \
  && ok "Abschnitt 1: 6.00 USD (kein Ueberlauf des Geschenk-Postens)" \
  || bad "Abschnitt 1 zeigt nicht die erwarteten 6.00 USD" "$SEG1_USD"
echo "$SEG2_USD" | grep -qF '13.50 USD' \
  && ok "Abschnitt 2: 13.50 USD (kein Ueberlauf des Geschenk-Postens)" \
  || bad "Abschnitt 2 zeigt nicht die erwarteten 13.50 USD" "$SEG2_USD"
echo "$OUT1" | grep -qF '250.00' \
  && bad "der Geschenk-Posten (250 USD, zwischen den Abschnitten) taucht in der Ausgabe auf" "$OUT1" \
  || ok "der Geschenk-Posten zwischen den Abschnitten taucht nirgends auf"

# Fall 2: der dritte Abschnitt (0%->2%, Delta 2) liegt unter der 3-Punkte-Schwelle.
echo "$OUT1" | grep -qF '+2 Punkte' \
  && bad "ein Abschnitt mit nur 2 Punkten Anstieg wurde trotzdem ausgegeben" "$OUT1" \
  || ok "Abschnitt unter 3 Punkten wurde verworfen"

# =============================================================================================
# Fall 3: Modell ohne Preiseintrag -> "ohne Preis", Tokens zaehlen trotzdem mit.
# =============================================================================================
HOME2="$TESTHOME/h2"
mkdir -p "$HOME2/.claude/workbench" "$HOME2/.claude/projects/proj/"
LOG2="$HOME2/.claude/workbench/limits.jsonl"
cat > "$LOG2" <<'EOF'
{"ts":"2026-01-02T00:00:00Z","session":"s","five_hour_pct":null,"seven_day_pct":5,"five_hour_resets_at":"0"}
{"ts":"2026-01-02T00:05:00Z","session":"s","five_hour_pct":null,"seven_day_pct":10,"five_hour_resets_at":"0"}
EOF
TX2="$HOME2/.claude/projects/proj/session.jsonl"
{
  msg "2026-01-02T00:02:00Z" "claude-ghost-9" 1000000
  msg "2026-01-02T00:03:00Z" "claude-sonnet-5" 1000000
} > "$TX2"

OUT2=$(HOME="$HOME2" "$TOOL" --limit-kalibrierung --tage 36500 2>&1)

echo "$OUT2" | grep -qF 'claude-ghost-9: 50.0% der Tokens, ohne Preis' \
  && ok "unbekanntes Modell zeigt 'ohne Preis'" \
  || bad "kein 'ohne Preis' fuer claude-ghost-9" "$OUT2"
echo "$OUT2" | grep -qF 'claude-sonnet-5: 50.0% der Tokens, 3.00 USD' \
  && ok "bekanntes Modell im selben Abschnitt korrekt bepreist (3.00 USD)" \
  || bad "claude-sonnet-5 nicht mit 3.00 USD ausgewiesen" "$OUT2"
echo "$OUT2" | grep -qF 'Tokens/Punkt ohne cache_read:  400000' \
  && ok "Tokens des unbekannten Modells zaehlen in der Summe mit (nicht stillschweigend 0)" \
  || bad "Tokens/Punkt ohne cache_read stimmt nicht (Ghost-Tokens fehlen?)" "$OUT2"

# =============================================================================================
# Fall 4: limits.jsonl fehlt ganz -> normaler Aufruf zeigt weiter die alte Meldung, Exit 0.
# =============================================================================================
HOME3="$TESTHOME/h3"
mkdir -p "$HOME3/.claude/projects"
OUT3=$(HOME="$HOME3" "$TOOL" 2>&1); RC3=$?

[ "$RC3" -eq 0 ] \
  && ok "kein limits.jsonl: Exit-Code 0" \
  || bad "kein limits.jsonl: Exit-Code $RC3 statt 0"
echo "$OUT3" | grep -qF 'nicht verfuegbar — kein Log vorhanden' \
  && ok "kein limits.jsonl: alte Fallback-Meldung steht noch" \
  || bad "die alte Fallback-Meldung fehlt" "$OUT3"

# =============================================================================================
# Fall 5: eine Plangrenze trennt einen Abschnitt, obwohl der Prozentwert durchgehend steigt
# (Nachtrag 2026-08-10, Planhistorie-Anforderung des Nutzers). Ohne die Trennung waere das EIN
# Abschnitt 0%->20%; mit ihr zwei kleinere, je mit ihrem eigenen Plan-Namen.
# =============================================================================================
HOME4="$TESTHOME/h4"
mkdir -p "$HOME4/.claude/workbench" "$HOME4/.claude/projects/proj/"
cat > "$HOME4/.claude/workbench/plan-historie.json" <<'EOF'
{
  "plaene": [
    { "plan": "Plan A", "von": "2026-01-01T00:00:00Z", "bis": "2026-02-01T12:00:00Z" },
    { "plan": "Plan B", "von": "2026-02-01T12:00:00Z", "bis": null }
  ]
}
EOF
cat > "$HOME4/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-02-01T11:00:00Z","session":"s","five_hour_pct":0,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-02-01T11:30:00Z","session":"s","five_hour_pct":5,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-02-01T12:30:00Z","session":"s","five_hour_pct":15,"seven_day_pct":null,"five_hour_resets_at":"0"}
{"ts":"2026-02-01T13:00:00Z","session":"s","five_hour_pct":20,"seven_day_pct":null,"five_hour_resets_at":"0"}
EOF
OUT4=$(HOME="$HOME4" "$TOOL" --limit-kalibrierung --tage 36500 2>&1)

echo "$OUT4" | grep -qF '(0%) -> 2026-02-01T11:30:00Z (5%)' \
  && ok "Fall 5: Abschnitt vor der Plangrenze endet an der Grenze (0%->5%)" \
  || bad "Fall 5: Abschnitt vor der Plangrenze fehlt/falsch" "$OUT4"
echo "$OUT4" | grep -qF '(15%) -> 2026-02-01T13:00:00Z (20%)' \
  && ok "Fall 5: Abschnitt nach der Plangrenze beginnt neu (15%->20%)" \
  || bad "Fall 5: Abschnitt nach der Plangrenze fehlt/falsch" "$OUT4"
echo "$OUT4" | grep -qF '(0%) -> 2026-02-01T13:00:00Z (20%)' \
  && bad "Fall 5: die Plangrenze wurde ignoriert -- ein Abschnitt spannt 0%->20%" "$OUT4" \
  || ok "Fall 5: kein Abschnitt spannt ueber die Plangrenze hinweg"
echo "$OUT4" | grep -qF 'Plan: Plan A' && echo "$OUT4" | grep -qF 'Plan: Plan B' \
  && ok "Fall 5: beide Abschnitte nennen ihren jeweiligen Plan" \
  || bad "Fall 5: Plan-Beschriftung fehlt fuer mindestens einen Abschnitt" "$OUT4"

# =============================================================================================
# Fall 6: die bekannte Montag-14:00-Berlin-Kante trennt einen 7-Tage-Abschnitt, obwohl der
# Prozentwert durchgehend steigt und kein Ruecksprung vorliegt. 2026-02-02 ist ein Montag,
# im Februar gilt CET (Berlin = UTC+1), die Kante liegt also bei 13:00 UTC.
# =============================================================================================
HOME5="$TESTHOME/h5"
mkdir -p "$HOME5/.claude/workbench" "$HOME5/.claude/projects/proj/"
cat > "$HOME5/.claude/workbench/limits.jsonl" <<'EOF'
{"ts":"2026-02-02T12:30:00Z","session":"s","five_hour_pct":null,"seven_day_pct":0,"five_hour_resets_at":"0"}
{"ts":"2026-02-02T12:45:00Z","session":"s","five_hour_pct":null,"seven_day_pct":5,"five_hour_resets_at":"0"}
{"ts":"2026-02-02T13:15:00Z","session":"s","five_hour_pct":null,"seven_day_pct":15,"five_hour_resets_at":"0"}
{"ts":"2026-02-02T13:30:00Z","session":"s","five_hour_pct":null,"seven_day_pct":20,"five_hour_resets_at":"0"}
EOF
OUT5=$(HOME="$HOME5" "$TOOL" --limit-kalibrierung --tage 36500 2>&1)

echo "$OUT5" | grep -qF '(0%) -> 2026-02-02T12:45:00Z (5%)' \
  && ok "Fall 6: Abschnitt vor der Montags-Kante endet an der Kante (0%->5%)" \
  || bad "Fall 6: Abschnitt vor der Montags-Kante fehlt/falsch" "$OUT5"
echo "$OUT5" | grep -qF '(15%) -> 2026-02-02T13:30:00Z (20%)' \
  && ok "Fall 6: Abschnitt nach der Montags-Kante beginnt neu (15%->20%)" \
  || bad "Fall 6: Abschnitt nach der Montags-Kante fehlt/falsch" "$OUT5"
echo "$OUT5" | grep -qF '(0%) -> 2026-02-02T13:30:00Z (20%)' \
  && bad "Fall 6: die Montags-Kante wurde ignoriert -- ein Abschnitt spannt 0%->20%" "$OUT5" \
  || ok "Fall 6: kein Abschnitt spannt ueber die Montags-Kante hinweg"

echo
echo "wb-budget-kalibrierung: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
