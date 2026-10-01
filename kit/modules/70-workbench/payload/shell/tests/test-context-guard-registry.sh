#!/usr/bin/env bash
# test-context-guard-registry.sh — V2: der Guard liest Kontext und Kompaktierbefehl
# aus der Registry.
#
# Anlass (Messung 2026-08-06): `contextPattern` und `compactCommand` standen in der
# Registry und wurden von NICHTS gelesen. Der Guard kannte drei fest verdrahtete
# Quellen und tippte an einer einzigen Stelle ein festes /compact — also auch in Panes,
# deren Harness gar nicht auf Kommando kompaktiert. Damit war jede Eintragung an einem
# fremden Harness eine Eintragung ohne Wirkung.
#
# Geprueft wird, in zwei Laeufen:
#   A1  Ein Harness MIT contextPattern wird gelesen: die gemeldete Zahl ist die vom
#       Bildschirm, und die Quelle heisst 'registry'.
#   A2  Der Kompaktierbefehl kommt aus der Registry: getippt wird '/verdichte',
#       nicht '/compact'.
#   A3  Danach FAELLT die gelesene Auslastung messbar — nachgewiesen daran, dass der
#       Guard nach einem erneuten Anstieg ein ZWEITES Mal warnt. Das kann er nur,
#       wenn er zwischendurch wirklich einen niedrigeren Wert gelesen hat (sonst
#       bleibt der Pane in 'warned' stehen und wird nie wieder gemeldet).
#   A4  Ein Harness OHNE contextPattern erzeugt die Meldung BLIND — und sie nennt
#       den Harness und sagt, was zu tun ist, statt eine Null zu behaupten.
#       Fuer 'claude' heisst das seit dem 26.08. ausdruecklich, dass ein Muster
#       NICHT nachzutragen ist: seine Statuszeile nennt fuer den Kontext keine
#       Prozentzahl (nur das Zahlenpaar; die 5h/7d-Prozente sind Kontingente).
#       Der frueher hier geprueft Satz rief nach einem Muster, das es per
#       Vertrag nicht geben kann — und hat genau so in die Irre gefuehrt.
#   C1  Der ALLGEMEINE Zweig derselben Meldung: ein Harness, den die Wache kennt
#       ('pi'), dem aber contextPattern UND Sitzungsquelle fehlen, wird beim
#       Namen genannt, samt beider fehlender Eintragungen. Er braucht einen
#       eigenen Lauf, weil pane_harness() nur 'claude' und 'pi' kennt — eine
#       dritt benannte Attrappe bekaeme gar keinen Harness (gemessen 26.08.).
#       Wortlaut angepasst 2026-08-08: seit der fuenften Quelle nennt die Meldung BEIDE
#       Felder, die fehlen koennen (contextPattern und der session-Block). Geprueft wird
#       weiter dasselbe — dass der Harness beim Namen genannt wird und die Meldung sagt,
#       welche Eintragung fehlt.
#   B1  Ein Harness ohne compactCommand: es wird NICHTS getippt, und der Guard sagt,
#       dass dieser Harness nicht kompaktiert.
#
# Das Kontextformat 'KTX <n> %' und der Befehl '/verdichte' sind ERFUNDEN und stehen
# vor diesem Lauf nirgends — weder im Code noch in einem ausgelieferten Preset. Ein
# Treffer kann also nur aus dieser Registry stammen.
#
# SICHERHEIT: eigener Socket, eigenes HOME, eigene Registry, tmux ohne ~/.tmux.conf.
# Der Guard laeuft in einem PANE des Testservers, damit seine eigenen tmux-Aufrufe
# dorthin gehen und nicht auf 'default' (Vorfall 2026-08-04). Er wird am Ende ueber
# seine gemerkte PID beendet, nicht durch Abraeumen seiner Umgebung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-cgreg-$$"
TESTHOME="$(mktemp -d)"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
GUARDPID=""

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
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

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench" \
         "$TESTHOME/.pi-workers/results"
for w in context-guard wb-state; do
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

# Die Registry dieses Laufs. 'pi' ist der lesbare Harness, 'claude' der blinde.
registry_schreiben() {   # <compactCommand-als-JSON>
  cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi", "command": "pi", "args": ["--model", "{model}"],
      "cwdMode": "cd", "readyPattern": "KTX", "promptPattern": "^KTX",
      "contextPattern": "KTX[[:space:]]*([0-9]{1,3})[[:space:]]*%",
      "compactCommand": $1
    },
    {
      "id": "claude", "label": "Pruef-Claude ohne Muster", "command": "claude",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "STILL",
      "promptPattern": "^STILL", "contextPattern": null, "compactCommand": null
    }
  ],
  "models": []
}
REGEOF
}

