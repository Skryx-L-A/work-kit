#!/usr/bin/env bash
# test-context-guard-panes-einmal.sh -- dieselbe Pane-Liste (`tmux list-panes -a -F
# '#{pane_id}'`) wird je Poll-Zyklus hoechstens EINMAL geholt, unabhaengig von der
# Zahl der Worker-Panes.
#
# ANLASS (2026-09-03, Audit "gleiche Pane-Liste mehrfach im selben Takt"):
# orch_pane_gone(), check_worker_results(), check_post_mail(), der Kompaktier-Block
# und der Worker-Durchlauf fragten je fuer sich dieselbe Vollserver-Auflistung ab --
# gemessen 6 Aufrufe je Zyklus bei 2 Workern, statt der 1 Aufruf, den die Buendelung
# seither liefert. Gemessen an den Herzschlag-Dateien lief der tatsaechliche Takt
# dadurch bei 95-97s statt der codierten 60s.
#
# WARUM HIER KEIN VORHER/NACHHER-VERGLEICH (MEHR) STEHT: eine fruehere Fassung dieser
# Datei baute den git-HEAD-Stand von context-guard live daneben und verglich beide
# Zahlen. Das ging, solange die Aenderung uncommittet neben HEAD lag -- SOBALD sie
# committet ist, IST der HEAD-Stand der neue Stand, und der Vergleich stellt
# "keine Senkung" fest, obwohl nichts kaputt ist (Befund vom Orchestrator, 2026-09-03,
# beim Nachfahren vor dem Merge: 3/1 statt 4/4 bzw. 2/2 statt 4/4). Ein Test, der nur
# gruen ist, solange der eigene Code UNCOMMITTET bleibt, ist ab dem naechsten Merge
# dauerhaft rot -- genau das Werkzeug, an das man sich gewoehnt und dessen echte
# Meldungen man dann uebersieht. Die Zahlen 6 auf 1 sind eine Tatsache von heute (siehe
# Commit-Nachricht und Ergebnis-File); diese Datei prueft stattdessen die Zusage, die
# auch naechstes Jahr noch gelten soll: hoechstens ein Aufruf je Zyklus.
#
# GEMESSEN WIRD HIER, NICHT GESCHAETZT: ein Stellvertreter-`tmux` protokolliert JEDEN
# Aufruf in eine Datei und reicht ihn an den echten tmux-Testsocket weiter -- die
# Wache laeuft also normal, mit echten Panes.
#
# ISOLATION: eigener Socket mit PID im Namen, eigenes HOME aus mktemp -d. Die Wache
# im Worktree wird NICHT nach ~/.local/bin ausgerollt -- nur eine Kopie in ein
# Wegwerfverzeichnis, exakt wie die Schwestersuiten es schon tun.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-cgpanes-$$"
TESTHOME="$(mktemp -d)"
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

GUARDPID=""
cleanup() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

echo "== test-context-guard-panes-einmal: hoechstens eine Pane-Liste je Poll-Zyklus =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/context-guard" ] || ueberspringen "$REPO/context-guard fehlt oder ist nicht ausfuehrbar"

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench" \
         "$TESTHOME/.pi-workers/results"

# Fake `wb-state` (nur `wache_an` wird gefragt -- "an" fuer beide Rollen) und `wb-post`
# (nichts Ungelesenes, fuer check_post_mail).
cat > "$BIN/wb-state" <<'EOF'
#!/bin/sh
case " $* " in
  *" wache "*" get "*) echo "an" ;;
  *) exit 1 ;;
esac
EOF
cat > "$BIN/wb-post" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$BIN/wb-state" "$BIN/wb-post"

