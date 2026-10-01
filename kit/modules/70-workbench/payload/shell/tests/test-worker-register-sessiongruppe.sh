#!/usr/bin/env bash
# test-worker-register-sessiongruppe.sh -- ein Worker landet im Zustandsdokument
# SEINER Session, auch wenn diese Session gerade in einer tmux-Sessiongruppe
# haengt (Basis '<sess>' + gruppierte Sicht '<sess>-view', wie sie das Programm
# fuer den Worker-Tab anlegt) -- und er landet NIE zufaellig im Dokument einer
# FREMDEN Session, nur weil deren Dateiname zufaellig zum Arbeitsverzeichnis passt.
#
# ANLASS (06.08.2026): zwei Worker aus derselben laufenden Session gestartet.
# 'sitzung' (Arbeitsverzeichnis .../app) landete in KEINEM Zustandsdokument --
# unsichtbar. 'symbol' (Arbeitsverzeichnis .../claude-workbench) landete beim
# ERSTEN Spawn im Dokument einer ANDEREN, laengst toten Session, weil deren
# Dateiname zufaellig zur Verzeichnis-Kennung passte; erst der zweite Auftrag an
# denselben Pane landete richtig.
#
# GEMESSENE URSACHE: `tmux display -p -t <pane> '#{session_name}'` ist INSTABIL,
# sobald das Fenster des Panes einer Sessiongruppe angehoert -- derselbe Pane
# antwortet je nach Aufrufzeitpunkt mal mit der Basis, mal mit der '-view'-
# Schwester (auf einem eigenen Testsocket nachgemessen: ein Pane, ueber
# `list-panes -t wb-AI` gefunden, meldete unter `display -p` als Session
# 'wb-AI-view'). `#{session_group}` ist dagegen fuer BEIDE Mitglieder derselbe,
# stabile Basisname. Der Fix: pi-worker's neue base_session_name() (Vorlage:
# context-guard's gleichnamige Funktion) nimmt `#{session_group}`, nicht
# `#{session_name}`. Zweite Verteidigungslinie in wb-state: der Ausweich-Pfad
# auf `own_file(dir)` darf eine Datei, die bereits einer ANDEREN, bekannten
# Session gehoert, nicht mehr stillschweigend uebernehmen.
#
# ZWEI TEILE:
#   A  Worker in einer bereits gruppierten Session, Arbeitsverzeichnis WEICHT
#      vom Projektverzeichnis ab (wie bei 'sitzung'): landet im Dokument DIESER
#      Session -- gefunden ueber tmuxSession, nicht ueber den Verzeichnisnamen.
#   B  Worker in einer NIE beruehrten Session, deren Arbeitsverzeichnis zufaellig
#      zum Dateinamen einer FREMDEN, toten Session passt (wie bei 'symbol'):
#      landet in KEINEM Dokument -- insbesondere nicht im fremden --, und
#      pi-worker meldet das auf stderr statt es zu verschweigen.
#
# KEIN ECHTER AGENT LAEUFT HIER (Schirm statt `claude`, siehe
# test-pi-worker-auftragsbuch.sh, gleiche Technik).
#
# ISOLATION: eigener tmux-Socket, eigenes HOME (Zustand, Ergebnisse, Registry
# liegen alle darunter), kein Zugriff auf die echte Session oder ~/.pi-workers.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-sessgruppe-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"
MARKE="s$(date +%s)$$$RANDOM"

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

echo "== Worker landen im richtigen Zustandsdokument, auch in einer Sessiongruppe (Socket $SOCKET, HOME $TESTHOME) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-state" ] || ueberspringen "shell/wb-state fehlt"

# --- Testumgebung, vollstaendig selbst hergestellt -------------------------
mkdir -p "$SHIM" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.local/bin"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Der falsche Agent (identisch zu test-pi-worker-auftragsbuch.sh): zeigt das
# Bereitschaftszeichen, laesst eine leere Eingabezeile stehen, fuehrt nichts aus,
# echot den empfangenen Text aber weiter -- die Absende-Pruefung belegt seit
# 2026-08-17 auch den Inhalt, nicht nur die leere Eingabezeile.
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

cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
chmod +x "$TESTHOME/.local/bin/wb-state"
# Echt, kein Stub (2026-08-07): pi-worker tippt jeden Tastendruck ueber
# $HOME/.local/bin/wb-pane-write (Abschirmung 2026-08-06). Fehlt es, tippt pi-worker
# nichts und meldet stattdessen selbst "FEHLER: ... fehlt" -- genau der String, den
# die Assertions unten als ECHTEN Fehlschlag lesen. Ohne das echte Werkzeug wurden
# Teil A und B faelschlich rot, unabhaengig vom eigentlich geprueften Verhalten.
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write"
chmod +x "$TESTHOME/.local/bin/wb-pane-write"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      TMUX= TMUX_PANE= WB_SESSION="$WBSESS_ARG" \
      bash "$REPO/pi-worker" "$@" 2>&1
}

slug() { printf '%s' "$1" | tr '/' '-'; }

echo
echo "-- Teil A: Worker in einer gruppierten Session, Arbeitsverzeichnis weicht vom Projekt ab --"

SESSA="wb-A-$MARKE"
PROJEKT="$TESTHOME/projekt"
APPDIR="$PROJEKT/app"
mkdir -p "$PROJEKT" "$APPDIR"

tmux -L "$SOCKET" -f /dev/null new-session -d -s "$SESSA" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "$SESSA" @wb_role orchestrator

# Wie die Extension es beim Sessionstart tut: das eigene Zustandsdokument des
# Projektverzeichnisses traegt die tmux-Session ein.
PATH="$TESTHOME/.local/bin:$PATH" HOME="$TESTHOME" "$TESTHOME/.local/bin/wb-state" touch "$PROJEKT" "$SESSA" >/dev/null

# Die gruppierte '-view'-Schwester entsteht (wie wb-worker-tab es beim Oeffnen
# des Worker-Tabs tut) -- VOR dem Spawn, wie im gemessenen Vorfall.
tmux -L "$SOCKET" new-session -d -t "=$SESSA" -s "$SESSA-view"
GRP="$(tmux -L "$SOCKET" display -p -t "$SESSA" '#{session_group}' 2>/dev/null)"
[ "$GRP" = "$SESSA" ] && ok "A: Sessiongruppe steht (session_group=$SESSA)" \
                       || bad "A: Sessiongruppe fehlt (session_group='$GRP') -- Testaufbau fehlerhaft"

DATEIA="$TESTHOME/.claude/workbench/sessions/$(slug "$PROJEKT").json"
[ -e "$DATEIA" ] && ok "A: Voraussetzung: Projekt-Zustandsdokument existiert ($DATEIA)" \
                  || bad "A: Voraussetzung verletzt -- kein Projekt-Zustandsdokument"

WORKERA="wA$MARKE"
# WB_SESSION ist die fuer einen Aufrufer ohne eigenen tmux-Kontext vorgesehene,
# explizite Form (siehe pi-worker's eigener Kommentar zu TARGET) -- mit zwei
# gruppierten Sessions waere die sonstige Rateweg-Kette (angehaengte/einzige
# wb-*-Session) ohnehin nicht eindeutig. Sie bestimmt nur, WELCHE Session den
# Pane bekommt; die eigentliche Frage dieses Tests -- WBSESS bei der
# Registrierung NACH dem Spawn -- bleibt davon unberuehrt.
WBSESS_ARG="$SESSA"
AUSA="$(pi "$WORKERA" claude-opus5 "$APPDIR" "Testauftrag A $MARKE")"
if grep -q "FEHLER" <<<"$AUSA"; then
  bad "A: pi-worker meldete einen FEHLER"
  printf '%s\n' "$AUSA" | sed 's/^/      | /' | tail -12
else
  ok "A: pi-worker lief ohne FEHLER durch"
fi

