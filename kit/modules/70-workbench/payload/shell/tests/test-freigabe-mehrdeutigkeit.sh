#!/usr/bin/env bash
# test-freigabe-mehrdeutigkeit.sh -- eine Freigabe darf nicht ins Leere gehen.
#
# Vorfall (Auftrag 2026-08-10): ein Wächter hielt `launchctl bootout` an, wurde
# viermal mit leicht verändertem Wortlaut wiederholt, und `wb-freigabe erteilen`
# gab am Ende genau EINEN der vier Wortlaute frei -- den, der gerade im Merker
# stand. Der Mensch sah "erteilt" und "trotzdem wieder angehalten", ohne dass
# irgendwo stand, WARUM: der Schlüssel ist ein Hash über pane+cwd+command, ein
# anderer Wortlaut ist ein anderer Schlüssel (shell/wb-freigabe:175).
#
# Geprüft wird hier, in dieser Reihenfolge:
#   A  Gegenprobe zuerst: der einfache Fall (genau EIN offener Wortlaut) läuft
#      unverändert -- `erteilen` gibt sofort frei, keine Mehrdeutigkeits-Meldung.
#   B  Mehrere Wortlaute derselben Pane: `erteilen` ohne Auswahl gibt NICHTS
#      frei, zählt sie nummeriert mit vollem Wortlaut auf.
#   C  `--index` gibt GENAU den gewählten Wortlaut frei, der Merker bleibt
#      stehen (die ältere Frage ist noch offen), bis der WIRKLICH freigegebene
#      Wortlaut läuft.
#   D  `--alle` gibt jeden offenen Wortlaut als eigene Freigabe frei.
#   E  Freigabe für den falschen Wortlaut: liegt bereits eine gültige Freigabe
#      für die Pane vor, nur für einen anderen Text, sagt die Meldung das --
#      samt der Stelle, an der sich die Texte unterscheiden -- statt sich wie
#      eine ganz neue Rückfrage zu lesen. Der richtige Wortlaut läuft danach
#      trotzdem durch, die falsche Freigabe bleibt unangetastet liegen.
#   F  Der Befehlstext wird vollständig gezeigt (liste UND erteilen), eine
#      Kürzung ist als solche erkennbar, Anfang und Ende bleiben stehen.
#   G  Die Meldungen nennen den konkreten Weg zurück (Wortlaut in eine Datei
#      schreiben, von dort wiederholen).
#   H  Auflagen: kein Agent kommt an --index/--alle vorbei an die Messung
#      heran; der Schlüssel bleibt hash(pane+cwd+command); die TTL-Obergrenze
#      gilt auch für --alle.
#
# ISOLATION: eigenes HOME (mktemp -d), eigene Verzeichnisse für Marker,
# Freigaben, Verlauf und Einstellungen -- AWB_GUARD_BLOCKS_DIR,
# AWB_GUARD_GRANTS_DIR, AWB_GUARD_LOG, AWB_CONFIG, AWB_SETTINGS_FILE. Kein
# tmux: bash-guard.py und wb-freigabe brauchen dafür nur die PANE-KENNUNG als
# Zeichenkette (TMUX_PANE), keinen echten Pane -- genau das nutzt schon
# hooks/tests/test-ask-muster.sh für dieselbe Stufe, ohne tmux-Server, ohne
# Netz, ohne dass ein Befehl je ausgeführt wird. `wb-mensch` wird durch einen
# Platzhalter ersetzt (wie in test-haerten-rolle-freigabe.sh) -- das ist das
# Programmfenster/Terminal, nicht die Prüfung selbst; dass eine ECHTE Messung
# einen Agenten erkennt, belegt jene Suite. Die echten Ablagen unter
# ~/.pi-workers/ werden nirgends berührt.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$REPO/hooks/bash-guard.py"
WB_FREIGABE="$REPO/shell/wb-freigabe"
PY=/usr/bin/python3

command -v "$PY" >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: python3 fehlt"; exit 77; }
[ -f "$GUARD" ] || { echo "UEBERSPRUNGEN: bash-guard.py fehlt"; exit 77; }
[ -f "$WB_FREIGABE" ] || { echo "UEBERSPRUNGEN: wb-freigabe fehlt"; exit 77; }

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT

BLOCKS="$TESTHOME/blocks"
GRANTS="$TESTHOME/pi-workers/guard-grants"
VERLAUF="$TESTHOME/guard.log"
CONFIG="$TESTHOME/config.json"
ARBEIT="$TESTHOME/arbeit"
mkdir -p "$BLOCKS" "$GRANTS" "$ARBEIT" "$TESTHOME/.local/bin"

# Platzhalter für `wb-mensch` -- steht hier für ein gemessenes Terminal (M1),
# genau wie in test-haerten-rolle-freigabe.sh. Was eine ECHTE Messung von
# einem Agenten unterscheidet, prüft jene Suite.
printf '#!/bin/sh\nprintf "mensch\\tSteuerndes Terminal (M1)\\n"\n' > "$TESTHOME/.local/bin/wb-mensch"
chmod +x "$TESTHOME/.local/bin/wb-mensch"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
section() { printf '\n=== %s ===\n' "$1"; }

NONCE="freimehr$$x$(date +%s)"
"$PY" - "$CONFIG" "$NONCE" <<'PY'
import json, sys
ziel, nonce = sys.argv[1], sys.argv[2]
with open(ziel, 'w') as fh:
    json.dump({'askPatterns': [{'befehl': nonce, 'grund': 'Erkennungsmerkmal dieses Laufs'}],
               'askGrantTtlSeconds': 300}, fh)
PY

# Ein Aufruf des Wächters. Gibt die Entscheidung als erstes Wort aus, danach
# den vollständigen Text.
guard() { # guard <pane> <command>
    local pane="$1" cmd="$2"
    "$PY" - "$GUARD" "$pane" "$cmd" "$ARBEIT" "$BLOCKS" "$GRANTS" "$VERLAUF" "$CONFIG" <<'PY'
import json, os, subprocess, sys
guard, pane, cmd, cwd, blocks, grants, verlauf, config = sys.argv[1:9]
umgebung = dict(os.environ)
umgebung.update({
    'AWB_GUARD_BLOCKS_DIR': blocks, 'AWB_GUARD_GRANTS_DIR': grants,
    'AWB_GUARD_LOG': verlauf, 'AWB_CONFIG': config, 'AWB_SETTINGS_FILE': config,
    'TMUX_PANE': pane,
})
eingabe = json.dumps({'session_id': 'test-freimehr', 'cwd': cwd, 'tool_name': 'Bash',
                      'tool_input': {'command': cmd}})
r = subprocess.run([sys.executable, guard], input=eingabe, capture_output=True, text=True,
                   env=umgebung)
try:
    out = (json.loads(r.stdout or '{}') or {}).get('hookSpecificOutput') or {}
except Exception:
    out = {}
print('DENY' if out.get('permissionDecision') == 'deny' else 'ALLOW')
print(out.get('permissionDecisionReason') or '')
PY
}
entscheidung() { printf '%s' "$1" | head -1; }
text() { printf '%s' "$1" | tail -n +2; }

# `wb-freigabe erteilen` mit isolierter Umgebung. Gibt stdout aus, stderr auf
# fd 2 durchgereicht -- Aufrufer fangen ab, was sie brauchen.
freigabe() { # freigabe <pane> <grund> [weitere Optionen...]
    local pane="$1" grund="$2"; shift 2
    HOME="$TESTHOME" \
    AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" AWB_GUARD_LOG="$VERLAUF" \
    "$WB_FREIGABE" erteilen "$@" "$pane" "$grund"
}
liste() {
    AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" AWB_GUARD_LOG="$VERLAUF" \
    "$WB_FREIGABE" liste
}
schluessel_von() { # schluessel_von <pane> <cwd> <command>
    "$PY" -c "import hashlib,sys; print(hashlib.sha256('\x00'.join(sys.argv[1:4]).encode()).hexdigest())" \
        "$1" "$2" "$3"
}
anzahl_grants() { find "$GRANTS" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# ---------------------------------------------------------------------------
section "A) Gegenprobe: der einfache Fall läuft unverändert"
PANE_A="%1001"
BEFEHL_A="$NONCE einfach"
A1="$(guard "$PANE_A" "$BEFEHL_A")"
[ "$(entscheidung "$A1")" = "DENY" ] \
    && ok "der einfache Befehl wird angehalten" \
    || bad "der einfache Befehl lief durch: $A1"

AUS="$(freigabe "$PANE_A" "einfacher Fall" 2>&1)"
RC=$?
[ $RC -eq 0 ] && ok "erteilen gelingt ohne --index/--alle, wenn nur EIN Wortlaut offen ist" \
             || bad "erteilen scheiterte im einfachen Fall (rc=$RC): $AUS"
case "$AUS" in
    *MEHRDEUTIG*) bad "der einfache Fall zeigt faelschlich eine Mehrdeutigkeits-Meldung" ;;
    *) ok "keine Mehrdeutigkeits-Meldung im einfachen Fall" ;;
