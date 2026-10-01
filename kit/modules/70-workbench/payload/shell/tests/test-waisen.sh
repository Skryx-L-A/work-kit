#!/usr/bin/env bash
# Tests fuer wb-waisen — findet Hintergrundprozesse, deren Eigentuemer
# nachweislich weg ist, und trennt sie von abgeloesten Prozessen, die noch
# in Benutzung sind (Anlass und Begruendung: Kopfkommentar von wb-waisen).
#
# Diese Suite deckt beide Wege ab:
#   Weg A (Eigentuemer-Eintrag via wb-nohup) — Fall A/B/H
#   Weg B (Heuristik ohne Eintrag)           — Fall C/D/E
# dazu Diskussions-Praezision (Fall F) und Registrierungs-Hygiene (Fall G).
#
# Jeder Testprozess ist harmlos: ein reiner `sleep`, ein trivialer
# Loopback-Socket zwischen zwei selbst gestarteten Python-Prozessen, oder ein
# Python-Skript, das nachweislich wachsenden Speicher belegt — NIE ein
# echter Modellserver, NIE etwas, das einen fremden Prozess beeinflussen
# koennte. PID 82087 (der reale Fund, der die Korrektur ausgeloest hat) wird
# hier nirgends erwaehnt oder angefasst.
#
# Isolation: eigener tmux-Socket, jede erzeugte PID wird im `trap` per PID
# beendet (nie per Muster). wb-waisen selbst braucht KEIN tmux-Pane (es ruft
# tmux nur LESEND fuer die Eigentuemer-Pruefung auf); es wird direkt mit
# umgelenktem HOME aufgerufen. wb-nohup dagegen braucht `$TMUX`/`$TMUX_PANE`
# und laeuft deshalb in einem Pane des Testservers.
#
# ZWEITE ISOLATIONSEBENE, EXIT-CODE (Auftrag "eine Pruefung, die von der
# echten Maschine abhaengt, prueft nichts", 2026-08-22): wb-waisen scannt
# grundsaetzlich ALLE eigenen Prozesse der Maschine, nicht nur die dieser
# Suite -- ein $HOME-Wechsel blendet nur Weg-A-Registrierungen aus, nie
# echte, unabhaengig entstandene Waisen (allen voran verwaiste Login-Shells
# anderer Suiten, die HOME-unabhaengig gefunden werden). Gemessen: acht
# solche Shells kippten im Volllauf den Exit-Code dieser Suite, obwohl kein
# einziger eigener Kandidat betroffen war. Jede Pruefung, die den ECHTEN
# Exit-Code von wb-waisen gegen eine feste Zahl vergleicht, laeuft deshalb
# stattdessen ueber `rc_eigene` (unten): sie filtert `$LINES` auf die PIDs,
# die diese Suite selbst erzeugt und in EIGENE_PIDS gemerkt hat, und bildet
# daraus dieselbe Exit-Code-Semantik nur fuer diese Teilmenge -- fremde
# Funde auf der Maschine bleiben darin unsichtbar, eigene Regressionen
# weiterhin sichtbar.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-waisen-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib-testwerkzeuge.sh"
TOOL="${WB_WAISEN:-$REPO_ROOT/shell/wb-waisen}"
NOHUP_TOOL="${WB_NOHUP:-$REPO_ROOT/shell/wb-nohup}"
WORK="$(mktemp -d)"
pass=0; fail=0
echo "Geprueft: $TOOL (wb-nohup: $NOHUP_TOOL)"

tm() { tmux -L "$SOCKET" "$@"; }

EIGENE_PIDS=()
merke_pid() { EIGENE_PIDS[${#EIGENE_PIDS[@]}]="$1"; }

cleanup() {
  local p
  for p in "${EIGENE_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    ps -o pid= -p "$p" >/dev/null 2>&1 && kill "$p" 2>/dev/null
  done
  # tmux_socket_beenden_ohne_reste statt eines blossen kill-server (Auftrag
  # "413 verwaiste Shells", 2026-08-22, siehe deren Kommentar in
  # lib-testwerkzeuge.sh) -- reapt jeden Pane, der den Server-Tod ueberlebt,
  # direkt, statt sich auf ein SIGHUP zu verlassen, das gemessen nicht immer
  # zugestellt wird.
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$WORK"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "SKIP -- wb-waisen ist nur auf macOS unterstuetzt (siehe dessen Kopfkommentar)"
  exit 0
fi

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp

# pane_run <session> <kommando> -> setzt OUT, RC (Ausgabe/Rueckgabewert eines
# im TESTSERVER ausgefuehrten Befehls). Dasselbe Muster wie test-nohup.sh und
# test-doctor-betriebs-befunde.sh.
pane_run() {
  local ziel="$1" cmd="$2" f="$WORK/out.$RANDOM"
  tm send-keys -t "$ziel" "{ $cmd ; } > '$f' 2>&1; echo \"RC=\$?\" >> '$f'; touch '$f.done'" Enter
  if warte_auf_datei "$f.done" 20 "pane_run auf $ziel: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

# waisen_lines <HOME> -> setzt LINES, RC (Aufruf von wb-waisen --lines mit
# umgelenktem HOME — braucht kein Pane, wb-waisen ruft tmux nur lesend auf).
waisen_lines() { LINES="$(HOME="$1" "$TOOL" --lines 2>/dev/null)"; RC=$?; }
# waisen_lines_nur_waisen <HOME> -> dasselbe mit --nur-waisen (Befund 8).
waisen_lines_nur_waisen() { LINES="$(HOME="$1" "$TOOL" --lines --nur-waisen 2>/dev/null)"; RC=$?; }
zeile_fuer_pid() { ZEILE="$(printf '%s\n' "$LINES" | awk -F'|' -v p="$1" '$1==p{print;exit}')"; }

# rc_eigene -> setzt RC_EIGENE: den Exit-Code, den wb-waisen fuer NUR die
# selbst erzeugten Kandidaten (EIGENE_PIDS/merke_pid oben) gemeldet haette --
# unabhaengig davon, was gerade sonst auf der Maschine steht. Auftrag "eine
# Pruefung, die von der echten Maschine abhaengt, prueft nichts" (2026-08-22):
# acht echte verwaiste Login-Shells ANDERER Suiten kippten waehrend eines
# Volllaufs den GLOBALEN Exit-Code von wb-waisen, obwohl kein einziger
# Kandidat dieser Suite betroffen war -- die Login-Shell-Klasse ist, anders
# als Weg A, nicht ueber $HOME isolierbar (sie fragt nie eine Registrierung,
# nur PPID/TTY der ganzen Maschine). Arbeitet auf dem bereits gesetzten
# $LINES (siehe waisen_lines/waisen_lines_nur_waisen), filtert aber auf die
# eigenen PIDs, bevor daraus ein Exit-Code wird -- dieselbe Semantik wie
# wb-waisens echter Exit-Code (1 = mindestens ein eigener Waise, 2 = kein
# eigener Waise, aber mindestens ein eigener unregistrierter Verdachtsfall,
# 0 = weder noch), nur ohne fremde Kandidaten mitzuzaehlen.
rc_eigene() {
  local p klasse hat_waise=0 hat_unreg=0
  for p in "${EIGENE_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    klasse="$(printf '%s\n' "$LINES" | awk -F'|' -v p="$p" '$1==p{print $6; exit}')"
    case "$klasse" in
      waise) hat_waise=1 ;;
      unregistriert) hat_unreg=1 ;;
    esac
  done
  if [ "$hat_waise" -eq 1 ]; then RC_EIGENE=1
  elif [ "$hat_unreg" -eq 1 ]; then RC_EIGENE=2
  else RC_EIGENE=0
  fi
}

pane_lebt_warten() {  # pane_lebt_warten <pid> -> wartet auf PPID=1 + TTY=??
  local pid="$1"
  warte_auf_bedingung 10 "PID $pid reparentet zu launchd (PPID 1, kein TTY)" \
    "[ \"\$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')\" = 1 ] && [ \"\$(ps -o tty= -p $pid 2>/dev/null | tr -d ' ')\" = '??' ]"
}

echo "== wb-waisen =="

# ===========================================================================
# Fall A/B — Weg A: Eigentuemer-Eintrag via wb-nohup
# ===========================================================================
echo "-- A: registrierter Prozess, Pane lebt -> kein Fund --"
HOMEAB="$WORK/homeAB"
mkdir -p "$HOMEAB/bin"
cat > "$HOMEAB/bin/llama-server" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$HOMEAB/bin/llama-server"
tm new-session -d -s wegAB -c /tmp
tm set -p -t wegAB @wb_worker wegAB-worker
pane_run wegAB "HOME='$HOMEAB' '$NOHUP_TOOL' probeAB -- '$HOMEAB/bin/llama-server' --port 60001"
PIDAB="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
if [ -n "$PIDAB" ] && [ "$PIDAB" -gt 0 ] 2>/dev/null; then
  merke_pid "$PIDAB"
  ok "wb-nohup hat den Fixture-Prozess gestartet (PID $PIDAB)"
  waisen_lines "$HOMEAB"
  zeile_fuer_pid "$PIDAB"
  [ -z "$ZEILE" ] \
    && ok "waehrend das Pane lebt: kein Fund fuer PID $PIDAB" \
    || bad "PID $PIDAB wurde gemeldet, obwohl sein Pane noch lebt: $ZEILE"

  echo "-- B: derselbe Prozess, Pane geschlossen -> Klasse 'waise' --"
  tm kill-session -t wegAB 2>/dev/null
  if pane_lebt_warten "$PIDAB"; then
    waisen_lines "$HOMEAB"
    zeile_fuer_pid "$PIDAB"
    if [ -n "$ZEILE" ]; then
      ok "PID $PIDAB wird nach dem Schliessen gemeldet: $ZEILE"
      printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}' | grep -qx waise \
        && ok "Klasse ist 'waise'" \
        || bad "Klasse ist nicht 'waise': $(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      printf '%s\n' "$ZEILE" | grep -qF "wegAB-worker" \
        && ok "Detail nennt den Worker-Namen aus der Registrierung" \
        || bad "Detail nennt den Worker-Namen nicht: $ZEILE"
      rc_eigene
      [ "$RC_EIGENE" -eq 1 ] && ok "Exit-Code (eigene Kandidaten) ist 1 (mindestens ein eigener Waise)" || bad "Exit-Code (eigene Kandidaten) war $RC_EIGENE, erwartet 1"
    else
      bad "PID $PIDAB wurde NACH dem Schliessen NICHT gemeldet"
    fi
  else
    bad "PID $PIDAB hat nicht wie gemessen reparentet -- Testaufbau fehlgeschlagen"
  fi
else
  bad "wb-nohup hat fuer Fall A/B keine PID geliefert: $OUT"
fi

# ===========================================================================
# Fall C — Weg B: eine offene ESTABLISHED-Verbindung heisst benutzt
# ===========================================================================
echo "-- C: unregistrierter Prozess mit offener Verbindung -> 'unregistriert', benutzt --"
HOMEC="$WORK/homeC"
mkdir -p "$HOMEC/bin"
cat > "$HOMEC/bin/llama-server" <<PYEOF
#!/usr/bin/env python3
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 0))
port = s.getsockname()[1]
with open('$WORK/c-port.txt', 'w') as f:
    f.write(str(port))
