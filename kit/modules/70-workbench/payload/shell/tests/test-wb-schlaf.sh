#!/usr/bin/env bash
# test-wb-schlaf.sh -- untaetige Sitzungen schlafen, Ausloeser wecken sie wieder.
#
# ANLASS (der Nutzer, 25.09.2026): untaetige Sitzungen aus dem Speicher nehmen und bei
# Klick oder Anfrage wieder laden, fuer jeden Harness. Gemessen wird auf einem EIGENEN
# tmux-Socket mit eigenem HOME; die Registry ist eine Kopie der lebenden, damit
# wb-revive den Fortsetzungsweg des Harness wirklich nachschlaegt. Der Harness ist eine
# Attrappe namens `claude`, die ihre Argumente mitschreibt und sich ins
# Sitzungsregister eintraegt -- dieselbe Datei, die Claude Code fuehrt.
# Geprueft wird auch, was NICHT passieren darf: ein arbeitender Pane, ein Pane mit
# @wb_schlaf_nie und ein Harness ohne Fortsetzungsweg bleiben wach.
unset TMUX TMUX_PANE
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHLAF="$HERE/../wb-schlaf"
[ -f "$HOME/.claude/workbench/models.json" ] || { echo "UEBERSPRUNGEN: keine Registry"; exit 77; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wbschlaf.XXXXXX")"
SOCK="wbschlaf$$"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
t() { tmux -L "$SOCK" "$@"; }
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null
  case "$TMP" in
    "${TMPDIR:-/tmp}"/wbschlaf.*) rm -rf "$TMP" ;;
    *) echo "Aufraeumen uebersprungen: '$TMP' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

H="$TMP/home"
mkdir -p "$H/.claude/workbench" "$H/.claude/sessions" "$H/.local/bin" "$TMP/bin"
cp "$HOME/.claude/workbench/models.json" "$H/.claude/workbench/"
ln -s "$HOME/.local/bin/wb-state" "$H/.local/bin/wb-state"
ln -s "$HERE/../wb-resume-id" "$H/.local/bin/wb-resume-id" 2>/dev/null

# Attrappe: schreibt ihre Argumente mit, traegt sich ins Register ein, zeigt die
# Eingabemarke und wartet. ARBEITET=1 startet zusaetzlich einen Werkzeugaufruf.
cat > "$TMP/bin/claude" <<EOF
#!/usr/bin/env python3
import json, os, subprocess, sys, time
pane = os.environ.get("TMUX_PANE", "")
with open("$TMP/argv." + pane.lstrip("%"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
json.dump({"pid": os.getpid(), "sessionId": "sid-" + pane.lstrip("%"), "tmux": "t:@1." + pane,
           "status": os.environ.get("REGISTER_STATUS", "idle"),
           "statusUpdatedAt": (time.time() - 7200) * 1000},
          open("$H/.claude/sessions/%d.json" % os.getpid(), "w"))
if os.environ.get("ARBEITET") == "1":
    subprocess.Popen(["sh", "-c", "sleep 600; true"])
print("\\u276f bereit", flush=True)
for _ in sys.stdin:
    pass
time.sleep(3600)
EOF
cp "$TMP/bin/claude" "$TMP/bin/ohnefortsetzung"
chmod +x "$TMP/bin/claude" "$TMP/bin/ohnefortsetzung"

export HOME="$H" WB_TMUX_SOCKET="$SOCK"
t -f /dev/null new-session -d -s t -x 200 -y 50 "sleep 3600"
t set-hook -g after-select-pane "run-shell -b '$SCHLAF hook #{pane_id} >/dev/null 2>&1'"
neu() { # neu <befehl> [env...] -> pane-id
  local cmd="$1"; shift
  local p; p="$(t split-window -d -P -F '#{pane_id}' -t t -e "PATH=$TMP/bin:$PATH" "$@" "$cmd")"
  t set -p -t "$p" @wb_cmd "$cmd"; t set -p -t "$p" @wb_role worker
  t select-layout -t t tiled >/dev/null
  printf '%s' "$p"
}
alt_machen() { # Beobachtung zurueckdatieren: Inhalt "seit 2 h unveraendert"
  python3 - "$H/.local/state/wb-schlaf/beobachtung.json" <<'PY'
import json, sys, time
p = sys.argv[1]; d = json.load(open(p))
for v in d.values(): v["seit"] = time.time() - 7200
json.dump(d, open(p, "w"))
PY
}
laeuft() { t display -p -t "$1" '#{pane_current_command}'; }
warte_auf() { # warte_auf <sekunden> <befehl...>
  local n="$1"; shift
  for _ in $(seq 1 $((n*4))); do "$@" && return 0; sleep 0.25; done; return 1
}

A="$(neu "$TMP/bin/claude --model x")"
B="$(neu "$TMP/bin/claude --model x" -e ARBEITET=1)"
C="$(neu "$TMP/bin/claude --model x")"; t set -p -t "$C" @wb_schlaf_nie 1
D="$(neu "$TMP/bin/claude --model x" -e REGISTER_STATUS=busy)"
E="$(neu "$TMP/bin/ohnefortsetzung --flag")"
sleep 2

echo "A) Einschlafen nur nach der Frist, nur wer untaetig ist"
out="$(python3 "$SCHLAF" runde --min 60)"
[ -z "$(t show -pqv -t "$A" @wb_schlaeft)" ] && ok "A1 erste Beobachtung legt niemanden schlafen" || bad "A1 zu frueh geschlafen" "$out"
alt_machen
out="$(python3 "$SCHLAF" runde --min 60)"
[ -n "$(t show -pqv -t "$A" @wb_schlaeft)" ] && ok "A2 untaetiger Pane schlaeft nach der Frist" || bad "A2 A schlaeft nicht" "$out"
warte_auf 10 bash -c "tmux -L $SOCK capture-pane -p -t $A | grep -q 'schlaeft seit'"
case "$(t show -pqv -t "$A" @wb_schlaf_cmd)" in
  *"--resume"*"sid-${A#%}"*) ok "A3 Aufweckbefehl traegt --resume mit der Kennung aus dem Register" ;;
  *) bad "A3 Aufweckbefehl ohne richtige Kennung" "$(t show -pqv -t "$A" @wb_schlaf_cmd)" ;;
