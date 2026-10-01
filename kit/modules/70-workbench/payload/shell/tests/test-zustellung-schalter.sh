#!/usr/bin/env bash
# test-zustellung-schalter.sh -- wirkt jede Stellung des Umschalters wirklich,
# oder gewinnt still eine andere?
#
# ANLASS (2026-08-20, Stresstest der Zustellung). `workerZustellung` hat drei
# Stellungen (auto|socket|paste) und dazu `WB_ZUSTELLUNG` fuer den Einzelfall.
# Von den dreien ist 'socket' die einzige mit einer harten Zusage -- sie
# verlangt die Sitzungs-Inbox und faellt NICHT aufs Tippen zurueck. Eine
# Stellung, die still zu einer anderen wird, nimmt genau diese Zusage weg, ohne
# dass es jemand merkt: im Erfolgsfall sieht 'auto' aus wie 'socket'.
#
# GEMESSENER BEFUND, der hier festgehalten wird: ein nicht erkannter Wert fiel
# still auf 'auto'. Mit workerZustellung=paste in den Einstellungen und einem
# vertippten WB_ZUSTELLUNG=sockett lief die Zustellung ueber die Inbox -- also
# ueber genau den Weg, den die Einstellung ausgeschlossen hatte. Die
# gespeicherte Einstellung prueft `wb-state settings set` beim Schreiben; die
# Umgebungsvariable und eine von Hand veraenderte Einstellungsdatei gingen
# daran vorbei.
#
#   1  Jede der drei Stellungen wirkt ohne Umgebungsvariable.
#   2  Die Umgebungsvariable schlaegt die Einstellung -- in BEIDE Richtungen.
#   3  Ein Tippfehler in der Umgebungsvariablen ist ein lauter Fehlschlag, kein
#      stilles 'auto'.
#   4  Ein Tippfehler in der EINSTELLUNG wird schon beim Schreiben abgelehnt --
#      und wenn er trotzdem in der Datei steht (von Hand hineingeschrieben),
#      faellt er beim naechsten Auftrag auf.
#
# ISOLATION und LOESCH-SICHERUNG: siehe lib-zustellbett.sh.
# LAUFZEIT: rund eine Minute.
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
[ -x "$VOR/wb-state" ]              || ueberspringen "shell/wb-state fehlt"
[ -f "$HIER/fake-claude-inbox.py" ] || ueberspringen "fake-claude-inbox.py fehlt"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

echo "== Der Umschalter workerZustellung und WB_ZUSTELLUNG =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

# Ein Empfaenger, der BEIDE Wege bedienen kann, ist hier nicht noetig und waere
# sogar irrefuehrend: gemessen wird, WELCHEN Weg pi-worker nimmt, und dafuer
# genuegt eine Sitzung mit Inbox -- der Tippweg funktioniert dagegen auch, weil
# der Stellvertreter eine '❯'-Zeile zeigt und den eingefuegten Text annimmt.
zustellbett_claude_inbox normal

einstellung() {   # <wert> -- direkt ueber wb-state, also mit dessen Formpruefung
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      "$TESTHOME/.local/bin/wb-state" settings set workerZustellung "$1" >/dev/null 2>&1
}
gelesen() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      "$TESTHOME/.local/bin/wb-state" settings get workerZustellung 2>/dev/null
}

probe() {   # <erwarteter-weg> <env-wert-oder-"-"> <name> <beschreibung>
  local erwartet="$1" env="$2" name="$3" text="$4" aus weg
  zustellbett_panes_weg
  aus="$(pi_lauf "$env" "$name" "SCHALT-$name")"
  weg="$(zustellweg "$aus")"
  if [ "$weg" = "$erwartet" ]; then
    ok "$text -> $weg"
  else
    bad "$text -> $weg statt $erwartet"
    printf '%s\n' "$aus" | grep -m1 -E 'FEHLER|zugestellt|verifiziert' | sed 's/^/        | /'
  fi
  ZULETZT="$aus"
}

# ── 1: die drei Stellungen ohne Umgebungsvariable ─────────────────────────────
echo
echo "-- 1: jede Stellung wirkt fuer sich --"
einstellung socket
[ "$(gelesen)" = socket ] && ok "1: 'socket' laesst sich speichern und wieder lesen" \
                          || bad "1: 'socket' kam nicht in den Einstellungen an"
