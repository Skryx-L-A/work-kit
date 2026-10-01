#!/usr/bin/env bash
# test-harness-wiederbelebung.sh — V1 und V3: der Weg zurueck steht in der Registry.
#
# Anlass (Messung 2026-08-06): wb-revive baute die Wiederaufnahme mit einer
# Textersetzung auf das Wort "claude " und konnte deshalb genau EINEN Harness
# wiederbeleben; der `resume`-Block der Registry wurde beim Wiederbeleben von keinem
# Harness gelesen, er wirkte nur beim ersten Spawn. Und drei Harnesses haengten ihre
# Fortsetzen-Flags an JEDEN Start, auch an den ersten — ein frischer Worker erbte damit
# eine fremde Unterhaltung.
#
# Geprueft wird:
#   1  Ein NICHT-Claude-Harness kommt mit seiner Unterhaltung zurueck: die Flags aus
#      der Registry stehen in der neuen Befehlszeile, der Pane laeuft danach.
#   2  Ein Harness OHNE resume-Block: der Pane kommt trotzdem zurueck, aber LEER, und
#      die Meldung sagt es. Ein stiller Neuanfang waere schlechter.
#   3  Der Registry-Weg ueber wb-harness-run: dort erreicht kein Flag von aussen die
#      innere CLI — auch das wird gesagt statt vorgetaeuscht.
#   4  claude mit gemerkter Sitzungskennung: die Kennung aus der Zustandsdatei landet
#      in der Zeile; ohne sie greift fallbackArgs.
#   5  Ein Pane mit @wb_role, dessen Harness unbekannt ist: kommt zurueck und sagt es.
#      Ein Pane OHNE @wb_role bleibt unberuehrt.
#   6  V3: `wb-state models resolve` haengt bei probe 'revive-only' NICHTS an den
#      ersten Spawn — und bei 'always' sehr wohl (Gegenprobe, damit der Test nicht
#      nur beweist, dass ueberhaupt nichts passiert).
#   7  V3 am ausgelieferten Stand: in shell/models.default.json traegt kein Harness
#      mehr probe 'always'.
#   8  --resume-args wird in wb-harness-run gegen den resume-Block gehalten.
#   9  Die Kennung je Harness (2026-09-05, resume.kennung): zwei Panes desselben
#      Harness in EINEM Verzeichnis unter EINEM HOME bekommen je ihre eigene
#      Unterhaltung (ueber @wb_started), ohne Startzeit wird bei zwei Treffern nicht
#      geraten (fallbackArgs), eine Unterhaltung aus einem fremden Verzeichnis oder
#      von NACH dem Tod des Panes zaehlt nicht. Alle drei Verfahren mit Fixtures:
#      cline-sessions, jcode-sessions, forge-sqlite — letzteres ueber einen
#      '/bin/sh -c'-Einzeiler mit resume.anker, weil die Flags dort hinter das
#      LETZTE Vorkommen des Programmworts gehoeren, nicht hinter 'sh'.
#   10 wb-code uebersetzt --resume <id> eines Registry-Harness in --resume-args
#      '<resume.args mit id>' fuer wb-harness-run (der Weg des Oberflaechen-Knopfes).
#   11 --resume ohne --harness bleibt claude, auch wenn die Einstellung pi sagt.
#
# ALLE Flags in den Fixtures sind ERFUNDEN ('--wiederauf', '--fortsetzen-mit') und
# stehen vor diesem Lauf nirgends. Taucht so eine Zeichenkette in der Befehlszeile auf,
# kann sie NUR aus der Registry gekommen sein — nicht aus dem Code, nicht aus einem
# ausgelieferten Preset, nicht aus der Maschine.
#
# SICHERHEIT: eigener tmux-Socket, eigenes HOME, eigene Registry. Der Prueflig laeuft
# in einem PANE des Testservers (nur dort zeigt sein $TMUX dorthin), zusaetzlich liegt
# ein tmux-Schirm vorn im PATH. Die global gebundenen tmux-Hooks werden abgeschaltet.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-hwieder-$$"
TESTHOME="$(mktemp -d)"
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
STATES="$TESTHOME/.claude/workbench/sessions"

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$STATES" "$TESTHOME/.local/state"
for w in wb-revive wb-state wb-harness-run wb-resume-id; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/*

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Eigene Registry. 'pi' und 'claude' tragen hier ERFUNDENE Fortsetzen-Flags, damit ein
# Treffer in der Befehlszeile nur aus dieser Datei stammen kann. 'stumm' hat keinen
# resume-Block, 'fern' hat einen, ist aber nur ueber wb-harness-run erreichbar.
mkdir -p "$(dirname "$REG")"
cat > "$REG" <<'REGEOF'
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi", "command": "pi", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--wiederauf"], "probe": "revive-only"}
    },
    {
      "id": "claude", "label": "Pruef-Claude", "command": "claude", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--fortsetzen-mit", "{resumeId}"],
                 "fallbackArgs": ["--wiederauf"], "probe": "revive-only"}
    },
    {
      "id": "stumm", "label": "Harness ohne Fortsetzen", "command": "stummcli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯"
    },
    {
      "id": "fern", "label": "Nur ueber wb-harness-run", "command": "ferncli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--wiederauf"], "probe": "revive-only"}
    },
    {
      "id": "pruef", "label": "Nur zum Pruefen der Durchreiche", "command": "pruefcli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--wiederauf"], "probe": "revive-only"}
    },
    {
      "id": "pruefid", "label": "Durchreiche mit Kennung", "command": "pruefidcli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--fortsetzen-mit", "{resumeId}"], "probe": "revive-only"}
    },
    {
      "id": "immer", "label": "Gegenprobe mit probe always", "command": "immercli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--wiederauf"], "probe": "always"}
    },
    {
      "id": "kenncline", "label": "Kennung wie cline", "command": "kennclinecli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--fortsetzen-mit", "{resumeId}"], "fallbackArgs": ["--wiederauf"],
                 "probe": "revive-only",
                 "kennung": {"verfahren": "cline-sessions", "ort": "~/kenn-cline/*/*.json"}}
    },
    {
      "id": "kennjcode", "label": "Kennung wie jcode", "command": "kennjcodecli",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--fortsetzen-mit", "{resumeId}"], "probe": "revive-only",
                 "kennung": {"verfahren": "jcode-sessions", "ort": "~/kenn-jcode/session_*.json"}}
    },
    {
      "id": "kennforge", "label": "Kennung wie forge, Startzeile sh -c", "command": "/bin/sh",
      "args": ["-c", "kennforgecli config {model} >/dev/null 2>&1; exec kennforgecli"],
      "cwdMode": "cd", "readyPattern": "❯", "promptPattern": "^❯",
      "resume": {"args": ["--fortsetzen-mit", "{resumeId}"], "probe": "revive-only",
                 "anker": "kennforgecli",
                 "kennung": {"verfahren": "forge-sqlite", "ort": "~/kenn-forge.db"}}
    }
  ],
  "models": [
    {"id": "m-stumm", "label": "m-stumm", "harness": "stumm", "provider": "pruefprovider",
     "modelRef": "m1", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-fern", "label": "m-fern", "harness": "fern", "provider": "pruefprovider",
     "modelRef": "m2", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-immer", "label": "m-immer", "harness": "immer", "provider": "pruefprovider",
     "modelRef": "m3", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-pruef", "label": "m-pruef", "harness": "pruef", "provider": "pruefprovider",
     "modelRef": "m4", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-pruefid", "label": "m-pruefid", "harness": "pruefid", "provider": "pruefprovider",
     "modelRef": "m5", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-kenncline", "label": "m-kenncline", "harness": "kenncline", "provider": "pruefprovider",
     "modelRef": "m6", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-kennjcode", "label": "m-kennjcode", "harness": "kennjcode", "provider": "pruefprovider",
     "modelRef": "m7", "roles": ["worker"], "machines": ["mac", "host2"]},
    {"id": "m-kennforge", "label": "m-kennforge", "harness": "kennforge", "provider": "pruefprovider",
     "modelRef": "m8", "roles": ["worker"], "machines": ["mac", "host2"]}
  ]
}
REGEOF

