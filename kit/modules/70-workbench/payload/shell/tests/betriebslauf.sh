#!/usr/bin/env bash
# betriebslauf.sh — eine ganze Session-Lebensgeschichte, in der Reihenfolge, in
# der ein Mensch sie durchlaeuft, mit einer Strukturpruefung nach JEDEM Schritt.
#
# Warum es das zusaetzlich zu den 23 Testsuiten gibt (2026-08-04): in der Nacht
# waren alle Suiten gruen, und zehn Minuten BENUTZUNG foerderten trotzdem zwei
# echte Fehler zutage — `wb-session-close <fremde-session>` liess die
# '-view'-Schwester stehen, und `wb-doctor` Punkt 7 uebersah einen fehlenden
# Worker-Tab, weil es `session_attached` ueber die ganze Gruppe summierte. Beide
# leben in der VERKETTUNG: jede Suite prueft ihr Werkzeug einzeln, niemand prueft
# die Handgriffe hintereinander. Genau das tut diese Datei.
#
# Der Massstab nach jedem Schritt ist `wb-doctor`: es darf nichts melden, was der
# Schritt nicht beabsichtigt hat — und die Befunde, die er melden MUSS, muessen
# wirklich kommen (ein uebersehener Befund ist derselbe Fehler wie ein falscher).
#
# SICHERHEIT. Nichts hiervon beruehrt die Live-Umgebung:
#   * eigener tmux-Socket 'wbtest-betrieb-<pid>', kein einziger Aufruf gegen
#     'default'. Jedes Werkzeug laeuft ueber einen PATH-Schirm, der `tmux`
#     unabaenderlich auf diesen Socket festnagelt — ein Werkzeug KANN den
#     Live-Server hier nicht erreichen, auch wenn es wollte.
#   * eigenes HOME (mktemp -d): Zustandsdateien, Einstellungen, Marken und
#     Sicherungen entstehen ausschliesslich dort.
#   * Sessionnamen mit eigenem Praefix ('wb-Betriebstest-…'), nie ein Name aus
#     laufenden des Nutzers Sessions.
#   * `trap` raeumt Server und Verzeichnisse auf, auch bei Abbruch. Kein pkill,
#     kein killall, kein Muster ueber fremde Prozesse.
#
# Gefundene Fehler werden GEMELDET, nicht repariert: jeder Befund erscheint am
# Ende mit Schritt, Erwartung, Beobachtung und der kuerzesten Befehlsfolge, die
# ihn zeigt.
unset TMUX TMUX_PANE
set -uo pipefail

# --- Werkzeuge --------------------------------------------------------------
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

WERKZEUGE="wb-doctor wb-session-close wb-session-delete wb-session-orphan
           wb-worker-tab wb-workers-window wb-grid wb-state wb-close"

SOCKET="wbtest-betrieb-$$"
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

pass=0; fail=0; skip=0
FUNDE=()

# Ist $REPO ein git-Worktree (statt des Hauptbaums)? Gleiche Pruefung wie in
# betriebslauf2.sh (dort ausfuehrlich begruendet): unterschiedliche
# `--git-dir` gegenueber `--git-common-dir` heisst Worktree; leer/kein git
# faellt auf "Hauptbaum" zurueck, damit die Pruefung im Zweifel LAEUFT.
is_worktree() {
  local gd cd
  gd="$(git -C "$REPO" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cd="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$gd" ] && [ -n "$cd" ] && [ "$gd" != "$cd" ]
}

tm() { tmux -L "$SOCKET" "$@"; }

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

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Ein BEFUND ist ein Fehler im Werkzeug, kein Fehler im Test: Schritt, Erwartung,
# Beobachtung, Reproduktion. Er wird gesammelt und am Ende ausgegeben — repariert
# wird hier nichts.
fund() { # fund <schritt> <erwartet> <beobachtet> <reproduktion>
  FUNDE+=("$(printf 'Schritt:      %s\nErwartet:     %s\nBeobachtet:   %s\nReproduktion: %s' "$1" "$2" "$3" "$4")")
}

# --- Vorbereitung -----------------------------------------------------------
# Geprueft wird der STAND IM REPO — dort entstehen die Reparaturen. Weicht die
# ausgerollte Fassung unter ~/.local/bin davon ab, ist das selbst ein Befund: sie
# ist es, die der Nutzer beim Arbeiten aufruft.
mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.local/state"
ABWEICHEND=""
for w in $WERKZEUGE; do
  # Je Werkzeug ueberschreibbar (WB_GRID, WB_DOCTOR, …) — so laesst sich ein
  # einzelnes Werkzeug gegen einen aelteren Stand halten, ohne im Repo etwas
  # anzufassen. Ohne Ueberschreibung gilt der Repo-Stand.
  var="$(printf '%s' "$w" | tr 'a-z-' 'A-Z_')"
  src="${!var:-$REPO/$w}"
  [ -x "$src" ] || src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
  if [ -x "$REPO/$w" ] && [ -x "$REAL_BIN/$w" ] && ! cmp -s "$REPO/$w" "$REAL_BIN/$w"; then
    ABWEICHEND="$ABWEICHEND $w"
  fi
