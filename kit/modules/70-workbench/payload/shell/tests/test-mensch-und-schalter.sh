#!/bin/bash
# test-mensch-und-schalter.sh — was ein MENSCH darf und woran ein Werkzeug ihn erkennt.
#
# Geprueft werden die drei Sicherungen, die 2026-08-06 lockerbar wurden, und die
# EINE Antwort darunter (`wb-mensch`):
#   1. der Effort-Deckel     (wb-state models effort / effort-cap, pi-worker --mensch)
#   2. die einzelnen Guards  (hooks/bash-guard.py, wb-state guard)
#   3. die Kontextwache      (shell/context-guard, wb-state wache)
#
# ISOLATION (Regeln 2026-07-25, beide nach echten Vorfaellen):
#   * `unset TMUX TMUX_PANE` als ERSTE Codezeile. Wer nur den Socket umlenkt, laesst
#     jeden aufgerufenen Helfer weiter mit dem LIVE-Server reden -- $TMUX schlaegt
#     TMUX_TMPDIR.
#   * eigener tmux-Server (`tmux -L wbtest-mensch-$$`), Socketname mit PID, damit zwei
#     gleichzeitige Laeufe sich nicht gegenseitig den Server abraeumen.
#   * eigenes HOME (mktemp -d). Die echte ~/.claude/workbench/settings.json und
#     models.json werden hier NIE gelesen oder geschrieben -- die Registry dieses
#     Laufs ist eine eigene Datei, gebaut aus shell/models.default.json.
#   * Aufraeumen killt den Server ueber den SOCKET, nie ueber ein pkill-Muster.
#
# DER LAUF STELLT SEINE VORAUSSETZUNG SELBST HER. Jedes Modell, jeder Grundtext und
# jeder Guard-Vermerk dieses Laufs traegt MARKE -- eine Zeichenkette, die es vor dem
# Lauf nirgends gab. Findet ein Test sie nicht, hat er nicht sein eigenes Objekt
# gemessen, sondern etwas Vorgefundenes.
#
# WIE EIN "MENSCH" IM TEST ENTSTEHT: in einem Pane des TEST-Servers, mit geleerter
# Agenten-Umgebung. Gemessen 2026-08-06: ein solcher Pane hat ein steuerndes Terminal
# und in seiner Ahnenreihe steht nur der Test-tmux-Server (er loest sich beim
# Daemonisieren vom Aufrufer) -- also genau das, was ein Mensch am Terminal hat. Ein
# AGENT entsteht im selben Pane, sobald er @wb_role=worker traegt.
#
# Lauf:  shell/tests/test-mensch-und-schalter.sh
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

SOCK="wbtest-mensch-$$"
SESS="wb-menschtest-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"      # …/claude-workbench/shell
WURZEL="$(cd "$REPO/.." && pwd)"
MARKE="marke$$$(date +%s)"
PASS=0; FAIL=0

echo "Geprueft: Repo-Stand aus $REPO"
echo "Erkennungsmerkmal dieses Laufs: $MARKE"

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-mensch-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
export TMPDIR="$TESTHOME/tmp/"; mkdir -p "$TMPDIR"

# Der ECHTE tmux, mit absolutem Pfad. Der Test setzt gleich einen Wrapper namens
# `tmux` in die PATH (damit jeder aufgerufene Helfer auf dem Testsocket landet), und
# ab da wuerde ein `tmux …` im Testkoerper selbst in diesem Wrapper landen. Der
# Wrapper ruft aus demselben Grund den absoluten Pfad: `env tmux` faende ihn ueber
# die eben gesetzte PATH wieder und wuerde sich endlos selbst aufrufen -- gemessen
# 2026-08-06 als ein Prozess, dessen Argumentliste auf ueber 700 Wiederholungen von
# '-L wbtest-mensch-…' anwuchs, bis er von Hand beendet wurde. Derselbe Fehler steht
# als Warnung schon in test-registry.sh; er hat sich hier trotzdem wiederholt.
REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "tmux nicht gefunden — Test kann nicht laufen." >&2; exit 1; }
T() { "$REALTMUX" -L "$SOCK" "$@"; }

# Der Gesamtlauf prueft absichtlich mit einem PATH ohne Homebrew. `timeout` ist
# auf macOS aber ein Homebrew-Werkzeug; die vier Guard-Fristen duerfen deshalb
# nicht daran scheitern, dass nur die Menschenprobe ihre festen Werkzeugpfade
# kennt. Wie bei tmux wird ein vorhandenes Systemwerkzeug einmal absolut
# aufgeloest und danach nicht mehr ueber den geerbten PATH gesucht.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
if [ ! -x "$TIMEOUT_BIN" ]; then
  for kandidat in /opt/homebrew/bin/timeout /usr/local/bin/timeout /usr/bin/timeout /bin/timeout; do
    [ -x "$kandidat" ] && { TIMEOUT_BIN="$kandidat"; break; }
  done
