#!/usr/bin/env bash
# test-chat-hook-dateisicherheit.sh -- die Chat-Hook-Installation (SPEC-V4
# 6.3 Punkt 4, shell/wb-chat-hook-install) darf ~/.claude/settings.json nur
# ANFASSEN, wenn sie schon existiert, lesbar UND nicht leer ist.
#
# ANLASS (11.08., Befund eines unabhaengigen Pruefers): json_hook() fing
# JEDE Ausnahme beim Lesen der Zieldatei ab und behandelte sie wie "Datei
# existiert nicht" -- roh wurde leer, daten = {}, der Hook wurde angehaengt,
# und os.replace ersetzte die Zieldatei durch eine, die NUR NOCH den einen
# Hook trug. Existierte ~/.claude/settings.json also, liess sich aber nicht
# LESEN (falsche Rechte, ein Verzeichnis an der Stelle, ein E/A-Fehler),
# waren sieben des Nutzers Hook-Ereignisse und alle Erlaubnisse weg -- und auf
# stderr stand die ERFOLGSMELDUNG. settings.json ist GLOBALE des Nutzers
# Konfiguration, an der jede seiner Claude-Sitzungen haengt.
#
# DIE VIER FAELLE, alle mit derselben Erwartung: NICHTS wird geschrieben,
# die Datei bleibt (falls vorhanden) Byte fuer Byte wie sie war, der Grund
# steht auf stderr:
#   1  Datei fehlt ganz.
#   2  Datei existiert, ist aber leer (0 Byte).
#   3  Datei existiert, traegt aber kein gueltiges JSON-Objekt.
#   4  Datei existiert MIT Inhalt, ist aber nicht LESBAR (chmod 000) -- der
#      eigentliche Befund: Faelle 1-3 sahen vorher schon "Datei fehlt"
#      aehnlich, Fall 4 ist der, den der alte Code mit Fall 1 verwechselte.
#
# GEGENPROBE (Fall 5): codex' hooks.json ist KEINE globale Konfiguration,
# sondern eine dedizierte, sonst leere Hook-Datei -- sie darf weiterhin neu
# entstehen, wenn sie fehlt (unveraendertes Verhalten, siehe
# test-chat-hook-installation.sh Fall 4). Die Unterscheidung ist Absicht,
# keine Luecke: codex' eigentliche Anmeldung liegt in config.toml, und die
# ist ueber toml_abschnitt() schon ebenso geschuetzt (existiert sie nicht,
# wird ebenfalls nichts eingetragen).
#
# ISOLATION: eigenes HOME, eigenes TMPDIR, ein Stub fuer wb-state, kein
# echter tmux-Server, keine Datei der laufenden Sitzung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUF="$REPO/shell/wb-harness-run"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-chathooksicherheit.XXXXXX")" && pwd)"
export TMPDIR="$TESTHOME/tmp"
mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/.claude" "$TESTHOME/.codex" "$TMPDIR"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() {
  # chmod 000 wuerde rm -rf sonst am eigenen Aufraeumen hindern.
  chmod -R u+rwx "$TESTHOME" 2>/dev/null
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

echo "== Datei-Sicherheit der Chat-Hook-Installation (settings.json) =="
echo "Geprueft: $LAUF"

cat > "$TESTHOME/.local/bin/wb-state" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "models resolve") printf 'harness\t%s\n' "$WB_TEST_HARNESS"; printf 'cmd\t/usr/bin/true\n' ;;
  "harness get") cat "$WB_TEST_HJSON" ;;
esac
exit 0
STUB
chmod +x "$TESTHOME/.local/bin/wb-state"

lauf() { # lauf <harness-id> <json-datei> -> Ausgabe
  env HOME="$TESTHOME" TMPDIR="$TMPDIR" WB_TEST_HARNESS="$1" WB_TEST_HJSON="$2" \
    bash "$LAUF" --model testmodell --role worker --dir "$TESTHOME" 2>&1
}

hjson() { # hjson <datei> <id> <hook-json>
  cat > "$1" <<JSON
{"id": "$2", "session": {"via": "sessionFile", "ort": "~/x/{sessionId}.jsonl",
 "format": "claude-transcript", "zuordnung": "hook", "live": true, "eingabe": "pane",
 "zeigtNicht": [], "probe": {"datum": "2026-08-11", "beleg": "Test"},
 "hook": $3}}
JSON
}

hjson "$TESTHOME/h-claude.json" testclaude \
  '{"style": "claude-settings-json", "file": "~/.claude/settings.json", "event": "SessionStart", "matcher": "startup|resume", "timeout": 5}'

HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"
SETTINGS="$TESTHOME/.claude/settings.json"

# --- 1: Datei fehlt ganz -------------------------------------------------
echo
echo "-- 1: settings.json fehlt --"
rm -f "$SETTINGS"
AUSGABE="$(lauf testclaude "$TESTHOME/h-claude.json")"
[ ! -e "$SETTINGS" ] && ok "1: settings.json wurde NICHT angelegt" \
  || bad "1: settings.json ist trotz Fehlens entstanden"