esac
A2="$(guard "$PANE_A" "$BEFEHL_A")"
[ "$(entscheidung "$A2")" = "ALLOW" ] \
    && ok "der freigegebene einfache Befehl läuft danach durch" \
    || bad "der einfache Befehl blieb trotz Freigabe angehalten: $A2"

# ---------------------------------------------------------------------------
section "B) Mehrere offene Wortlaute -- erteilen ohne Auswahl gibt NICHTS frei"
PANE_B="%1002"
BEFEHL_B1="$NONCE eins"
BEFEHL_B2="$NONCE zwei"
BEFEHL_B3="$NONCE drei"
guard "$PANE_B" "$BEFEHL_B1" >/dev/null
B_ZWEITE="$(guard "$PANE_B" "$BEFEHL_B2")"
case "$(text "$B_ZWEITE")" in
    *"another question is already waiting"*) ok "die zweite Fassung wird als Alternative erkannt, nicht ersetzt" ;;
    *) bad "die zweite Fassung wurde nicht als Alternative erkannt: $B_ZWEITE" ;;
esac
guard "$PANE_B" "$BEFEHL_B3" >/dev/null

VOR="$(anzahl_grants)"
AUS_B="$(freigabe "$PANE_B" "welcher davon?" 2>&1)"
RC_B=$?
[ $RC_B -ne 0 ] && ok "erteilen ohne Auswahl scheitert bei Mehrdeutigkeit (rc=$RC_B)" \
                || bad "erteilen hat bei Mehrdeutigkeit trotzdem etwas freigegeben"
[ "$(anzahl_grants)" = "$VOR" ] \
    && ok "dabei wurde NICHTS freigegeben (Anzahl Freigaben unveraendert)" \
    || bad "trotz Mehrdeutigkeit wurde eine Freigabe angelegt"
case "$AUS_B" in *MEHRDEUTIG*) ok "die Meldung nennt sich MEHRDEUTIG" ;;
                  *) bad "die Meldung sagt nicht, dass es mehrdeutig ist: $AUS_B" ;; esac
for erwartet in "$BEFEHL_B1" "$BEFEHL_B2" "$BEFEHL_B3"; do
    case "$AUS_B" in
        *"$erwartet"*) ok "Wortlaut '$erwartet' steht vollstaendig in der Aufzaehlung" ;;
        *) bad "Wortlaut '$erwartet' fehlt in der Aufzaehlung: $AUS_B" ;;
    esac
done
case "$AUS_B" in
    *'[1]'*'[2]'*'[3]'*) ok "die drei Wortlaute sind nummeriert (1..3)" ;;
    *) bad "die Aufzaehlung ist nicht nummeriert: $AUS_B" ;;
esac

LISTE_B="$(liste)"
case "$LISTE_B" in
    *"$PANE_B"*MEHRDEUTIG*) ok "wb-freigabe liste zeigt die Mehrdeutigkeit fuer diese Pane" ;;
    *) bad "wb-freigabe liste zeigt die Mehrdeutigkeit nicht: $LISTE_B" ;;
esac

# ---------------------------------------------------------------------------
section "C) --index gibt GENAU den gewaehlten Wortlaut frei"
MARKER_B="$BLOCKS/${PANE_B//%/_}.json"
AUS_C="$(freigabe "$PANE_B" "Nummer zwei ist gemeint" --index 2 2>&1)"
RC_C=$?
[ $RC_C -eq 0 ] && ok "erteilen mit --index 2 gelingt" || bad "erteilen mit --index 2 scheiterte: $AUS_C"
case "$AUS_C" in
    *"$BEFEHL_B2"*) ok "die Ausgabe nennt den GEWAEHLTEN Wortlaut (Nummer 2)" ;;
    *) bad "die Ausgabe nennt nicht den gewaehlten Wortlaut: $AUS_C" ;;