esac
t capture-pane -p -t "$A" | grep -q 'schlaeft seit' && ok "A4 der Pane zeigt, dass er schlaeft" || bad "A4 keine Schlafanzeige"
for p in "$B:laufender Werkzeugaufruf" "$C:@wb_schlaf_nie" "$D:Register busy"; do
  [ -z "$(t show -pqv -t "${p%%:*}" @wb_schlaeft)" ] && ok "A5 bleibt wach: ${p#*:}" || bad "A5 schlaeft trotz ${p#*:}"
done
[ -z "$(t show -pqv -t "$E" @wb_schlaeft)" ] && ok "A6 Harness ohne Fortsetzungsweg bleibt wach" || bad "A6 E schlaeft ohne Fortsetzungsweg"
echo "$out" | grep -q "$E.*kein Fortsetzungsweg" && ok "A7 und die Runde sagt warum" || bad "A7 Grund fehlt" "$out"

echo "B) Aufwecken ueber jeden Ausloeser"
out="$(python3 "$SCHLAF" wecken "$A" --warten 20)"
[ -z "$(t show -pqv -t "$A" @wb_schlaeft)" ] && tail -1 "$TMP/argv.${A#%}" | grep -q -- "--resume sid-${A#%}" \
  && ok "B1 wecken startet den Harness mit --resume <Kennung>" || bad "B1 wecken" "$out / $(tail -1 "$TMP/argv.${A#%}" 2>/dev/null)"
echo "$out" | grep -q 'geweckt' && ok "B2 --warten kehrt erst zurueck, wenn der Harness bereit ist" || bad "B2 nicht bereit" "$out"
python3 "$SCHLAF" legen "$A" >/dev/null
n0="$(wc -l < "$TMP/argv.${A#%}")"
t send-keys -t "$A" x
warte_auf 15 bash -c "[ \$(wc -l < '$TMP/argv.${A#%}') -gt $n0 ]" \
  && ok "B3 eine Taste im Pane weckt ihn" || bad "B3 Taste weckt nicht"
warte_auf 5 bash -c "[ -z \"\$(tmux -L $SOCK show -pqv -t $A @wb_schlaeft)\" ]"
python3 "$SCHLAF" legen "$A" >/dev/null
n0="$(wc -l < "$TMP/argv.${A#%}")"
t select-pane -t "$B"; t select-pane -t "$A"
warte_auf 15 bash -c "[ \$(wc -l < '$TMP/argv.${A#%}') -gt $n0 ]" \
  && ok "B4 die Auswahl des Panes (Klick auf die Kachel) weckt ihn" || bad "B4 Auswahl weckt nicht"
out="$(python3 "$SCHLAF" wecken "$C")"
echo "$out" | grep -q 'schlaeft nicht' && ok "B5 wecken eines wachen Panes tut nichts" || bad "B5" "$out"

echo "C) von Hand"
out="$(python3 "$SCHLAF" legen "$B" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && [ -z "$(t show -pqv -t "$B" @wb_schlaeft)" ] && ok "C1 legen verweigert einen arbeitenden Pane" || bad "C1 rc=$rc" "$out"

echo
echo "test-wb-schlaf: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
