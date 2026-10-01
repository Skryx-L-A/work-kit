#!/usr/bin/env bash
# test-worker-mcp-knapp.sh -- ein Claude-Worker startet mit knapper
# MCP-Ausstattung, und der seltene Ausnahmefall bleibt erreichbar.
#
# ANLASS (2026-08-20, Messung des Workers "speicher"). Eine frische
# Claude-Sitzung kostet 516 MiB; mit `--strict-mcp-config --mcp-config <datei>`
# und nur `basic-memory` darin sind es 252 MiB. Die Differenz von 264 MiB je
# Sitzung -- 51 Prozent -- ist fast vollstaendig der Playwright-MCP: 163 MiB
# fuer den npm-exec-Wrapper und 97 MiB fuer den Server. Ein Worker benutzt ihn
# fast nie; der Orchestrator schon, und der laeuft nicht durch diesen Pfad.
#
# Diese Suite prueft die Startzeile, nicht den Speicher: gemessen hat "speicher"
# schon, hier geht es darum, dass die beiden Schalter auch wirklich dort landen
# und dass die knappe Konfiguration `basic-memory` behaelt. Ohne den Eintrag
# waere der Kbase fuer jeden Worker zu -- das waere teurer als die 264 MiB.
#
#   1  Ohne Zutun startet ein Claude-Worker mit --strict-mcp-config und einer
#      --mcp-config, die es wirklich gibt.
#   2  Diese Konfiguration nennt basic-memory und NICHT den Browser-MCP.
#   3  WB_MCP_VOLL=1 nimmt beide Schalter wieder heraus und sagt das auch.
#
# ISOLATION und LOESCH-SICHERUNG: siehe lib-zustellbett.sh.
# LAUFZEIT: rund 20 Sekunden, zwei Spawns.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-zustellbett.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOR="$(cd "$HIER/.." && pwd)"
command -v tmux >/dev/null 2>&1 || ueberspringen "tmux nicht im PATH"
[ -x "$VOR/pi-worker" ]             || ueberspringen "shell/pi-worker fehlt"
[ -f "$HIER/fake-claude-inbox.py" ] || ueberspringen "fake-claude-inbox.py fehlt"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

echo "== Knappe MCP-Ausstattung fuer Worker =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

# Ein Stellvertreter, der seine eigenen Argumente aufschreibt. Nur so ist
# nachpruefbar, was wirklich auf der Startzeile stand -- die Pane-Optionen
# fuehren sie fuer diesen Zweig nicht.
ARGLOG="$TESTHOME/claude-argumente.txt"
cat > "$TESTHOME/.local/bin/claude" <<CCEOF
#!/bin/sh
printf '%s\n' "\$@" > $ARGLOG
FAKE_CC_SOCK=$SOCKDIR/\$\$.sock FAKE_CC_NAME=fake-\$\$ FAKE_CC_MODE=normal \\
FAKE_CC_STATUS=idle FAKE_CC_RECV=$RECV/\$\$ FAKE_CC_READY='❯' \\
exec /usr/bin/python3 "$FAKE_CC"
CCEOF
chmod +x "$TESTHOME/.local/bin/claude"

argument_da() { grep -qxF -- "$1" "$ARGLOG" 2>/dev/null; }

# ── 1 und 2: die Vorgabe ──────────────────────────────────────────────────────
echo
echo "-- 1: ohne Zutun startet der Worker knapp --"
zustellbett_panes_weg
pi_lauf socket "k1$MARKE" "MCPKNAPP-$MARKE" >/dev/null 2>&1
if [ ! -s "$ARGLOG" ]; then
  bad "1: der Stellvertreter hat keine Argumente aufgezeichnet -- Testaufbau"
else
  argument_da "--strict-mcp-config" \
    && ok "1: --strict-mcp-config steht auf der Startzeile" \
    || bad "1: --strict-mcp-config fehlt"
  KONF="$(grep -A1 -xF -- '--mcp-config' "$ARGLOG" 2>/dev/null | tail -1)"
  if [ -z "$KONF" ]; then
    bad "1: --mcp-config fehlt oder nennt keine Datei"
  else
    ok "1: --mcp-config nennt eine Datei"
    [ -s "$KONF" ] \
      && ok "1: und diese Datei existiert -- sie wird angelegt, wenn sie fehlt" \
      || bad "1: die genannte Datei '$KONF' gibt es nicht"
    if grep -q 'basic-memory' "$KONF" 2>/dev/null; then
      ok "2: die knappe Konfiguration behaelt basic-memory (Kbase bleibt erreichbar)"
    else
      bad "2: basic-memory fehlt -- der Kbase waere fuer jeden Worker zu"
    fi
    if grep -qi 'playwright' "$KONF" 2>/dev/null; then
      bad "2: der Browser-MCP steht in der knappen Konfiguration -- genau der kostet die 264 MiB"
    else
      ok "2: der Browser-MCP steht nicht darin"
    fi
  fi
fi

# ── 3: der Ausnahmefall ───────────────────────────────────────────────────────
echo
echo "-- 3: WB_MCP_VOLL=1 gibt die volle Ausstattung zurueck --"
zustellbett_panes_weg
rm -f -- "$ARGLOG"
AUS="$(env WB_MCP_VOLL=1 WB_ZUSTELLUNG=socket HOME="$TESTHOME" \
        PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
        bash "$ZB_REPO/pi-worker" "k2$MARKE" claude-haiku45 "$TESTHOME/arbeit" "MCPVOLL-$MARKE" 2>&1)"
if [ ! -s "$ARGLOG" ]; then
  bad "3: der Stellvertreter hat keine Argumente aufgezeichnet"
else
  argument_da "--strict-mcp-config" \
    && bad "3: --strict-mcp-config steht trotz WB_MCP_VOLL noch da" \
    || ok "3: --strict-mcp-config ist verschwunden"
  argument_da "--mcp-config" \
    && bad "3: --mcp-config steht trotz WB_MCP_VOLL noch da" \
    || ok "3: --mcp-config ebenfalls"
fi
case "$AUS" in
  *WB_MCP_VOLL*) ok "3: und pi-worker sagt, dass es die teurere Ausstattung ist" ;;
  *) bad "3: der Ausnahmefall wird stillschweigend gewaehrt" ;;
esac

echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "k1$MARKE" "k2$MARKE"
if [ -e "$ECHTHOME/.claude/workbench/mcp-worker.json" ]; then
  # Kein Fehlschlag: im Betrieb SOLL die Datei dort liegen. Gemeldet wird nur,
  # dass dieser Test sie nicht angelegt hat -- er arbeitet im eigenen HOME.
  echo "  hinweis  im echten HOME liegt bereits eine mcp-worker.json (vom Betrieb, nicht von diesem Test)"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