s.listen(1)
conn, addr = s.accept()
import time
time.sleep(300)
PYEOF
chmod +x "$HOMEC/bin/llama-server"
tm new-session -d -s wegC -c /tmp
tm send-keys -t wegC "nohup '$HOMEC/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/c-pid.txt'" Enter
if warte_auf_datei "$WORK/c-port.txt" 10 "Fall C: Server-Port"; then
  PIDC="$(cat "$WORK/c-pid.txt")"
  merke_pid "$PIDC"
  cat > "$WORK/c-client.py" <<PYEOF
import socket, time
port = int(open('$WORK/c-port.txt').read().strip())
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', port))
open('$WORK/c-client-ready.txt', 'w').write('ok')
time.sleep(300)
PYEOF
  python3 "$WORK/c-client.py" &
  CLIENT_PID_C=$!
  disown   # sonst druckt bash beim Aufraeumen ein kosmetisches "Terminated"
  merke_pid "$CLIENT_PID_C"
  if warte_auf_datei "$WORK/c-client-ready.txt" 10 "Fall C: Client verbunden"; then
    tm kill-session -t wegC 2>/dev/null
    if pane_lebt_warten "$PIDC"; then
      waisen_lines "$HOMEC"
      zeile_fuer_pid "$PIDC"
      if [ -n "$ZEILE" ]; then
        klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
        detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
        [ "$klasse" = "unregistriert" ] && ok "Klasse ist 'unregistriert' (kein Eigentuemer-Eintrag)" || bad "Klasse ist '$klasse', erwartet 'unregistriert'"
        printf '%s' "$detail" | grep -qF "benutzt" && printf '%s' "$detail" | grep -qF "ESTABLISHED" \
          && ok "Detail nennt die offene Verbindung: $detail" \
          || bad "Detail nennt keine Verbindung: $detail"
        printf '%s' "$detail" | grep -qi "kill" \
          && bad "Detail enthaelt trotz Verbindung einen kill-Hinweis: $detail" \
          || ok "kein kill-Vorschlag im Detail"
      else
        bad "PID $PIDC (mit offener Verbindung) wurde NICHT gemeldet"
      fi
    else
      bad "PID $PIDC hat nicht wie gemessen reparentet"
    fi
  else
    bad "Client konnte sich nicht verbinden (Fall C)"
  fi
else
  bad "Server in Fall C hat keinen Port gemeldet"
fi

# ===========================================================================
# Fall D — Weg B: wachsender Speicher heisst benutzt (das LADENDE Modell)
# ===========================================================================
echo "-- D: unregistrierter Prozess mit wachsendem Speicher -> 'unregistriert', benutzt --"
HOMED="$WORK/homeD"
mkdir -p "$HOMED/bin"
# 120 Schritte a 5 MB, JEDE Seite wirklich angefasst (buf[-1]=1) statt nur
# virtuell alloziert -- macOS komprimiert/reclaimt sonst ungenutzte Seiten
# schnell, und ein rein virtueller Zuwachs zeigt sich nicht im RSS (gemessen
# 2026-08-11: eine Fassung ohne Anfassen fiel nach wenigen Sekunden auf
# einstellige MB zurueck, obwohl der Prozess weiterlief). 120*0.5s = 60s
# Gesamtdauer -- reichlich Vorlauf gegenueber wb-waisens eigener Laufzeit
# (typisch 1-4s bis zum Start des Messfensters).
cat > "$HOMED/bin/mlx_lm.server" <<'PYEOF'
#!/usr/bin/env python3
import time
buf = bytearray()
for i in range(120):
    buf += bytearray(5 * 1024 * 1024)
    buf[-1] = 1
    time.sleep(0.5)
time.sleep(300)
PYEOF
chmod +x "$HOMED/bin/mlx_lm.server"
tm new-session -d -s wegD -c /tmp
tm send-keys -t wegD "nohup '$HOMED/bin/mlx_lm.server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/d-pid.txt'" Enter
warte_auf_datei "$WORK/d-pid.txt" 10 "Fall D: PID-Datei"
PIDD="$(cat "$WORK/d-pid.txt" 2>/dev/null)"
# GEWARTET WIRD, BIS DER SPEICHER WIRKLICH WAECHST (2026-08-24, Auftrag "was
# bei zwanzig gleichzeitig passiert"). Hier stand ein fester Vorlauf von einer
# Sekunde. Unter Last reichte der nicht: die Attrappe ist eine FRISCH
# GESCHRIEBENE ausfuehrbare Datei, und macOS prueft jede davon beim ERSTEN
# Start einzeln durch (XprotectService, maschinenweit hintereinander, gemessen
# 100 bis 250 ms je Datei; bei 24 gleichzeitigen ersten Starts wartete der
# langsamste 2,6 s). Die PID steht dann laengst in der Datei, der Prozess hat
# aber noch kein Byte belegt -- und wb-waisens Messfenster von drei Sekunden
# sah folgerichtig kein Wachstum. Gemessen wird jetzt, statt zu schaetzen:
# erst wenn der Zuwachs wirklich dasteht, faellt das Pane.
RSS_START="$(ps -o rss= -p "${PIDD:-0}" 2>/dev/null | tr -d ' ')"
RSS_ZIEL=$(( ${RSS_START:-0} + 10240 ))
warte_auf_bedingung 40 "Fall D: die Attrappe belegt messbar Speicher (Start ${RSS_START:-?} KB, Ziel ${RSS_ZIEL} KB)" \
  '[ "$(ps -o rss= -p "${PIDD:-0}" 2>/dev/null | tr -d " ")" -gt "$RSS_ZIEL" ]'