probe SOCKET - "s1$MARKE" "1: Einstellung socket, keine Umgebungsvariable"
einstellung paste
probe PASTE  - "s2$MARKE" "1: Einstellung paste,  keine Umgebungsvariable"
einstellung auto
probe SOCKET - "s3$MARKE" "1: Einstellung auto,   keine Umgebungsvariable (Inbox ist da, also Inbox)"

# ── 2: die Umgebungsvariable schlaegt die Einstellung ─────────────────────────
echo
echo "-- 2: der Einzelfall schlaegt die Einstellung, in beide Richtungen --"
einstellung paste
probe SOCKET socket "s4$MARKE" "2: Einstellung paste,  WB_ZUSTELLUNG=socket"
einstellung socket
probe PASTE  paste  "s5$MARKE" "2: Einstellung socket, WB_ZUSTELLUNG=paste"

# ── 3: Tippfehler in der Umgebungsvariablen ───────────────────────────────────
echo
echo "-- 3: ein Tippfehler im Einzelfall wird nicht zu 'auto' geraten --"
einstellung paste
probe FEHLSCHLAG sockett "s6$MARKE" "3: Einstellung paste, WB_ZUSTELLUNG=sockett"
case "$ZULETZT" in
  *"ist keiner der drei bekannten"*) ok "3: die Meldung nennt den unbekannten Wert und die drei gueltigen" ;;
  *) bad "3: die erwartete Meldung fehlt: $(printf '%s' "$ZULETZT" | tail -2)" ;;
esac
case "$ZULETZT" in
  *"WB_ZUSTELLUNG"*) ok "3: und sie sagt, WOHER der Wert kam" ;;
  *) bad "3: die Herkunft des Werts wird nicht genannt" ;;
esac
[ "$(zustellbett_platzhalter "s6$MARKE")" = weg ] \
  && ok "3: kein Platzhalter zurueckgeblieben" \
  || bad "3: '.laufend.md' steht noch da"

# ── 4: Tippfehler in der Einstellung ──────────────────────────────────────────
echo
echo "-- 4: ein Tippfehler in der Einstellung faellt auf, auf beiden Ebenen --"
AUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
        "$TESTHOME/.local/bin/wb-state" settings set workerZustellung sockett 2>&1)"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "4: wb-state speichert den vertippten Wert gar nicht erst (rc=$RC)" \
  || bad "4: wb-state hat 'sockett' gespeichert"
case "$AUS" in
  *"kennt nur auto|socket|paste"*) ok "4: und nennt die drei gueltigen Stellungen" ;;
  *) bad "4: die Meldung nennt die gueltigen Werte nicht: $AUS" ;;
esac
# Der zweite Weg an der Formpruefung vorbei: von Hand in die Datei geschrieben.
einstellung auto
/usr/bin/python3 - "$TESTHOME/.claude/workbench/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["workerZustellung"] = "sockett"
json.dump(d, open(p, "w"), indent=2)
PY
if [ "$(gelesen)" = sockett ]; then
  probe FEHLSCHLAG - "s7$MARKE" "4: von Hand vertippte Einstellungsdatei"
  case "$ZULETZT" in
    *"Einstellung workerZustellung"*) ok "4: und die Meldung nennt die Einstellung als Quelle" ;;
    *) bad "4: die Quelle wird nicht genannt: $(printf '%s' "$ZULETZT" | tail -2)" ;;
  esac
else
  bad "4: der von Hand gesetzte Wert liess sich nicht lesen ('$(gelesen)') -- die Gegenprobe faellt aus"
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "s1$MARKE" "s2$MARKE" "s3$MARKE" "s4$MARKE" \
                             "s5$MARKE" "s6$MARKE" "s7$MARKE"
if grep -q '"workerZustellung"' "$ECHTHOME/.claude/workbench/settings.json" 2>/dev/null; then
  ECHT="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("workerZustellung",""))' \
          "$ECHTHOME/.claude/workbench/settings.json" 2>/dev/null)"
  case "$ECHT" in
    sockett) bad "die ECHTE Einstellungsdatei traegt den Testwert -- Testisolation gebrochen" ;;
    *) ok "die echte Einstellungsdatei blieb unveraendert (workerZustellung='$ECHT')" ;;
  esac
else
  ok "die echte Einstellungsdatei blieb ohne Test-Eintrag"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