case "$AUSGABE" in *"fehlt"*"kein Hook eingetragen"*) ok "1: der Grund (fehlt) steht auf stderr" ;;
  *) bad "1: keine Meldung ueber die fehlende Datei (Ausgabe: $AUSGABE)" ;; esac

# --- 2: Datei existiert, ist aber leer ------------------------------------
echo
echo "-- 2: settings.json existiert, ist aber leer (0 Byte) --"
: > "$SETTINGS"
VORHER="$(shasum "$SETTINGS")"
AUSGABE="$(lauf testclaude "$TESTHOME/h-claude.json")"
NACHHER="$(shasum "$SETTINGS")"
[ ! -s "$SETTINGS" ] && ok "2: settings.json blieb 0 Byte gross" \
  || bad "2: settings.json hat jetzt Inhalt -- wurde ueberschrieben"
[ "$VORHER" = "$NACHHER" ] && ok "2: die leere Datei ist bytegleich geblieben" \
  || bad "2: die leere Datei wurde veraendert"
case "$AUSGABE" in *"leer"*"kein Hook eingetragen"*) ok "2: der Grund (leer) steht auf stderr" ;;
  *) bad "2: keine Meldung ueber die leere Datei (Ausgabe: $AUSGABE)" ;; esac

# --- 3: Datei existiert, aber kein gueltiges JSON-Objekt ------------------
echo
echo "-- 3: settings.json traegt kaputtes JSON --"
printf '{"hooks": DAS IST KEIN JSON' > "$SETTINGS"
VORHER="$(shasum "$SETTINGS")"
AUSGABE="$(lauf testclaude "$TESTHOME/h-claude.json")"
NACHHER="$(shasum "$SETTINGS")"
[ "$VORHER" = "$NACHHER" ] && ok "3: die kaputte Datei ist bytegleich geblieben" \
  || bad "3: die kaputte Datei wurde veraendert"
case "$AUSGABE" in *"nicht lesbar"*"kein Hook eingetragen"*) ok "3: der Grund (nicht lesbar/kaputt) steht auf stderr" ;;
  *) bad "3: keine Meldung ueber das kaputte JSON (Ausgabe: $AUSGABE)" ;; esac

# --- 4: Datei existiert MIT Inhalt, ist aber nicht lesbar (chmod 000) ----
# Der eigentliche Nachtrags-Befund: eine Leseausnahme darf NICHT wie
# "Datei fehlt" behandelt werden, sonst ersetzt os.replace() eine volle,
# lesbare Datei durch eine, die nur noch den einen Hook traegt.
echo
echo "-- 4: settings.json existiert MIT Inhalt, ist aber NICHT lesbar (chmod 000) --"
INHALT='{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/fremd/guard.sh"}]}]}, "model": "opus"}'
printf '%s' "$INHALT" > "$SETTINGS"
chmod 000 "$SETTINGS"
AUSGABE="$(lauf testclaude "$TESTHOME/h-claude.json")"
RC=$?
chmod 644 "$SETTINGS"
NACHHER_INHALT="$(cat "$SETTINGS")"
[ "$NACHHER_INHALT" = "$INHALT" ] && ok "4: der Inhalt ist Byte fuer Byte erhalten -- NICHT durch den Hook ersetzt" \
  || bad "4: der Inhalt wurde durch die Installation ueberschrieben (Datenverlust!): $NACHHER_INHALT"
case "$AUSGABE" in *"nicht lesbar"*"kein Hook eingetragen"*) ok "4: der Grund (nicht lesbar) steht auf stderr" ;;
  *) bad "4: keine Meldung ueber die unlesbare Datei (Ausgabe: $AUSGABE)" ;; esac
case "$AUSGABE" in *"Chat-Zuordnung als SessionStart-Hook"*)
  bad "4: die Ausgabe behauptet einen Eintrag, obwohl die Datei unlesbar war" ;;
  *) ok "4: keine falsche Erfolgsmeldung" ;; esac

# --- 5: Gegenprobe -- codex' hooks.json darf weiterhin neu entstehen -----
echo
echo "-- 5: Gegenprobe -- codex' hooks.json (keine globale Konfiguration) --"
CODEXHOOKS="$TESTHOME/.codex/hooks.json"
CODEXTOML="$TESTHOME/.codex/config.toml"
rm -f "$CODEXHOOKS"
printf '%s\n' '[projects."/x"]' 'trust_level = "trusted"' > "$CODEXTOML"
hjson "$TESTHOME/h-codex.json" testcodex \
  "{\"style\": \"codex-hooks-json\", \"file\": \"$CODEXHOOKS\", \"event\": \"SessionStart\", \"trustFile\": \"$CODEXTOML\", \"trustTable\": \"hooks.state\"}"
lauf testcodex "$TESTHOME/h-codex.json" >/dev/null
[ -f "$CODEXHOOKS" ] && ok "5: eine fehlende hooks.json von codex entsteht weiterhin neu (Absicht, keine Luecke)" \
  || bad "5: hooks.json fehlt -- die Gegenprobe zeigt keinen Unterschied mehr zu settings.json"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