if [ -n "$PIDD" ]; then
  merke_pid "$PIDD"
  tm kill-session -t wegD 2>/dev/null
  if pane_lebt_warten "$PIDD"; then
    waisen_lines "$HOMED"
    zeile_fuer_pid "$PIDD"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
      [ "$klasse" = "unregistriert" ] && ok "Klasse ist 'unregistriert'" || bad "Klasse ist '$klasse', erwartet 'unregistriert'"
      printf '%s' "$detail" | grep -qF "waechst" \
        && ok "Detail nennt wachsenden Speicher: $detail" \
        || bad "Detail nennt kein Wachstum (evtl. Timing zu knapp): $detail"
      printf '%s' "$detail" | grep -qi "kill" \
        && bad "Detail enthaelt trotz Wachstum einen kill-Hinweis: $detail" \
        || ok "kein kill-Vorschlag im Detail"
    else
      bad "PID $PIDD (waechst) wurde NICHT gemeldet"
    fi
  else
    bad "PID $PIDD hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegD' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall E — Weg B: KEIN Signal -> 'unregistriert', "keine Anhaltspunkte",
# trotzdem KEIN kill-Vorschlag (der Kern der Korrektur: reine Heuristik ohne
# Eigentuemer-Beleg schlaegt nie ein Beenden vor).
# Wartet, bis der Speicher eines Prozesses zwei Messungen lang gleich bleibt.
#
# Anlass (18.08., Volllauf): Fall E startete seinen Prozess und mass sofort. Ein
# frisch gestarteter Prozess belegt aber noch Seiten nach, und `wb-waisen` meldet
# dann ehrlich "benutzt — Speicher waechst" statt "keine Anhaltspunkte". Die
# Zusage prueft die Klassifizierung, nicht die Anlaufphase, also stellt der Test
# jetzt her, was er voraussetzt: einen Prozess, der zur Ruhe gekommen ist.
speicher_ruhig_warten() {
    local pid="$1" grenze="${2:-25}" vorher="" jetzt="" i=0
    while [ "$i" -lt "$grenze" ]; do
        jetzt="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
        [ -n "$jetzt" ] || return 1
        [ "$jetzt" = "$vorher" ] && return 0
        vorher="$jetzt"
        sleep 1
        i=$((i + 1))
    done
    return 0
}

# ===========================================================================
echo "-- E: unregistrierter Prozess ohne jedes Signal -> 'unregistriert', kein kill-Vorschlag --"
HOMEE="$WORK/homeE"
mkdir -p "$HOMEE/bin"
cat > "$HOMEE/bin/llama-server" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$HOMEE/bin/llama-server"
tm new-session -d -s wegE -c /tmp
tm send-keys -t wegE "nohup '$HOMEE/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/e-pid.txt'" Enter
warte_auf_datei "$WORK/e-pid.txt" 10 "Fall E: PID-Datei"
PIDE="$(cat "$WORK/e-pid.txt" 2>/dev/null)"
if [ -n "$PIDE" ]; then
  merke_pid "$PIDE"
  tm kill-session -t wegE 2>/dev/null
  if pane_lebt_warten "$PIDE"; then
    speicher_ruhig_warten "$PIDE"
    waisen_lines "$HOMEE"
    zeile_fuer_pid "$PIDE"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
      [ "$klasse" = "unregistriert" ] && ok "Klasse ist 'unregistriert'" || bad "Klasse ist '$klasse'"
      printf '%s' "$detail" | grep -qF "keine Anhaltspunkte" \
        && ok "Detail sagt ehrlich 'keine Anhaltspunkte': $detail" \
        || bad "Detail sagt etwas anderes: $detail"
      printf '%s' "$detail" | grep -qi "^kill \|kill [0-9]" \
        && bad "trotzdem ein kill-Vorschlag im Detail: $detail" \
        || ok "kein kill-Vorschlag trotz Fund (der Kern der Korrektur)"
      rc_eigene
      [ "$RC_EIGENE" -eq 2 ] && ok "Exit-Code (eigene Kandidaten) ist 2 (kein eigener Waise, aber eigener unregistrierter Verdachtsfall)" || bad "Exit-Code (eigene Kandidaten) war $RC_EIGENE, erwartet 2"
    else
      bad "PID $PIDE wurde NICHT gemeldet"
    fi
  else
    bad "PID $PIDE hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegE' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall F — Praezision: unpassender Name wird NIE gemeldet, auch nicht als
# 'unregistriert' (Diskussions-Ebene, siehe wb-waisens Kopfkommentar).
# ===========================================================================
echo "-- F: unpassender Name wird trotz Verwaisung nie gemeldet --"
HOMEF="$WORK/homeF"
mkdir -p "$HOMEF"
tm new-session -d -s wegF -c /tmp
tm send-keys -t wegF "nohup sleep 300 >/dev/null 2>&1 & disown; echo \$! > '$WORK/f-pid.txt'" Enter
warte_auf_datei "$WORK/f-pid.txt" 10 "Fall F: PID-Datei"
PIDF="$(cat "$WORK/f-pid.txt" 2>/dev/null)"
if [ -n "$PIDF" ]; then
  merke_pid "$PIDF"
  tm kill-session -t wegF 2>/dev/null
  if pane_lebt_warten "$PIDF"; then
    waisen_lines "$HOMEF"
    zeile_fuer_pid "$PIDF"
    [ -z "$ZEILE" ] \
      && ok "unverkleidetes 'sleep' bleibt trotz Verwaisung ungemeldet" \
      || bad "unverkleidetes 'sleep' wurde faelschlich gemeldet: $ZEILE"
  else
    bad "PID $PIDF hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegF' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall G — Hygiene: eine Registrierung ohne lebende PID wird beim naechsten
# Lauf entfernt (schreibt NUR in die eigene Buchhaltung, ruehrt keinen
# Prozess an).
# ===========================================================================
echo "-- G: verwaiste Registrierung (PID existiert nicht) wird aufgeraeumt --"
HOMEG="$WORK/homeG"
mkdir -p "$HOMEG/.local/state/wb-nohup/eigentuemer"
cat > "$HOMEG/.local/state/wb-nohup/eigentuemer/999999.json" <<'EOF'
{"pid": 999999, "name": "geist", "befehl": ["echo","x"], "worker": "niemand",
 "pane": "%0", "socket_path": "/tmp/nichts", "log": "/tmp/nichts.log",
 "gestartet": "2020-01-01T00:00:00", "lstart_pruefwert": "irrelevant"}
EOF
[ -f "$HOMEG/.local/state/wb-nohup/eigentuemer/999999.json" ] || bad "Testaufbau Fall G: Datei wurde nicht angelegt"
waisen_lines "$HOMEG"
if [ -f "$HOMEG/.local/state/wb-nohup/eigentuemer/999999.json" ]; then
  bad "die verwaiste Registrierung steht nach dem Lauf noch da"
else
  ok "die verwaiste Registrierung (PID existiert nicht) wurde entfernt"
fi

# ===========================================================================
# Fall H — PID-Wiederverwendung: ein Eintrag mit falschem lstart_pruefwert
# wird NICHT vertraut (weder als 'waise' noch als 'Eigentuemer lebt') --
# der Kandidat faellt auf Weg B zurueck.
# ===========================================================================
echo "-- H: Eintrag mit falschem lstart_pruefwert wird verworfen, faellt auf Weg B zurueck --"
HOMEH="$WORK/homeH"
mkdir -p "$HOMEH/bin" "$HOMEH/.local/state/wb-nohup/eigentuemer"
cat > "$HOMEH/bin/llama-server" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$HOMEH/bin/llama-server"
tm new-session -d -s wegH -c /tmp
tm send-keys -t wegH "nohup '$HOMEH/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/h-pid.txt'" Enter
warte_auf_datei "$WORK/h-pid.txt" 10 "Fall H: PID-Datei"
PIDH="$(cat "$WORK/h-pid.txt" 2>/dev/null)"
if [ -n "$PIDH" ]; then
  merke_pid "$PIDH"
  cat > "$HOMEH/.local/state/wb-nohup/eigentuemer/$PIDH.json" <<EOF
{"pid": $PIDH, "name": "falsch-zugeordnet", "befehl": ["etwas","anderes"],
 "worker": "geist-worker", "pane": "%99", "socket_path": "/tmp/existiert-nicht",
 "log": "/tmp/x.log", "gestartet": "2020-01-01T00:00:00",
 "lstart_pruefwert": "Mon Jan  1 00:00:00 2020"}