# Fake-CLIs: schreiben ihr argv weg und leben nur weiter, WENN ein Fortsetzen-Flag
# dabei ist. Sonst enden sie sofort — genau der Absturz, den wb-revive reparieren soll.
MARKER="$TESTHOME/argv.log"
: > "$MARKER"
for c in pi claude stummcli ferncli immercli kennclinecli kennjcodecli kennforgecli; do
  cat > "$SHIM/$c" <<CLIEOF
#!/bin/sh
echo "$c ARGV: \$*" >> "$MARKER"
case " \$* " in
  *" --wiederauf "*|*" --fortsetzen-mit "*) while :; do sleep 1; done ;;
  *) exit 9 ;;
esac
CLIEOF
  chmod +x "$SHIM/$c"
done

for c in pruefcli pruefidcli; do
  cat > "$SHIM/$c" <<CLIEOF
#!/bin/sh
echo "$c ARGV: \$*" >> "$MARKER"
exit 0
CLIEOF
  chmod +x "$SHIM/$c"
done

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-harness-wiederbelebung: Fortsetzen aus der Registry (V1) + erster Spawn bleibt leer (V3) =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp -x 100 -y 30
CTRL="$(tm list-panes -t steuer -F '#{pane_id}' | head -1)"
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh
# `tmux respawn-pane` (wb-revive) startet die neue Shell OHNE das inline
# 'PATH=... exec claude' der ERSTEN Erzeugung -- sie bekommt nur das ererbte
# PATH. zsh (der Default-Shell dieser Maschine) sourced dabei IMMER, auch
# nicht-interaktiv, das systemweite /etc/zshenv, und das setzt hier
# 'PATH=$HOME/.local/bin:$PATH' -- genau der Pfad des ECHTEN installierten
# claude. Ohne diese Zeile laeuft nach jedem wb-revive-Respawn also der
# ECHTE claude statt des Fake-CLI aus $SHIM (gemessen 2026-08-09: Pane bleibt
# leben, aber $MARKER bekommt nie eine zweite Zeile). bash sourced fuer
# 'sh -c' keine vergleichbare Datei, bleibt beim ererbten PATH.
tm set-option -g default-shell /bin/bash