# Der Stellvertreter: JEDEN Aufruf in eine Datei protokollieren, dann an den echten
# tmux-Testsocket weiterreichen -- die Wache bekommt echte Antworten, wir bekommen
# die Zaehlung.
CALLLOG="$TESTHOME/tmux-calls.log"
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$CALLLOG"
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Buehne: ein Orchestrator-Pane, zwei Worker-Panes -------------------------------
tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgpanes -c /tmp -x 120 -y 30 'while :; do sleep 30; done'
ORCH="$(tm list-panes -t '=wb-Cgpanes' -F '#{pane_id}' | head -1)"
tm set -p -t "$ORCH" @wb_role orchestrator
for n in bauer pruefer; do
  tm new-window -d -t '=wb-Cgpanes:' -n "$n" 'while :; do sleep 30; done'
  p="$(tm list-panes -t "=wb-Cgpanes:$n" -F '#{pane_id}' | head -1)"
  tm set -p -t "$p" @wb_role worker
  tm set -p -t "$p" @wb_worker "$n"
done

cp "$REPO/context-guard" "$BIN/context-guard"
chmod +x "$BIN/context-guard"

GLOG="$TESTHOME/guard.log"
: > "$CALLLOG"
PATH="$PANE_PATH" HOME="$TESTHOME" POLL=2 "$BIN/context-guard" --auto "$ORCH" \
  > "$GLOG" 2>&1 &
GUARDPID=$!
# Auf den Start warten ("orchestrator=" markiert ihn), danach ueber mehrere
# POLL=2-Zyklen mitzaehlen, fuer eine belastbare Stichprobe.
d=$((SECONDS + 15))
until grep -q "orchestrator=" "$GLOG" 2>/dev/null; do
  [ $SECONDS -ge "$d" ] && break
  sleep 0.2
done
sleep 9
kill "$GUARDPID" 2>/dev/null
wait "$GUARDPID" 2>/dev/null
GUARDPID=""

# Zwei Zahlen aus demselben Log: die Zielzeile, und ein von dieser Aenderung
# UNBERUEHRTER Zyklenzaehler -- `list-panes -s -t =wb-Cgpanes ...` (Worker-
# Neuermittlung im AUTO-Modus) laeuft GENAU EINMAL je abgeschlossenem Poll, NUR aus
# der Hauptschleife heraus (anders als `display -p -t $ORCH #{session_name}`, das
# auch beim Start einmal zusaetzlich laeuft und die Zykluszahl damit verfaelscht
# haette -- gemessen, nicht geraten).
ZIEL="$(grep -c '^list-panes -a -F #{pane_id}$' "$CALLLOG" 2>/dev/null || echo 0)"
ZYKLEN="$(grep -c '^list-panes -s -t =wb-Cgpanes -F #{pane_id}:#{@wb_worker}$' "$CALLLOG" 2>/dev/null || echo 0)"

echo "      | $ZIEL Aufruf(e) von 'list-panes -a -F #{pane_id}' ueber $ZYKLEN Poll-Zyklen (2 Worker-Panes)"

if [ "$ZYKLEN" -ge 2 ]; then
  ok "Testaufbau: mindestens 2 vollstaendige Poll-Zyklen gemessen ($ZYKLEN)"
else
  bad "Testaufbau: zu wenige Poll-Zyklen gemessen ($ZYKLEN) -- das Zeitfenster reicht nicht"
fi

# DIE ZUSAGE: hoechstens EIN Aufruf je Zyklus, unabhaengig von der Worker-Zahl (hier 2,
# obwohl bis zu 3+2=5 Stellen je Zyklus fragen koennten: orch_pane_gone,
# check_worker_results, check_post_mail, Kompaktier-Block, Worker-Durchlauf).
if [ "$ZIEL" -le "$ZYKLEN" ]; then
  ok "hoechstens ein Aufruf je Poll-Zyklus, unabhaengig von der Worker-Zahl ($ZIEL Aufrufe / $ZYKLEN Zyklen)"
else
  bad "mehr als ein Aufruf je Zyklus gemessen ($ZIEL / $ZYKLEN) -- die Buendelung greift nicht"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