EOF
  tm kill-session -t wegH 2>/dev/null
  if pane_lebt_warten "$PIDH"; then
    waisen_lines "$HOMEH"
    zeile_fuer_pid "$PIDH"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      [ "$klasse" = "unregistriert" ] \
        && ok "der falsch zugeordnete Eintrag wird verworfen, PID faellt auf Weg B zurueck: $ZEILE" \
        || bad "Klasse ist '$klasse' -- der falsche Eintrag wurde faelschlich vertraut: $ZEILE"
      printf '%s\n' "$ZEILE" | grep -qF "geist-worker" \
        && bad "die erfundenen Eigentuemer-Angaben tauchen trotzdem in der Ausgabe auf" \
        || ok "die erfundenen Eigentuemer-Angaben ('geist-worker') tauchen nicht auf"
    else
      bad "PID $PIDH wurde gar nicht gemeldet (haette als 'unregistriert' auftauchen muessen)"
    fi
  else
    bad "PID $PIDH hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegH' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall I — Weg A + Benutzung: ein REGISTRIERTER Prozess mit totem Eigentuemer,
# der gerade benutzt wird (offene ESTABLISHED-Verbindung), bleibt Klasse
# 'waise' (der Eigentuemer ist tatsaechlich tot), bekommt aber KEINEN
# kill-Vorschlag -- der Kern von Befund 1 (unabhaengiger Pruefdurchgang
# 2026-08-11): fruehere Fassung schlug hier sofort kill vor, ohne die
# Benutzung je zu pruefen (derselbe Fehler wie Fund 2, nur ueber den
# Eigentuemer-Eintrag statt ueber PPID 1).
# ===========================================================================
echo "-- I: registrierter Prozess mit totem Eigentuemer UND offener Verbindung -> 'waise', aber kein kill --"
HOMEI="$WORK/homeI"
mkdir -p "$HOMEI/bin"
cat > "$HOMEI/bin/llama-server" <<PYEOF
#!/usr/bin/env python3
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 0))
port = s.getsockname()[1]
with open('$WORK/i-port.txt', 'w') as f:
    f.write(str(port))
s.listen(1)
conn, addr = s.accept()
import time
time.sleep(300)
PYEOF
chmod +x "$HOMEI/bin/llama-server"
tm new-session -d -s wegI -c /tmp
tm set -p -t wegI @wb_worker wegI-worker
pane_run wegI "HOME='$HOMEI' '$NOHUP_TOOL' probeI -- '$HOMEI/bin/llama-server' --port 60002"
PIDI="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
if [ -n "$PIDI" ] && [ "$PIDI" -gt 0 ] 2>/dev/null; then
  merke_pid "$PIDI"
  if warte_auf_datei "$WORK/i-port.txt" 10 "Fall I: Server-Port"; then
    cat > "$WORK/i-client.py" <<PYEOF
import socket, time
port = int(open('$WORK/i-port.txt').read().strip())
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', port))
open('$WORK/i-client-ready.txt', 'w').write('ok')
time.sleep(300)
PYEOF
    python3 "$WORK/i-client.py" &
    CLIENT_PID_I=$!
    disown
    merke_pid "$CLIENT_PID_I"
    if warte_auf_datei "$WORK/i-client-ready.txt" 10 "Fall I: Client verbunden"; then
      tm kill-session -t wegI 2>/dev/null
      if pane_lebt_warten "$PIDI"; then
        waisen_lines "$HOMEI"
        zeile_fuer_pid "$PIDI"
        if [ -n "$ZEILE" ]; then
          klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
          detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
          [ "$klasse" = "waise" ] && ok "Klasse bleibt 'waise' (der Eigentuemer ist tatsaechlich tot)" \
            || bad "Klasse ist '$klasse', erwartet 'waise'"
          printf '%s' "$detail" | grep -qF "wegI-worker" \
            && ok "Detail nennt weiterhin den Eigentuemer: $detail" \
            || bad "Detail nennt den Eigentuemer nicht mehr: $detail"
          printf '%s' "$detail" | grep -qF "benutzt" && printf '%s' "$detail" | grep -qF "ESTABLISHED" \
            && ok "Detail nennt die Gegenstelle/Benutzung: $detail" \
            || bad "Detail nennt keine Benutzung: $detail"
          # Enger Musterabgleich statt blossem "kill"-Substring (wie Fall E):
          # $detail traegt hier ABSICHTLICH die Formulierung "kein
          # automatischer kill-Vorschlag" -- gesucht wird ein tatsaechlicher
          # kill-BEFEHL ("kill 12345"), nicht das Wort im Satz, der ihn verneint.
          printf '%s' "$detail" | grep -qi "^kill \|kill [0-9]" \
            && bad "Detail enthaelt trotz Benutzung einen kill-Befehl: $detail" \
            || ok "kein kill-Befehl im Detail trotz totem Eigentuemer (der Kern von Befund 1)"
          rc_eigene
          [ "$RC_EIGENE" -eq 1 ] && ok "Exit-Code (eigene Kandidaten) ist 1 (weiterhin ein bestaetigter eigener Waise)" || bad "Exit-Code (eigene Kandidaten) war $RC_EIGENE, erwartet 1"
        else
          bad "PID $PIDI (registriert, benutzt) wurde NICHT gemeldet"
        fi
      else
        bad "PID $PIDI hat nicht wie gemessen reparentet"
      fi
    else
      bad "Client konnte sich nicht verbinden (Fall I)"
    fi
  else
    bad "Server in Fall I hat keinen Port gemeldet"
  fi
else
  bad "wb-nohup hat fuer Fall I keine PID geliefert: $OUT"
fi

# ===========================================================================
# Fall J — --nur-waisen (Befund 8): ein UNREGISTRIERTER Kandidat (Weg B)
# wird unter --nur-waisen weder gemessen noch gemeldet -- nur Weg A
# (registrierte Kandidaten mit totem Eigentuemer) bleibt aktiv. Der Beweis,
# dass das Messfenster uebersprungen wurde, ist der Quellcode-Pfad selbst
# (siehe Kommentar direkt vor der Pruefung unten), keine Wanduhr mehr --
# Auftrag "eine Pruefung, die von der echten Maschine abhaengt, prueft
# nichts" (2026-08-22): ein fruehrer Laufzeitvergleich verglich zwei fast
# gleiche Sekundenwerte und wurde unter Last bedeutungslos.
# ===========================================================================
echo "-- J: --nur-waisen ueberspringt Weg B (weder gemeldet noch gemessen) --"
HOMEJ="$WORK/homeJ"
mkdir -p "$HOMEJ/bin"
cat > "$HOMEJ/bin/llama-server" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$HOMEJ/bin/llama-server"
tm new-session -d -s wegJ -c /tmp
tm send-keys -t wegJ "nohup '$HOMEJ/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/j-pid.txt'" Enter
warte_auf_datei "$WORK/j-pid.txt" 10 "Fall J: PID-Datei"
PIDJ="$(cat "$WORK/j-pid.txt" 2>/dev/null)"
if [ -n "$PIDJ" ]; then
  merke_pid "$PIDJ"
  tm kill-session -t wegJ 2>/dev/null
  if pane_lebt_warten "$PIDJ"; then
    waisen_lines "$HOMEJ"
    zeile_fuer_pid "$PIDJ"
    [ -n "$ZEILE" ] \
      && ok "ohne --nur-waisen wird der unregistrierte Kandidat weiterhin gemeldet (Referenz): $ZEILE" \
      || bad "Referenzlauf ohne --nur-waisen hat PID $PIDJ nicht gemeldet -- Testaufbau fehlgeschlagen"

    waisen_lines_nur_waisen "$HOMEJ"
    zeile_fuer_pid "$PIDJ"
    # Der Beweis, dass das 3s-Messfenster uebersprungen wurde, ist "nicht
    # gemeldet", nicht die Uhr: wb-waisen nimmt einen Weg-B-Kandidaten unter
    # --nur-waisen gar nicht erst in UNREG_META auf (dessen Kommentar
    # "Weg-B-Kandidaten werden gar nicht erst aufgenommen"), und NUR wer dort
    # steht, durchlaeuft das gemeinsame SLEEP_SEK-Fenster -- "nicht gemeldet"
    # beweist damit bereits "nicht gemessen". Ein fruehrer Laufzeitvergleich
    # (nur-waisen deutlich schneller als die Referenz) mass stattdessen die
    # MASCHINE: teilt sich ein FREMDER echter Waise (z.B. eine verwaiste
    # Login-Shell einer anderen Suite, siehe rc_eigene oben) dasselbe
    # Messfenster, zahlt auch --nur-waisen dessen volle 3s, obwohl PIDJ nie
    # gemessen wurde -- beide Laeufe landen dann bei denselben paar Sekunden,
    # ohne dass das etwas ueber PIDJ aussagt. Deshalb faellt der
    # Laufzeitvergleich hier ersatzlos weg.
    [ -z "$ZEILE" ] \
      && ok "unter --nur-waisen wird derselbe unregistrierte Kandidat NICHT gemeldet" \
      || bad "unter --nur-waisen trotzdem gemeldet: $ZEILE"
    rc_eigene
    [ "$RC_EIGENE" -eq 0 ] \
      && ok "Exit-Code (eigene Kandidaten) ist 0 (keine Weg-B-Funde unter --nur-waisen, kein eigener Waise)" \
      || bad "Exit-Code (eigene Kandidaten) war $RC_EIGENE, erwartet 0"
  else
    bad "PID $PIDJ hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegJ' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall K — zweite Eigentuemer-Art (2026-08-13): der Eintrag nennt keinen Pane,