lauf() { # lauf <kommando> -> setzt OUT und RC
  local f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t "$CTRL" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; $1 ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 40 "lauf: $1" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

SESS="wb-Hwieder-$$"
tm set-option -wg remain-on-exit on
tm new-session -d -s "$SESS" -c /tmp -x 100 -y 30

toter_pane() { # toter_pane <startbefehl> [rolle] -> Pane-Id
  local p deadline
  p="$(tm new-window -d -t "=$SESS:" -P -F '#{pane_id}' "PATH='$PANE_PATH' $1" 2>/dev/null)"
  [ -n "$p" ] || return 1
  tm set -p -t "$p" @wb_cmd "$1"
  [ -n "${2:-}" ] && tm set -p -t "$p" @wb_role "$2"
  # Abfrage mit Frist statt eines festen 'sleep 1' (Betriebsbefund 2026-08-20,
  # Abnahme des Auftrags zu den drei roten Suiten): wie lange der Startbefehl
  # bis zum Sterben braucht, haengt am System (Registry-Aufloesung, wie viele
  # andere Prozesse gerade laufen) -- ein fester Sekundenwert traf das gemessen
  # nur in rund 80% der Laeufe, auf ALTEM wie auf NEUEM Stand gleichermassen
  # (10 Laeufe je Seite, 1-2 Fehlschlaege je Seite bei genau dieser Zeile). Die
  # Suite bewertet den Zustand ohnehin selbst (dead_of() gleich nach dem
  # Aufruf) -- diese Frist macht nur die MESSUNG zuverlaessig, nicht die
  # Zusage weicher: bleibt der Pane laenger als 10s am Leben, faellt die
  # nachfolgende Pruefung weiterhin ehrlich durch.
  deadline=$((SECONDS + 10))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(tm display -p -t "$p" '#{pane_dead}' 2>/dev/null)" = 1 ] && break
    sleep 0.2
  done
  printf '%s' "$p"
}
dead_of() { tm display -p -t "$1" '#{pane_dead}' 2>/dev/null; }
cmd_of()  { tm display -p -t "$1" '#{pane_start_command}' 2>/dev/null; }

# ── 1: ein NICHT-Claude-Harness kommt mit seiner Unterhaltung zurueck ──────
echo "-- 1: Harness 'pi' (nicht claude) wird aus der Registry fortgesetzt --"
P1="$(toter_pane "exec pi --model lmalpha:9b" worker)"
[ "$(dead_of "$P1")" = 1 ] && ok "1: der Pane ist tot -- Testaufbau korrekt" \
                           || bad "1: Testaufbau fehlerhaft, der Pane lebt noch"
lauf "wb-revive '$P1'"
sleep 1
case "$(cmd_of "$P1")" in
  *--wiederauf*) ok "1: die neue Zeile traegt '--wiederauf' aus der Registry" ;;
  *) bad "1: '--wiederauf' fehlt in der neuen Zeile: $(cmd_of "$P1")" ;;
esac
[ "$(dead_of "$P1")" = 0 ] && ok "1: der Pane laeuft wieder" \
                           || bad "1: der Pane ist nach der Wiederbelebung tot"
grep -q -- '--wiederauf' "$MARKER" && ok "1: die CLI hat das Flag wirklich bekommen" \
                                   || bad "1: kein Aufruf mit '--wiederauf' im Protokoll"
printf '%s' "$OUT" | grep -q 'fortgesetzt mit' && ok "1: die Meldung nennt das Fortsetzen" \
                                               || bad "1: Meldung ohne Fortsetzen-Hinweis: $OUT"

# ── 2: ein Harness ohne resume-Block kommt LEER zurueck und sagt es ────────
echo
echo "-- 2: ein Harness ohne resume-Block kann nicht fortsetzen --"
cp "$REG" "$REG.orig"
/usr/bin/python3 - "$REG" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
for h in d["harnesses"]:
    if h["id"] == "pi":
        h["resume"] = {}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY2
P2="$(toter_pane "exec pi --model lmalpha:9b" worker)"
lauf "wb-revive '$P2'"
sleep 1
printf '%s' "$OUT" | grep -q 'kennt kein Fortsetzen' \
  && ok "2: die Meldung sagt, dass dieser Harness nicht fortsetzen kann" \
  || bad "2: Meldung ohne den Hinweis: $OUT"
case "$(cmd_of "$P2")" in
  *--wiederauf*|*--fortsetzen-mit*) bad "2: es wurde doch ein Fortsetzen-Flag eingefuegt" ;;
  *) ok "2: kein Fortsetzen-Flag in der neuen Zeile" ;;
esac
printf '%s' "$OUT" | grep -q "Harness 'pi'" \
  && ok "2: die Meldung nennt den Harness beim Namen" \
  || bad "2: Meldung ohne Harness-Namen: $OUT"
mv "$REG.orig" "$REG"