esac
[ -s "$MARKER_B" ] \
    && ok "der Merker bleibt stehen -- die urspruengliche (aeltere) Frage ist noch offen" \
    || bad "der Merker verschwand, obwohl nur eine ALTERNATIVE freigegeben wurde"
C_B2="$(guard "$PANE_B" "$BEFEHL_B2")"
[ "$(entscheidung "$C_B2")" = "ALLOW" ] \
    && ok "der per --index freigegebene Wortlaut laeuft durch" \
    || bad "der per --index freigegebene Wortlaut blieb angehalten: $C_B2"
[ ! -s "$MARKER_B" ] \
    && ok "nach dem Einloesen ist der Merker weg (auch wenn er dem PRIMAEREN Wortlaut galt)" \
    || bad "der Merker haengt nach dem Einloesen noch"
C_B1="$(guard "$PANE_B" "$BEFEHL_B1")"
[ "$(entscheidung "$C_B1")" = "DENY" ] \
    && ok "der NICHT gewaehlte, urspruengliche Wortlaut bleibt angehalten" \
    || bad "der nicht gewaehlte Wortlaut lief unerwartet durch: $C_B1"
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "D) --alle gibt jeden offenen Wortlaut als eigene Freigabe frei"
PANE_D="%1003"
BEFEHL_D1="$NONCE vier"
BEFEHL_D2="$NONCE fuenf"
guard "$PANE_D" "$BEFEHL_D1" >/dev/null
guard "$PANE_D" "$BEFEHL_D2" >/dev/null
VOR_D="$(anzahl_grants)"
AUS_D="$(freigabe "$PANE_D" "beide sind harmlos" --alle 2>&1)"
RC_D=$?
[ $RC_D -eq 0 ] && ok "erteilen mit --alle gelingt" || bad "erteilen mit --alle scheiterte: $AUS_D"
NACH_D="$(anzahl_grants)"
[ "$((NACH_D - VOR_D))" -eq 2 ] \
    && ok "--alle legt fuer JEDEN Wortlaut eine eigene Freigabe an (2 neue Dateien)" \
    || bad "--alle hat nicht genau zwei Freigaben angelegt (vorher=$VOR_D, nachher=$NACH_D)"
MARKER_D="$BLOCKS/${PANE_D//%/_}.json"
[ ! -s "$MARKER_D" ] \
    && ok "der Merker ist weg -- der primaere Wortlaut war unter den freigegebenen" \
    || bad "der Merker haengt nach --alle noch"
D_1="$(guard "$PANE_D" "$BEFEHL_D1")"
[ "$(entscheidung "$D_1")" = "ALLOW" ] && ok "der erste Wortlaut laeuft durch" \
                                       || bad "der erste Wortlaut blieb angehalten: $D_1"
D_2="$(guard "$PANE_D" "$BEFEHL_D2")"
[ "$(entscheidung "$D_2")" = "ALLOW" ] && ok "der zweite Wortlaut laeuft UNABHAENGIG davon ebenfalls durch" \
                                       || bad "der zweite Wortlaut blieb angehalten: $D_2"
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "E) Freigabe fuer den falschen Wortlaut -- die Meldung sagt es"
PANE_E="%1004"
BEFEHL_E_RICHTIG="$NONCE sechs original"
BEFEHL_E_FALSCH="$NONCE sechs veraendert"
guard "$PANE_E" "$BEFEHL_E_RICHTIG" >/dev/null
AUS_E="$(freigabe "$PANE_E" "das hier meine ich" 2>&1)"
[ $? -eq 0 ] && ok "die Freigabe fuer den urspruenglichen Wortlaut gelingt" \
             || bad "die Freigabe scheiterte unerwartet: $AUS_E"
VOR_E="$(anzahl_grants)"

# Der Agent variiert den Wortlaut -- genau der Fehler aus dem Vorfall.
E_FALSCH="$(guard "$PANE_E" "$BEFEHL_E_FALSCH")"
[ "$(entscheidung "$E_FALSCH")" = "DENY" ] \
    && ok "der veraenderte Wortlaut bleibt angehalten" \
    || bad "der veraenderte Wortlaut lief durch: $E_FALSCH"