# sondern einen launchd-Job (wb-nohup --launchd, gebraucht von
# wb-modell-proxy, das unter launchd ohne Pane laeuft). Geprueft wird beides:
# ein Job, den launchd gar nicht kennt, macht den Prozess zur Waise; ein Job,
# der GERADE laeuft, haelt ihn aus der Meldung heraus.
#
# Auch hier wird die lebende launchd-Domain nur GELESEN (`launchctl list` /
# `print`) — kein Job wird geladen, entladen oder angefasst.
# ===========================================================================
echo "-- K: Eigentuemer ist ein launchd-Job statt eines Panes --"
HOMEK="$WORK/homeK"
mkdir -p "$HOMEK/bin" "$HOMEK/.local/state/wb-nohup/eigentuemer"
cat > "$HOMEK/bin/llama-server" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$HOMEK/bin/llama-server"

# K1: Label unbekannt -> Eigentuemer tot -> Klasse 'waise'
tm new-session -d -s wegK -c /tmp
tm send-keys -t wegK "nohup '$HOMEK/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/k-pid.txt'" Enter
warte_auf_datei "$WORK/k-pid.txt" 10 "Fall K: PID-Datei"
PIDK="$(cat "$WORK/k-pid.txt" 2>/dev/null)"
if [ -n "$PIDK" ]; then
  merke_pid "$PIDK"
  LSTARTK="$(LC_ALL=C ps -o lstart= -p "$PIDK" 2>/dev/null)"
  cat > "$HOMEK/.local/state/wb-nohup/eigentuemer/$PIDK.json" <<EOF
{"pid": $PIDK, "name": "probeK", "befehl": ["$HOMEK/bin/llama-server"],
 "worker": "launchd:agent-workbench.gibt-es-nicht-$$", "pane": "", "socket_path": "",
 "launchd_label": "agent-workbench.gibt-es-nicht-$$",
 "log": "/tmp/x.log", "gestartet": "2026-08-13T00:00:00",
 "lstart_pruefwert": "$LSTARTK"}
EOF
  tm kill-session -t wegK 2>/dev/null
  if pane_lebt_warten "$PIDK"; then
    waisen_lines "$HOMEK"
    zeile_fuer_pid "$PIDK"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      [ "$klasse" = "waise" ] \
        && ok "ein launchd-Job, den es nicht (mehr) gibt, macht den Prozess zur Waise" \
        || bad "Klasse ist '$klasse', erwartet 'waise': $ZEILE"
      printf '%s\n' "$ZEILE" | grep -qF "launchd-Job" \
        && ok "das Detail benennt den launchd-Job als Eigentuemer" \
        || bad "das Detail nennt den launchd-Job nicht: $ZEILE"
    else
      bad "PID $PIDK wurde gar nicht gemeldet"
    fi
  else
    bad "PID $PIDK hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegK' konnte nicht gestartet werden"
fi

# K2: Label eines JETZT laufenden EIGENEN Jobs -> kein Fund.
#
# Gefragt wird nicht die lebende launchd-Domain, sondern eine Attrappe im
# PATH (dieselbe Bauart wie in test-nohup.sh): welcher echte Job gerade
# laeuft, ist Zufall der Maschine und taugt nicht als Zusage. Seit dem Review
# vom 13.08. zaehlen ausserdem nur Labels mit dem Praefix agent-workbench. —
# ein fremder Dauerlaeufer wie com.apple.Finder darf keine unbefristete
# Ausnahme von dieser Pruefung stiften.
LAUFENDES_LABEL="agent-workbench.testjob-$$"
STUBBIN="$WORK/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/launchctl" <<EOF
#!/bin/bash
if [ "\$1" = "print" ]; then
  case "\$2" in
    */"$LAUFENDES_LABEL") printf '\tstate = running\n\tpid = %s\n' "\$\$"; exit 0 ;;
  esac
  echo "Could not find service \"\$2\"" >&2; exit 113
fi
exit 0
EOF
chmod +x "$STUBBIN/launchctl"
if [ -z "$LAUFENDES_LABEL" ]; then
  echo "  SKIP  kein laufender launchd-Job gefunden — K2 nicht pruefbar"
else
  HOMEK2="$WORK/homeK2"
  mkdir -p "$HOMEK2/bin" "$HOMEK2/.local/state/wb-nohup/eigentuemer"
  cp "$HOMEK/bin/llama-server" "$HOMEK2/bin/llama-server"
  tm new-session -d -s wegK2 -c /tmp
  tm send-keys -t wegK2 "nohup '$HOMEK2/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/k2-pid.txt'" Enter
  warte_auf_datei "$WORK/k2-pid.txt" 10 "Fall K2: PID-Datei"
  PIDK2="$(cat "$WORK/k2-pid.txt" 2>/dev/null)"
  if [ -n "$PIDK2" ]; then
    merke_pid "$PIDK2"
    LSTARTK2="$(LC_ALL=C ps -o lstart= -p "$PIDK2" 2>/dev/null)"
    cat > "$HOMEK2/.local/state/wb-nohup/eigentuemer/$PIDK2.json" <<EOF
{"pid": $PIDK2, "name": "probeK2", "befehl": ["$HOMEK2/bin/llama-server"],
 "worker": "launchd:$LAUFENDES_LABEL", "pane": "", "socket_path": "",
 "launchd_label": "$LAUFENDES_LABEL",
 "log": "/tmp/x.log", "gestartet": "2026-08-13T00:00:00",
 "lstart_pruefwert": "$LSTARTK2"}
EOF
    tm kill-session -t wegK2 2>/dev/null
    if pane_lebt_warten "$PIDK2"; then
      LINES="$(HOME="$HOMEK2" PATH="$STUBBIN:$PATH" "$TOOL" --lines 2>/dev/null)"
      zeile_fuer_pid "$PIDK2"
      [ -z "$ZEILE" ] \
        && ok "ein laufender launchd-Job als Eigentuemer haelt den Prozess aus der Meldung heraus" \
        || bad "trotz laufendem Eigentuemer gemeldet: $ZEILE"
    else
      bad "PID $PIDK2 hat nicht wie gemessen reparentet"
    fi
  else
    bad "Fixture 'wegK2' konnte nicht gestartet werden"
  fi
fi

# K3: ein FREMDER Dauerlaeufer als Eigentuemer stiftet keine Ausnahme.
# `wb-nohup` laesst so ein Label nicht mehr eintragen (Review S6), aber eine
# von Hand geschriebene Registrierung koennte es — deshalb steht dieselbe
# Schranke auch hier, und dieser Fall belegt sie.
echo "-- K3: ein fremdes Label (com.apple.*) nimmt niemanden aus der Pruefung --"
HOMEK3="$WORK/homeK3"
mkdir -p "$HOMEK3/bin" "$HOMEK3/.local/state/wb-nohup/eigentuemer"
cp "$HOMEK/bin/llama-server" "$HOMEK3/bin/llama-server"
tm new-session -d -s wegK3 -c /tmp
tm send-keys -t wegK3 "nohup '$HOMEK3/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/k3-pid.txt'" Enter
warte_auf_datei "$WORK/k3-pid.txt" 10 "Fall K3: PID-Datei"
PIDK3="$(cat "$WORK/k3-pid.txt" 2>/dev/null)"
if [ -n "$PIDK3" ]; then
  merke_pid "$PIDK3"
  LSTARTK3="$(LC_ALL=C ps -o lstart= -p "$PIDK3" 2>/dev/null)"
  cat > "$HOMEK3/.local/state/wb-nohup/eigentuemer/$PIDK3.json" <<EOF
{"pid": $PIDK3, "name": "probeK3", "befehl": ["$HOMEK3/bin/llama-server"],
 "worker": "launchd:com.apple.Finder", "pane": "", "socket_path": "",
 "launchd_label": "com.apple.Finder",
 "log": "/tmp/x.log", "gestartet": "2026-08-13T00:00:00",
 "lstart_pruefwert": "$LSTARTK3"}