if grep -q "\"name\": \"$WORKERA\"" "$DATEIA" 2>/dev/null; then
  ok "A: der Worker steht im Zustandsdokument DIESER Session ($DATEIA)"
else
  bad "A: der Worker fehlt im Zustandsdokument der Session ($DATEIA)"
fi

DATEIAPP="$TESTHOME/.claude/workbench/sessions/$(slug "$APPDIR").json"
[ ! -e "$DATEIAPP" ] \
  && ok "A: kein zusaetzliches Dokument fuer das Arbeitsverzeichnis entstanden ($DATEIAPP)" \
  || bad "A: es entstand ein FALSCHES Dokument fuer das Arbeitsverzeichnis ($DATEIAPP)"

echo
echo "-- Teil B: fremdes, totes Zustandsdokument mit passendem Dateinamen darf nicht uebernommen werden --"

SESSB="wb-B-$MARKE"
ALTPROJEKT="$TESTHOME/altprojekt"
mkdir -p "$ALTPROJEKT"

tmux -L "$SOCKET" new-session -d -s "$SESSB" -x 200 -y 40
tmux -L "$SOCKET" set-option -p -t "$SESSB" @wb_role orchestrator
tmux -L "$SOCKET" new-session -d -t "=$SESSB" -s "$SESSB-view"

# Ein STALE-Dokument, das rein zufaellig denselben Dateinamen wie das
# Arbeitsverzeichnis dieses Workers traegt, aber einer LAENGST TOTEN, anderen
# Session gehoert (genau der Fall, der 'symbol' beim ersten Spawn traf).
DATEIB="$TESTHOME/.claude/workbench/sessions/$(slug "$ALTPROJEKT").json"
cat > "$DATEIB" <<EOF
{"dir": "$ALTPROJEKT", "tmuxSession": "wb-tot-$MARKE", "workers": [], "lastActive": "2020-01-01T00:00:00Z"}
EOF
VORHER_MD5="$(md5 -q "$DATEIB" 2>/dev/null || md5sum "$DATEIB" | cut -d' ' -f1)"

WORKERB="wB$MARKE"
WBSESS_ARG="$SESSB"
AUSB="$(pi "$WORKERB" claude-opus5 "$ALTPROJEKT" "Testauftrag B $MARKE")"

if grep -q "FEHLER" <<<"$AUSB"; then
  bad "B: pi-worker meldete einen FEHLER -- der Spawn selbst darf trotz fehlender Registrierung gelingen"
  printf '%s\n' "$AUSB" | sed 's/^/      | /' | tail -12
else
  ok "B: pi-worker spawnte den Pane trotzdem (Registrierung ist kein Abbruchgrund)"
fi

NACHHER_MD5="$(md5 -q "$DATEIB" 2>/dev/null || md5sum "$DATEIB" | cut -d' ' -f1)"
[ "$VORHER_MD5" = "$NACHHER_MD5" ] \
  && ok "B: das fremde Dokument blieb UNVERAENDERT (kein Diebstahl)" \
  || bad "B: das fremde Dokument wurde veraendert -- der Worker wurde der falschen, toten Session zugeschlagen"

if grep -q "\"name\": \"$WORKERB\"" "$DATEIB" 2>/dev/null; then
  bad "B: der Worker steht (falsch) im fremden Dokument"
fi

if grep -qi "WARNUNG" <<<"$AUSB" && grep -q "$WORKERB" <<<"$AUSB"; then
  ok "B: eine WARNUNG auf stderr nennt den Workernamen -- nichts blieb still"
else
  bad "B: keine WARNUNG mit dem Workernamen gefunden -- der Ausfall bleibt stumm"
  printf '%s\n' "$AUSB" | sed 's/^/      | /' | tail -12
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
[ ! -e "$HOME/.claude/workbench/sessions/$(slug "$PROJEKT").json" ] \
  && ok "kein Eintrag unter dem ECHTEN HOME entstanden" \
  || bad "es wurde in das ECHTE ~/.claude/workbench geschrieben -- Testisolation gebrochen"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