E_TEXT="$(text "$E_FALSCH")"
case "$E_TEXT" in
    *"an approval already exists"*"DIFFERENT wording"*) \
        ok "die Meldung sagt: eine Freigabe liegt vor, aber fuer einen anderen Wortlaut" ;;
    *) bad "die Meldung erklaert den Fehlschlag nicht: $E_TEXT" ;;
esac
case "$E_TEXT" in
    *"differ from character"*) ok "die Meldung nennt die Stelle des Unterschieds" ;;
    *) bad "die Meldung nennt keine Unterschieds-Stelle: $E_TEXT" ;;
esac
case "$E_TEXT" in
    *"$BEFEHL_E_RICHTIG"*) ok "die Meldung zeigt den TATSAECHLICH freigegebenen Wortlaut" ;;
    *) bad "die Meldung zeigt den freigegebenen Wortlaut nicht: $E_TEXT" ;;
esac
[ "$(anzahl_grants)" = "$VOR_E" ] \
    && ok "die vorhandene (falsch angesprochene) Freigabe wurde NICHT verbraucht" \
    || bad "die vorhandene Freigabe wurde durch den Fehlversuch verbraucht"

# Und jetzt der WIRKLICH freigegebene Wortlaut -- er muss trotzdem laufen.
E_RICHTIG="$(guard "$PANE_E" "$BEFEHL_E_RICHTIG")"
[ "$(entscheidung "$E_RICHTIG")" = "ALLOW" ] \
    && ok "der wirklich freigegebene Wortlaut laeuft anschliessend durch" \
    || bad "der wirklich freigegebene Wortlaut blieb angehalten: $E_RICHTIG"
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "F) Voller Befehlstext -- keine stille Kuerzung mitten im Wort"
PANE_F="%1005"
KOPF="START-MARKE-$$"
SCHWANZ="END-MARKE-$$"
FUELLER="$("$PY" -c "print('x' * 900)")"
BEFEHL_F="$NONCE $KOPF $FUELLER $SCHWANZ"
guard "$PANE_F" "$BEFEHL_F" >/dev/null
LISTE_F="$(liste)"
case "$LISTE_F" in
    *"$KOPF"*) ok "liste zeigt den ANFANG eines langen Befehls" ;;
    *) bad "liste zeigt den Anfang eines langen Befehls nicht: fehlt $KOPF" ;;
esac
case "$LISTE_F" in
    *"$SCHWANZ"*) ok "liste zeigt das ENDE eines langen Befehls" ;;
    *) bad "liste zeigt das Ende eines langen Befehls nicht: fehlt $SCHWANZ" ;;
esac
case "$LISTE_F" in
    *"Zeichen gekuerzt"*) ok "eine Kuerzung ist als solche erkennbar markiert" ;;
    *) bad "keine erkennbare Kuerzungs-Markierung in der Ausgabe" ;;
esac

AUS_F="$(freigabe "$PANE_F" "langer befehl" 2>&1)"
[ $? -eq 0 ] && ok "erteilen fuer den langen Befehl gelingt" || bad "erteilen scheiterte: $AUS_F"
case "$AUS_F" in
    *"$KOPF"*"$SCHWANZ"*) ok "erteilen zeigt Anfang UND Ende des freigegebenen Befehls" ;;
    *) bad "erteilen zeigt Anfang/Ende des Befehls nicht vollstaendig: $AUS_F" ;;
esac
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "G) Die Meldung nennt den konkreten Weg zurueck"
PANE_G="%1006"
BEFEHL_G="$NONCE sieben"
G1="$(guard "$PANE_G" "$BEFEHL_G")"
case "$(text "$G1")" in
    *"literally to a file"*"instead of typing it again"*) \
        ok "die ERSTE Rueckfrage nennt schon die Datei-Praxis gegen eigene Textvarianten" ;;
    *) bad "die erste Rueckfrage nennt die Datei-Praxis nicht: $G1" ;;