# ── 3: der Registry-Weg ueber wb-harness-run ──────────────────────────────
echo
echo "-- 3: ueber wb-harness-run kommt das Fortsetzen jetzt an --"
P3="$(toter_pane "exec $BIN/wb-harness-run --model m-fern --role worker --dir /tmp --name f1" worker)"
[ "$(dead_of "$P3")" = 1 ] && ok "3: der Pane ist tot -- Testaufbau korrekt" \
                           || bad "3: Testaufbau fehlerhaft, der Pane lebt noch"
lauf "wb-revive '$P3'"
sleep 2
case "$(cmd_of "$P3")" in
  *--resume-args*) ok "3: wb-revive reicht die Flags als --resume-args weiter" ;;
  *) bad "3: kein --resume-args in der neuen Zeile: $(cmd_of "$P3")" ;;
esac
grep -q 'ferncli ARGV:.*--wiederauf' "$MARKER" \
  && ok "3: die INNERE CLI hat das Fortsetzen-Flag bekommen" \
  || bad "3: ferncli ohne '--wiederauf' aufgerufen: $(grep ferncli "$MARKER" | tail -1)"
[ "$(dead_of "$P3")" = 0 ] && ok "3: der Pane laeuft wieder" \
                           || bad "3: der Pane ist nach der Wiederbelebung tot"

# ── 4: claude mit und ohne gemerkte Sitzungskennung ────────────────────────
echo
echo "-- 4: claude nimmt die Kennung dieser Sitzung, sonst den Ersatz --"
P4="$(toter_pane "exec claude --model opus" worker)"
S4="$(tm display -p -t "$P4" '#{session_name}')"
cat > "$STATES/pruef.json" <<STEOF
{"tmuxSession": "$S4", "claudeSessionId": "pruef-kennung-4711"}
STEOF
lauf "wb-revive '$P4'"
sleep 1
C4="$(cmd_of "$P4")"
case "$C4" in
  *--fortsetzen-mit*pruef-kennung-4711*)
    ok "4: Flag aus der Registry UND Kennung aus der Zustandsdatei stehen in der Zeile" ;;
  *) bad "4: erwartet '--fortsetzen-mit' + 'pruef-kennung-4711', bekommen: $C4" ;;
esac
grep -q 'pruef-kennung-4711' "$MARKER" \
  && ok "4: die CLI hat die Kennung wirklich bekommen" \
  || bad "4: kein Aufruf mit der Kennung im Protokoll"

rm -f "$STATES/pruef.json"
P4B="$(toter_pane "exec claude --model opus" worker)"
lauf "wb-revive '$P4B'"
sleep 1
case "$(cmd_of "$P4B")" in
  *--wiederauf*) ok "4: ohne Kennung greift fallbackArgs" ;;
  *) bad "4: fallbackArgs griff nicht: $(cmd_of "$P4B")" ;;
esac

# ── 5: unbekannter Harness — mit und ohne @wb_role ─────────────────────────
echo
echo "-- 5: unbekannter Harness --"
P5="$(toter_pane "exec /usr/bin/false" worker)"
lauf "wb-revive '$P5'"
printf '%s' "$OUT" | grep -q 'unbekannt' \
  && ok "5: mit @wb_role wird der Pane behandelt und der Grund genannt" \
  || bad "5: Meldung ohne 'unbekannt': $OUT"
P5B="$(toter_pane "exec /usr/bin/false")"
lauf "wb-revive '$P5B'"
printf '%s' "$OUT" | grep -q 'nichts getan' \
  && ok "5: ohne @wb_role bleibt ein fremder Pane unberuehrt" \
  || bad "5: fremder Pane wurde angefasst: $OUT"

# ── 6: V3 — der erste Spawn bleibt leer ───────────────────────────────────
echo
echo "-- 6: erster Spawn ohne Fortsetzen-Flag (probe 'revive-only') --"
R6="$(PATH="$SHIM:$PATH" HOME="$TESTHOME" "$BIN/wb-state" models resolve m-fern --role worker --dir /tmp --name x 2>&1)"
printf '%s' "$R6" | grep -q '^cmd	' && ok "6: der Aufloeser hat ueberhaupt eine Startzeile geliefert" \
                                     || bad "6: kein Startbefehl aus dem Aufloeser: $R6"
case "$R6" in
  *--wiederauf*) bad "6: probe 'revive-only' hat trotzdem ein Flag angehaengt" ;;
  *) ok "6: probe 'revive-only' haengt beim ersten Spawn nichts an" ;;
esac
R6B="$(PATH="$SHIM:$PATH" HOME="$TESTHOME" "$BIN/wb-state" models resolve m-immer --role worker --dir /tmp --name x 2>&1)"
case "$R6B" in
  *--wiederauf*) ok "6: Gegenprobe — probe 'always' haengt sehr wohl an" ;;
  *) bad "6: Gegenprobe fehlgeschlagen, 'always' haengte nichts an: $R6B" ;;
esac

# ── 7: der ausgelieferte Stand traegt kein 'always' mehr ──────────────────
echo
echo "-- 7: shell/models.default.json --"
UEBRIG="$(/usr/bin/python3 - "$REPO/models.default.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(" ".join(h["id"] for h in d.get("harnesses", [])
                if ((h.get("resume") or {}).get("probe") or "always") == "always"
                and (h.get("resume") or {}).get("args")))