# Die beiden Fake-CLIs. 'pi' zeigt eine Statuszeile im erfundenen Format und reagiert
# auf getippte Zeilen: '/verdichte' senkt die Anzeige, '/hoch' hebt sie wieder.
# 'claude' zeigt einen Bildschirm ganz ohne Zahlen — nichts, was eine der drei
# gewachsenen Quellen lesen koennte.
TYPED="$TESTHOME/getippt.log"
: > "$TYPED"
cat > "$SHIM/pi" <<PIEOF
#!/bin/sh
pct=91
schirm() { printf '\\n\\n\\nPruef-Harness laeuft\\nKTX %s %%\\n' "\$pct"; }
schirm
while IFS= read -r zeile; do
  echo "PI: \$zeile" >> "$TYPED"
  case "\$zeile" in
    */verdichte*) pct=7 ;;
    */hoch*)      pct=96 ;;
  esac
  schirm
done
sleep 600
PIEOF
cat > "$SHIM/claude" <<CLEOF
#!/bin/sh
printf '\\n\\n\\nSTILL: dieser Harness zeigt keine Auslastung\\nkeine Zahlen hier\\n'
while IFS= read -r zeile; do echo "CLAUDE: \$zeile" >> "$TYPED"; done
sleep 600
CLEOF
chmod +x "$SHIM/pi" "$SHIM/claude"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-registry: Kontextmuster und Kompaktierbefehl aus der Registry (V2) =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
# Erst die Session (die den Server ueberhaupt erzeugt), dann die globalen Optionen --
# umgekehrt laeuft jedes `set-option` ins Leere, weil noch kein Server da ist.
tm new-session -d -s wb-Cgreg -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

neuer_pane() {   # neuer_pane <programm> -> Pane-Id
  local p
  p="$(tm new-window -d -t "=wb-Cgreg:" -P -F '#{pane_id}' "PATH='$PANE_PATH' $1" 2>/dev/null)"
  tm set -p -t "$p" @wb_cmd "exec $1"
  printf '%s' "$p"
}

guard_starten() {   # guard_starten <orch> <worker>:<name> -> Logdatei in $GLOG
  GLOG="$TESTHOME/guard.$RANDOM.log"
  tm send-keys -t "$STEUER" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=2 ORCH_PCT=50 WARN_PCT=50 \
       ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$TESTHOME' \
       context-guard '$1' '$2'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
  sleep 2
  GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"
}
warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.5
  done
  return 0
}
guard_stoppen() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
  sleep 1
  if [ -n "$GUARDPID" ] && kill -0 "$GUARDPID" 2>/dev/null; then
    bad "Aufraeumen: Guard $GUARDPID laeuft noch"
  fi
  GUARDPID=""
}

# ── Lauf A: Muster vorhanden, Kompaktierbefehl vorhanden ──────────────────
registry_schreiben '"/verdichte"'
# Der Steuer-Pane muss eine SCHALE sein, die stdin liest -- send-keys an eine
# Endlosschleife tut nichts (erst gemessen, dann gemerkt).
STEUER="$(tm new-window -d -t "=wb-Cgreg:" -P -F '#{pane_id}')"
ORCH="$(neuer_pane pi)"
WORKER="$(neuer_pane claude)"
tm set -p -t "$WORKER" @wb_worker w1
sleep 2

echo "-- A: Harness 'pi' als Orchestrator (Muster + Kompaktierbefehl) --"
guard_starten "$ORCH" "$WORKER:w1"

if warte_auf "$GLOG" 'at 91% \(registry\)' 25; then
  ok "A1: die Auslastung wird aus dem Registry-Muster gelesen (91 %, Quelle 'registry')"
else
  bad "A1: keine Zeile 'at 91% (registry)' im Guard-Log: $(tail -5 "$GLOG" 2>/dev/null)"
fi

if warte_auf "$GLOG" '\-> /verdichte typed' 40; then
  ok "A2: getippt wurde '/verdichte' aus der Registry, nicht '/compact'"
else
  bad "A2: kein '/verdichte typed' im Guard-Log: $(tail -5 "$GLOG" 2>/dev/null)"
fi
grep -qE '^PI: /compact' "$TYPED" && bad "A2: es wurde doch ein '/compact' getippt" \
                                  || ok "A2: kein '/compact' als Befehl im Protokoll des Panes"