fi
[ -x "$TIMEOUT_BIN" ] || { echo "timeout nicht gefunden — Test kann nicht laufen." >&2; exit 1; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && T ls >/dev/null 2>&1; do
    T kill-server 2>/dev/null || true
    sleep 0.3
  done
  if T ls >/dev/null 2>&1; then
    echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch: tmux -L $SOCK ls" >&2
  fi
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK"
  # Eine Aufraeumung, die ihr Ziel aus einer Variablen nimmt, muss VOR dem
  # Loeschen belegen, dass die Variable bedeutet, was sie bedeuten soll
  # (2026-08-06, nach einem `rm -rf "$HOME"` in einem Wegwerf-Versuch: der Guard
  # sah dort das echte Heimatverzeichnis, weil er den Text prueft und die
  # Umlenkung nicht kennen kann -- und haette `mktemp` versagt, waere die
  # Variable leer gewesen). Deshalb: NIE `$HOME` als Loeschziel, immer die
  # eigene Variable, und ein Praefix-Vergleich davor.
  case "$TESTHOME" in
    /tmp/wb-mensch-test.*|/private/tmp/wb-mensch-test.*|/var/folders/*/wb-mensch-test.*)
      rm -rf "$TESTHOME" ;;
    *)
      echo "WARNUNG: TESTHOME='$TESTHOME' sieht nicht nach einem Testverzeichnis aus — NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
nok()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# ── Werkzeuge in das Test-HOME, so wie sie ausgerollt wuerden ──────────────────
for f in wb-state wb-mensch wb-pane-write pi-worker claude-worker context-guard wb-code; do
  cp "$REPO/$f" "$BIN/$f"; chmod +x "$BIN/$f"
done
# tmux-Wrapper: JEDER Helfer landet auf dem Testsocket, nicht auf dem echten Server.
cat > "$BIN/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L $SOCK "\$@"
EOF
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

# ── Die Registry dieses Laufs: eigene Datei, mit einem Modell, das es sonst nicht gibt
python3 - "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json" "$MARKE" <<'PY'
import json, sys
quelle, ziel, marke = sys.argv[1:4]
d = json.load(open(quelle))
vorlage = next(m for m in d["models"] if m["id"] == "claude-opus-5-5")  # Kit: shipped claude model
neu = dict(vorlage)
neu["id"] = "modell-" + marke          # existiert vor diesem Lauf nirgends
neu["label"] = "Testmodell " + marke
neu["alias"] = None
neu.pop("alias", None)
neu.pop("workerClass", None)
d["models"].append(neu)
# Ein zweites Modell an einem Harness OHNE `max` -- fuer den Nachweis, dass `max`
# nur dort waehlbar ist, wo der Harness es annimmt.
# Kit: agy is not shipped; aider's effort map (low, medium, high) has no 'max' either.
ohne = next(m for m in d["models"] if m.get("harness") == "aider")
zwei = dict(ohne)
zwei.update(supportsEffort=True, efforts=["low", "medium", "high"], maxEffort="high", defaultEffort="low")
zwei["id"] = "agymodell-" + marke
zwei["label"] = "Testmodell agy " + marke
zwei.pop("alias", None)
zwei.pop("workerClass", None)
d["models"].append(zwei)
json.dump(d, open(ziel, "w"), indent=2, ensure_ascii=False)
PY
MODELL="modell-$MARKE"
AGYMODELL="agymodell-$MARKE"

# ── Test-tmux-Server + ein Pane, der als AGENT markiert ist ────────────────────
T new-session -d -s "$SESS" -x 200 -y 50 "sleep 600"
sleep 0.5
ORCHPANE=$(T list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
T set -p -t "$ORCHPANE" @wb_role orchestrator

# In einem Pane des Testservers laufen lassen und die Ausgabe einsammeln.
#   im_pane <als-agent|als-mensch> <kommando…>   -> Ausgabe auf stdout, Exitcode in LETZTER_RC
#
# Das Kommando geht ueber eine SKRIPTDATEI in den Pane, nicht als Zeichenkette in
# `bash -c '…'`: die Testkommandos tragen selbst Anfuehrungszeichen (--grund '…'),
# und die haetten die aeussere Quotierung geschlossen. Eine Datei hat dieses
# Problem nicht.
# Der Exitcode kommt ueber eine DATEI zurueck, nicht ueber eine Variable: jeder
# Aufruf steht in `AUS=$(im_pane …)`, also in einer Subshell, und eine dort gesetzte
# Variable erreicht diesen Test nie. Beim ersten Lauf brach genau daran alles ab
# ("LETZTER_RC: unbound variable"). Aus demselben Grund traegt jeder Aufruf einen
# eigenen, zufaelligen Dateinamen -- ein in der Subshell hochgezaehlter Zaehler
# blieb draussen stehen, alle Aufrufe schrieben in dieselbe Datei, und die
# 'los'-Datei des VORIGEN Aufrufs liess den naechsten sofort loslaufen, bevor seine
# Pane-Rolle gesetzt war.
RC() { cat "$TESTHOME/letzter.rc" 2>/dev/null || echo 99; }
im_pane() {
  local art="$1"; shift
  local basis skript aus rc pane los
  basis="$TESTHOME/cmd.$RANDOM$RANDOM"
  skript="$basis.sh"; aus="$basis.out"; rc="$basis.rc"; los="$basis.los"
  rm -f "$skript" "$aus" "$rc" "$los"
  {
    printf '#!/bin/bash\n'
    # WARTEN, bis die Rolle am Pane steht. Ohne das lief das Kommando manchmal,
    # bevor `set -p @wb_role` durch war -- der Pane war dann noch rollenlos und der
    # Test haette einen Agenten faelschlich fuer einen Menschen gehalten. Ein Test,
    # der seine eigene Voraussetzung nicht abwartet, misst den Zufall.
    printf 'while [ ! -e %q ]; do sleep 0.05; done\n' "$los"
    # Die Agenten-Umgebung wird IMMER geleert: sonst waere jeder Pane schon ueber
    # CLAUDECODE ein Agent (A1), und der Nachweis haenge an einer Variablen statt
    # an der Herkunft. Ein AGENT entsteht hier ueber die PANE-ROLLE (A3), also so,
    # wie er im Betrieb entsteht.
    printf 'unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_EXECPATH CLAUDE_PID\n'
    printf 'export HOME=%q\nexport PATH=%q\nexport TMPDIR=%q\n' "$TESTHOME" "$PATH" "$TMPDIR"
    printf '%s > %q 2>&1\n' "$*" "$aus"
    printf 'echo $? > %q\n' "$rc"
  } > "$skript"
  chmod +x "$skript"
  pane=$(T new-window -d -t "=$SESS:" -P -F '#{pane_id}' "bash $skript")
  [ "$art" = als-agent ] && T set -p -t "$pane" @wb_role worker
  : > "$los"
  local d=$((SECONDS + 25))
  while [ ! -s "$rc" ] && [ $SECONDS -lt $d ]; do sleep 0.2; done
  T kill-pane -t "$pane" 2>/dev/null || true
  cat "$rc" 2>/dev/null > "$TESTHOME/letzter.rc" || echo 99 > "$TESTHOME/letzter.rc"
  [ -s "$TESTHOME/letzter.rc" ] || echo 99 > "$TESTHOME/letzter.rc"
  cat "$aus" 2>/dev/null
}

echo
echo "=== 1. wb-mensch: die eine Antwort ==========================================="

AUS=$(im_pane als-mensch "wb-mensch beleg")
case "$AUS" in
  mensch*) ok "Terminal ohne Agenten-Herkunft wird als MENSCH erkannt" ;;
  *)       nok "Terminal ohne Agenten-Herkunft wird als MENSCH erkannt" "$AUS" ;;
esac

AUS=$(im_pane als-agent "wb-mensch beleg")
case "$AUS" in
  agent*) ok "Pane mit @wb_role=worker wird als AGENT erkannt (A3)" ;;
  *)      nok "Pane mit @wb_role=worker wird als AGENT erkannt (A3)" "$AUS" ;;
esac

# Die Behauptung allein traegt nichts: eine erfundene Oberflaechen-Herkunft, deren
# PID kein Ahne ist, darf niemanden zum Menschen machen.
AUS=$(im_pane als-agent "WB_MENSCH_QUELLE=oberflaeche WB_APP_PID=1 wb-mensch beleg")
case "$AUS" in
  agent*) ok "Erfundene Oberflaechen-Herkunft (WB_APP_PID kein Ahne) zaehlt nicht" ;;
  *)      nok "Erfundene Oberflaechen-Herkunft zaehlt nicht" "$AUS" ;;
esac

# ── M2, der Weg der OBERFLAECHE ───────────────────────────────────────────────
# Ohne laufendes Electron laesst sich M2 trotzdem echt messen, wenn man die zwei
# Bedingungen herstellt, unter denen es ueberhaupt zum Zug kommt:
#   (a) KEIN steuerndes Terminal -- sonst entscheidet schon M1, und M2 waere nie
#       geprueft. `os.setsid()` loest den Prozess vom Terminal des Panes, ohne
#       ihn umzuhaengen: die Ahnenreihe bleibt vollstaendig.
#   (b) ein echter Ahne, dessen Kommandoname wie das Werkbank-Programm aussieht.
# Was damit NICHT geprueft ist: ob der echte Electron-Hauptprozess auf dieser
# Maschine wirklich so heisst. Das sieht erst der erste echte Klick.
cat > "$BIN/entkoppeln" <<'EOF'
#!/usr/bin/env python3
# Startet das Kommando OHNE steuerndes Terminal, im selben Prozessbaum.
# NUR stdin wird auf /dev/null gelegt: stdout und stderr zeigen im Test ohnehin
# schon in eine Datei (nicht auf das Terminal), und sie umzubiegen haette die
# Ausgabe verschluckt, die der Test gerade lesen will -- der erste Anlauf ist
# genau daran gescheitert. `[ -t N ]` fragt nach dem Deskriptor, `setsid` nimmt
# zusaetzlich das steuernde Terminal; beides zusammen ergibt die Lage, in der M2
# ueberhaupt zum Zug kommt.
import os, sys
try:
    os.setsid()
except OSError:
    pass                      # schon Sessionleader -- dann stimmt die Lage bereits
os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
os.execvp(sys.argv[1], sys.argv[1:])
EOF
chmod +x "$BIN/entkoppeln"
# Der Ahne, der wie die Oberflaeche heisst. Ein SYMLINK auf bash, und zwar aus
# zwei Gruenden, die beide gemessen sind (2026-08-06):
#   * kein Skript: `ps -o comm=` zeigt fuer ein Shell-Skript den INTERPRETER
#     ('bash'), nicht den Skriptnamen -- ein Skript namens 'electron' waere in
#     der Ahnenreihe unsichtbar geblieben.
#   * keine Kopie: eine Kopie von /bin/bash wird unter macOS sofort mit
#     "Killed: 9" beendet, weil sie ihre Signatur verliert. Der Symlink fuehrt
#     die signierte Datei aus und traegt trotzdem den eigenen Namen in comm.
# Und kein `exec` in der Kette: wer sich selbst ersetzt, verschwindet als Ahne,
# und genau darauf kommt es hier an.
ln -sf /bin/bash "$BIN/electron"

# `; true` verhindert, dass bash sich beim letzten Kommando wegoptimiert (exec)
# und der Ahne doch wieder verschwindet. $$ ist die PID DIESES electron.
AUS=$(im_pane als-mensch "electron -c 'export WB_MENSCH_QUELLE=oberflaeche; export WB_APP_PID=\$\$; entkoppeln wb-mensch beleg; true'")
case "$AUS" in
  mensch*M2*) ok "Ohne Terminal entscheidet M2: geprueften Oberflaechen-Ahnen erkannt" ;;
  mensch*)    nok "M2 sollte entscheiden, nicht M1" "$AUS" ;;
  *)          nok "Ohne Terminal entscheidet M2" "$AUS" ;;
esac
# Gegenprobe unter denselben Bedingungen: dieselben Variablen, aber eine PID, die
# KEIN Ahne ist. Ohne diese Probe belegte die vorige nur, dass irgendetwas gesetzt war.
AUS=$(im_pane als-mensch "electron -c 'export WB_MENSCH_QUELLE=oberflaeche; export WB_APP_PID=1; entkoppeln wb-mensch beleg; true'")
case "$AUS" in
  agent*) ok "... und dieselbe Behauptung mit fremder PID traegt auch dort nicht" ;;
  *)      nok "Fremde PID traegt auch ohne Terminal nicht" "$AUS" ;;
esac

# `wb-pane-write` misst bei umgebogenem HOME absichtlich ZWEIMAL: mit der
# Testfassung unter $HOME und mit der Betriebsfassung unter dem echten
# passwd-HOME. M2 muss beide Proben erreichen; die Behauptung allein bleibt
# wegen der echten Ahnenpruefung wirkungslos. Ziel ist der eigens angelegte
# Orchestrator-Pane, der ohne einen gemessenen Menschen abgelehnt werden muss.
AUS=$(im_pane als-mensch "electron -c 'export WB_MENSCH_QUELLE=oberflaeche; export WB_APP_PID=\$\$; entkoppeln wb-pane-write darf $ORCHPANE; rc=\$?; echo RC=\$rc; true'")
case "$AUS" in
  *RC=0*) ok "M2 erreicht beide HOME-Proben von wb-pane-write und erlaubt den Orchestrator-Pane" ;;
  *)      nok "M2 erreicht die Dual-HOME-Pruefung von wb-pane-write" "$AUS" ;;
esac
AUS=$(im_pane als-mensch "electron -c 'export WB_MENSCH_QUELLE=oberflaeche; export WB_APP_PID=1; entkoppeln wb-pane-write darf $ORCHPANE; rc=\$?; echo RC=\$rc; true'")
case "$AUS" in
  *RC=77*) ok "wb-pane-write lehnt dieselbe M2-Behauptung mit fremder PID weiter ab" ;;
  *)       nok "wb-pane-write muss eine fremde M2-PID ablehnen" "$AUS" ;;
esac

# ── A4, die Schleife ueber die eigene Maschine ────────────────────────────────
# der Nutzer hat am 06.08. gemessen, dass ein Agent die Abschirmung umgehen konnte,
# indem er sich per `ssh -tt <eigene Adresse>` mit dieser Maschine selbst verband:
# sshd gibt ihm einen frischen Prozessbaum mit Pseudoterminal, damit greifen A1 bis A3
# nicht mehr, und M1 sah einen Menschen. Eine Schleife ueber den eigenen Rechner ist
# aber kein Mensch, sondern ein Umweg.
#
# Die eigene Adresse fuer die Probe wird HIER eigenstaendig gemessen und nicht bei
# wb-mensch erfragt -- sonst pruefte der Test die Funktion mit ihrem eigenen Ergebnis
# und koennte nie widersprechen. Die Rueckschleife ist dabei der verlaesslichste Fall:
# 127.0.0.1 hat jede Maschine, auf jeder Plattform, ohne Netz.
EIGENE_NETZ="$( { ifconfig 2>/dev/null | awk '$1=="inet" && $2!="127.0.0.1" { print $2 }'
                 ip -4 -o addr show scope global 2>/dev/null | awk '{ sub("/.*", "", $4); print $4 }'
               } | head -1 || true)"

ssh_fall() {   # <label> <SSH_CONNECTION-Wert> <erwartet: mensch|agent>
  local label="$1" wert="$2" erwartet="$3" aus
  aus=$(im_pane als-mensch "SSH_CONNECTION='$wert' wb-mensch beleg")
  case "$aus" in
    "$erwartet"*) ok "$label" ;;
    *)            nok "$label (erwartet: $erwartet)" "$aus" ;;
  esac
}

ssh_fall "A4: SSH von der eigenen Rueckschleife ist KEIN Mensch" \
         "127.0.0.1 51234 127.0.0.1 22" agent
ssh_fall "A4: dieselbe Adresse in IPv4-gemappter Schreibweise ebenfalls nicht" \
         "::ffff:127.0.0.1 51234 ::1 22" agent
ssh_fall "A4: auch ueber die IPv6-Rueckschleife nicht" \
         "::1 51234 ::1 22" agent
if [ -n "$EIGENE_NETZ" ]; then
  ssh_fall "A4: SSH ueber die eigene Netzadresse ($EIGENE_NETZ) ist KEIN Mensch" \
           "$EIGENE_NETZ 51234 $EIGENE_NETZ 22" agent
else
  echo "  ----  A4 ueber die Netzadresse: uebersprungen (keine Adresse ausser der Rueckschleife)"
fi
# Die Gegenrichtung, ohne die der Test nur belegte, dass A4 IRGENDWAS ablehnt:
# 203.0.113.0/24 ist TEST-NET-3 (RFC 5737) und gehoert garantiert keiner Maschine hier.
ssh_fall "A4: SSH von einer FREMDEN Maschine bleibt unveraendert ein Mensch" \
         "203.0.113.7 51234 100.64.0.1 22" mensch
# Und ohne SSH im Spiel aendert A4 gar nichts -- derselbe Aufruf wie ganz oben.
AUS=$(im_pane als-mensch "wb-mensch beleg")
case "$AUS" in
  mensch*M1*) ok "A4: ohne SSH_CONNECTION entscheidet weiterhin M1" ;;
  *)          nok "A4 aendert etwas, wo gar kein SSH im Spiel ist" "$AUS" ;;
esac

# GEGENPROBE: dieselbe Probe gegen eine Fassung OHNE die Pruefung. Kommt sie dort als
# Mensch durch, misst der Test wirklich A4 und nicht eine Nebenwirkung der Buehne.
sed 's/^    if ssh_auf_sich_selbst; then$/    if false; then/' "$REPO/wb-mensch" > "$BIN/wb-mensch-ohne-a4"
chmod +x "$BIN/wb-mensch-ohne-a4"
if grep -q 'if false; then' "$BIN/wb-mensch-ohne-a4"; then
  ok "Gegenprobe vorbereitet: eine Fassung, in der A4 nicht gerufen wird"
else
  nok "Gegenprobe: A4 liess sich nicht herausnehmen -- der Aufruf sieht anders aus als erwartet"
fi
AUS=$(im_pane als-mensch "SSH_CONNECTION='127.0.0.1 51234 127.0.0.1 22' wb-mensch-ohne-a4 beleg")
case "$AUS" in
  mensch*) ok "Gegenprobe: OHNE A4 gilt die Selbst-SSH-Sitzung wieder als Mensch -- die Probe misst A4" ;;
  *)       nok "Gegenprobe: auch ohne A4 kein Mensch -- die Probe misst etwas anderes" "$AUS" ;;
esac
rm -f "$BIN/wb-mensch-ohne-a4"

# ── Der ECHTE Selbst-SSH-Fall ─────────────────────────────────────────────────
# Simulierte Umgebungsvariablen belegen die Regel, aber nicht, dass sie im Ernstfall
# ueberhaupt zum Zug kommt: erst eine echte Sitzung hat den frischen Prozessbaum, das
# Pseudoterminal und die geleerte Agenten-Umgebung, die den Umweg ueberhaupt lohnend
# machten. Deshalb wird er hier wirklich gefahren -- wenn die Maschine es hergibt.
# Er laeuft NUR lesend (`wb-mensch beleg`), fasst nichts an und braucht keinen Pane.
# Ohne erreichbaren sshd oder ohne schluessellosen Zugang wird er uebersprungen, mit
# Grund: ein Test, der die Voraussetzung nicht hat, darf nicht schweigend gruen sein.
SSHZIEL="${EIGENE_NETZ:-127.0.0.1}"
if "$TIMEOUT_BIN" 10 ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
     "$SSHZIEL" true >/dev/null 2>&1; then
  # Der lokale ssh-Client darf sein steuerndes Test-Pane nicht behalten: auf
  # macOS kann `ssh -tt` nach dem bereits gemeldeten "Connection closed" sonst
  # bis zum aeusseren timeout haengen. Die Remote-Seite erhaelt mit `-tt`
  # weiterhin genau das fuer A4 erforderliche Pseudoterminal.
  AUS=$("$TIMEOUT_BIN" 20 /usr/bin/python3 -c \
          'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
          ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -tt "$SSHZIEL" \
          "bash $REPO/wb-mensch beleg" 2>/dev/null | tr -d '\r')
  case "$AUS" in
    agent*A4\)*) ok "ECHTER Selbst-SSH nach $SSHZIEL wird als Agent erkannt (A4)" ;;
    *)           nok "ECHTER Selbst-SSH nach $SSHZIEL" "$AUS" ;;
  esac
  # A4b: die Variable loeschen nuetzt nichts, weil dann der sshd in der Ahnenreihe
  # entscheidet. Ohne diesen Fall waere A4 mit einem einzigen `unset` zu umgehen.
  AUS=$("$TIMEOUT_BIN" 20 /usr/bin/python3 -c \
          'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
          ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -tt "$SSHZIEL" \
          "unset SSH_CONNECTION SSH_CLIENT SSH_TTY; bash $REPO/wb-mensch beleg" 2>/dev/null | tr -d '\r')
  case "$AUS" in
    agent*A4b\)*) ok "ECHTER Selbst-SSH mit geloeschtem SSH_CONNECTION: sshd in der Ahnenreihe entscheidet (A4b)" ;;
    *)            nok "ECHTER Selbst-SSH mit geloeschtem SSH_CONNECTION" "$AUS" ;;
  esac
else
  echo "  ----  ECHTER Selbst-SSH: uebersprungen -- '$SSHZIEL' ist nicht schluessellos"
  echo "        erreichbar (Fernanmeldung aus, kein Schluessel, oder kein Netz). Die Regel"
  echo "        selbst ist oben ueber SSH_CONNECTION geprueft, samt Gegenprobe; ungeprueft"
  echo "        bleibt hier nur, dass eine echte Sitzung dieselbe Variable traegt."
fi

echo
echo "=== 2. Effort-Deckel ========================================================="

AUS=$(wb-state models effort "$MODELL" --liste 2>&1)
case "$AUS" in
  *max*) ok "Stufenliste kommt vom HARNESS und enthaelt 'max' ($AUS)" ;;
  *)     nok "Stufenliste kommt vom HARNESS und enthaelt 'max'" "$AUS" ;;
esac

AUS=$(wb-state models effort "$AGYMODELL" --liste 2>&1)
case "$AUS" in
  *max*) nok "Harness ohne 'max' bietet es auch nicht an" "$AUS" ;;
  *)     ok  "Harness ohne 'max' bietet es auch nicht an ($AUS)" ;;
esac

AUS=$(im_pane als-agent "wb-state models effort $MODELL --effort max"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "gedeckelt"; then
  ok "Agent-Aufruf ueber dem Deckel wird abgelehnt"
else
  nok "Agent-Aufruf ueber dem Deckel wird abgelehnt" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state models effort $MODELL --effort max --mensch"); RC=$(RC)
if [ "$RC" = 0 ] && [ "$(printf '%s' "$AUS" | tail -1)" = max ]; then
  ok "Derselbe Aufruf als MENSCH laeuft durch"
else
  nok "Derselbe Aufruf als MENSCH laeuft durch" "rc=$RC $AUS"
fi

# DIE VIERTE KOMBINATION (2026-08-06, Reviewer-Befund). Drei Ecken standen hier:
# Agent ohne Merkmal, Mensch mit Merkmal, Harness-Grenze. Die vierte -- AGENT MIT
# MERKMAL -- fehlte, und genau sie ist die Zusage: `wb-state models effort … --mensch`
# laesst sich aus jedem Pane direkt aufrufen und lieferte vorher die ungedeckelte
# Stufe, weil das Merkmal hier geglaubt statt gemessen wurde. Der Schaden war
# begrenzt (mit der Antwort muss man immer noch selbst starten, und dort misst
# pi-worker erneut), aber eine Zusage, die nur fuer die vorgesehenen Wege gilt,
# ist keine.
AUS=$(im_pane als-agent "wb-state models effort $MODELL --effort max --mensch"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "gedeckelt"; then
  ok "VIERTE Kombination: Agent MIT Merkmal bekommt trotzdem den Deckel"
else
  nok "Agent MIT Merkmal bekommt trotzdem den Deckel" "rc=$RC $AUS"
fi
if printf '%s' "$AUS" | grep -q "'--mensch' gilt hier nicht"; then
  ok "... und der Rueckfall wird gesagt, nicht verschwiegen"
else
  nok "Der Rueckfall wird gesagt" "$AUS"
fi
# Unterhalb des Deckels antwortet dieselbe Abfrage weiter -- sie ist eine Abfrage,
# kein Start, und die richtige Antwort ist die geltende Stufe.
AUS=$(im_pane als-agent "wb-state models effort $MODELL --effort xhigh --mensch"); RC=$(RC)
if [ "$RC" = 0 ] && [ "$(printf '%s' "$AUS" | tail -1)" = xhigh ]; then
  ok "... unterhalb des Deckels liefert sie weiterhin die gedeckelte Stufe"
else
  nok "Unterhalb des Deckels liefert sie die gedeckelte Stufe" "rc=$RC $AUS"
fi
# Dasselbe fuer `resolve`, den zweiten Weg, der `--mensch` annimmt.
AUS=$(im_pane als-agent "wb-state models resolve $MODELL --role worker --effort max --mensch --dir $TESTHOME/work --name p"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "gedeckelt"; then
  ok "... und 'models resolve --mensch' aus einem Pane ebenso"
else
  nok "'models resolve --mensch' aus einem Pane" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state models effort $AGYMODELL --effort max --mensch"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "nimmt effort 'max' nicht an"; then
  ok "'max' ist auch fuer einen Menschen nur waehlbar, wo der Harness es annimmt"
else
  nok "'max' nur wo der Harness es annimmt" "rc=$RC $AUS"
fi

# pi-worker: das Merkmal am ECHTEN Aufrufweg, nicht nur an wb-state.
AUS=$(im_pane als-agent "pi-worker --mensch w-$MARKE $MODELL $TESTHOME/work nichts"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "'--mensch' abgelehnt"; then
  ok "pi-worker weist '--mensch' aus einem Agenten-Pane ab"
else
  nok "pi-worker weist '--mensch' aus einem Agenten-Pane ab" "rc=$RC $AUS"
fi
if tmux -L "$SOCK" list-panes -s -t "=$SESS" -F '#{@wb_worker}' 2>/dev/null | grep -qx "w-$MARKE"; then
  nok "Der abgewiesene Aufruf hat keinen Pane hinterlassen"
else
  ok "Der abgewiesene Aufruf hat keinen Pane hinterlassen"
fi

echo
echo "=== 3. Ein gesetzter Deckel wirkt ============================================"

# Vorher: derselbe Aufruf laeuft durch.
AUS=$(im_pane als-agent "wb-state models effort $MODELL --effort xhigh"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "vorher: xhigh laeuft fuer einen Agenten durch"
else nok "vorher: xhigh laeuft fuer einen Agenten durch" "rc=$RC $AUS"; fi

# Senken ist keine Lockerung -- das darf auch ein Agent.
AUS=$(im_pane als-agent "wb-state effort-cap set $MODELL medium --grund 'Testlauf $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Deckel SENKEN verlangt keinen Menschen"
else nok "Deckel SENKEN verlangt keinen Menschen" "rc=$RC $AUS"; fi

AUS=$(wb-state models cap "$MODELL" 2>&1)
case "$AUS" in
  medium*einstellung*$MARKE*) ok "Die Setzung ist als solche erkennbar (Quelle 'einstellung' + Grund)" ;;
  *) nok "Die Setzung ist als solche erkennbar" "$AUS" ;;
esac

AUS=$(im_pane als-agent "wb-state models effort $MODELL --effort xhigh"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "$MARKE"; then
  ok "nachher: derselbe Aufruf wird abgelehnt, mit dem gesetzten Grund"
else
  nok "nachher: derselbe Aufruf wird abgelehnt" "rc=$RC $AUS"
fi

AUS=$(im_pane als-agent "wb-state effort-cap set $MODELL xhigh --grund 'zurueck $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "nur ein MENSCH"; then
  ok "Deckel ANHEBEN aus einem Pane heraus scheitert"
else
  nok "Deckel ANHEBEN aus einem Pane heraus scheitert" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state effort-cap set $MODELL xhigh --grund 'zurueck $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Deckel ANHEBEN als Mensch geht"
else nok "Deckel ANHEBEN als Mensch geht" "rc=$RC $AUS"; fi

AUS=$(im_pane als-mensch "wb-state effort-cap set $MODELL low"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "grund"; then
  ok "Ein Deckel OHNE Grund wird nicht gespeichert"
else
  nok "Ein Deckel OHNE Grund wird nicht gespeichert" "rc=$RC $AUS"
fi

# Protokoll: ein Start ueber dem Deckel wird festgehalten.
im_pane als-mensch "wb-state models effort $MODELL --effort max --mensch" >/dev/null
LOG="$TESTHOME/.local/state/wb-effort-mensch.log"
if [ -s "$LOG" ] && grep -q "$MODELL" "$LOG"; then
  ok "Ein Start ueber dem Deckel steht im Protokoll ($(wc -l < "$LOG" | tr -d ' ') Zeile(n))"
else
  nok "Ein Start ueber dem Deckel steht im Protokoll" "$LOG fehlt oder ist leer"
fi

echo
echo "=== 4. Einzelne Guards abschalten ============================================"

GUARD="$WURZEL/hooks/bash-guard.py"
export AWB_GUARD_BLOCKS_DIR="$TESTHOME/guard-blocks"
export AWB_GUARD_LOG="$TESTHOME/guard.log"

# Der Befehl, an dem der commit-trailer-Guard greift: ein Commit MIT Co-Author-Trailer.
BOESE="git commit -m 'test $MARKE

Co-Authored-By: Claude <noreply@anthropic.com>'"
eingabe() {   # kommando -> Hook-Eingabe als JSON
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"session_id":"s","tool_input":{"command":sys.argv[1]}}))' "$1" "$TESTHOME/work"
}
hook() {      # kommando -> Ausgabe; Exitcode ueber dieselbe Datei wie im_pane
  local aus rc
  aus=$(eingabe "$1" | python3 "$GUARD" 2>&1); rc=$?
  # Auch hier eine DATEI statt einer Variablen: `AUS=$(hook …)` ist eine Subshell.
  echo "$rc" > "$TESTHOME/letzter.rc"
  printf '%s' "$aus"
}

AUS=$(hook "$BOESE"); RC=$(RC)
if [ "$RC" = 2 ]; then ok "vorher: commit-trailer-Guard lehnt ab (exit 2)"
else nok "vorher: commit-trailer-Guard lehnt ab" "rc=$RC $AUS"; fi

AUS=$(im_pane als-agent "wb-state guard set commit-trailer aus --grund 'Testlauf $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "nur ein MENSCH"; then
  ok "Guard abschalten aus einem Pane heraus scheitert"
else
  nok "Guard abschalten aus einem Pane heraus scheitert" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state guard set commit-trailer aus"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "grund"; then
  ok "Guard abschalten OHNE Grund scheitert"
else
  nok "Guard abschalten OHNE Grund scheitert" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state guard set commit-trailer aus --grund 'Testlauf $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Guard abschalten als Mensch geht"
else nok "Guard abschalten als Mensch geht" "rc=$RC $AUS"; fi

AUS=$(hook "$BOESE"); RC=$(RC)
if [ "$RC" = 0 ] && printf '%s' "$AUS" | grep -q "SWITCHED OFF" && printf '%s' "$AUS" | grep -q "$MARKE"; then
  ok "nachher: derselbe Befehl laeuft durch, mit sichtbarer Warnung samt Grund"
else
  nok "nachher: derselbe Befehl laeuft durch, mit sichtbarer Warnung" "rc=$RC $AUS"
fi

# ALLE ANDEREN Guards greifen weiter: ein `git add` einer .env-Datei muss abgelehnt
# bleiben, obwohl commit-trailer aus ist.
mkdir -p "$TESTHOME/work"; : > "$TESTHOME/work/.env"
AUS=$(hook "git add .env"); RC=$(RC)
if printf '%s' "$AUS" | grep -q '"deny"'; then
  ok "Ein anderer Guard (secrets) lehnt weiter ab"
else
  nok "Ein anderer Guard (secrets) lehnt weiter ab" "rc=$RC $AUS"
fi

VERMERK="$AWB_GUARD_BLOCKS_DIR/.abgeschaltet.json"
if [ -s "$VERMERK" ] && grep -q "commit-trailer" "$VERMERK" && grep -q "$MARKE" "$VERMERK"; then
  ok "Der Hook vermerkt bei jedem Lauf, welche Guards aus sind"
else
  nok "Der Hook vermerkt, welche Guards aus sind" "$VERMERK fehlt oder ist unvollstaendig"
fi

# Rollenbezug: nur fuer den ORCHESTRATOR abgeschaltet -> in einem Pane OHNE Rolle
# greift der Guard weiter.
im_pane als-mensch "wb-state guard set commit-trailer an" >/dev/null
im_pane als-mensch "wb-state guard set commit-trailer aus --grund 'nur orch $MARKE' --rolle orchestrator" >/dev/null
AUS=$(hook "$BOESE"); RC=$(RC)
if [ "$RC" = 2 ]; then
  ok "Nur fuer den Orchestrator abgeschaltet: ohne diese Rolle greift der Guard weiter"
else
  nok "Rollenbezug wirkt" "rc=$RC $AUS"
fi
TMUX_PANE="$ORCHPANE" hook "$BOESE" >/dev/null   # derselbe Guard, aber aus dem Orchestrator-Pane
AUS=$(TMUX_PANE="$ORCHPANE" hook "$BOESE"); RC=$(RC)
if [ "$RC" = 0 ] && printf '%s' "$AUS" | grep -q "SWITCHED OFF"; then
  ok "... und im Orchestrator-Pane ist er aus"
else
  nok "... und im Orchestrator-Pane ist er aus" "rc=$RC $AUS"
fi
im_pane als-mensch "wb-state guard set commit-trailer an" >/dev/null

echo
echo "=== 5. Kontextwache je Rolle ================================================="

AUS=$(wb-state wache get 2>&1)
if printf '%s' "$AUS" | grep -q "^orchestrator	an	75" && printf '%s' "$AUS" | grep -q "^worker	an	80"; then
  ok "Vorgabe unveraendert: beide Rollen an, 75 / 80"
else
  nok "Vorgabe unveraendert" "$AUS"
fi

AUS=$(im_pane als-agent "wb-state wache set orchestrator --an false --grund 'Testlauf $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "nur ein MENSCH"; then
  ok "Wache abschalten aus einem Pane heraus scheitert"
else
  nok "Wache abschalten aus einem Pane heraus scheitert" "rc=$RC $AUS"
fi

AUS=$(im_pane als-mensch "wb-state wache set orchestrator --an false --grund 'Testlauf $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Wache fuer den Orchestrator abschalten (als Mensch) geht"
else nok "Wache fuer den Orchestrator abschalten geht" "rc=$RC $AUS"; fi

AUS=$(wb-state wache get 2>&1)
if printf '%s' "$AUS" | grep -q "^orchestrator	aus" && printf '%s' "$AUS" | grep -q "^worker	an"; then
  ok "Orchestrator aus, Worker weiter an — getrennt einstellbar"
else
  nok "Orchestrator aus, Worker weiter an" "$AUS"
fi

# Und der Guard selbst sagt es beim Start, mit denselben Zahlen.
GLOG="$TESTHOME/guard-start.log"
( cd "$TESTHOME/work" && PROJECT="$TESTHOME/work" POLL=1 "$TIMEOUT_BIN" 8 context-guard "$ORCHPANE" >"$GLOG" 2>&1 )
if grep -q "ORCHESTRATOR ist AUS" "$GLOG"; then
  ok "context-guard benennt die abgeschaltete Rolle beim Start"
else
  nok "context-guard benennt die abgeschaltete Rolle beim Start" "$(head -5 "$GLOG")"
fi
if grep -q "worker warn 80%" "$GLOG"; then
  ok "context-guard beobachtet Worker weiter (Schwelle 80% unveraendert)"
else
  nok "context-guard beobachtet Worker weiter" "$(head -5 "$GLOG")"
fi

im_pane als-mensch "wb-state wache set worker --mahnen-ab 60 --grund 'Testlauf $MARKE'" >/dev/null
( cd "$TESTHOME/work" && PROJECT="$TESTHOME/work" POLL=1 "$TIMEOUT_BIN" 8 context-guard "$ORCHPANE" >"$GLOG" 2>&1 )
if grep -q "worker warn 60%" "$GLOG"; then
  ok "Die Mahnschwelle je Rolle wirkt (Worker 60%)"
else
  nok "Die Mahnschwelle je Rolle wirkt" "$(head -5 "$GLOG")"
fi

im_pane als-mensch "wb-state wache set orchestrator --notbremse-ab 95 --grund 'Testlauf $MARKE'" >/dev/null
im_pane als-mensch "wb-state wache set orchestrator --an true" >/dev/null
( cd "$TESTHOME/work" && PROJECT="$TESTHOME/work" POLL=1 "$TIMEOUT_BIN" 8 context-guard "$ORCHPANE" >"$GLOG" 2>&1 )
if grep -q "Notbremse 95%" "$GLOG"; then
  ok "Die Notbremse steht in der Aufstellung und ist einstellbar (95%)"
else
  nok "Die Notbremse ist einstellbar" "$(head -5 "$GLOG")"
fi

echo
echo
echo "=== 6. Der Mensch startet SEINEN Orchestrator ================================"

# wb-code startet den Orchestrator. Gemessen wird hier nur die Stufenentscheidung,
# nicht der Start selbst: der Aufruf bricht danach ohnehin ab (kein claude im
# Test-BIN), und genau bis dorthin reicht das, was dieser Auftrag geaendert hat.
# WB_NO_DISCOVER haelt den Hintergrundabruf aus dem Lauf heraus.
wbcode() {   # <als-agent|als-mensch> <weitere Argumente>
  local art="$1"; shift
  im_pane "$art" "WB_NO_DISCOVER=1 wb-code $* $TESTHOME/work 2>&1"
}

AUS=$(wbcode als-agent "--model $MODELL --effort max"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "gedeckelt"; then
  ok "Orchestrator-Start ueber dem Deckel, ohne Merkmal: Deckel greift"
else
  nok "Orchestrator-Start ohne Merkmal: Deckel greift" "rc=$RC $AUS"
fi

AUS=$(wbcode als-agent "--mensch --model $MODELL --effort max"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "'--mensch' abgelehnt"; then
  ok "wb-code weist '--mensch' aus einem Agenten-Pane ab"
else
  nok "wb-code weist '--mensch' aus einem Agenten-Pane ab" "rc=$RC $AUS"
fi

# Als Mensch muss die Stufe DURCHGEHEN. Der Start scheitert danach am fehlenden
# claude-Binary -- entscheidend ist, dass er NICHT mehr am Deckel scheitert.
AUS=$(wbcode als-mensch "--mensch --model $MODELL --effort max")
if printf '%s' "$AUS" | grep -q "gedeckelt"; then
  nok "Orchestrator-Start als MENSCH laeuft am Deckel vorbei" "$AUS"
else
  ok "Orchestrator-Start als MENSCH laeuft am Deckel vorbei"
fi
if printf '%s' "$AUS" | grep -q "der Effort-Deckel gilt fuer diesen Start nicht (effort max)"; then
  ok "... und wb-code sagt, dass der Deckel fuer diesen Start nicht gilt"
else
  nok "wb-code benennt den Ausnahmefall" "$AUS"
fi

# EIN MENSCH WIRD GEWARNT, NICHT AUFGEHALTEN (21.08.2026, zweite des Nutzers Ansage).
# Bis heute war eine abgelehnte Speicherbuchung das Ende des Starts -- auch fuer ihn, an
# seiner eigenen Maschine, nachdem die Oberflaeche die Stufe laengst als nicht passend
# gezeigt hatte. `--auf-eigene-gefahr` macht daraus eine laute Warnung; `wb-belegung` misst
# dahinter mit `wb-mensch` selbst nach und weist einen AGENTEN weiterhin ab.
#
# WAS HIER GEPRUEFT WIRD UND WAS NICHT: dass `wb-code` den Weg oeffnet und es sagt, und dass
# ein Agent ihn NICHT bekommt. Dass das Flag am Ende wirklich bei `wb-mlx-server` ankommt,
# haengt an einem MLX-Modell in der Registry und damit an einem echten Modellstart -- den
# fuehrt diese Suite bewusst nicht. Die Verdrahtung dorthin prueft die Zusage darunter am
# Quelltext, und die andere Haelfte -- ein Agent kommt nicht durch -- ist die, auf die es
# ankommt.
if printf '%s' "$AUS" | grep -q "eine abgelehnte Speicherbuchung wird zur WARNUNG"; then
  ok "Als MENSCH wird eine abgelehnte Speicherbuchung zur Warnung, der Start laeuft weiter"
else
  nok "Als MENSCH wird die Buchungsablehnung zur Warnung" "$AUS"
fi

AUS_AG=$(wbcode als-agent "--model $MODELL --effort medium")
if printf '%s' "$AUS_AG" | grep -q "eine abgelehnte Speicherbuchung wird zur WARNUNG"; then
  nok "Ein AGENT bekommt den Weg an der Ablehnung vorbei NICHT" "$AUS_AG"
else
  ok "Ein AGENT bekommt den Weg an der Ablehnung vorbei nicht"
fi

if grep -q 'GEFAHR_ARGS\[@\]' "$BIN/wb-code" && grep -q 'GEFAHR_ARGS=(--auf-eigene-gefahr)' "$BIN/wb-code"; then
  ok "und das Flag haengt wirklich am Aufruf von wb-mlx-server (Verdrahtung im Quelltext)"
else
  nok "die Verdrahtung zu wb-mlx-server fehlt" "GEFAHR_ARGS nicht am ensure-Aufruf"
fi

# Eine Stufe, die der Harness nicht annimmt, bleibt auch fuer den Menschen zu.
AUS=$(wbcode als-mensch "--mensch --model $AGYMODELL --harness aider --effort max")
if printf '%s' "$AUS" | grep -q "nimmt effort 'max' nicht an"; then
  ok "Auch beim Orchestrator gilt die Stufenliste des Harness"
else
  nok "Stufenliste des Harness gilt auch beim Orchestrator" "$AUS"
fi

# Bis zum 06.08. ging $EFFORT im claude-Zweig voellig ungeprueft in die CLI.
AUS=$(wbcode als-agent "--model $MODELL --effort quatsch")
if printf '%s' "$AUS" | grep -q "unbekannter effort"; then
  ok "Ein unsinniger Effort wird jetzt VOR dem Start abgelehnt"
else
  nok "Unsinniger Effort wird vor dem Start abgelehnt" "$AUS"
fi

# Das Protokoll unterscheidet die eigene Sitzung vom Worker (7. Spalte).
if grep -q "	orchestrator$" "$TESTHOME/.local/state/wb-effort-mensch.log" 2>/dev/null \
   && grep -q "	worker$" "$TESTHOME/.local/state/wb-effort-mensch.log" 2>/dev/null; then
  ok "Das Protokoll trennt Orchestrator-Start und Worker-Start"
else
  nok "Protokoll trennt Orchestrator und Worker" \
      "$(cat "$TESTHOME/.local/state/wb-effort-mensch.log" 2>/dev/null)"
fi

echo
echo "=== 7. wb-consistency findet einen Deckel-Widerspruch im SKRIPT ==============="
if [ -f "$WURZEL/shell/wb-consistency" ]; then  # Kit: wb-consistency is not shipped

# Die Cap-Pruefung gab es schon; sie war fuer Kommentar-Dateien blind, und genau
# dort (im Kopf von claude-worker) stehen die meisten Behauptungen. Der Aufbau
# hier ist die Form aus claude-worker: Spaltenliste, Behauptung ueber zwei Zeilen.
CROOT="$TESTHOME/cons"
mkdir -p "$CROOT/.claude/workbench" "$CROOT/.local/bin" "$CROOT/.claude/regeln"
python3 - "$CROOT/.claude/workbench/models.json" "$MARKE" <<'PY'
import json, sys
ziel, marke = sys.argv[1:3]
json.dump({"models": [
    {"id": "m-" + marke, "alias": "probemodell", "harness": "claude",
     "provider": "claude-subscription", "modelRef": "x", "maxEffort": "medium"}],
    "harnesses": [], "providers": []}, open(ziel, "w"))
PY
cat > "$CROOT/.local/bin/claude-worker" <<EOF
#!/bin/bash
# Routing:
#   probemodell    NUR nach ausdruecklicher Anweisung, fuer jede Aufgabe. Effort cap
#                  \`high\` (angehoben 2026-08-06, $MARKE).
EOF
AUS=$(python3 "$WURZEL/shell/wb-consistency" --base "$CROOT" \
        --config "$WURZEL/shell/wb-consistency.config.json" 2>&1)
# Kein `printf | grep -q` hier, sondern der Mustervergleich der Shell. Grund, gemessen am
# 2026-08-21 auf host2: `grep -q` bricht beim ERSTEN Treffer ab und schliesst die Pipe, das
# schreibende `printf` faengt sich ein SIGPIPE und endet mit 141 -- und weil oben
# `set -o pipefail` steht, gilt die ganze Pipeline als gescheitert, obwohl grep gefunden
# hat, was es finden sollte. Ob es dazu kommt, haengt allein daran, ob printf mit Schreiben
# fertig ist, bevor grep zumacht; bei den 43 KB, die wb-consistency hier ausgibt, gewinnt
# mal der eine und mal der andere. Der Test war deshalb nicht plattformabhaengig rot,
# sondern zufaellig rot -- auf dem Mac gruen, auf host2 rot, im selben Baum.
if [ "${AUS#*claude-worker}" != "$AUS" ] && [ "${AUS#*probemodell}" != "$AUS" ]; then
  ok "Widerspruch im Skript-Kommentar wird gefunden (Datei und Modell benannt)"
else
  nok "Widerspruch im Skript-Kommentar wird gefunden" "$AUS"
fi
# Gegenprobe: Registry auf denselben Wert -> Ruhe. Ohne sie belegte der Test nur,
# dass irgendetwas gemeldet wird.
python3 - "$CROOT/.claude/workbench/models.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for m in d["models"]:
    m["maxEffort"] = "high"
json.dump(d, open(p, "w"))
PY
AUS=$(python3 "$WURZEL/shell/wb-consistency" --base "$CROOT" \
        --config "$WURZEL/shell/wb-consistency.config.json" 2>&1)
if printf '%s' "$AUS" | grep -q "probemodell"; then
  nok "Stimmen Registry und Kommentar ueberein, bleibt es still" "$AUS"
else
  ok "Stimmen Registry und Kommentar ueberein, bleibt es still"
fi
# Und Fliesstext, der mit einem Modellnamen ANFAENGT, ist kein Label: er darf
# keinen Absatz zerschneiden und keine fremde Behauptung an sich ziehen.
printf -- '- Zur Einordnung: probemodell liegt vorn (1341 zu 1324) und kostet halb\n  so viel. Ein anderes Modell ist auf `low` gedeckelt.\n' \
  > "$CROOT/.claude/regeln/prosa.md"
AUS=$(python3 "$WURZEL/shell/wb-consistency" --base "$CROOT" \
        --config "$WURZEL/shell/wb-consistency.config.json" 2>&1)
if printf '%s' "$AUS" | grep -q "probemodell.*\`low\`"; then
  nok "Fliesstext mit Modellnamen am Satzanfang zieht keine fremde Behauptung an" "$AUS"
else
  ok "Fliesstext mit Modellnamen am Satzanfang zieht keine fremde Behauptung an"
fi
else
  ok "wb-consistency gehoert nicht zum Kit -- Abschnitt 7 entfaellt"
fi

echo
echo "=== 8. 'discover' raeumt nur seine EIGENE Quelle auf =========================="

# Unter EINEM Harness koennen mehrere Quellen registrieren: der Harness-Lauf
# (ollama, CLI-Liste, Datei) und ein Anbieter-KATALOG. Die Aufraeumregel des
# Harness-Laufs lautete "alle automatischen Eintraege dieses Harness" und traf
# damit auch die Ausbeute des Katalogs -- gemessen als "-17 entfernt" bei einem
# `aider`-Lauf, wobei die 17 sSmtlich `aider-openrouter-*` waren. Ein Befehl, der
# wie eine Bestandsaufnahme aussieht, loeschte Eintraege, deren Quelle er nicht
# einmal abgefragt hatte.
#
# (Die natuerliche Heimat dieser Zusage waere test-models-discover.sh; die Datei
# steht in diesem Auftrag nicht in meinem Bereich, deshalb liegt sie hier.)
DROOT="$TESTHOME/discover"
DBIN="$DROOT/.local/bin"
mkdir -p "$DBIN" "$DROOT/.claude/workbench" "$DROOT/.local/state"
cp "$REPO/wb-state" "$DBIN/wb-state"; chmod +x "$DBIN/wb-state"
# Ein FAKES ollama, nie das echte: der Lauf darf nicht am Zustand dieses Rechners
# haengen. 'bleibt-model' meldet es, 'weg-model' nicht mehr.
cat > "$DBIN/ollama" <<EOF
#!/bin/bash
[ "\$1" = "list" ] && cat "$DROOT/liste.txt"
EOF
chmod +x "$DBIN/ollama"
printf 'NAME        ID   SIZE   MODIFIED\nbleibt-%s  a1   1 GB   1 day ago\n' "$MARKE" > "$DROOT/liste.txt"

DWBS="$DBIN/wb-state"
dwb() { HOME="$DROOT" PATH="$DBIN:$PATH" "$DWBS" "$@"; }

dwb models add --kind provider '{"id":"katalogquelle","label":"Katalog","kind":"cloud"}' >/dev/null
dwb models add --kind harness "$(printf '{"id":"probeharness","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"ollama","provider":"ollama"}}')" >/dev/null

# Erster Lauf: legt die EIGENEN Eintraege an (Quelle ollama).
dwb models discover probeharness --json >/dev/null 2>&1
# Und jetzt ein Eintrag, wie ihn ein KATALOG-Lauf hinterlaesst: derselbe Harness,
# ein ANDERER Anbieter, ebenfalls source=auto.
dwb models add "$(printf '{"id":"probeharness-katalogquelle-fremd-%s","harness":"probeharness","provider":"katalogquelle","modelRef":"fremd/%s","roles":["worker"],"source":"auto"}' "$MARKE" "$MARKE")" >/dev/null

VORHER_EIGEN=$(dwb models list --all 2>/dev/null | grep -c "^probeharness-pfx\|^probeharness-bleibt\|^probeharness-weg" || true)
VORHER_FREMD=$(dwb models list --all 2>/dev/null | grep -c "katalogquelle-fremd" || true)
# Der Harness-Lauf meldet ab jetzt nur noch 'bleibt-…'; alles andere aus SEINER
# Quelle ist weg und soll aufgeraeumt werden.
printf 'NAME        ID   SIZE   MODIFIED\nbleibt-%s  a1   1 GB   1 day ago\n' "$MARKE" > "$DROOT/liste.txt"
AUS=$(dwb models discover probeharness --json 2>&1)
NACHHER_FREMD=$(dwb models list --all 2>/dev/null | grep -c "katalogquelle-fremd" || true)

if [ "$VORHER_FREMD" -ge 1 ]; then
  ok "Vorbedingung: der fremdquellige Eintrag steht in der Registry ($VORHER_FREMD)"
else
  nok "Vorbedingung: fremdquelliger Eintrag angelegt" "vorher=$VORHER_FREMD"
fi
if [ "$NACHHER_FREMD" = "$VORHER_FREMD" ]; then
  ok "Nach dem Harness-Lauf ist er NOCH DA ($VORHER_FREMD -> $NACHHER_FREMD)"
else
  nok "Fremdquelliger Eintrag ueberlebt den Harness-Lauf" "vorher=$VORHER_FREMD nachher=$NACHHER_FREMD; $AUS"
fi
if printf '%s' "$AUS" | grep -q "katalogquelle-fremd"; then
  nok "Der Lauf nennt den fremden Eintrag nicht einmal" "$AUS"
else
  ok "Der Lauf nennt den fremden Eintrag nicht einmal"
fi
# Gegenprobe: die EIGENE Aufraeumung muss weiter greifen, sonst haette der Test
# nur das Aufraeumen abgeschaltet statt es einzugrenzen.
printf 'NAME        ID   SIZE   MODIFIED\nneu-%s  a2   1 GB   1 day ago\n' "$MARKE" > "$DROOT/liste.txt"
AUS=$(dwb models discover probeharness --json 2>&1)
if printf '%s' "$AUS" | grep -q "bleibt-$MARKE"; then
  ok "Die eigene Aufraeumung greift weiter (verschwundene Referenz wird entfernt)"
else
  nok "Die eigene Aufraeumung greift weiter" "$AUS"
fi

echo
echo "=== 9. Die echte Umgebung wurde nicht angefasst =============================="
# Der Gegenbeweis zur Isolation: das Merkmal dieses Laufs steht in der TEST-Datei
# und darf in der echten nirgends auftauchen. Ohne diese Probe waere "wir leiten ja
# HOME um" eine Behauptung.
ECHT_S="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')/.claude/workbench/settings.json"
ECHT_M="$(dirname "$ECHT_S")/models.json"
if grep -q "$MARKE" "$TESTHOME/.claude/workbench/settings.json" 2>/dev/null; then
  ok "Die Test-settings.json traegt das Merkmal (die Schreibvorgaenge landeten dort)"
else
  nok "Die Test-settings.json traegt das Merkmal" "nichts geschrieben?"
fi
if ! grep -q "$MARKE" "$ECHT_S" 2>/dev/null; then
  ok "Die echte settings.json traegt das Merkmal dieses Laufs nicht"
else
  nok "Die echte settings.json traegt das Merkmal dieses Laufs nicht" "$ECHT_S"
fi
if ! grep -q "$MARKE" "$ECHT_M" 2>/dev/null; then
  ok "Die echte models.json traegt das Merkmal dieses Laufs nicht"
else
  nok "Die echte models.json traegt das Merkmal dieses Laufs nicht" "$ECHT_M"
fi

echo
echo "================================================================"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