PY
)"
[ -z "$UEBRIG" ] && ok "7: kein ausgelieferter Harness haengt sein Fortsetzen an den ersten Spawn" \
                 || bad "7: noch auf 'always': $UEBRIG"


# ── 8: die Durchreiche laesst nur Fortsetzen-Flags aus der Registry durch ──
echo
echo "-- 8: --resume-args wird gegen den resume-Block gehalten --"
hrun() {   # hrun <modell> <resume-args> -> setzt HOUT
  HOUT="$(PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" "$BIN/wb-harness-run" \
          --model "$1" --role worker --dir /tmp --name p1 --resume-args "$2" 2>&1)"
}
BEWEIS="$TESTHOME/eingeschleust"

: > "$MARKER"
hrun m-pruef '--wiederauf'
grep -q 'pruefcli ARGV:.*--wiederauf' "$MARKER" \
  && ok "8: ein Flag AUS dem resume-Block kommt bei der CLI an" \
  || bad "8: das erlaubte Flag kam nicht an: $(cat "$MARKER")"

: > "$MARKER"; rm -f "$BEWEIS"
hrun m-pruef "--wiederauf; touch $BEWEIS"
[ -e "$BEWEIS" ] && bad "8: ein angehaengter Befehl wurde ausgefuehrt" \
                 || ok "8: ein angehaengter Befehl wird NICHT ausgefuehrt"
grep -q -- '--wiederauf' "$MARKER" && bad "8: die manipulierte Folge kam trotzdem durch" \
                                   || ok "8: die manipulierte Folge wird verworfen"
printf '%s' "$HOUT" | grep -q 'verworfen' \
  && ok "8: und der Start sagt, dass er ohne Fortsetzen weiterlaeuft" \
  || bad "8: keine Meldung ueber das Verwerfen: $HOUT"
grep -q 'pruefcli ARGV:' "$MARKER" \
  && ok "8: die CLI wird trotzdem gestartet (kein Pane, der gar nicht zurueckkommt)" \
  || bad "8: die CLI wurde gar nicht gestartet"

: > "$MARKER"
hrun m-pruef '--boese'
grep -q -- '--boese' "$MARKER" && bad "8: ein fremdes Flag kam durch" \
                               || ok "8: ein Flag, das nicht im resume-Block steht, wird verworfen"

: > "$MARKER"
hrun m-pruefid '--fortsetzen-mit abc-123.XY_9'
grep -q 'pruefidcli ARGV:.*--fortsetzen-mit abc-123.XY_9' "$MARKER" \
  && ok "8: eine plausible Kennung fuellt den Platzhalter {resumeId}" \
  || bad "8: die Kennung kam nicht an: $(cat "$MARKER")"

: > "$MARKER"; rm -f "$BEWEIS"
hrun m-pruefid "--fortsetzen-mit x;touch $BEWEIS"
[ -e "$BEWEIS" ] && bad "8: eine Kennung mit Semikolon wurde ausgefuehrt" \
                 || ok "8: eine Kennung, die keine sein kann, wird verworfen"

# ── 9: die Kennung je Harness ─────────────────────────────────────────────
echo
echo "-- 9: resume.kennung — jeder Pane findet SEINE Unterhaltung --"
JETZT="$(date +%s)"
KWORK="$TESTHOME/kenn-work"; KFREMD="$TESTHOME/kenn-fremd"
mkdir -p "$KWORK" "$KFREMD" "$TESTHOME/kenn-cline" "$TESTHOME/kenn-jcode"
# Fixtures: Sitzung A (2 s nach Pane 1), B (2 s nach Pane 2), F (fremdes Verzeichnis),
# Z (erst NACH dem Tod jedes Panes dieses Laufs) — in allen drei Ablageformen.
/usr/bin/python3 - "$TESTHOME" "$KWORK" "$KFREMD" "$JETZT" <<'PY'
import datetime, json, os, sqlite3, sys
home, work, fremd, jetzt = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def sql(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.000000")
cl = [("kenn-A", work, jetzt - 298), ("kenn-B", work, jetzt - 238),
      ("kenn-F", fremd, jetzt - 297), ("kenn-Z", work, jetzt + 3600)]
for sid, cwd, t in cl:
    d = os.path.join(home, "kenn-cline", sid); os.makedirs(d, exist_ok=True)
    json.dump({"session_id": sid, "cwd": cwd, "started_at": iso(t)},
              open(os.path.join(d, sid + ".json"), "w"))
    open(os.path.join(d, sid + ".messages.json"), "w").write("[]")
for sid, cwd, t in cl:
    json.dump({"id": "session_" + sid, "working_dir": cwd, "created_at": iso(t)},
              open(os.path.join(home, "kenn-jcode", "session_%s.json" % sid), "w"))
con = sqlite3.connect(os.path.join(home, "kenn-forge.db"))
con.execute("create table conversations (conversation_id text primary key, title text, "
            "workspace_id bigint not null, context text, created_at timestamp not null, "
            "updated_at timestamp, metrics text)")
for sid, cwd, t in cl:
    con.execute("insert into conversations values (?, null, 1, ?, ?, null, null)",
                (sid, "x<current_working_directory>%s</current_working_directory>y" % cwd, sql(t)))
con.commit(); con.close()
PY

kenn_pane() {   # <modell> <name> [startsekunde] -> toter Pane mit @wb_started
  local p
  p="$(toter_pane "exec $BIN/wb-harness-run --model $1 --role worker --dir $KWORK --name $2" worker)"
  [ -n "${3:-}" ] && tm set -p -t "$p" @wb_started "$3"
  printf '%s' "$p"
}

# 9a: zwei Panes, ein Verzeichnis, ein HOME — jeder seine eigene Kennung (cline-Verfahren)
: > "$MARKER"
K1="$(kenn_pane m-kenncline k1 $((JETZT - 300)))"
K2="$(kenn_pane m-kenncline k2 $((JETZT - 240)))"
lauf "wb-revive '$K1'"; O1="$OUT"
lauf "wb-revive '$K2'"; O2="$OUT"
sleep 2
case "$O1" in
  *"--fortsetzen-mit kenn-A"*|*"--fortsetzen-mit 'kenn-A'"*) ok "9a: Pane 1 (Start vor A) bekommt kenn-A" ;;
  *) bad "9a: Pane 1 sollte kenn-A bekommen: $O1" ;;
