#!/usr/bin/env bash
# test-wb-code-claude-chathook.sh -- der eingebaute claude-Zweig von
# shell/wb-code (der Orchestrator-Pane) muss die Chat-Zuordnung (SPEC-V4
# 6.3 Punkt 4) wirklich ausloesen, nicht nur der Registry-Zweig.
#
# ANLASS (11.08.): derselbe Fund wie bei shell/pi-worker
# (test-pi-worker-claude-chathook.sh), an der ZWEITEN Stelle. wb-code baut
# fuer HARNESS=claude seine Startzeile ab Zeile ~427 selbst und laeuft nie
# durch wb-harness-run, dem einzigen anderen Ort, der den Hook eintraegt --
# 'claude' ist zudem der einzige Harness mit session.zuordnung=hook
# (models.default.json). Orchestrator-Sitzungen liefen damit ebenfalls ohne
# Chat-Zuordnung: nach einem Start stand ~/.claude/settings.json unveraendert
# da und ~/.claude/workbench/chat-zuordnung.sh existierte nicht.
#
# DIE VIER AUSSAGEN, Vorbild test-pi-worker-claude-chathook.sh:
#   1  Ein Start ueber den eingebauten claude-Zweig legt den Haken an und
#      traegt ihn in settings.json ein -- OHNE dass irgendetwas
#      wb-harness-run oder wb-chat-hook-install von Hand aufruft.
#   2  Fremde Hooks/Einstellungen in derselben Datei bleiben unveraendert.
#   3  Ein ZWEITER Start (anderes Projektverzeichnis, also eine andere
#      Session) traegt den Haken NICHT ein zweites Mal ein.
#   4  Die echte Umgebung (~/.pi-workers, Rollenregister) bleibt unberuehrt.
#
# WARUM ZWEI VERSCHIEDENE VERZEICHNISSE FUER AUSSAGE 3, nicht derselbe
# zweimal: ein zweiter Aufruf auf DASSELBE Verzeichnis traefe die schon
# laufende tmux-Session (Zeile ~361, `if tmux has-session ...; then attach;
# fi`) und wuerde den ganzen claude-Zweig gar nicht mehr durchlaufen -- das
# pruefte dann nichts. Zwei Projektverzeichnisse ergeben zwei Sessions und
# zwei tatsaechliche Durchlaeufe des Zweigs.
#
# ISOLATION: eigener tmux-Socket, eigenes HOME, ein Schirm statt der echten
# claude-CLI, eigene Modell-Registry -- niemals eine laufende Sitzung. Der
# Hintergrundschreiber, den wb-code am Ende jedes Starts abtrennt
# (record_conversation, bis zu 40s), wird beim Aufraeumen ueber seinen
# TESTHOME-Pfad in der Kommandozeile gezielt beendet -- er gehoert zu keiner
# tmux-Session, die kill-server sonst mitnaehme.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-codechathook-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="w$(date +%s)$$$RANDOM"

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
  pkill -f "$TESTHOME" 2>/dev/null || true
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== wb-code (claude-Zweig): loest die Chat-Zuordnung wirklich aus (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
command -v timeout >/dev/null 2>&1 || ueberspringen "timeout nicht im PATH"
[ -x "$REPO/wb-code" ] || ueberspringen "shell/wb-code fehlt"
[ -x "$REPO/wb-chat-hook-install" ] || ueberspringen "shell/wb-chat-hook-install fehlt"
[ -f "$REPO/models.default.json" ] || ueberspringen "shell/models.default.json fehlt"

# --- Die Testumgebung, vollstaendig selbst hergestellt ----------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.claude/roles" \
         "$TESTHOME/.local/bin" "$TESTHOME/arbeit-a" "$TESTHOME/arbeit-b"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent: zeigt das Bereitschaftszeichen und schluckt den Rest.
# Diese Suite prueft NICHT den injizierten Text, nur ob die Installation lief.
cat > "$TESTHOME/.local/bin/claude" <<'SHIMEOF'
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec cat >/dev/null
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"

# Die ECHTEN Werkzeuge -- sie entscheiden hier mit, kein Platzhalter.
for w in wb-state wb-rolle; do
  cp "$REPO/$w" "$TESTHOME/.local/bin/$w"
  chmod +x "$TESTHOME/.local/bin/$w"
done
# wb-chat-hook-install NICHT hierher kopiert: der Punkt dieser Suite ist,
# dass wb-code die REPO-Fassung neben sich selbst findet (dieselbe Bauart
# wie wb-rolle/pi-worker), ohne Installationsschritt.
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"
# Volle Registry statt der eingebauten Kurzfassung: nur models.default.json
# traegt session.zuordnung=hook fuer 'claude' -- die eingebaute Kurzfassung in
# wb-state (BUILTIN_HARNESSES) kennt das Feld nicht.
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"
printf 'Testrolle orchestrator\n' > "$TESTHOME/.claude/roles/orchestrator.md"

# Vorher-Stand der ECHTEN Register -- der Lauf darf sie nicht anfassen.
ECHT_ROLLEN="$HOME/.pi-workers/rollen"
ROLLEN_VORHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"

# settings.json traegt schon FREMDE Eintraege UND muss bereits existieren --
# wb-chat-hook-install legt fuer den Stil 'claude-settings-json' nie eine neue
# globale Konfiguration aus dem Nichts an (Absicht, siehe dort).
printf '%s\n' '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/fremd/guard.sh"}]}]}, "model": "opus"}' \
  > "$TESTHOME/.claude/settings.json"

SETTINGS="$TESTHOME/.claude/settings.json"
HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"

hookzahl() {
  /usr/bin/python3 - "$SETTINGS" "$HAKEN" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); sys.exit(0)
h = (d.get("hooks") or {}).get("SessionStart") or []
print(sum(1 for g in h for e in (g.get("hooks") or []) if e.get("command") == sys.argv[2]))
PY
}