done
chmod +x "$BIN"/*

# Der Schirm: jedes Werkzeug, das `tmux` aufruft, landet auf dem Testsocket.
# Damit ist der Live-Socket 'default' aus diesem Lauf heraus unerreichbar, auch
# fuer ein Werkzeug, das $TMUX ignoriert.
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

PROJEKT="$TESTHOME/AI/Betriebstest"
mkdir -p "$PROJEKT"
SLUG="-$(printf '%s' "${PROJEKT#/}" | tr '/' '-')"
CSLUG="$(printf '%s' "$PROJEKT" | tr -c 'a-zA-Z0-9' '-')"
STATE="$TESTHOME/.claude/workbench/sessions"
TRANS="$TESTHOME/.claude/projects/$CSLUG"
mkdir -p "$TRANS"

SESS="wb-Betriebstest-$$"
CID="44444444-4444-4444-4444-444444444444"

zustandsdatei() { # zustandsdatei <slug> <tmux-session> <claude-id>
  cat > "$STATE/$1.json" <<JSON
{ "dir": "$PROJEKT", "name": "Betriebstest", "tmuxSession": "$2",
  "claudeSessionId": "$3", "workers": [] }
JSON
  echo '{"type":"user"}' > "$TRANS/$3.jsonl"
}

# --- Ausfuehrung in einem Pane des TESTSERVERS -------------------------------
# Nie aus dieser Shell heraus: nur in einem Pane zeigt $TMUX auf den Testsocket,
# und nur so gehen die Werkzeuge dieselben Wege wie im echten Betrieb.
lauf() { # lauf <pane> <kommando> -> setzt OUT und RC
  local ziel="$1" cmd="$2" f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t "$ziel" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 60 "lauf: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}
steuer() { lauf "$CTRL" "$1"; }

lebt() { tm has-session -t "=$1" 2>/dev/null; }

# Ein Client, wie ihn ein VS-Code-Tab darstellt: ein Pane der Steuersession, in
# dem ein verschachtelter `attach` laeuft. Gemessen: das ergibt einen echten
# Client, `session_attached` zaehlt ihn.
klient_basis() { # klient_basis <session> -> gibt die Pane-Id aus
  tm split-window -d -t "$CTRL" -P -F '#{pane_id}' \
    "TMUX= TMUX_PANE= PATH='$PANE_PATH' HOME='$TESTHOME' tmux attach -t '=$1'"
}
klient_workertab() { # klient_workertab <session> [fenster] -> Pane-Id
  local w="${2:-workers}"
  tm split-window -d -t "$CTRL" -P -F '#{pane_id}' \
    "TMUX= TMUX_PANE= PATH='$PANE_PATH' HOME='$TESTHOME' WB_WORKER_TAB_WAIT=5 wb-worker-tab '$1' --window '$w'"
}
klient_zu() { tm kill-pane -t "$1" 2>/dev/null; }

klienten_an() { # klienten_an <session> -> Zahl der Clients an genau dieser Session
  tm list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
    | awk -v n="$1" '$1==n{print $2; found=1} END{if(!found) print 0}'
}

warte_auf_klient() { # warte_auf_klient <session> <soll>
  local deadline=$((SECONDS+10))
  until [ "$(klienten_an "$1")" = "$2" ] || [ $SECONDS -ge $deadline ]; do sleep 0.3; done
}

# --- Die Strukturpruefung nach jedem Schritt --------------------------------
# `wb-doctor` laeuft, seine BEFUND-Zeilen werden gegen die Liste der fuer diesen
# Schritt BEABSICHTIGTEN Befunde gehalten. Beides zaehlt als Fehler: ein Befund,
# den der Schritt nicht beabsichtigt hat, und ein beabsichtigter, der ausbleibt.
# Zeilen ueber die Steuersession werden ausgeblendet — sie ist das Geruest des
# Tests (ein Pane ohne @wb_role, kein workers-Fenster) und nicht der Prueflig.
DOC=""
ZAEHLER_GEMELDET=""
doctor() {
  steuer "wb-doctor"
  DOC="$OUT"
}
# Ein Regex mit vorangestelltem '?' ist GEDULDET: er darf auftreten, muss aber
# nicht (etwa ein Ueberlauf-Befund, der verschwindet, sobald wb-grid das zweite
# Fenster wieder einklappt). Alles ohne '?' MUSS kommen.
pruefe_struktur() { # pruefe_struktur <kontext> [ [?]erwartetes-regex ... ]
  local kontext="$1"; shift
  doctor
  local alle; alle="$(printf '%s\n' "$DOC" | sed -n 's/^  BEFUND  *//p')"
  local zeilen; zeilen="$(printf '%s\n' "$alle" | grep -v 'steuer')"
  # Die Schlusszeile von wb-doctor ist das, was ein Mensch liest, wenn er nicht
  # die ganze Ausgabe durchgeht. Sie muss so viele Befunde nennen, wie darueber
  # stehen — sonst haelt er den Rechner fuer aufgeraeumter, als er ist.
  local gedruckt genannt schluss
  gedruckt="$(printf '%s\n' "$alle" | grep -c . | tr -d ' ')"
  schluss="$(printf '%s\n' "$DOC" | grep '^wb-doctor: ' | tail -1)"
  case "$schluss" in
    *"keine Befunde"*) genannt=0 ;;
    *) genannt="$(printf '%s' "$schluss" | sed -n 's/^wb-doctor: \([0-9]*\) Befund.*/\1/p')" ;;
  esac
  if [ -n "${genannt:-}" ] && [ "$genannt" != "$gedruckt" ] && [ -z "$ZAEHLER_GEMELDET" ]; then
    ZAEHLER_GEMELDET=1
    bad "$kontext: wb-doctor druckt $gedruckt Befund(e) und zaehlt darunter $genannt"
    fund "$kontext (Schlusszeile von wb-doctor)" \
         "die Schlusszeile nennt so viele Befunde, wie darueber gedruckt wurden" \
         "gedruckt $gedruckt, gezaehlt $genannt ('$schluss') — die Punkte 5 und 6 laufen in einer Pipeline ('tmux list-panes … | while'), ihr \$befunde-Zaehler lebt in der Subshell und ist nach der Schleife wieder verloren" \
         "einen Worker-Pane in ein Fenster legen, das nicht 'workers' heisst (oder ein Pane ohne @wb_role), dann wb-doctor: die letzte Zeile zaehlt diesen Befund nicht mit"
  fi
  local -a muster=("$@") getroffen=()
  local i unerwartet=0 z m
  for ((i=0; i<${#muster[@]}; i++)); do getroffen[i]=0; done
  while IFS= read -r z; do
    [ -n "$z" ] || continue
    local trifft=0
    for ((i=0; i<${#muster[@]}; i++)); do
      m="${muster[i]#\?}"
      if printf '%s' "$z" | grep -qE "$m"; then getroffen[i]=1; trifft=1; fi
    done
    if [ "$trifft" -eq 0 ]; then
      bad "$kontext: wb-doctor meldet unerwartet: $z"
      unerwartet=$((unerwartet+1))
    fi
  done <<< "$zeilen"
  for ((i=0; i<${#muster[@]}; i++)); do
    case "${muster[i]}" in
      '?'*) [ "${getroffen[i]}" -eq 1 ] && ok "$kontext: der geduldete Befund tritt auf (${muster[i]#\?})" ;;
      *)    if [ "${getroffen[i]}" -eq 1 ]; then
              ok "$kontext: der beabsichtigte Befund kommt (${muster[i]})"
            else
              bad "$kontext: der beabsichtigte Befund BLEIBT AUS (${muster[i]})"
            fi ;;
    esac
  done
  if [ "$unerwartet" -eq 0 ]; then
    if [ "${#muster[@]}" -eq 0 ]; then
      ok "$kontext: wb-doctor meldet nichts"
    else
      ok "$kontext: wb-doctor meldet nichts Unerwartetes"
    fi
  fi
  return 0
}

# Meldet wb-doctor einen Befund UND behauptet '--fix', ihn repariert zu haben,
# dann muss er danach weg sein. Bleibt er stehen, ist die Meldung eine leere
# Zusage — die naechste Person haelt den Rechner fuer aufgeraeumt.
pruefe_reparatur() { # pruefe_reparatur <kontext> <regex> <reproduktion>
  local kontext="$1" regex="$2" repro="$3"
  steuer "wb-doctor --fix"
  local behauptet; behauptet="$(printf '%s\n' "$OUT" | grep -c '^  REPARIERT' | tr -d ' ')"
  doctor
  if printf '%s\n' "$DOC" | grep -qE "$regex"; then
    if [ "${behauptet:-0}" -gt 0 ]; then
      bad "$kontext: '--fix' meldet $behauptet Reparatur(en), der Befund steht danach unveraendert da"
      fund "$kontext" \
           "wb-doctor --fix beseitigt den Befund oder sagt, dass er ihn nicht beseitigen kann" \
           "--fix meldet $behauptet REPARIERT, derselbe Befund kommt beim naechsten Lauf unveraendert wieder" \
           "$repro"
    else
      ok "$kontext: '--fix' verspricht nichts, was es nicht halten kann"
    fi
  else
    ok "$kontext: '--fix' hat den Befund wirklich beseitigt"
  fi
}

# --- Worker ------------------------------------------------------------------
worker_starten() { # worker_starten <name>
  local wp
  wp="$(tm split-window -t "$ORCH" -P -F '#{pane_id}' 2>/dev/null)"
  [ -n "$wp" ] || { bad "Worker '$1' liess sich nicht anlegen"; return 1; }
  tm set -p -t "$wp" @wb_role worker
  tm set -p -t "$wp" @wb_worker "$1"
  lauf "$ORCH" "wb-grid $ORCH"
  printf '%s' "$wp"
}
worker_panes() { # worker_panes [fenstermuster] -> Anzahl
  local muster="${1:-^workers(-[0-9]+)?$}"
  tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
    | awk -F'|' -v s="$SESS" -v m="$muster" '$1==s && $2 ~ m && $3=="worker"' | wc -l | tr -d ' '
}
panes_im_fenster() { # panes_im_fenster <fenster>
  tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
    | awk -F'|' -v s="$SESS" -v w="$1" '$1==s && $2==w && $3=="worker"' | wc -l | tr -d ' '
}
# Worker-Panes ueber ALLE Worker-Fenster ('workers', 'workers-2', ...). Seit dem
# 03.09.2026 (Stufe A) bekommt jeder Worker im Layout 'window' sein eigenes
# Fenster; die Frage "sind sie drueben?" laesst sich deshalb nicht mehr an einem
# einzelnen Fensternamen stellen.
panes_in_workerfenstern() {
  tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
    | awk -F'|' -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="worker"' | wc -l | tr -d ' '
}
# Ohne die Steuersession: sie ist das Geruest des Tests, nicht der Prueflig.
sichten() {
  tm list-sessions -F '#{session_name}' 2>/dev/null | grep -v '^steuer' | grep -c -- '-view$' | tr -d ' '
}
streusessions() {
  tm list-sessions -F '#{session_name}|#{session_group}' 2>/dev/null \
    | awk -F'|' '$2 ~ /^=/{print $1}'
}
aktives_fenster() { # aktives_fenster <session>
  tm list-windows -t "=$1" -F '#{window_name} #{window_active}' 2>/dev/null | awk '$2==1{print $1; exit}'
}

echo "== Betriebslauf: eine Session von der Geburt bis zum Aufraeumen =="
echo "   Socket: $SOCKET   HOME: $TESTHOME   Session: $SESS"
echo "   Geprueft wird der Repo-Stand aus $REPO"
if is_worktree; then
  # Der Vergleich ist in einem Worktree bedeutungslos, gleicher Grund wie in
  # betriebslauf2.sh: ~/.local/bin gehoert zum Hauptbaum, Worker rollen dort
  # seit 04.08. nichts mehr aus. Sichtbar uebersprungen statt als dauerhaft
  # zutreffender, aber nun bedeutungsloser "hinw"-Fund mitgefuehrt.
  printf '  %-5s %s\n' "SKIP" "Deploy-Vergleich uebersprungen -- $REPO ist ein Arbeitsbaum (git-Worktree, nicht der Hauptbaum). ~/.local/bin gehoert zum Hauptbaum; Worker rollen dorthin nichts mehr aus."
  skip=$((skip+1))
elif [ -n "$ABWEICHEND" ]; then
  # Als Befund notiert, aber NICHT als FAIL gezaehlt: dass eine Reparatur im Repo
  # noch nicht ausgerollt ist, sagt nichts ueber den Stand aus, den dieser Lauf
  # prueft — und run-all.sh waere sonst dauerhaft rot, solange irgendetwas im
  # Repo neuer ist als die Kopie unter ~/.local/bin.
  printf '  %-5s %s\n' "hinw" "Ausgerollt und Repo gehen auseinander:$ABWEICHEND"
  fund "0 (vor dem ersten Schritt)" \
       "die Fassung unter ~/.local/bin ist dieselbe wie im Repo — sie ist es, die beim Arbeiten laeuft" \
       "diese Werkzeuge weichen ab:$ABWEICHEND (im Betrieb laeuft also noch der Stand ohne die Reparaturen dieser Nacht)" \
       "for f in$ABWEICHEND; do cmp -s shell/\$f ~/.local/bin/\$f || echo \"\$f abweichend\"; done"
else
  ok "ausgerollte Fassung und Repo-Stand sind identisch"
fi
echo

tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp -x 200 -y 50
tmux_live_hooks_kappen "$SOCKET"   # ~/.tmux.conf ist keine Isolationsgrenze, siehe lib-testwerkzeuge.sh
CTRL="$(tm list-panes -t steuer -F '#{pane_id}' | head -1)"
steuer "wb-state settings set workerLayout window; wb-state settings set maxWorkerPanesPerTab 6"
MAXPT="$(sed -n 's/.*"maxWorkerPanesPerTab" *: *\([0-9]*\).*/\1/p' "$TESTHOME/.claude/workbench/settings.json" 2>/dev/null)"
MAXPT="${MAXPT:-6}"
echo "   workerLayout=window  maxWorkerPanesPerTab=$MAXPT"
echo

# ── Schritt 1: Session anlegen ───────────────────────────────────────────────
echo "-- Schritt 1: Session anlegen (Basis, workers-Fenster, gruppierte Sicht) --"
lebt "$SESS" && bad "1 davor: '$SESS' existiert schon" || ok "1 davor: '$SESS' existiert noch nicht"

tm new-session -d -x 197 -y 54 -s "$SESS" -n main -c "$PROJEKT"
ORCH="$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)"
tm set -p -t "$ORCH" @wb_role orchestrator
zustandsdatei "$SLUG" "$SESS" "$CID"
lebt "$SESS" && ok "1: Basis-Session laeuft" || bad "1: Basis-Session fehlt"

# Nur die Basis: das workers-Fenster und die Sicht fehlen noch, und niemand sieht
# hin. Genau diese drei Befunde MUSS wb-doctor jetzt bringen.
pruefe_struktur "1a (nur Basis)" \
  "'$SESS' hat kein 'workers'-Fenster" \
  "'$SESS' hat keine Sicht" \
  "'$SESS' laeuft, aber KEIN Client sieht sie"

steuer "wb-workers-window '$SESS'"
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qx workers \
  && ok "1: workers-Fenster angelegt" || bad "1: kein workers-Fenster"
lebt "$SESS-view" && ok "1: gruppierte Sicht '$SESS-view' angelegt" || bad "1: keine Sicht"
[ "$(sichten)" = 1 ] && ok "1: genau eine Sicht" || bad "1: $(sichten) Sichten"

pruefe_struktur "1b (Struktur steht, kein Fenster offen)" \
  "'$SESS' laeuft, aber KEIN Client sieht sie"

KL_ORCH="$(klient_basis "$SESS")"
warte_auf_klient "$SESS" 1
[ "$(klienten_an "$SESS")" = 1 ] && ok "1: ein Client am Orchestrator-Tab" \
                                 || bad "1: kein Client am Orchestrator-Tab"
# Das ist Fehler (b) vom 04.08.: die Sicht hat KEINEN Client, die Gruppe schon.
# Wer ueber die Gruppe summiert, sieht hier nichts.
pruefe_struktur "1c (nur Orchestrator-Tab offen)" \
  "'$SESS': kein Client am Worker-Tab"

KL_TAB="$(klient_workertab "$SESS")"
warte_auf_klient "$SESS-view" 1
[ "$(klienten_an "$SESS-view")" = 1 ] && ok "1: ein Client am Worker-Tab" \
                                      || bad "1: kein Client am Worker-Tab"
pruefe_struktur "1d (beide Tabs offen)"

# ── Schritt 2: Worker-Tab zweimal ────────────────────────────────────────────
echo
echo "-- Schritt 2: wb-worker-tab zweimal hintereinander --"
vorher_sichten="$(sichten)"
steuer "WB_WORKER_TAB_WAIT=5 wb-worker-tab '$SESS' --no-attach"
printf '%s\n' "$OUT" | grep -qx "BASE=$SESS" && ok "2: erster Lauf arbeitet auf der Basis" \
                                             || bad "2: erster Lauf meldet nicht BASE=$SESS: $OUT"
steuer "WB_WORKER_TAB_WAIT=5 wb-worker-tab '$SESS' --no-attach"
printf '%s\n' "$OUT" | grep -qx "VIEW=$SESS-view" && ok "2: zweiter Lauf zeigt auf dieselbe Sicht" \
                                                  || bad "2: zweiter Lauf meldet nicht VIEW=$SESS-view: $OUT"
[ "$(sichten)" = "$vorher_sichten" ] \
  && ok "2: der zweite Lauf hat keine zweite Sicht gebaut ($vorher_sichten)" \
  || bad "2: aus $vorher_sichten Sichten wurden $(sichten)"
lebt "$SESS-view-view" && bad "2: '-view-view' entstanden" || ok "2: kein '-view-view'"
[ -z "$(streusessions)" ] && ok "2: keine Streu-Session mit '='-Gruppe" \
                          || bad "2: Streu-Session(en): $(streusessions | tr '\n' ' ')"
[ "$(klienten_an "$SESS-view")" = 1 ] && ok "2: der offene Worker-Tab haengt weiter" \
                                      || bad "2: der Worker-Tab hat seinen Client verloren"
pruefe_struktur "2 (nach zwei Tab-Aufrufen)"

# ── Schritt 3: Worker-Panes und Layoutwechsel ────────────────────────────────
echo
echo "-- Schritt 3: drei Worker, Layout window <-> split --"
W1="$(worker_starten w1)"; W2="$(worker_starten w2)"; W3="$(worker_starten w3)"
[ "$(panes_in_workerfenstern)" = 3 ] \
  && ok "3: drei Worker-Panes, jeder in seinem eigenen Worker-Fenster" \
  || bad "3: $(panes_in_workerfenstern) Worker-Panes in Worker-Fenstern (erwartet 3)"
tm list-panes -a -F '#{session_name}|#{window_name}|#{@wb_role}' 2>/dev/null \
  | awk -F'|' -v s="$SESS" '$1==s && $2 ~ /^workers(-[0-9]+)?$/ && $3=="placeholder"' | grep -q . \
  && bad "3: ein Platzhalter steht noch neben echten Workern" \
  || ok "3: der Platzhalter ist gewichen"
pruefe_struktur "3a (drei Worker, workerLayout=window)"

# Der Wechsel, wie die Extension ihn ausloest (applyWorkerLayout): Einstellung
# setzen, wb-grid auf dem ORCHESTRATOR-Pane, danach faellt der Worker-Tab weg.
#
# minWorkerPaneWidth geht dafuer auf 60. Das Fenster ist 197 Spalten breit, drei
# Worker nebeneinander brauchen also je 65 Spalten; beim Default 80 waere einer
# von ihnen regulaerer Ueberlauf und bliebe ABSICHTLICH im Fenster 'workers'
# stehen. Dieser Schritt fragt nach der Rueckholung, nicht nach der
# Breitengrenze — die hat ihren eigenen Fall in test-worker-grid-layout.sh.
steuer "wb-state settings set minWorkerPaneWidth 60"
steuer "wb-state settings set workerLayout split"
lauf "$ORCH" "wb-grid $ORCH"
sleep 0.5
im_haupt="$(panes_im_fenster main)"
noch_workers="$(panes_in_workerfenstern)"
if [ "$im_haupt" = 3 ]; then
  ok "3: nach dem Wechsel auf 'split' liegen alle drei im Orchestrator-Fenster"
else
  bad "3: nur $im_haupt von 3 Workern im Orchestrator-Fenster ($noch_workers stehen weiter in einem workers*-Fenster)"
  fund "3 (Layoutwechsel window -> split)" \
       "wb-grid holt die Worker aus dem 'workers'-Fenster zurueck ins Orchestrator-Fenster (so steht es im Kopf von wb-grid: \"Switching the setting at runtime MOVES panes\")" \
       "die $noch_workers Worker bleiben in ihren Worker-Fenstern liegen; wb-grids split-Zweig bildet 'rest' nur aus Panes des ORCHESTRATOR-Fensters (shell/wb-grid, \$3==ow), Panes in einem workers*-Fenster sieht er nie" \
       "wb-state settings set workerLayout window; 3 Worker spawnen + wb-grid; wb-state settings set workerLayout split; wb-grid <orch-pane>; tmux list-panes -a"
fi
# Unter 'split' gibt es kein 'workers'-Fenster mehr — wb-grid raeumt es weg, das
# ist der richtige Zustand. Dass wb-doctor Punkt 4 es trotzdem einfordert, ist
# derselbe Befund wie die eingeforderte Sicht ein paar Zeilen weiter unten (B5)
# und gehoert dort hin, nicht hierher.
pruefe_struktur "3b (workerLayout=split)" \
  "?obwohl workerLayout=split gilt" \
  "?'$SESS' hat kein 'workers'-Fenster"
# Meldet wb-doctor die zurueckgebliebenen Worker, muss '--fix' sie auch bewegen.
if printf '%s\n' "$DOC" | grep -q "obwohl workerLayout=split gilt"; then
  pruefe_reparatur "3b (workerLayout=split)" "obwohl workerLayout=split gilt" \
    "wb-state settings set workerLayout split; wb-doctor --fix; wb-doctor"
fi
# Dieser '--fix'-Lauf ist der erste des Betriebslaufs — und die Gelegenheit zu
# sehen, was er mit einer Session anstellt, die gar keine Workbench-Session ist.
# Die Steuersession dieses Tests ist eine ganz gewoehnliche tmux-Session, wie
# der Nutzer sie nebenher offen hat.
if tm has-session -t '=steuer-view' 2>/dev/null \
   || tm list-windows -t '=steuer' -F '#{window_name}' 2>/dev/null | grep -qx workers; then
  bad "3: 'wb-doctor --fix' hat die fremde Session 'steuer' zu einer Workbench-Session umgebaut"
  fund "3 (erster '--fix'-Lauf)" \
       "wb-doctor fasst nur Workbench-Sessions an (die Zustandsdateien und der Name 'wb-…' sagen, welche das sind — Punkt 8 filtert bereits so)" \
       "die Punkte 4/5/7 pruefen JEDE tmux-Session; '--fix' hat der voellig unbeteiligten Session 'steuer' ein 'workers'-Fenster und die gruppierte Sicht 'steuer-view' verpasst" \
       "tmux -L <testsocket> new-session -d -s beliebig; wb-doctor --fix; tmux -L <testsocket> list-sessions"
else
  ok "3: 'wb-doctor --fix' laesst fremde tmux-Sessions in Ruhe"
fi

# Die Extension schliesst beim Wechsel auf 'split' zusaetzlich den Worker-Tab und
# seine Sicht (extension/src/extension.ts, killViewSession). Ob wb-doctor diesen
# absichtlichen Zustand mittraegt, entscheidet sich hier.
tm kill-session -t "=$SESS-view" 2>/dev/null
KL_TAB=""
sleep 0.3
doctor
if printf '%s\n' "$DOC" | grep -q "'$SESS' hat keine Sicht"; then
  bad "3: wb-doctor verlangt unter workerLayout=split eine Sicht, die die Extension gerade absichtlich geschlossen hat"
  fund "3 (Layoutwechsel window -> split)" \
       "unter workerLayout=split ist eine fehlende '-view'-Sicht der richtige Zustand — es gibt keinen Worker-Tab, an dem sie haengen koennte (so haelt es Punkt 7 bereits)" \
       "Punkt 4 meldet '$SESS hat keine Sicht' unabhaengig vom Layout und legt sie mit --fix ueber wb-workers-window neu an — samt 'workers'-Fenster, das der split-Zweig von wb-grid gerade entfernt hat" \
       "wb-state settings set workerLayout split; tmux kill-session -t '=<sess>-view'; wb-doctor"
else
  ok "3: wb-doctor traegt die geschlossene Sicht unter 'split' mit"
fi

steuer "wb-state settings set workerLayout window"
steuer "wb-state settings set minWorkerPaneWidth 80"
lauf "$ORCH" "wb-grid $ORCH"
steuer "wb-workers-window '$SESS'"
KL_TAB="$(klient_workertab "$SESS")"
warte_auf_klient "$SESS-view" 1
sleep 0.5
[ "$(panes_in_workerfenstern)" = 3 ] \
  && ok "3: zurueck auf 'window' liegen wieder alle drei in eigenen Worker-Fenstern" \
  || bad "3: nach dem Rueckwechsel $(panes_in_workerfenstern) von 3 in einem workers*-Fenster"
[ "$(klienten_an "$SESS-view")" = 1 ] && ok "3: der Worker-Tab hat beide Wechsel ueberlebt" \
                                      || bad "3: der Worker-Tab hat einen der Wechsel nicht ueberlebt"
pruefe_struktur "3c (zurueck auf workerLayout=window)"

# ── Schritt 4: Ueberlauf-Fenster ─────────────────────────────────────────────
echo
echo "-- Schritt 4: so viele Worker, dass 'workers-2' faellig wird --"
i=4
while [ "$i" -le $((MAXPT + 1)) ]; do
  worker_starten "w$i" >/dev/null
  i=$((i+1))
done
GESAMT=$((MAXPT + 1))
tm list-windows -t "=$SESS" -F '#{window_name}' | grep -qx workers-2 \
  && ok "4: bei $GESAMT Workern existiert 'workers-2'" \
  || bad "4: kein 'workers-2' bei $GESAMT Workern"
[ "$(worker_panes)" = "$GESAMT" ] \
  && ok "4: alle $GESAMT Worker stecken in einem workers*-Fenster" \
  || bad "4: nur $(worker_panes) von $GESAMT Workern in einem workers*-Fenster"
UEBERLAUF_BEFUND="ist ein Worker im Fenster 'workers-2', obwohl workerLayout=window gilt"
pruefe_struktur "4a (Ueberlauf entstanden, Tab zeigt noch 'workers')" "?$UEBERLAUF_BEFUND"
if printf '%s\n' "$DOC" | grep -q "$UEBERLAUF_BEFUND"; then
  fund "4 (Ueberlauf-Fenster 'workers-2')" \
       "wb-doctor schweigt: 'workers-2' ist das Fenster, das wb-grid fuer den zweiten Worker selbst anlegt" \
       "Punkt 6 kennt nur den Fensternamen 'workers' und meldet jeden Worker im Ueberlauf-Fenster als 'im falschen Fenster'" \
       "wb-state settings set maxWorkerPanesPerTab 1; zwei Worker spawnen + wb-grid; wb-doctor"
  pruefe_reparatur "4a (Ueberlauf-Fenster)" "$UEBERLAUF_BEFUND" \
    "wb-state settings set maxWorkerPanesPerTab 1; zwei Worker spawnen + wb-grid; wb-doctor --fix; wb-doctor"
fi

steuer "WB_WORKER_TAB_WAIT=5 wb-worker-tab '$SESS' --window workers-2 --no-attach"
[ "$(aktives_fenster "$SESS-view")" = workers-2 ] \
  && ok "4: der Worker-Tab steht auf 'workers-2'" \
  || bad "4: der Worker-Tab steht auf '$(aktives_fenster "$SESS-view")', erwartet 'workers-2'"
[ "$(klienten_an "$SESS-view")" = 1 ] && ok "4: der Tab-Client haengt weiter an der Sicht" \
                                      || bad "4: der Tab-Client ist beim Umschalten verlorengegangen"
# Hier wird sichtbar, ob wb-doctor den Ueberlauf-Tab als Strukturfehler ansieht.
DOC_ROH=""
doctor; DOC_ROH="$DOC"
if printf '%s\n' "$DOC_ROH" | grep -q "steht auf 'workers-2' statt auf 'workers'"; then
  fund "4 (Ueberlauf-Tab geoeffnet)" \
       "wb-doctor schweigt: 'workers-2' anzuzeigen ist der vorgesehene Weg (wb-worker-tab --window workers-2)" \
       "wb-doctor Punkt 4 meldet \"'$SESS-view' steht auf 'workers-2' statt auf 'workers'\" und stellt es mit --fix zurueck" \
       "wb-workers-window S; wb-worker-tab S --window workers-2 --no-attach; wb-doctor"
  bad "4: wb-doctor haelt den geoeffneten Ueberlauf-Tab fuer einen Strukturfehler (Befund notiert)"
else
  ok "4: wb-doctor akzeptiert den geoeffneten Ueberlauf-Tab"
fi
steuer "WB_WORKER_TAB_WAIT=5 wb-worker-tab '$SESS' --no-attach"
pruefe_struktur "4b (Tab zurueck auf 'workers')" "?$UEBERLAUF_BEFUND"

# ── Schritt 5: einen Worker beenden, waehrend die Sicht offen ist ────────────
echo
echo "-- Schritt 5: einen Worker beenden, waehrend der Worker-Tab offen ist --"
vorher="$(worker_panes)"
steuer "wb-close w2"
sleep 0.5
lauf "$ORCH" "wb-grid $ORCH"
nachher="$(worker_panes)"
[ "$nachher" = "$((vorher-1))" ] && ok "5: aus $vorher Workern wurden $nachher" \
                                 || bad "5: aus $vorher Workern wurden $nachher (erwartet $((vorher-1)))"
lebt "$SESS-view" && ok "5: die Sicht lebt weiter" || bad "5: die Sicht ist mitgestorben"
[ "$(klienten_an "$SESS-view")" = 1 ] && ok "5: der Worker-Tab haengt weiter" \
                                      || bad "5: der Worker-Tab hat seinen Client verloren"
pruefe_struktur "5 (ein Worker beendet)" "?$UEBERLAUF_BEFUND"

# ── Schritt 6: Session schliessen ───────────────────────────────────────────
echo
echo "-- Schritt 6: Session schliessen --"
# Erst die Gegenprobe: mit laufenden Workern und offenen Fenstern muss das
# Werkzeug verweigern.
steuer "wb-session-close '$SESS'"
[ "$RC" -ne 0 ] && ok "6: verweigert, solange Clients haengen (rc=$RC)" \
                || bad "6: hat trotz haengender Clients geschlossen"
lebt "$SESS" || bad "6: '$SESS' ist trotz Verweigerung weg"

klient_zu "$KL_TAB"; klient_zu "$KL_ORCH"
warte_auf_klient "$SESS" 0
warte_auf_klient "$SESS-view" 0
ok "6: beide Fenster geschlossen (Clients: Basis $(klienten_an "$SESS"), Sicht $(klienten_an "$SESS-view"))"

steuer "wb-session-close '$SESS'"
[ "$RC" -ne 0 ] && ok "6: verweigert weiterhin, solange Worker laufen (rc=$RC)" \
                || bad "6: hat trotz laufender Worker geschlossen"

WPANES="$(tm list-panes -a -F '#{session_name}|#{@wb_role}|#{pane_id}' \
          | awk -F'|' -v s="$SESS" '$1==s && $2=="worker"{printf "%s ", $3}')"
steuer "wb-close $WPANES"
sleep 0.5
[ "$(worker_panes)" = 0 ] && ok "6: alle Worker beendet" || bad "6: es laufen noch $(worker_panes) Worker"

steuer "wb-session-close '$SESS'"
[ "$RC" -eq 0 ] && ok "6: wb-session-close laeuft durch (rc=0)" \
                || bad "6: wb-session-close scheitert (rc=$RC): $OUT"

lebt "$SESS"      && bad "6: die Basis '$SESS' lebt noch"      || ok "6: die Basis ist weg"
if lebt "$SESS-view"; then
  bad "6: die Sicht '$SESS-view' ist stehengeblieben"
  fund "6 (Session schliessen)" \
       "wb-session-close <basis> nimmt die gruppierte '-view'-Schwester mit" \
       "'$SESS-view' lebt weiter; wb-doctor meldet sie unmittelbar danach als verwaiste Sicht" \
       "wb-workers-window S; wb-session-close S; tmux list-sessions"
  # Aufraeumen, sonst schleppt jeder folgende Schritt denselben Befund mit sich
  # herum und die spaeteren Pruefungen sagen nichts mehr ueber sich selbst aus.
  steuer "wb-session-close '$SESS-view'"
  lebt "$SESS-view" && bad "6: die stehengebliebene Sicht liess sich nicht einmal einzeln schliessen" \
                    || ok "6: die stehengebliebene Sicht wurde nachtraeglich einzeln geschlossen"
else
  ok "6: die Sicht ist mitgeschlossen"
fi
[ "$(sichten)" = 0 ] && ok "6: keine Sicht mehr uebrig" \
  || bad "6: $(sichten) Sicht(en) uebrig: $(tm list-sessions -F '#{session_name}' | grep -v '^steuer' | grep -- '-view$' | tr '\n' ' ')"
[ -z "$(streusessions)" ] && ok "6: keine Streu-Session mit '='-Gruppe" \
                          || bad "6: Streu-Session(en) uebrig: $(streusessions | tr '\n' ' ')"
uebrig="$(tm list-sessions -F '#{session_name}' | grep -c "^$SESS" | tr -d ' ')"
[ "$uebrig" = 0 ] && ok "6: kein Fenster, keine Session dieses Namens mehr" \
                  || bad "6: $uebrig Session(s) mit diesem Namen uebrig"
pruefe_struktur "6 (Session geschlossen)"

# Die Zustandsdatei ueberlebt das Schliessen — die Session soll fortsetzbar sein.
[ -f "$STATE/$SLUG.json" ] && ok "6: die Zustandsdatei bleibt (fortsetzbar)" \
                           || bad "6: die Zustandsdatei wurde beim Schliessen entfernt"
doctor
printf '%s\n' "$DOC" | grep -q "ruht *$SESS" \
  && ok "6: wb-doctor fuehrt sie als ruhende, fortsetzbare Session" \
  || bad "6: wb-doctor nennt die ruhende Zustandsdatei nicht"

# ── Schritt 7: Zustandsdatei loeschen ───────────────────────────────────────
echo
echo "-- Schritt 7: Zustandsdatei loeschen --"
[ -f "$TRANS/$CID.jsonl" ] && ok "7 davor: das Transkript liegt noch da" \
                           || bad "7 davor: das Transkript fehlt schon"
steuer "wb-session-delete --dir '$PROJEKT' --yes"
[ "$RC" -eq 0 ] && ok "7: wb-session-delete laeuft durch (rc=0)" \
                || bad "7: wb-session-delete scheitert (rc=$RC): $OUT"
[ -f "$STATE/$SLUG.json" ] && bad "7: die Zustandsdatei lebt noch" || ok "7: die Zustandsdatei ist weg"
[ -f "$TRANS/$CID.jsonl" ] && bad "7: das Transkript lebt noch" || ok "7: das Transkript ist weg"
[ -d "$PROJEKT" ] && ok "7: der Projektordner ist unberuehrt" || bad "7: der Projektordner wurde angefasst"
doctor
printf '%s\n' "$DOC" | grep -q "ruht *$SESS" \
  && bad "7: wb-doctor kennt die Fortsetzungsdaten immer noch" \
  || ok "7: keine Fortsetzungsdaten mehr"
pruefe_struktur "7 (Zustandsdatei geloescht)"

# ── Schritt 8: der Verwaisungs-Weg ──────────────────────────────────────────
echo
echo "-- Schritt 8: Verwaisungs-Marke, Karenz, und der Gegenfall --"
ORPHANS="$TESTHOME/.claude/workbench/orphans"
ORPHANLOG="$TESTHOME/.local/state/wb-session-orphan.log"
mkdir -p "$ORPHANS"
marke() { # marke <session> <token>
  printf '{"session":"%s","folder":"%s","token":"%s","at":%s}\n' \
    "$1" "$PROJEKT" "$2" "$(( $(date +%s) * 1000 ))" > "$ORPHANS/$1.json"
}

S2="wb-Betriebstest-zu-$$"
zustandsdatei "${SLUG}__aa11bb" "$S2" "55555555-5555-5555-5555-555555555555"
tm new-session -d -x 197 -y 54 -s "$S2" -n main -c "$PROJEKT"
tm set -p -t "$(tm list-panes -t "=$S2" -F '#{pane_id}' | head -1)" @wb_role orchestrator
steuer "wb-workers-window '$S2'"
lebt "$S2" && lebt "$S2-view" && ok "8 davor: '$S2' und ihre Sicht laufen" \
                              || bad "8 davor: '$S2' oder ihre Sicht fehlt"
marke "$S2" tzu
lauf "$CTRL" "wb-session-orphan --session '$S2' --token tzu --grace 3"
[ "$RC" -eq 0 ] && ok "8: der Wachposten laeuft durch (rc=0)" \
                || bad "8: der Wachposten scheitert (rc=$RC): $OUT"
lebt "$S2"      && bad "8: '$S2' laeuft nach der Karenz noch"      || ok "8: '$S2' ist geschlossen"
lebt "$S2-view" && bad "8: die Sicht '$S2-view' ist stehengeblieben" || ok "8: die Sicht ist mitgegangen"
[ -f "$ORPHANS/$S2.json" ] && bad "8: die Marke liegt noch da" || ok "8: die Marke ist abgeraeumt"
grep -q "GESCHLOSSEN session=$S2" "$ORPHANLOG" 2>/dev/null \
  && ok "8: die Entscheidung steht im Log" || bad "8: die Entscheidung fehlt im Log"
pruefe_struktur "8a (verwaiste Session geschlossen)"

echo "   Gegenfall: die Marke verschwindet vor Ablauf der Karenz (Fenster-Reload)"
S3="wb-Betriebstest-reload-$$"
zustandsdatei "${SLUG}__cc22dd" "$S3" "66666666-6666-6666-6666-666666666666"
tm new-session -d -x 197 -y 54 -s "$S3" -n main -c "$PROJEKT"
tm set -p -t "$(tm list-panes -t "=$S3" -F '#{pane_id}' | head -1)" @wb_role orchestrator
steuer "wb-workers-window '$S3'"
marke "$S3" treload
WACHE="$(tm split-window -d -t "$CTRL" -P -F '#{pane_id}' \
  "export PATH='$PANE_PATH' HOME='$TESTHOME'; wb-session-orphan --session '$S3' --token treload --grace 8 > '$TESTHOME/wache.out' 2>&1; touch '$TESTHOME/wache.done'")"
sleep 2
lebt "$S3" && ok "8: waehrend der Karenz laeuft '$S3' unveraendert" || bad "8: '$S3' wurde vor Ablauf der Karenz geschlossen"
rm -f "$ORPHANS/$S3.json"     # das zurueckgekehrte Fenster raeumt seine Marke ab
warte_auf_datei "$TESTHOME/wache.done" 30 "8: Wachposten fertig" "$TESTHOME/wache.out" \
  && ok "8: der Wachposten ist fertig"
lebt "$S3" && ok "8: ohne Marke bleibt '$S3' stehen" || bad "8: '$S3' wurde trotz entfernter Marke geschlossen"
lebt "$S3-view" && ok "8: ihre Sicht steht ebenfalls noch" || bad "8: die Sicht wurde geschlossen"
grep -q "STEHENGELASSEN session=$S3 grund=marke-weg" "$ORPHANLOG" 2>/dev/null \
  && ok "8: das Log nennt den Grund 'marke-weg'" || bad "8: 'marke-weg' fehlt im Log"
pruefe_struktur "8b (Marke vor Ablauf entfernt)" \
  "'$S3' laeuft, aber KEIN Client sieht sie"

# Aufraeumen, damit der Lauf nichts hinterlaesst, was er nicht selbst geschlossen hat.
steuer "wb-session-close '$S3'"
lebt "$S3" && bad "Abschluss: '$S3' liess sich nicht mehr schliessen" \
           || ok "Abschluss: auch die stehengebliebene Session ist geschlossen"

echo
echo "== Befunde =="
if [ "${#FUNDE[@]}" -eq 0 ]; then
  echo "  keine"
else
  for f in "${FUNDE[@]}"; do printf '%s\n\n' "$f" | sed 's/^/  /'; done
fi

echo "== Ergebnis: $pass ok, $fail FAIL, $skip SKIP, ${#FUNDE[@]} Befund(e) =="
[ "$fail" -eq 0 ]