EOF
  tm kill-session -t wegK3 2>/dev/null
  if pane_lebt_warten "$PIDK3"; then
    waisen_lines "$HOMEK3"
    zeile_fuer_pid "$PIDK3"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      [ "$klasse" = "waise" ] \
        && ok "ein fremdes Label zaehlt nicht als lebender Eigentuemer" \
        || bad "Klasse ist '$klasse', erwartet 'waise': $ZEILE"
    else
      bad "PID $PIDK3 wurde gar nicht gemeldet — das fremde Label hat eine Ausnahme gestiftet"
    fi
  else
    bad "PID $PIDK3 hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegK3' konnte nicht gestartet werden"
fi

# ===========================================================================
# Fall M — ein Server, mehrere Benutzer (2026-08-21, nachmittags)
# ===========================================================================
# DER GEMESSENE VORFALL: Vier Sitzungen benutzten EINEN Modellserver.
# Eingetragen war der Pane der zuletzt gestarteten; genau die wurde zuerst
# geschlossen. `wb-waisen` meldete daraufhin
#
#   68479 ... |waise|Eigentuemer: Pane %95 (tot) — gestartet 2026-08-21T06:19:40
#
# waehrend eine lebende Sitzung den Server benutzte. Wer nach dieser Meldung
# handelt, beendet einen Server, an dem jemand haengt.
#
# Die drei Faelle, in derselben Reihenfolge wie im Auftrag:
#   M1  Eigentuemer stirbt, ein anderer Benutzer lebt -> KEIN Fund
#   M2  auch der letzte Benutzer stirbt               -> Fund
#   M3  von Anfang an kein Benutzer                   -> Fund (Fall A..K decken
#       das bereits; hier nur der Vollstaendigkeit halber ueber dieselbe Kette)
echo "-- M: ein Server, mehrere Benutzer --"
HOMEM="$WORK/homeM"
mkdir -p "$HOMEM/bin"
cat > "$HOMEM/bin/llama-server" <<'PYEOF'
#!/usr/bin/env python3
import time
time.sleep(300)
PYEOF
chmod +x "$HOMEM/bin/llama-server"
tm new-session -d -s wegM1 -c /tmp
tm set -p -t wegM1 @wb_worker wegM1-worker
tm new-session -d -s wegM2 -c /tmp
tm set -p -t wegM2 @wb_worker wegM2-worker
PANE_M2="$(tm list-panes -t wegM2 -F '#{pane_id}' 2>/dev/null | head -1)"
SOCK_M="$(tm display -p -t wegM2 '#{socket_path}' 2>/dev/null)"
pane_run wegM1 "HOME='$HOMEM' '$NOHUP_TOOL' probeM -- '$HOMEM/bin/llama-server' --port 60003"
PIDM="$(printf '%s\n' "$OUT" | tail -1 | tr -d ' ')"
if [ -n "$PIDM" ] && [ "$PIDM" -gt 0 ] 2>/dev/null && [ -n "$PANE_M2" ]; then
  merke_pid "$PIDM"
  # Die zweite Sitzung traegt sich als Benutzer ein -- genau das tut `wb-code`,
  # sobald seine tmux-Sitzung steht.
  HOME="$HOMEM" "$NOHUP_TOOL" benutzer "$PIDM" --pane "$PANE_M2" --socket "$SOCK_M" >/dev/null 2>&1 \
    && ok "M0: die zweite Sitzung traegt sich als Benutzer ein" \
    || bad "M0: der Eintrag als Benutzer schlug fehl"
  # Jetzt stirbt der EIGENTUEMER -- die Sitzung, die den Server gestartet hat.
  tm kill-session -t wegM1 2>/dev/null
  if pane_lebt_warten "$PIDM"; then
    waisen_lines "$HOMEM"
    zeile_fuer_pid "$PIDM"
    if [ -z "$ZEILE" ]; then
      ok "M1: der Eigentuemer ist tot, ein Benutzer lebt -> KEIN Fund"
    else
      bad "M1: gemeldet, obwohl eine lebende Sitzung den Server benutzt: $ZEILE"
    fi
    # Und jetzt geht auch der letzte.
    tm kill-session -t wegM2 2>/dev/null
    sleep 0.6
    waisen_lines "$HOMEM"
    zeile_fuer_pid "$PIDM"
    if [ -n "$ZEILE" ]; then
      klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
      detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
      [ "$klasse" = "waise" ] \
        && ok "M2: stirbt der letzte Benutzer, ist es eine Waise" \
        || bad "M2: Klasse ist '$klasse', erwartet 'waise': $ZEILE"
      printf '%s' "$detail" | grep -qF "Benutzer" \
        && ok "M2b: das Detail sagt, dass keiner der eingetragenen Benutzer mehr lebt" \
        || bad "M2b: das Detail nennt die Benutzer nicht: $detail"
    else
      bad "M2: nach dem Ende ALLER Benutzer wurde gar nichts gemeldet — das ist der stille Fehler"
    fi
  else
    bad "M: PID $PIDM hat nicht wie gemessen reparentet"
  fi
else
  bad "Fixture 'wegM' konnte nicht gestartet werden (PID '$PIDM', Pane '$PANE_M2')"
fi

# ===========================================================================
# Fall N -- vierte Klasse (2026-08-22, Auftrag "413 verwaiste Shells, und ein
# Waechter, der sie nicht sah"): eine verwaiste LOGIN-SHELL.
#
# GEBAUT STATT ERWUERFELT (2026-08-24, Auftrag "was bei zwanzig gleichzeitig
# passiert"). Bis dahin stellte dieser Fall das SIGHUP-Rennen nach: achtmal
# zwoelf tmux-Sitzungen anlegen, den Server sofort erschiessen und hoffen, dass
# eine Pane-Shell ueberlebt. Das Rennen blieb aus -- in vier vollen Laeufen
# hintereinander ueberlebte keine einzige Shell, und der Fall meldete jedesmal
# FAIL, obwohl an wb-waisen nichts falsch war. Ohne jede Last nachgemessen:
# 0 von 96 Panes ueberlebten den Server-Tod, 0 von 70 ein kill-session. Ein
# Test, der ein Rennen BRAUCHT, prueft die Maschine und nicht sein Werkzeug --
# und kostete dabei 96 tmux-Server je Lauf. Die Fixture
# fixtures/waise-login-shell.py baut denselben ZUSTAND unmittelbar (nackte
# '-zsh', PPID 1, echtes Pseudoterminal, Master-Seite von einem Halter offen
# gehalten); geprueft wird damit unveraendert das, worum es geht: ob wb-waisen
# diesen Zustand als 'waise' der Kategorie 'Login-Shell (verwaist)' meldet.
# ===========================================================================
echo "-- N: verwaiste Login-Shell (nackte '-zsh', PPID 1, echtes Pseudoterminal) --"
UEBERLEBENDE_PID=""
UEBERLEBENDE_TTY=""
WAISE_HALTER=""
WAISE_ZEILE="$(python3 "$(dirname "${BASH_SOURCE[0]}")/fixtures/waise-login-shell.py" 120 2>/dev/null)"
UEBERLEBENDE_PID="$(printf '%s' "$WAISE_ZEILE" | awk '{print $2}')"
WAISE_HALTER="$(printf '%s' "$WAISE_ZEILE" | awk '{print $4}')"
[ -n "$UEBERLEBENDE_PID" ] && merke_pid "$UEBERLEBENDE_PID"
[ -n "$WAISE_HALTER" ] && merke_pid "$WAISE_HALTER"
# Der execv der Shell braucht einen Augenblick, bis `ps` sie als '-zsh' fuehrt.
for _versuch in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(ps -o command= -p "${UEBERLEBENDE_PID:-0}" 2>/dev/null | tr -d ' ')" = "-zsh" ] && break
  sleep 0.2
done
UEBERLEBENDE_TTY="$(ps -o tty= -p "${UEBERLEBENDE_PID:-0}" 2>/dev/null | tr -d ' ')"

