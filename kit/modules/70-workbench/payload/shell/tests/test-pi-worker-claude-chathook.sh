#!/usr/bin/env bash
# test-pi-worker-claude-chathook.sh -- der eingebaute claude-Zweig von
# shell/pi-worker (ENGINE=claude) muss die Chat-Zuordnung (SPEC-V4 6.3
# Punkt 4) wirklich ausloesen, nicht nur der Registry-Zweig.
#
# ANLASS (11.08.): shell/wb-harness-run traegt die Installation seit ihrem
# Bau, aber pi-worker ruft wb-harness-run NUR im Registry-Zweig
# (ENGINE=registry). Der eingebaute Schnellpfad fuer die Aliase
# haiku45|sonnet5|opus5|opus48|fable5 (ENGINE=claude) baut seine Startzeile
# SELBST und lief nie durch wb-harness-run -- und 'claude' ist der EINZIGE
# Harness mit session.zuordnung=hook. Beleg vor der Korrektur: nach einem
# claude-worker-Spawn stand ~/.claude/settings.json unveraendert da und
# ~/.claude/workbench/chat-zuordnung.sh existierte nicht.
#
# Die vorhandenen Suiten test-chat-hook-installation.sh und
# test-chat-hook-registry.sh riefen wb-harness-run stets DIREKT auf und
# pruefen damit nur den MECHANISMUS -- nie seinen tatsaechlichen Aufrufer.
# Genau diese Luecke deckt diese Suite: ein ECHTER pi-worker-Spawn ueber den
# claude-Zweig, danach die Kontrolle, ob die Installation gelaufen ist.
#
# DIE VIER AUSSAGEN:
#   1  Ein Spawn ueber den claude-Zweig legt den Haken an und traegt ihn in
#      settings.json ein -- OHNE dass irgendetwas wb-harness-run oder
#      wb-chat-hook-install von Hand aufruft.
#   2  Fremde Hooks/Einstellungen in derselben Datei bleiben unveraendert.
#   3  Ein zweiter Spawn (anderer Worker, selbe Datei) traegt den Haken
#      NICHT ein zweites Mal ein.
#   4  Die echte Umgebung (~/.pi-workers, Rollenregister) bleibt unberuehrt.
#
# ISOLATION: eigener tmux-Socket, eigenes HOME, ein Schirm statt der echten
# claude-CLI, eigene Modell-Registry -- niemals eine laufende Sitzung.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-claudechathook-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="h$(date +%s)$$$RANDOM"

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
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

echo "== pi-worker (claude-Zweig): loest die Chat-Zuordnung wirklich aus (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-chat-hook-install" ] || ueberspringen "shell/wb-chat-hook-install fehlt"

# --- Die Testumgebung, vollstaendig selbst hergestellt ----------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent: zeigt das Bereitschaftszeichen und echot den Rest, statt ihn
# zu schlucken (die Absende-Pruefung braucht das seit 2026-08-17, um den Inhalt zu
# belegen, nicht nur die leere Eingabezeile). Diese Suite prueft NICHT selbst den
# injizierten Text (das tut test-pi-worker-worktreehinweis.sh schon) -- nur, ob
# die Installation lief.
cat > "$TESTHOME/.local/bin/claude" <<'SHIMEOF'
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec cat
SHIMEOF
chmod +x "$TESTHOME/.local/bin/claude"

for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done

# Die ECHTEN Werkzeuge -- sie entscheiden hier mit, kein Platzhalter.
for w in wb-state wb-worktree wb-pane-write wb-mensch wb-rolle; do
  cp "$REPO/$w" "$TESTHOME/.local/bin/$w"
  chmod +x "$TESTHOME/.local/bin/$w"
done
# wb-chat-hook-install NICHT hierher kopiert: der Punkt dieser Suite ist,
# dass pi-worker die REPO-Fassung neben sich selbst findet (dieselbe
# Bauart wie wb-rolle/wb-pane-write), ohne Installationsschritt.
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"
mkdir -p "$TESTHOME/.claude/roles"
printf 'Testrolle worker\n' > "$TESTHOME/.claude/roles/agent.md"

# Vorher-Stand der ECHTEN Register -- der Lauf darf sie nicht anfassen.
ECHT_ROLLEN="$HOME/.pi-workers/rollen"
ROLLEN_VORHER="$(ls -1 "$ECHT_ROLLEN" 2>/dev/null | wc -l | tr -d ' ')"

# settings.json traegt schon FREMDE Eintraege -- Aussage 2 haengt daran.
printf '%s\n' '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/fremd/guard.sh"}]}]}, "model": "opus"}' \
  > "$TESTHOME/.claude/settings.json"

HOME="$TESTHOME" PATH="$TESTHOME/.local/bin:$PATH" \
  "$TESTHOME/.local/bin/wb-state" settings set workerWorktrees false >/dev/null 2>&1

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"
SETTINGS="$TESTHOME/.claude/settings.json"

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

# Eine Workbench-Session, in die pi-worker seine Panes haengen kann.
tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

echo
echo "-- 1: erster Spawn ueber den claude-Zweig --"
WORKER_A="a$MARKE"
AUS_A="$(pi "$WORKER_A" claude-opus5 "$TESTHOME/arbeit" "Testauftrag $MARKE")"
RC_A=$?
if [ "$RC_A" -ne 0 ]; then
  bad "1: pi-worker endete mit rc=$RC_A"
  printf '%s\n' "$AUS_A" | sed 's/^/      | /' | tail -20
else
  [ -x "$HAKEN" ] && ok "1: der Haken existiert nach dem claude-Spawn" \
    || bad "1: $HAKEN fehlt -- die Installation lief nicht"
  [ "$(hookzahl)" = 1 ] && ok "1: settings.json traegt genau einen Eintrag auf den Haken" \
    || bad "1: settings.json traegt den Haken nicht (oder mehrfach): $(hookzahl)"
  case "$AUS_A" in *"Chat-Zuordnung als SessionStart-Hook"*) ok "1: die Ausgabe bestaetigt den Eintrag" ;;
    *) bad "1: keine Bestaetigung in der Ausgabe" ;; esac
fi

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
echo "-- 3: zweiter Spawn (anderer Worker) traegt den Haken NICHT noch einmal ein --"
WORKER_B="b$MARKE"
AUS_B="$(pi "$WORKER_B" claude-opus5 "$TESTHOME/arbeit" "Testauftrag B $MARKE")"
RC_B=$?
if [ "$RC_B" -ne 0 ]; then
  bad "3: pi-worker endete mit rc=$RC_B"
  printf '%s\n' "$AUS_B" | sed 's/^/      | /' | tail -20
else
  [ "$(hookzahl)" = 1 ] && ok "3: nach dem zweiten Spawn steht der Haken weiterhin genau einmal da" \
    || bad "3: der Haken steht $(hookzahl)x in settings.json"
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
if [ ! -e "$HOME/.pi-workers/results/$WORKER_A" ] && [ ! -e "$HOME/.pi-workers/results/$WORKER_B" ]; then
  ok "keine Ergebnisordner fuer die Testworker unter dem echten HOME"
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