esac
rm -f "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "H) Auflagen: kein Agent kommt an der Messung vorbei"
PANE_H="%1007"
BEFEHL_H1="$NONCE acht"
BEFEHL_H2="$NONCE neun"
guard "$PANE_H" "$BEFEHL_H1" >/dev/null
guard "$PANE_H" "$BEFEHL_H2" >/dev/null
VOR_H="$(anzahl_grants)"
rm -f "$TESTHOME/.local/bin/wb-mensch"
AUS_H="$(HOME="$TESTHOME" AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" \
         AWB_GUARD_LOG="$VERLAUF" "$WB_FREIGABE" erteilen --index 1 "$PANE_H" "ich versuchs trotzdem" 2>&1)"
RC_H=$?
[ $RC_H -eq 77 ] && ok "ohne gemessenen Menschen scheitert erteilen auch mit --index (rc=77)" \
                 || bad "erteilen ohne gemessenen Menschen gab rc=$RC_H statt 77: $AUS_H"
AUS_H2="$(HOME="$TESTHOME" AWB_GUARD_BLOCKS_DIR="$BLOCKS" AWB_GUARD_GRANTS_DIR="$GRANTS" \
          AWB_GUARD_LOG="$VERLAUF" "$WB_FREIGABE" erteilen --alle "$PANE_H" "und mit --alle" 2>&1)"
RC_H2=$?
[ $RC_H2 -eq 77 ] && ok "ohne gemessenen Menschen scheitert erteilen auch mit --alle (rc=77)" \
                  || bad "erteilen ohne gemessenen Menschen gab rc=$RC_H2 statt 77 (--alle): $AUS_H2"
[ "$(anzahl_grants)" = "$VOR_H" ] \
    && ok "dabei wurde keine einzige Freigabe angelegt" \
    || bad "trotz fehlender Messung wurde eine Freigabe angelegt"
# wb-mensch wieder herstellen fuer den Rest der Suite.
printf '#!/bin/sh\nprintf "mensch\\tSteuerndes Terminal (M1)\\n"\n' > "$TESTHOME/.local/bin/wb-mensch"
chmod +x "$TESTHOME/.local/bin/wb-mensch"

section "H) Der Schluessel bleibt hash(pane+cwd+command), auch bei --index"
PANE_H3="%1008"
BEFEHL_H3A="$NONCE zehn"
BEFEHL_H3B="$NONCE elf"
guard "$PANE_H3" "$BEFEHL_H3A" >/dev/null
guard "$PANE_H3" "$BEFEHL_H3B" >/dev/null
freigabe "$PANE_H3" "zweiter Wortlaut" --index 2 >/dev/null 2>&1
ERWARTETER_SCHLUESSEL="$(schluessel_von "$PANE_H3" "$ARBEIT" "$BEFEHL_H3B")"
[ -f "$GRANTS/$ERWARTETER_SCHLUESSEL.json" ] \
    && ok "die per --index erteilte Freigabe liegt exakt unter hash(pane+cwd+command)" \
    || bad "die per --index erteilte Freigabe liegt nicht unter dem erwarteten Schluessel"
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

section "H) Die TTL-Obergrenze gilt auch fuer --alle"
PANE_H4="%1009"
BEFEHL_H4A="$NONCE zwoelf"
BEFEHL_H4B="$NONCE dreizehn"
guard "$PANE_H4" "$BEFEHL_H4A" >/dev/null
guard "$PANE_H4" "$BEFEHL_H4B" >/dev/null
freigabe "$PANE_H4" "lange Frist gewuenscht" --alle --ttl 999999 >/dev/null 2>&1
UEBERSCHRITTEN=0
for f in "$GRANTS"/*.json; do
    [ -f "$f" ] || continue
    DAUER="$("$PY" -c "
import calendar, json, time
d = json.load(open('$f'))
g = calendar.timegm(time.strptime(d['granted_ts'], '%Y-%m-%dT%H:%M:%SZ'))
e = calendar.timegm(time.strptime(d['expires_ts'], '%Y-%m-%dT%H:%M:%SZ'))
print(e - g)
")"
    [ "$DAUER" -gt 900 ] && UEBERSCHRITTEN=1
done
[ "$UEBERSCHRITTEN" -eq 0 ] \
    && ok "keine der --alle-Freigaben ueberschreitet die 900-Sekunden-Obergrenze" \
    || bad "mindestens eine --alle-Freigabe liegt ueber der TTL-Obergrenze"
rm -f "$GRANTS"/*.json "$BLOCKS"/*.json

# ---------------------------------------------------------------------------
section "ZUSAMMENFASSUNG"
printf 'PASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