HOMEN="$WORK/homeN_unbenutzt"; mkdir -p "$HOMEN"
if [ -n "$UEBERLEBENDE_PID" ] && ps -o pid= -p "$UEBERLEBENDE_PID" >/dev/null 2>&1 \
   && [ "$(ps -o command= -p "$UEBERLEBENDE_PID" | tr -d ' ')" = "-zsh" ]; then
  ok "die Fixture steht: nackte Anmelde-Shell PID $UEBERLEBENDE_PID auf $UEBERLEBENDE_TTY, PPID $(ps -o ppid= -p "$UEBERLEBENDE_PID" | tr -d ' ')"
  waisen_lines "$HOMEN"
  zeile_fuer_pid "$UEBERLEBENDE_PID"
  if [ -n "$ZEILE" ]; then
    klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
    kategorie="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $5}')"
    detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
    [ "$klasse" = "waise" ] && ok "Klasse ist 'waise'" || bad "Klasse ist '$klasse', erwartet 'waise': $ZEILE"
    [ "$kategorie" = "Login-Shell (verwaist)" ] \
      && ok "Kategorie benennt die Klasse: $kategorie" \
      || bad "Kategorie ist '$kategorie', erwartet 'Login-Shell (verwaist)'"
    printf '%s' "$detail" | grep -qF "PPID 1" \
      && ok "Detail nennt PPID 1 als Beleg: $detail" \
      || bad "Detail nennt PPID 1 nicht: $detail"
    printf '%s' "$detail" | grep -qi "^kill \|kill [0-9]" \
      && bad "Detail enthaelt einen kill-BEFEHL (gehoert nicht ins Detail, nur die menschliche Ausgabe schlaegt kill vor): $detail" \
      || ok "kein kill-Befehl im Detail"
    waisen_lines "$HOMEN"
    rc_eigene
    [ "$RC_EIGENE" -eq 1 ] && ok "Exit-Code (eigene Kandidaten) ist 1 (mindestens ein eigener Waise)" || bad "Exit-Code (eigene Kandidaten) war $RC_EIGENE, erwartet 1"
  else
    bad "PID $UEBERLEBENDE_PID (verwaiste Login-Shell) wurde NICHT gemeldet"
  fi
else
  bad "die Fixture fixtures/waise-login-shell.py hat keine verwaiste Anmelde-Shell hinterlassen (Ausgabe: '${WAISE_ZEILE:-leer}')"
fi

echo "-- N2: eine LEBENDE Login-Shell (Pane einer laufenden Session) wird NICHT gemeldet --"
LEBENDIGE_PID="$(tm list-panes -t steuer -F '#{pane_pid}' 2>/dev/null)"
if [ -n "$LEBENDIGE_PID" ]; then
  waisen_lines "$HOMEN"
  zeile_fuer_pid "$LEBENDIGE_PID"
  [ -z "$ZEILE" ] \
    && ok "die lebende Shell des 'steuer'-Panes wird nicht gemeldet" \
    || bad "die lebende Shell des 'steuer'-Panes wurde faelschlich gemeldet: $ZEILE"
else
  bad "Fall N2: PID des 'steuer'-Panes nicht ermittelbar"
fi

# ===========================================================================
# Fall O — Praezision der reinen Erkennungsfunktionen, OHNE lebenden Prozess
# und OHNE das Rennen aus Fall N: ist_login_shell()/ist_echtes_pty() aus
# wb-waisen direkt gegen erfundene Werte geprueft (extrahiert per sed in eine
# eigene Datei -- `source <(...)` funktioniert dafuer auf dieser Maschine
# NICHT zuverlaessig, gemessen: die Funktionsdefinition landet dann nicht im
# aufrufenden Prozess). Deterministisch, kein Fixture, keine Wartezeit --
# deckt genau die Faelle ab, die ueber einen echten Pane kaum zuverlaessig
# zu erzwingen waeren (eine Shell MIT Argumenten, ein Skriptname, ein
# nicht-echtes TTY).
# ===========================================================================
echo "-- O: Praezision -- eine Shell MIT Argumenten oder ein Nicht-PTY faellt nie unter die Klasse --"
FUNKTIONEN="$WORK/wb-waisen-funktionen.sh"
sed -n '/^ist_echtes_pty()/,/^}/p; /^ist_login_shell()/,/^}/p' "$TOOL" > "$FUNKTIONEN"
if [ -s "$FUNKTIONEN" ]; then
  # shellcheck source=/dev/null
  . "$FUNKTIONEN"
  if command -v ist_login_shell >/dev/null 2>&1 && command -v ist_echtes_pty >/dev/null 2>&1; then
    for c in "-zsh" "zsh" "-bash" "bash" "-sh" "sh"; do
      ist_login_shell "$c" && ok "ist_login_shell erkennt die nackte Shell '$c'" \
        || bad "ist_login_shell erkennt '$c' NICHT, obwohl es eine nackte Shell ist"
    done
    for c in "zsh -c sleep 300" "/bin/zsh -c hello" "bash script.sh" "vim" "kshell" ""; do
      ist_login_shell "$c" \
        && bad "ist_login_shell erkennt faelschlich '$c' als nackte Shell" \
        || ok "ist_login_shell laesst '$c' durch (kein nackter Prompt)"
    done
    for t in ttys004 ttys004s001 ttys0 pts/0; do  # Kit fix (Linux): pts/N is a real pty
      ist_echtes_pty "$t" && ok "ist_echtes_pty erkennt '$t' als echtes PTY" \
        || bad "ist_echtes_pty erkennt '$t' NICHT als echtes PTY"
    done
    for t in "??" "tty1" ""; do
      ist_echtes_pty "$t" \
        && bad "ist_echtes_pty haelt '$t' faelschlich fuer ein echtes PTY" \
        || ok "ist_echtes_pty laesst '$t' durch (kein echtes PTY)"
    done
  else
    bad "die Funktionen ist_login_shell/ist_echtes_pty liessen sich nicht aus $TOOL extrahieren"
  fi
else
  bad "Extraktion nach $FUNKTIONEN blieb leer -- passen die Funktionsnamen in wb-waisen noch?"
fi

# ===========================================================================
# Fall P — die neue fuenfte Kategorie (Mac-Werkbank kopflos) erkennt beide
# Haelften an gestellten Befehlszeilen, mit Pfad im Etikett, und bleibt auf
# das bekannte Projektlayout eingeengt (Gegenlesen 08.09.2026, Punkte 8/9/11)
# ===========================================================================
echo "-- P: match_kategorie erkennt Mac-Werkbank kopflos (App und Electron-Kern), mit Pfad im Etikett --"
FUNKTIONEN_P="$WORK/wb-waisen-match-kategorie.sh"
sed -n '/^match_kategorie()/,/^}/p' "$TOOL" > "$FUNKTIONEN_P"
if [ -s "$FUNKTIONEN_P" ]; then
  # shellcheck source=/dev/null
  . "$FUNKTIONEN_P"
  if command -v match_kategorie >/dev/null 2>&1; then
    # App unter einem Worktree-Bau, mit --kopflos -> Fund, Pfad im Etikett.
    K="$(match_kategorie '$HOME/.pi-workers/worktrees/waisen/mac/build/Werkbank.app/Contents/MacOS/Werkbank --terminal strom --kopflos')"
    case "$K" in
      'Mac-Werkbank kopflos (Build: $HOME/.pi-workers/worktrees/waisen/mac/build)') ok "App unter einem Worktree-Bau erkannt, Etikett nennt den Bau: $K" ;;
      *) bad "App unter einem Worktree-Bau: Etikett '$K' nennt den Bau nicht wie erwartet" ;;
    esac
    # Kern unter claude-workbench/app, mit --headless -> Fund, Pfad im Etikett.
    K="$(match_kategorie 'node $HOME/AI/claude-workbench/app/node_modules/.bin/electron $HOME/AI/claude-workbench/app --headless')"
    case "$K" in
      'Mac-Werkbank kopflos (Electron-Kern, Build: $HOME/AI/claude-workbench)') ok "Kern unter claude-workbench/app erkannt, Etikett nennt den Bau: $K" ;;
      *) bad "Kern unter claude-workbench/app: Etikett '$K' nennt den Bau nicht wie erwartet" ;;
    esac
    # Kern unter einem ANDEREN Worktree -- dieselbe Kategorie, eigener Pfad im Etikett.
    K="$(match_kategorie '$HOME/.pi-workers/worktrees/geometrie/app/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron $HOME/.pi-workers/worktrees/geometrie/app --headless')"
    case "$K" in
      'Mac-Werkbank kopflos (Electron-Kern, Build: $HOME/.pi-workers/worktrees/geometrie)') ok "Kern unter einem zweiten Worktree erkannt, eigener Pfad im Etikett: $K" ;;
      *) bad "Kern unter zweitem Worktree: Etikett '$K' falsch" ;;
    esac
    # ECHTE des Nutzers, normal gestartete App (kein --kopflos) -- bleibt unerkannt.
    match_kategorie '/Applications/Werkbank.app/Contents/MacOS/Werkbank' >/dev/null \
      && bad "normal des Nutzers gestartete /Applications/Werkbank.app wurde faelschlich als kopflos erkannt" \
      || ok "normal des Nutzers gestartete /Applications/Werkbank.app (ohne --kopflos) bleibt unerkannt"
    # Punkt 9: ein VOELLIG FREMDES Electron-Werkzeug mit einem Verzeichnis, das
    # zufaellig 'app' heisst, darf NICHT mitgezaehlt werden -- die Regex ist auf
    # das bekannte Layout (claude-workbench/app, worktrees/<name>/app) eingeengt.
    match_kategorie 'node /Users/irgendwer/anderes-projekt/app/node_modules/.bin/electron /Users/irgendwer/anderes-projekt/app --headless' >/dev/null \
      && bad "ein fremdes Electron-Werkzeug mit zufaelligem 'app'-Verzeichnis wurde faelschlich erkannt" \
      || ok "ein fremdes Electron-Werkzeug (Verzeichnis heisst nur zufaellig 'app') bleibt unerkannt"
  else
    bad "match_kategorie liess sich nicht aus $TOOL extrahieren"
  fi