wbc() { # wbc <dir> -- ein Start ueber den eingebauten claude-Zweig
  local dir="$1"
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= WB_NO_DISCOVER=1 WB_NO_RESUME=1 \
      timeout 30 bash "$REPO/wb-code" "$dir" --harness claude \
        --model "testmodell-$MARKE" --effort medium --fresh </dev/null 2>&1
}

echo
echo "-- 1: erster Start ueber den claude-Zweig --"
AUS_A="$(wbc "$TESTHOME/arbeit-a")"
[ -x "$HAKEN" ] && ok "1: der Haken existiert nach dem ersten Start" \
  || bad "1: $HAKEN fehlt -- die Installation lief nicht"
[ "$(hookzahl)" = 1 ] && ok "1: settings.json traegt genau einen Eintrag auf den Haken" \
  || bad "1: settings.json traegt den Haken nicht (oder mehrfach): $(hookzahl)"
case "$AUS_A" in *"Chat-Zuordnung als SessionStart-Hook"*) ok "1: die Ausgabe bestaetigt den Eintrag" ;;
  *) bad "1: keine Bestaetigung in der Ausgabe -- $(printf '%s\n' "$AUS_A" | tail -10)" ;; esac

echo
echo "-- 2: fremde Eintraege bleiben --"
if /usr/bin/python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
pre = (d.get("hooks") or {}).get("PreToolUse") or []
gut = d.get("model") == "opus" and any(
    e.get("command") == "/fremd/guard.sh" for g in pre for e in (g.get("hooks") or []))
sys.exit(0 if gut else 1)
PY
then ok "2: der fremde PreToolUse-Hook und 'model' stehen unveraendert da"
else bad "2: fremde Eintraege sind verschwunden oder veraendert"; fi

echo
echo "-- 3: zweiter Start (anderes Projektverzeichnis) traegt den Haken NICHT noch einmal ein --"
AUS_B="$(wbc "$TESTHOME/arbeit-b")"
if [ "$(hookzahl)" = 1 ]; then
  ok "3: nach dem zweiten Start steht der Haken weiterhin genau einmal da"
else
  bad "3: der Haken steht $(hookzahl)x in settings.json"
  printf '%s\n' "$AUS_B" | sed 's/^/      | /' | tail -10
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
if [ ! -e "$HOME/.pi-workers/sessions/orch-${TESTHOME//\//-}" ]; then
  ok "kein Eintrag unter dem echten ~/.pi-workers fuer diesen Testlauf"
else
  bad "es wurde ins ECHTE ~/.pi-workers geschrieben -- Testisolation gebrochen"
fi
ROLLEN_NACHHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"
[ "$ROLLEN_NACHHER" = "$ROLLEN_VORHER" ] \
  && ok "das ECHTE Rollenregister blieb unberuehrt ($ROLLEN_VORHER Eintraege wie vorher)" \
  || bad "der Lauf hat in das echte $ECHT_ROLLEN geschrieben ($ROLLEN_VORHER -> $ROLLEN_NACHHER)"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