esac
case "$O2" in
  *"--fortsetzen-mit kenn-B"*|*"--fortsetzen-mit 'kenn-B'"*) ok "9a: Pane 2 (Start zwischen A und B) bekommt kenn-B — nicht die juengste, nicht die aelteste, SEINE" ;;
  *) bad "9a: Pane 2 sollte kenn-B bekommen: $O2" ;;
esac
printf '%s' "$O1" | grep -q 'Kennung ueber cline-sessions' \
  && ok "9a: die Meldung nennt das Verfahren" || bad "9a: Meldung ohne Verfahren: $O1"
grep -q 'kennclinecli ARGV:.*--fortsetzen-mit kenn-A' "$MARKER" \
  && ok "9a: die INNERE CLI von Pane 1 hat kenn-A wirklich bekommen" \
  || bad "9a: kennclinecli ohne kenn-A: $(grep kennclinecli "$MARKER")"
grep -q 'kennclinecli ARGV:.*--fortsetzen-mit kenn-B' "$MARKER" \
  && ok "9a: die INNERE CLI von Pane 2 hat kenn-B wirklich bekommen" \
  || bad "9a: kennclinecli ohne kenn-B: $(grep kennclinecli "$MARKER")"
[ "$(dead_of "$K1")" = 0 ] && [ "$(dead_of "$K2")" = 0 ] \
  && ok "9a: beide Panes laufen wieder" || bad "9a: ein Pane ist nach der Wiederbelebung tot"

# 9b: ohne @wb_started und zwei Treffern im Verzeichnis wird NICHT geraten
K3="$(kenn_pane m-kenncline k3)"
lauf "wb-revive '$K3'"
case "$OUT" in
  *"--wiederauf"*) ok "9b: ohne Startzeit und mit zwei Unterhaltungen greift fallbackArgs" ;;
  *) bad "9b: es wurde geraten statt fallbackArgs zu nehmen: $OUT" ;;
esac
printf '%s' "$OUT" | grep -q 'nicht geraten' \
  && ok "9b: und die Meldung sagt, warum" || bad "9b: Meldung ohne Grund: $OUT"

# 9c: ein Pane, das NACH beiden Sitzungen startete, sieht nur kenn-Z — und die liegt
#     nach seinem Tod, zaehlt also nicht: fallbackArgs, mit Grund.
K4="$(kenn_pane m-kenncline k4 $((JETZT - 100)))"
lauf "wb-revive '$K4'"
case "$OUT" in
  *"--wiederauf"*) ok "9c: eine Unterhaltung von NACH dem Tod des Panes zaehlt nicht" ;;
  *"kenn-Z"*) bad "9c: kenn-Z (entstanden nach dem Tod des Panes) wurde genommen: $OUT" ;;
  *) bad "9c: weder fallbackArgs noch kenn-Z: $OUT" ;;
esac
printf '%s' "$OUT" | grep -q 'Zeitfenster' \
  && ok "9c: die Meldung nennt das Zeitfenster" || bad "9c: Meldung ohne Zeitfenster: $OUT"

# 9d: jcode-Verfahren, dieselbe Fixture-Logik, Startzeit zwischen A und B
: > "$MARKER"
K5="$(kenn_pane m-kennjcode k5 $((JETZT - 240)))"
lauf "wb-revive '$K5'"
sleep 2
grep -q 'kennjcodecli ARGV:.*--fortsetzen-mit session_kenn-B' "$MARKER" \
  && ok "9d: jcode-sessions liefert session_kenn-B (working_dir + created_at)" \
  || bad "9d: kennjcodecli ohne session_kenn-B: $(grep kennjcodecli "$MARKER") / $OUT"