else
  bad "Extraktion nach $FUNKTIONEN_P blieb leer -- passt der Funktionsname in wb-waisen noch?"
fi

# ===========================================================================
# Fall Q — unix_verbindungen_von() erkennt eine UNIX-Socket-Gegenstelle
# (Gegenlesen 08.09.2026, Pflichtpunkt 3): direkter Test der Funktion gegen
# einen selbst gestellten UNIX-Domain-Socket, vor und nach einer Verbindung.
# ===========================================================================
echo "-- Q: unix_verbindungen_von erkennt eine UNIX-Socket-Gegenstelle --"
FUNKTIONEN_Q="$WORK/wb-waisen-unix-verbindungen.sh"
sed -n '/^unix_verbindungen_von()/,/^}/p' "$TOOL" > "$FUNKTIONEN_Q"
if [ -s "$FUNKTIONEN_Q" ]; then
  # shellcheck source=/dev/null
  . "$FUNKTIONEN_Q"
  if command -v unix_verbindungen_von >/dev/null 2>&1; then
    QSOCK="$WORK/q.sock"
    cat > "$WORK/q-server.py" <<PYEOF
import socket, os, time
try: os.unlink('$QSOCK')
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('$QSOCK')
s.listen(1)
open('$WORK/q-bound.txt', 'w').write('ok')
time.sleep(3)
conn, _ = s.accept()
open('$WORK/q-accepted.txt', 'w').write('ok')
time.sleep(300)
PYEOF
    python3 "$WORK/q-server.py" &
    QPID=$!
    disown
    merke_pid "$QPID"
    if warte_auf_datei "$WORK/q-bound.txt" 10 "Fall Q: Server gebunden"; then
      N="$(unix_verbindungen_von "$QPID")"
      [ "${N:-0}" = 0 ] && ok "vor einer Verbindung: 0 Gegenstellen (nur gebunden, kein Client)" \
        || bad "vor einer Verbindung meldet unix_verbindungen_von faelschlich $N Gegenstelle(n)"
      cat > "$WORK/q-client.py" <<PYEOF
import socket, time
c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
c.connect('$QSOCK')
open('$WORK/q-client-ready.txt', 'w').write('ok')
time.sleep(300)
PYEOF
      python3 "$WORK/q-client.py" &
      QCPID=$!
      disown
      merke_pid "$QCPID"
      if warte_auf_datei "$WORK/q-client-ready.txt" 10 "Fall Q: Client verbunden" \
         && warte_auf_datei "$WORK/q-accepted.txt" 10 "Fall Q: Server hat akzeptiert"; then
        N="$(unix_verbindungen_von "$QPID")"
        [ "${N:-0}" -gt 0 ] 2>/dev/null && ok "nach einer Verbindung: $N Gegenstelle(n) erkannt" \
          || bad "nach einer Verbindung meldet unix_verbindungen_von immer noch $N Gegenstelle(n)"
      else
        bad "Fall Q: Client/Server kamen nicht zusammen"
      fi
    else
      bad "Fall Q: Server hat sich nicht gebunden"
    fi
  else
    bad "unix_verbindungen_von liess sich nicht aus $TOOL extrahieren"
  fi
else
  bad "Extraktion nach $FUNKTIONEN_Q blieb leer -- passt der Funktionsname in wb-waisen noch?"
fi

# ===========================================================================
# Fall R — End-zu-Ende: ein unregistrierter Prozess, der NUR ueber einen
# UNIX-Socket redet (keine ESTABLISHED-TCP-Verbindung, keine CPU-/RSS-
# Bewegung im Messfenster), wird trotzdem als 'benutzt' gemeldet -- genau der
# Fund, den der Gegenleser als BUG benannt hat (Pflichtpunkt 3): ohne das
# vierte Signal waere das hier "keine Anhaltspunkte fuer Benutzung" gewesen,
# und ein Mensch haette den kill getippt.
# ===========================================================================
echo "-- R: unregistrierter Prozess NUR mit UNIX-Socket-Gegenstelle -> 'unregistriert', benutzt (nicht 'keine Anhaltspunkte') --"
HOMER="$WORK/homeR"
mkdir -p "$HOMER/bin"
RSOCK="$WORK/r.sock"
cat > "$HOMER/bin/llama-server" <<PYEOF
#!/usr/bin/env python3
import socket, os, time
try: os.unlink('$RSOCK')
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('$RSOCK')
s.listen(1)
open('$WORK/r-bound.txt', 'w').write('ok')
conn, _ = s.accept()
time.sleep(300)
PYEOF
chmod +x "$HOMER/bin/llama-server"
tm new-session -d -s wegR -c /tmp
tm send-keys -t wegR "nohup '$HOMER/bin/llama-server' >/dev/null 2>&1 & disown; echo \$! > '$WORK/r-pid.txt'" Enter
if warte_auf_datei "$WORK/r-bound.txt" 10 "Fall R: Server gebunden"; then
  PIDR="$(cat "$WORK/r-pid.txt")"
  merke_pid "$PIDR"
  cat > "$WORK/r-client.py" <<PYEOF
import socket, time
c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
c.connect('$RSOCK')
open('$WORK/r-client-ready.txt', 'w').write('ok')
time.sleep(300)
PYEOF
  python3 "$WORK/r-client.py" &
  CLIENT_PID_R=$!
  disown
  merke_pid "$CLIENT_PID_R"
  if warte_auf_datei "$WORK/r-client-ready.txt" 10 "Fall R: Client verbunden"; then
    tm kill-session -t wegR 2>/dev/null
    if pane_lebt_warten "$PIDR"; then
      waisen_lines "$HOMER"
      zeile_fuer_pid "$PIDR"
      if [ -n "$ZEILE" ]; then
        klasse="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $6}')"
        detail="$(printf '%s\n' "$ZEILE" | awk -F'|' '{print $7}')"
        [ "$klasse" = "unregistriert" ] && ok "Klasse ist 'unregistriert' (kein Eigentuemer-Eintrag)" || bad "Klasse ist '$klasse', erwartet 'unregistriert'"
        printf '%s' "$detail" | grep -qF "benutzt" && printf '%s' "$detail" | grep -qF "UNIX-Socket" \
          && ok "Detail nennt die UNIX-Socket-Gegenstelle (nicht 'keine Anhaltspunkte'): $detail" \
          || bad "Detail nennt keine UNIX-Socket-Benutzung -- genau der gemeldete Bug: $detail"
        printf '%s' "$detail" | grep -qi "kill" \
          && bad "Detail enthaelt trotz Verbindung einen kill-Hinweis: $detail" \
          || ok "kein kill-Vorschlag im Detail"
      else
        bad "PID $PIDR (mit UNIX-Socket-Gegenstelle) wurde NICHT gemeldet"
      fi
    else
      bad "PID $PIDR hat nicht wie gemessen reparentet"
    fi
  else
    bad "Client konnte sich nicht verbinden (Fall R)"
  fi
else
  bad "Server in Fall R hat sich nicht gebunden"
fi

echo
echo "wb-waisen: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