grep -q '/verdichte' "$TYPED" && ok "A2: die CLI hat den Befehl wirklich bekommen" \
                              || bad "A2: '/verdichte' fehlt im Protokoll des Panes"

# Die Auslastung ist jetzt 7. Wieder hoch treiben: eine ZWEITE Warnung kann nur
# kommen, wenn der Guard dazwischen wirklich den kleineren Wert gelesen hat.
vorher="$(grep -c 'brain+state update requested' "$GLOG" 2>/dev/null || echo 0)"
tm send-keys -t "$ORCH" '/hoch' Enter
if warte_auf "$GLOG" 'at 96% \(registry\)' 30; then
  ok "A3: nach dem Kompaktieren wurde ein NIEDRIGERER Wert gelesen (sonst gaebe es keine zweite Meldung bei 96 %)"
else
  bad "A3: keine zweite Meldung nach dem Wiederanstieg (vorher $vorher): $(tail -5 "$GLOG" 2>/dev/null)"
fi

if warte_auf "$GLOG" 'BLIND' 10; then
  if grep -q "Fuer den Harness 'claude' ist ein contextPattern NICHT nachzutragen" "$GLOG"; then
    ok "A4: fuer 'claude' sagt die Meldung, dass ein Muster NICHT nachzutragen ist"
  else
    bad "A4: BLIND-Meldung schickt auf die falsche Faehrte (Muster nachtragen): $(grep BLIND "$GLOG" | head -1)"
  fi
else
  bad "A4: keine BLIND-Meldung fuer den Pane ohne lesbare Auslastung"
fi
guard_stoppen

# ── Lauf B: Muster vorhanden, aber KEIN Kompaktierbefehl ──────────────────
echo
echo "-- B: derselbe Harness ohne compactCommand --"
registry_schreiben 'null'
: > "$TYPED"
ORCH2="$(neuer_pane pi)"
sleep 2
guard_starten "$ORCH2" "$WORKER:w1"

if warte_auf "$GLOG" 'kennt kein Kompaktieren' 40; then
  ok "B1: der Guard sagt, dass dieser Harness nicht kompaktiert"
else
  bad "B1: keine Meldung 'kennt kein Kompaktieren': $(tail -5 "$GLOG" 2>/dev/null)"
fi
grep -qE '^PI: /(verdichte|compact)' "$TYPED" \
  && bad "B1: es wurde trotzdem ein Kompaktierbefehl getippt: $(cat "$TYPED")" \
  || ok "B1: es wurde nichts getippt"
guard_stoppen

# ── Lauf C: der ALLGEMEINE Zweig der BLIND-Begruendung ────────────────────
# 'pi' ohne contextPattern und ohne Sitzungsquelle, mit einem Bildschirm ohne
# Zahlen. Das ist der Fall, den A4 frueher zu pruefen glaubte: ein FREMDER
# Harness, dem beide Eintragungen fehlen. Ohne diesen Lauf waere der Zweig seit
# dem 26.08. unbewacht.
echo
echo "-- C: fremder Harness ohne Muster und ohne Sitzungsquelle --"
cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi ohne Muster", "command": "pi",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "STILL",
      "promptPattern": "^STILL", "contextPattern": null, "compactCommand": null
    },
    {
      "id": "claude", "label": "Pruef-Claude", "command": "claude",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "STILL",
      "promptPattern": "^STILL", "contextPattern": null, "compactCommand": null
    }
  ],
  "models": []
}
REGEOF
# Ein 'pi'-Pane, der KEINE Zahlen zeigt -- sonst laese ihn Quelle 1 oder 2.
cat > "$SHIM/pi" <<STUMMEOF
#!/bin/sh
printf '\\n\\n\\nSTILL: dieser Harness zeigt keine Auslastung\\nkeine Zahlen hier\\n'
while IFS= read -r zeile; do echo "PI: \$zeile" >> "$TYPED"; done
sleep 600
STUMMEOF
chmod +x "$SHIM/pi"
: > "$TYPED"
ORCH3="$(neuer_pane claude)"
WORKER_PI="$(neuer_pane pi)"
tm set -p -t "$WORKER_PI" @wb_worker wpi
sleep 2
guard_starten "$ORCH3" "$WORKER_PI:wpi"
if warte_auf "$GLOG" "Harness 'pi' hat weder contextPattern noch eine lesbare Sitzungsquelle" 40; then
  ok "C1: der fremde blinde Harness wird benannt, samt beider fehlender Eintragungen"
else
  bad "C1: keine allgemeine Harness-Begruendung: $(grep BLIND "$GLOG" | head -1)"
fi
guard_stoppen

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