# 9e: forge-Verfahren ueber die SQLite-Ablage UND die Startzeile '/bin/sh -c ...; exec
#     kennforgecli': das Flag muss hinter dem LETZTEN kennforgecli landen (resume.anker),
#     sonst bekaeme 'sh' ein Flag und der Pane stuerbe erneut.
: > "$MARKER"
K6="$(kenn_pane m-kennforge k6 $((JETZT - 300)))"
lauf "wb-revive '$K6'"
sleep 2
grep -q 'kennforgecli ARGV:.*--fortsetzen-mit kenn-A' "$MARKER" \
  && ok "9e: forge-sqlite liefert kenn-A, und die INNERE CLI hinter 'exec' bekommt es (anker)" \
  || bad "9e: kennforgecli ohne kenn-A: $(grep kennforgecli "$MARKER") / $OUT"
[ "$(dead_of "$K6")" = 0 ] && ok "9e: der sh -c-Pane laeuft wieder" \
                           || bad "9e: der sh -c-Pane ist nach der Wiederbelebung tot"
grep -q 'kennforgecli ARGV: config' "$MARKER" \
  && ok "9e: der Einzeiler davor lief unveraendert (config-Aufruf im Protokoll)" \
  || bad "9e: der config-Aufruf des Einzeilers fehlt: $(grep kennforgecli "$MARKER")"

# 9f: der ausgelieferte Stand — cline, forge und jcode tragen kennung UND revive-only
AUSGELIEFERT="$(/usr/bin/python3 - "$REPO/models.default.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = []
for h in d.get("harnesses", []):
    r = h.get("resume") or {}
    k = r.get("kennung") or {}
    if h["id"] in ("cline", "forge"):
        if not (r.get("args") and "{resumeId}" in r["args"] and k.get("verfahren") and k.get("ort")
                and r.get("probe") == "revive-only"):
            out.append(h["id"])
    elif k and k.get("verfahren") not in ("cline-sessions", "jcode-sessions", "forge-sqlite"):
        out.append(h["id"] + ":unbekanntes-verfahren")
print(" ".join(out))
PY
)"
JRES="$(/usr/bin/python3 - "$REPO/models.default.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
h = next((x for x in d["harnesses"] if x["id"] == "jcode"), {})  # Kit: jcode is not shipped
print(json.dumps(h.get("resume")))
PY2
)"
[ "$JRES" = "null" ] \
  && ok "9f: jcode.resume bleibt null (haengt reproduzierbar, siehe notes; im Kit nicht ausgeliefert)" \
  || bad "9f: jcode.resume ist '$JRES' statt null"
[ -z "$AUSGELIEFERT" ] \
  && ok "9f: cline und forge tragen {resumeId} + kennung + revive-only; jcode bleibt null; kein unbekanntes Verfahren" \
  || bad "9f: unvollstaendig oder unbekannt: $AUSGELIEFERT"

# ── 10: wb-code uebersetzt --resume <id> eines Registry-Harness in --resume-args ──
# Der Knopf der Oberflaeche ruft `wb-code ... --resume <id>` (test-app-harness-
# wiederbelebung.sh Zusagen 9/10). wb-code baut daraus die Startzeile fuer
# wb-harness-run und muss die Kennung als --resume-args '<resume.args mit id>'
# durchreichen -- sonst kaeme der Pane leer zurueck. Eigenes Wegwerf-HOME mit
# Stellvertretern fuer tmux und die Randwerkzeuge; das echte wb-state/wb-code
# gegen eine Fixture-Registry. Der tmux-Stellvertreter schreibt nur mit.
echo
echo "-- 10: wb-code reicht --resume eines Registry-Harness als --resume-args weiter --"
H10="$(mktemp -d)"
mkdir -p "$H10/.local/bin" "$H10/.claude/workbench" "$H10/proj"
cat > "$H10/.claude/workbench/models.json" <<'REG10'
{ "version": 1,
  "providers": [{"id": "pp", "label": "pp", "kind": "subscription"}],
  "harnesses": [
    { "id": "kc", "label": "kc", "command": "kccli", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "x", "promptPattern": "x",
      "resume": { "args": ["--id", "{resumeId}"], "probe": "revive-only",
        "kennung": {"verfahren": "cline-sessions", "ort": "~/x/*/*.json"} } } ],
  "models": [ {"id": "mkc", "label": "mkc", "harness": "kc", "provider": "pp",
    "modelRef": "m", "roles": ["orchestrator", "worker"], "machines": ["mac", "host2"]} ] }
REG10
cp "$REPO/wb-state" "$H10/.local/bin/wb-state"; chmod +x "$H10/.local/bin/wb-state"
cp "$REPO/wb-code" "$H10/.local/bin/wb-code"; chmod +x "$H10/.local/bin/wb-code"
cat > "$H10/.local/bin/tmux" <<TMX
#!/bin/sh
printf '%s\n' "\$*" >> "$H10/tmux.log"
case "\$1" in ls) exit 1;; has-session) exit 1;; list-panes) echo "%0|orchestrator";; *) exit 0;; esac
TMX
chmod +x "$H10/.local/bin/tmux"
for w in wb-harness-run wb-chat-hook-install context-guard wb-grid wb-belegung wb-remote-view; do
  printf '#!/bin/sh\nexit 0\n' > "$H10/.local/bin/$w"; chmod +x "$H10/.local/bin/$w"
done
# kccli muss existieren, sonst lehnt `wb-state models resolve` den Start ab (Binary-Pruefung).
printf '#!/bin/sh\nexit 0\n' > "$H10/.local/bin/kccli"; chmod +x "$H10/.local/bin/kccli"
: > "$H10/tmux.log"
HOME="$H10" PATH="$H10/.local/bin:$PATH" WB_NO_DISCOVER=1 \
  bash "$REPO/wb-code" "$H10/proj" --harness kc --model mkc --resume "conv-abc-$$" --name w1 >/dev/null 2>&1 || true
# Der tmux-new-session-Aufruf traegt bash -lc <REG_CMD>; die Anfuehrung von @wb_cmd
# schreibt --resume-args '--id conv' als "--resume-args --id\ conv". Geprueft wird auf
# beide Teile in der Zeile, unabhaengig von der genauen Quotierung.
NS="$(grep 'new-session' "$H10/tmux.log" | head -1)"
case "$NS" in
  *"--resume-args"*"--id"*"conv-abc-$$"*) ok "10: wb-code baut --resume-args mit --id conv-abc-$$ fuer wb-harness-run" ;;
  *) bad "10: --resume-args/--id fehlt in der wb-code-Startzeile: $NS" ;;
esac
case "$NS" in
  *"wb-harness-run"*) ok "10: die Startzeile geht ueber wb-harness-run (der Registry-Weg)" ;;
  *) bad "10: kein wb-harness-run in der Startzeile: $NS" ;;
esac
rm -rf "$H10"

# ── 11: --resume ohne --harness bleibt Claude, auch wenn die Einstellung pi sagt ──
# Befund 26.09.2026: orchestratorHarness/Model standen auf pi/qwen. Der Knopf der
# Oberflaeche schickt fuer eine Claude-Sitzung nur `--resume <id>` (revive.ts, der
# Vorgabe-Harness bekommt kein --harness). wb-code nahm den Harness aus der Einstellung
# und brach mit "--resume gilt nur fuer den Claude-Harness" ab -- die Sitzung liess sich
# nicht fortsetzen. Erwartet: claude mit dieser Kennung, das pi-Modell verworfen.
echo
echo "-- 11: --resume ohne --harness startet claude trotz pi in den Einstellungen --"
H11="$(mktemp -d)"
mkdir -p "$H11/.local/bin" "$H11/.claude/workbench" "$H11/proj"
cat > "$H11/.claude/workbench/models.json" <<'REG11'
{ "version": 1,
  "providers": [{"id": "lk", "label": "lk", "kind": "local"}],
  "harnesses": [],
  "models": [ {"id": "qwtest", "label": "qwtest", "harness": "pi", "provider": "lk",
    "modelRef": "q", "roles": ["orchestrator", "worker"], "machines": ["mac", "host2"]} ] }
REG11
printf '{"orchestratorHarness": "pi", "orchestratorModel": "qwtest"}\n' > "$H11/.claude/workbench/settings.json"
cp "$REPO/wb-state" "$H11/.local/bin/wb-state"; chmod +x "$H11/.local/bin/wb-state"
cp "$REPO/wb-code" "$H11/.local/bin/wb-code"; chmod +x "$H11/.local/bin/wb-code"
cat > "$H11/.local/bin/tmux" <<TMX
#!/bin/sh
printf '%s\n' "\$*" >> "$H11/tmux.log"
case "\$1" in ls) exit 1;; has-session) exit 1;; list-panes) echo "%0|orchestrator";; *) exit 0;; esac
TMX
chmod +x "$H11/.local/bin/tmux"
for w in wb-harness-run wb-chat-hook-install context-guard wb-grid wb-belegung wb-remote-view claude pi; do
  printf '#!/bin/sh\nexit 0\n' > "$H11/.local/bin/$w"; chmod +x "$H11/.local/bin/$w"
done
: > "$H11/tmux.log"
A11="$(HOME="$H11" PATH="$H11/.local/bin:$PATH" WB_NO_DISCOVER=1 \
  bash "$REPO/wb-code" "$H11/proj" --resume "conv-claude-$$" --name w1 2>&1 >/dev/null || true)"
NS="$(grep 'new-session' "$H11/tmux.log" | head -1)"
case "$A11" in
  *"gilt nur fuer den Claude-Harness"*) bad "11: wb-code lehnt --resume ab, weil die Einstellung pi sagt: $A11" ;;
  *) ok "11: kein Abbruch wegen des pi-Harness aus der Einstellung" ;;
esac
case "$NS" in
  *claude*"--resume"*"conv-claude-$$"*) ok "11: Startzeile ist claude --resume conv-claude-$$" ;;
  *) bad "11: keine claude-Startzeile mit der Kennung: ${NS:-<kein new-session>} / $A11" ;;
esac
rm -rf "$H11"

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
