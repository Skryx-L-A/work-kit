#!/usr/bin/env bash
# test-wb-traeger.sh -- der Traeger des Agents-Features (Bau-Schritt 2, Auftrag traeger).
#
# Jede Zusage laeuft gegen die echten Programme shell/wb-traeger und shell/wb-aufgabe,
# meist ueber `wb-traeger takt` (genau ein Takt). Isolation:
#   * eigenes HOME (TESTHOME) mit Schirmen fuer claude, wb-budget, wb-inbox, wb-revive,
#     wb-belegung, wb-mlx-server, ssh, caffeinate, pi, wb-nohup, context-guard, wb-rolle,
#     wb-state und wb-mensch. Jeder Schirm schreibt seine Aufrufe nach $HOME/schirm.log,
#     das der Test liest, und nimmt sein Verhalten aus $HOME/steuer/.
#   * Testdaten (Vorrat, Projekte) je Abschnitt unter BASISROOT, AUSSERHALB von TESTHOME,
#     weil --mensch-beleg nur im Testbett gilt.
#   * ein eigener tmux-Server (`tmux -L wbtest-traeger-$$`, per WB_TMUX_SOCKET an Traeger
#     und wb-inbox gereicht) fuer die Pane-Lebendigkeit, TMUX/TMUX_PANE geleert. Der
#     Schirm-claude im Pane schlaeft nur; der Server wird je Abschnitt neu gestartet.
#   * die Zeit ist injiziert (WB_TRAEGER_JETZT, gilt fuer Traeger UND wb-aufgabe).
# Kein Netz, kein Modell, keine echte Claude-Sitzung, nichts im echten HOME.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKE="t$(date +%s)$$"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-traeger-test.XXXXXX")"
BASISROOT="$(mktemp -d "${TMPDIR:-/tmp}/wb-traeger-basen.XXXXXX")"
# wb-aufgabe legt Projektpfade mit os.path.abspath ab; ein "//" aus $TMPDIR ergaebe sonst
# zwei Schreibweisen desselben Pfads und jeder Vergleich im Protokoll schluege fehl.
TESTHOME="$(python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$TESTHOME")"
BASISROOT="$(python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$BASISROOT")"
PYBIN_DIR="$(dirname "$(command -v python3)")"
SOCK="wbtest-traeger-$$"
LOG="$TESTHOME/schirm.log"
STEUER="$TESTHOME/steuer"
unset TMUX TMUX_PANE

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null
  rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"
  pkill -f "$BASISROOT" 2>/dev/null
  pkill -f "$TESTHOME" 2>/dev/null
  for d in "$TESTHOME" "$BASISROOT"; do
    case "$d" in
      /tmp/wb-traeger-*|/private/tmp/wb-traeger-*|/var/folders/*/wb-traeger-*) rm -rf "$d" ;;
      *) echo "WARNUNG: '$d' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
    esac
  done
}
trap cleanup EXIT INT TERM

echo "== wb-traeger (HOME $TESTHOME, tmux -L $SOCK, Marke $MARKE) =="
[ -x "$REPO/wb-traeger" ] || { echo "UEBERSPRUNGEN: shell/wb-traeger fehlt"; exit 77; }
command -v tmux >/dev/null || { echo "UEBERSPRUNGEN: tmux fehlt"; exit 77; }
command -v git >/dev/null || { echo "UEBERSPRUNGEN: git fehlt"; exit 77; }

mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/tbin" "$STEUER"
ln -s "$(command -v tmux)" "$TESTHOME/tbin/tmux"
ln -s "$(command -v git)" "$TESTHOME/tbin/git"
printf '[user]\n\tname = Test\n\temail = test@example.invalid\n[commit]\n\tgpgsign = false\n' > "$TESTHOME/.gitconfig"
PFAD="$TESTHOME/.local/bin:$TESTHOME/tbin:$PYBIN_DIR:/usr/bin:/bin"

# --- Schirme --------------------------------------------------------------
schirm() {
  { printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$HOME/schirm.log"\n' "$1"; cat; } > "$TESTHOME/.local/bin/$1"
  chmod +x "$TESTHOME/.local/bin/$1"
}
schirm claude <<'EOF'
S="$HOME/steuer"
if [ "${1:-}" = "-p" ]; then
  if [ -s "$S/claude.folge" ]; then
    r="$(head -1 "$S/claude.folge")"; tail -n +2 "$S/claude.folge" > "$S/claude.folge.n"; mv "$S/claude.folge.n" "$S/claude.folge"
    exit "$r"
  fi
  [ -f "$S/claude.rc" ] && exit "$(cat "$S/claude.rc")"
  exit 0
fi
printf 'claude-start env WB_AUFGABE_ID=%s WB_AUFGABE_PROJEKT=%s tty=%s\n' "${WB_AUFGABE_ID:-}" \
  "${WB_AUFGABE_PROJEKT:-}" "$( [ -t 0 ] && echo ja || echo nein)" >> "$HOME/schirm.log"
exec sleep 600
EOF
schirm wb-budget <<'EOF'
S="$HOME/steuer"
if [ -f "$S/budget.json" ]; then cat "$S/budget.json"; else
  printf '{"ts":"2026-09-10T18:00:00Z","alter_s":60,"five_hour_pct":20,"five_hour_resets_at":"2099-01-01T12:00:00Z","five_hour_resets_at_epoch":4070952000,"seven_day_pct":10,"erlaubt_pct":80,"tageslimit_erreicht":false,"fuenf_stunden_erreicht":false}\n'
fi
[ -f "$S/budget.rc" ] && exit "$(cat "$S/budget.rc")"
exit 0
EOF
schirm wb-inbox <<'EOF'
if [ "${1:-}" = "transcript" ]; then [ -f "$HOME/steuer/transcript" ] || exit 1; cat "$HOME/steuer/transcript"; exit 0; fi
if [ "${1:-}" = "--absender" ] && [ "${2:-}" = "traeger" ] && [ "${3:-}" = "sende" ]; then
  printf 'inbox-text %s sock=%s | %s | absender=%s vorrat=%s\n' "$4" "${WB_TMUX_SOCKET:-}" \
    "$(tr '\n' ' ' < "$5")" "$1-$2" "${WB_VORRAT:-}" >> "$HOME/schirm.log"
fi
[ -f "$HOME/steuer/inbox.rc" ] && exit "$(cat "$HOME/steuer/inbox.rc")"
exit 0
EOF
schirm wb-companion <<'EOF'
printf 'companion-call %s\n' "$*" >> "$HOME/schirm.log"
[ -f "$HOME/steuer/companion.rc" ] && exit "$(cat "$HOME/steuer/companion.rc")"
exit 0
EOF
schirm wb-revive <<'EOF'
if [ -f "$HOME/steuer/revive.echt" ]; then tmux -L "$WB_TMUX_SOCKET" respawn-pane -k -t "$1" "sleep 600"; exit $?; fi
[ -f "$HOME/steuer/revive.rc" ] && exit "$(cat "$HOME/steuer/revive.rc")"
exit 1
EOF
schirm wb-belegung <<'EOF'
if [ "${1:-}" = "nimm" ]; then
  if [ -f "$HOME/steuer/belegung.rc" ]; then printf '{"ja": false, "grund": "Schirm"}\n'; exit "$(cat "$HOME/steuer/belegung.rc")"; fi
  n=$(( $(cat "$HOME/steuer/belegung.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$HOME/steuer/belegung.n"
  printf '{"ja": true, "kennung": "k-%s"}\n' "$n"
fi
exit 0
EOF
schirm scp <<'EOF'
[ -f "$HOME/steuer/scp.rc" ] && exit "$(cat "$HOME/steuer/scp.rc")"
exit 0
EOF
schirm wb-mlx-server <<'EOF'
[ -f "$HOME/steuer/mlx.rc" ] && exit "$(cat "$HOME/steuer/mlx.rc")"
exit 0
EOF
# Kit: the Traeger checks the local engine with 'kit-llm status' (15-local-llm).
schirm kit-llm <<'EOF'
[ -f "$HOME/steuer/mlx.rc" ] && exit "$(cat "$HOME/steuer/mlx.rc")"
exit 0
EOF
schirm ssh <<'EOF'
case "$*" in *"status --json"*) cat "$HOME/steuer/ssh-status.json" 2>/dev/null || printf '{"laeuft": false}\n' ;; esac
case "$*" in *aufnehmen*) [ -f "$HOME/steuer/ssh-aufnehmen.rc" ] && exit "$(cat "$HOME/steuer/ssh-aufnehmen.rc")" ;; esac
[ -f "$HOME/steuer/ssh.rc" ] && exit "$(cat "$HOME/steuer/ssh.rc")"
exit 0
EOF
schirm caffeinate <<'EOF'
echo $$ > "$HOME/steuer/caffeinate.pid"
w=""; while [ $# -gt 0 ]; do [ "$1" = "-w" ] && w="$2"; shift; done
while [ -n "$w" ] && kill -0 "$w" 2>/dev/null; do sleep 0.2; done
EOF
schirm pi <<'EOF'
printf 'pi-start pid=%s env WB_AUFGABE_ID=%s\n' "$$" "${WB_AUFGABE_ID:-}" >> "$HOME/schirm.log"
d=""; vor=""; for x in "$@"; do [ "$vor" = "--session-dir" ] && d="$x"; vor="$x"; done
[ -n "$d" ] && mkdir -p "$d" && echo '{}' >> "$d/sitzung.jsonl"
[ -f "$HOME/steuer/pi.schlaf" ] && sleep "$(cat "$HOME/steuer/pi.schlaf")"
exit 0
EOF
schirm wb-nohup <<'EOF'
exit 1
EOF
schirm context-guard <<'EOF'
exit 0
EOF
schirm wb-rolle <<'EOF'
exit 0
EOF
schirm wb-state <<'EOF'
case "${1:-} ${2:-}" in "settings valid") exit 0 ;; "settings get") exit 1 ;; esac
exit 0
EOF
schirm wb-mensch <<'EOF'
[ "${1:-}" = "pruefen" ] && exit 1
printf 'agent\tSchirm\n'
EOF
# wb-vertrauen: Meldungen im Wortlaut des echten Werkzeugs (immer Exit 0), Vorgabe "schon vertraut".
schirm wb-vertrauen <<'EOF'
case "$(cat "$HOME/steuer/vertrauen" 2>/dev/null || echo vertraut)" in
  vertraut) echo "wb-vertrauen: schon vertraut: $1" >&2 ;;
  eintragbar)
    if [ "${2:-}" = "--pruefen" ]; then echo "wb-vertrauen: wuerde eintragen: $1 (Vertrauen uebertragen von /schirm)" >&2
    else echo "wb-vertrauen: eingetragen: $1 (Vertrauen uebertragen von /schirm)" >&2; fi ;;
  *) echo "wb-vertrauen: kein vertrauter Buerge fuer $1 (weder der Hauptbaum eines Worktrees noch ein Elternordner unter \$HOME) — nicht eingetragen, der Dialog bleibt." >&2 ;;
esac
exit 0
EOF
BELEG="$TESTHOME/beleg.txt"
printf 'mensch\tTest %s\n' "$MARKE" > "$BELEG"

# --- Hilfen ---------------------------------------------------------------
JETZT=""
lauf() {
  local prog="$1" b="$2"; shift 2
  env HOME="$TESTHOME" PATH="$PFAD" WB_TMUX_SOCKET="$SOCK" WB_TRAEGER_MASCHINE=mac \
      WB_TRAEGER_WIEDERHOLUNG_S=0 WB_TRAEGER_NACHSEHEN=0 WB_TRAEGER_SCP="$TESTHOME/.local/bin/scp" \
      ${JETZT:+WB_TRAEGER_JETZT="$JETZT"} \
      python3 "$REPO/$prog" "$@" --base "$b" --vorrat "$b/.claude/workbench/vorrat"
}
wa() { lauf wb-aufgabe "$@"; }
wt() { lauf wb-traeger "$@"; }
takt() { wt "$1" takt >> "$1/takt.log" 2>&1; }

basis_neu() {
  local b; b="$(mktemp -d "$BASISROOT/b.XXXXXX")"
  mkdir -p "$b/.claude/workbench/vorrat"
  # Kit: the second machine is an explicit setting now (default: this machine only).
  printf '{"agents": {"nachtfenster": "00:00-00:00", "taktSekunden": 1, "maschinen": [{"name": "mac"}, {"name": "host2", "ssh": "host2", "standard": true}]}}\n' > "$b/.claude/workbench/settings.json"
  printf '%s' "$b"
}
einstellen() {
  python3 - "$1/.claude/workbench/settings.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["agents"].update(json.loads(sys.argv[2]))
json.dump(d, open(sys.argv[1], "w"))
PY
}
neu() {
  local b="$1" p="$2" id; shift 2
  mkdir -p "$p"
  id="$(wa "$b" anlegen "$p" --ziel "Ziel $MARKE" --fertig gruen --maschine mac "$@" 2>/dev/null | tail -1)"
  wa "$b" freigeben "$id" --mensch-beleg "$BELEG" >/dev/null 2>&1
  printf '%s' "$id"
}
vd() { printf '%s/.companion/auftraege/%s.verlauf.json' "$1" "$2"; }
vj() {
  python3 - "$1" "$2" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"v": v, "E": v.get("verlauf") or []}))
PY
}
stand() { vj "$(vd "$1" "$2")" 'v["stand"]'; }
feld() { vj "$(vd "$1" "$2")" "v.get('$3')"; }
arten() { vj "$(vd "$1" "$2")" "sum(1 for e in E if e['art']=='$3')"; }
letzter_grund() { vj "$(vd "$1" "$2")" 'next((e["text"] for e in reversed(E) if e["art"]=="nicht-gestartet"), "")'; }
letzter_companion_text() { vj "$(vd "$1" "$2")" 'next((e["text"] for e in reversed(E) if e["art"] in ("companion", "companion-fehlgeschlagen")), "")'; }
zaehle() { local n; n="$(grep -c -- "$1" "$LOG" 2>/dev/null)"; printf '%s' "${n:-0}"; }
pane_von() { vj "$(vd "$1" "$2")" '(v.get("hauptagent_sitzung") or {}).get("pane", "")'; }
pane_lebt() { tmux -L "$SOCK" list-panes -a -F '#{pane_id} #{pane_dead}' 2>/dev/null | grep -qx "$1 0"; }
pane_pid() { tmux -L "$SOCK" list-panes -a -F '#{pane_id} #{pane_pid}' 2>/dev/null | awk -v p="$1" '$1==p{print $2}'; }
wecker() { printf '%s %s\n' "$3" "$4" > "$1/.claude/workbench/vorrat/.wecker/$2"; }
ortszeit() {
  python3 - "$1" "$2" "$3" <<'PY'
import datetime, sys
t, h, m = map(int, sys.argv[1:4])
d = datetime.date.today() + datetime.timedelta(days=t)
z = datetime.datetime(d.year, d.month, d.day, h, m).astimezone()
print(z.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}
plus() { python3 -c 'import datetime,sys; d=datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00"))+datetime.timedelta(seconds=int(sys.argv[2])); print(d.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1" "$2"; }
warte_auf() { local i=0; while [ $i -lt 50 ]; do eval "$1" && return 0; sleep 0.2; i=$((i+1)); done; return 1; }
abschnitt() { tmux -L "$SOCK" kill-server 2>/dev/null; : > "$LOG"; rm -f "$STEUER"/*; JETZT=""; echo; echo "-- $1 --"; }
budget() { printf '%s\n' "$1" > "$STEUER/budget.rc"; [ -n "${2:-}" ] && printf '%s\n' "$2" > "$STEUER/budget.json"; return 0; }
companion_rc() { printf '%s\n' "$1" > "$STEUER/companion.rc"; return 0; }
modell_setzen() {
  python3 - "$1/.companion/auftraege/$2.json" "$3" <<'PY'
import json, sys
p, wert = sys.argv[1], sys.argv[2]
a = json.load(open(p)); a["hauptagent"]["model"] = a["model"] = wert
a["approval"] = None  # wie `freigeben --neu-freigeben`; danach gilt nur eine neue Freigabe
json.dump(a, open(p, "w"))
PY
  wa "$(dirname "$1")" freigeben "$2" --mensch-beleg "$BELEG" >/dev/null 2>&1
}
auftrag_modell() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hauptagent"]["model"])' "$1/.companion/auftraege/$2.json"; }
ergebnispfad_setzen() {
  python3 - "$(vd "$1" "$2")" "$3" <<'PY'
import json, sys
pfad, wert = sys.argv[1], sys.argv[2]
v = json.load(open(pfad))
v["ergebnis"]["pfad"] = wert
json.dump(v, open(pfad, "w"))
PY
}

# ==========================================================================
abschnitt "A: takt startet die vorderste startbare Aufgabe, keine zweite im selben Repo"
B="$(basis_neu)"; P="$B/proj-a"
A1="$(neu "$B" "$P")"; A2="$(neu "$B" "$P")"
takt "$B"
[ "$(stand "$P" "$A1")" = "läuft" ] && ok "A: vorderste Aufgabe steht auf 'läuft'" || bad "A: Stand A1" "$(stand "$P" "$A1") / $(tail -3 "$B/takt.log")"
PA="$(pane_von "$P" "$A1")"
pane_lebt "$PA" && ok "A: der Pane $PA des Hauptagenten lebt auf dem Testserver" || bad "A: Pane lebt nicht" "'$PA'"
[ "$(vj "$(vd "$P" "$A1")" 'v["hauptagent_sitzung"]["tmux_session"]')" = "$(vj "$(vd "$P" "$A1")" 'v["hauptagent_sitzung"]["tmux_session"]' | grep -x "wb-proj-a-[0-9a-f]\{6\}-$A1")" ] \
  && [ -n "$(vj "$(vd "$P" "$A1")" 'v["hauptagent_sitzung"]["tmux_session"]' | grep -x "wb-proj-a-[0-9a-f]\{6\}-$A1")" ] \
  && ok "A: Sitzungsname nach wb-code-Muster wb-<projekt>-<hash>-<id>" || bad "A: Sitzungsname" "$(vj "$(vd "$P" "$A1")" 'v["hauptagent_sitzung"]')"
grep -q -- "--model claude-opus-5-5 --effort xhigh -n $A1 --remote-control $A1 --append-system-prompt" "$LOG" \
  && ok "A: claude-Zeile wie wb-code: Modell, Denkstufe, Name, Fernsteuerung, Rollenprompt" || bad "A: claude-Zeile" "$(grep '^claude ' "$LOG" | grep -v -- ' -p ')"
grep -q "Du bist der Hauptagent der Werkbank-Aufgabe $A1" "$LOG" && ok "A: erster Prompt als Startargument, nicht getippt" || bad "A: erster Prompt fehlt"
grep -q "claude-start env WB_AUFGABE_ID=$A1 WB_AUFGABE_PROJEKT=$P tty=ja" "$LOG" \
  && ok "A: WB_AUFGABE_ID/PROJEKT kommen in der Sitzung an, der Pane hat ein Terminal" || bad "A: Umgebung im Pane" "$(grep claude-start "$LOG")"
grep -q "^wb-state touch $P wb-proj-a-.*-$A1 --key $A1" "$LOG" && ok "A: Sitzungs-Statusfile über wb-state touch --key" || bad "A: wb-state touch" "$(grep wb-state "$LOG" | tail -3)"
grep -q "^context-guard --auto $PA --exit-when-session-gone" "$LOG" && ok "A: Kontext-Guard je Hauptagent" || bad "A: context-guard" "$(grep context-guard "$LOG")"
[ "$(arten "$P" "$A1" fernsteuerung)" = 0 ] && ok "A: kein Eintrag 'Fernsteuerung fehlt' (Pane hat ein pty)" || bad "A: Fernsteuerung fehlt eingetragen"
takt "$B"
[ "$(stand "$P" "$A2")" = "offen" ] && ok "A: zweite Aufgabe im selben Repo bleibt offen" || bad "A: Stand A2" "$(stand "$P" "$A2")"
[ "$(letzter_grund "$P" "$A2")" = "Repo belegt durch Aufgabe $A1" ] && ok "A: Nichtstart-Grund wörtlich 'Repo belegt durch Aufgabe $A1'" \
  || bad "A: Nichtstart-Grund A2" "'$(letzter_grund "$P" "$A2")'"
takt "$B"
[ "$(zaehle '^claude-start')" = 1 ] && ok "A: zweiter Takt startet nichts doppelt" || bad "A: Starts nach zwei Takten" "$(zaehle '^claude-start')"
[ "$(arten "$P" "$A2" nicht-gestartet)" = 1 ] && ok "A: der Nichtstart-Grund steht einmal, nicht je Takt" || bad "A: Nichtstart-Einträge" "$(arten "$P" "$A2" nicht-gestartet)"
[ "$(vj "$(vd "$P" "$A1")" 'v["hauptagent_sitzung"].get("zuletzt_gesehen") is not None')" = True ] \
  && ok "A: Lebendigkeit stempelt zuletzt_gesehen" || bad "A: zuletzt_gesehen fehlt"

# ==========================================================================
abschnitt "B: Fünf-Stunden-Fenster (wb-budget Exit 2)"
B="$(basis_neu)"
L="$(neu "$B" "$B/p1")"; takt "$B"
O="$(neu "$B" "$B/p2")"
budget 2 '{"ts":"2026-09-10T18:00:00Z","alter_s":60,"five_hour_pct":100,"five_hour_resets_at":"2099-01-01T12:00:00Z","five_hour_resets_at_epoch":4070952000,"seven_day_pct":50,"erlaubt_pct":0,"tageslimit_erreicht":false,"fuenf_stunden_erreicht":true}'
wecker "$B" "$L" 2026-09-10T18:00:00Z limit
takt "$B"
[ "$(stand "$B/p1" "$L")" = "pausiert (Kontingent)" ] && ok "B: laufende Aufgabe mit limit-Wecker -> 'pausiert (Kontingent)'" || bad "B: Stand L" "$(stand "$B/p1" "$L")"
[ "$(feld "$B/p1" "$L" weckzeit)" = "2099-01-01T12:00:00Z" ] && ok "B: Weckzeit = five_hour_resets_at aus dem JSON" || bad "B: Weckzeit" "$(feld "$B/p1" "$L" weckzeit)"
[ "$(arten "$B/p1" "$L" limit)" = 1 ] && ok "B: Verlaufseintrag 'limit'" || bad "B: limit-Eintrag fehlt"
[ ! -e "$B/.claude/workbench/vorrat/.wecker/$L" ] && ok "B: Wecker-Datei gelesen und gelöscht" || bad "B: Wecker-Datei blieb liegen"
[ "$(stand "$B/p2" "$O")" = "offen" ] && [ "$(letzter_grund "$B/p2" "$O")" = "Kontingent" ] \
  && ok "B: keine Cloud-Starts, offene Aufgabe trägt 'Kontingent'" || bad "B: offene Aufgabe" "$(stand "$B/p2" "$O") / $(letzter_grund "$B/p2" "$O")"
[ "$(zaehle '^claude-start')" = 1 ] && ok "B: kein weiterer Hauptagent gestartet" || bad "B: Starts" "$(zaehle '^claude-start')"

# ==========================================================================
abschnitt "C: keine Kontingent-Quelle (Exit 3) -> steckt (Umgebung)"
B="$(basis_neu)"
L="$(neu "$B" "$B/p1")"; takt "$B"
O="$(neu "$B" "$B/p2")"
budget 3
wecker "$B" "$L" 2026-09-10T18:00:00Z limit
takt "$B"
[ "$(vj "$(vd "$B/p1" "$L")" '(v["stand"], v["grund"], v["steckt_vorher"], v["weckzeit"])')" = "('steckt', 'Umgebung', 'läuft', None)" ] \
  && ok "C: limit ohne lesbare Reset-Zeit: steckt (Umgebung), keine erfundene Weckzeit" || bad "C: L" "$(vj "$(vd "$B/p1" "$L")" '(v["stand"], v["grund"], v["steckt_vorher"], v["weckzeit"])')"
[ "$(vj "$(vd "$B/p2" "$O")" '(v["stand"], v["grund"], v["steckt_vorher"])')" = "('steckt', 'Umgebung', 'offen')" ] \
  && ok "C: Startkandidatin bei Exit 3: steckt (Umgebung)" || bad "C: O" "$(vj "$(vd "$B/p2" "$O")" '(v["stand"], v["grund"], v["steckt_vorher"])')"

# ==========================================================================
abschnitt "D: veralteter Messwert startet genau eine Cloud-Aufgabe"
B="$(basis_neu)"
budget 0 '{"ts":"2026-09-10T02:00:00Z","alter_s":50000,"five_hour_pct":20,"five_hour_resets_at":"2099-01-01T12:00:00Z","five_hour_resets_at_epoch":4070952000,"seven_day_pct":10,"erlaubt_pct":80,"tageslimit_erreicht":false,"fuenf_stunden_erreicht":false}'
D1="$(neu "$B" "$B/p1")"; D2="$(neu "$B" "$B/p2")"; D3="$(neu "$B" "$B/p3")"
takt "$B"; takt "$B"
[ "$(stand "$B/p1" "$D1")" = "läuft" ] && [ "$(zaehle '^claude-start')" = 1 ] \
  && ok "D: vorderste startet, zweiter Takt startet keine weitere" || bad "D: Starts" "$(zaehle '^claude-start') / $(stand "$B/p1" "$D1")"
[ "$(letzter_grund "$B/p2" "$D2")|$(letzter_grund "$B/p3" "$D3")" = "Kontingent-Messwert veraltet|Kontingent-Messwert veraltet" ] \
  && ok "D: die übrigen tragen 'Kontingent-Messwert veraltet'" || bad "D: Gründe" "$(letzter_grund "$B/p2" "$D2") | $(letzter_grund "$B/p3" "$D3")"
wecker "$B" "$D1" 2026-09-10T18:00:00Z zugende
takt "$B"
[ "$(zaehle '^claude-start')" = 2 ] && [ "$(stand "$B/p2" "$D2")" = "läuft" ] && [ "$(stand "$B/p3" "$D3")" = "offen" ] \
  && ok "D: nach dem ersten Zug liest er neu und startet wieder genau eine" || bad "D: nach Zugende" "$(zaehle '^claude-start') $(stand "$B/p2" "$D2") $(stand "$B/p3" "$D3")"

abschnitt "E: Tageslimit (Exit 1): Starts laufen weiter, Verlauf trägt 'Tageslimit'"
B="$(basis_neu)"; budget 1
T="$(neu "$B" "$B/p1")"; takt "$B"
[ "$(stand "$B/p1" "$T")" = "läuft" ] && [ "$(vj "$(vd "$B/p1" "$T")" 'next((e["text"] for e in E if e["art"]=="tageslimit"), "")')" = "Tageslimit" ] \
  && ok "E: gestartet, Verlaufseintrag 'Tageslimit'" || bad "E: Tageslimit" "$(stand "$B/p1" "$T")"

# ==========================================================================
abschnitt "F: Sicherung -- nur ohne arbeitenden Worker, mit Kennung, Mindestabstand, Weckzeit"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"
B="$(basis_neu)"; P="$B/p1"
S="$(neu "$B" "$P")"; takt "$B"; PS="$(pane_von "$P" "$S")"
wecker "$B" "$S" "$T0" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && grep -q "inbox-text $PS sock=$SOCK | Sicherung: du hast nichts entschieden" "$LOG" \
  && ok "F: zugende ohne Entscheidung -> Sicherung über wb-inbox an den Pane" || bad "F: Sicherung" "$(grep inbox "$LOG")"
[ "$(vj "$(vd "$P" "$S")" "sum(1 for e in E if e.get('kennung')=='sicherung-$S-$T0')")" = 1 ] \
  && ok "F: Zustellung mit Vorgangs-Kennung quittiert" || bad "F: Kennung fehlt"
wecker "$B" "$S" "$T0" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && [ "$(arten "$P" "$S" zustellung)" = 1 ] \
  && ok "F: zweiter Wecker mit derselben Kennung ist No-op" || bad "F: Doppelte Kennung" "$(zaehle '^inbox-text') / $(arten "$P" "$S" zustellung)"
JETZT="$(plus "$T0" 60)"; wecker "$B" "$S" "$JETZT" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && ok "F: Mindestabstand (900 s) hält den zweiten automatischen Wecker zurück" || bad "F: Mindestabstand" "$(zaehle '^inbox-text')"
JETZT="$(plus "$T0" 1000)"
wa "$B" worker "$S" setzen w1 --rolle tester --zustand arbeitet >/dev/null 2>&1
wecker "$B" "$S" "$JETZT" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && ok "F: Sicherung entfällt, solange ein Worker arbeitet" || bad "F: Worker arbeitet" "$(zaehle '^inbox-text')"
wa "$B" worker "$S" entfernen w1 >/dev/null 2>&1
JETZT="$(plus "$T0" 1100)"; wecker "$B" "$S" "$JETZT" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 2 ] && ok "F: nach dem Abstand und ohne Worker greift sie wieder" || bad "F: zweite Sicherung" "$(zaehle '^inbox-text')"
WZ="$(plus "$T0" 1150)"; JETZT="$WZ"; wa "$B" weckzeit "$S" "$WZ" >/dev/null 2>&1
JETZT="$(plus "$T0" 1200)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 3 ] && [ "$(vj "$(vd "$P" "$S")" "sum(1 for e in E if e.get('kennung')=='weckzeit-$S-$WZ')")" = 1 ] \
  && [ "$(feld "$P" "$S" weckzeit)" = None ] && ok "F: verstrichene Weckzeit weckt trotz Mindestabstand und wird geleert" \
  || bad "F: Weckzeit" "$(zaehle '^inbox-text') / $(feld "$P" "$S" weckzeit)"
JETZT="$(plus "$T0" 2100)"
wa "$B" wiederaufnahme "$S" "warte auf den Messlauf" >/dev/null 2>&1; wa "$B" weckzeit "$S" 2099-01-01T12:00:00Z >/dev/null 2>&1
wecker "$B" "$S" "$JETZT" zugende; takt "$B"
[ "$(zaehle '^inbox-text')" = 3 ] && ok "F: hinterlassene Weckzeit mit Wiederaufnahme ist eine Entscheidung, keine Sicherung" || bad "F: entschieden" "$(zaehle '^inbox-text')"

# ==========================================================================
abschnitt "G: tote Sitzung -- zweimal Wiederbelebung, dann steckt (Hauptagent weg)"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"
B="$(basis_neu)"; P="$B/p1"
G1="$(neu "$B" "$P")"; takt "$B"; PG="$(pane_von "$P" "$G1")"
kill "$(pane_pid "$PG")"; warte_auf '! pane_lebt "$PG"'
JETZT="$(plus "$T0" 10)"; takt "$B"; R1="$(zaehle '^wb-revive')"
JETZT="$(plus "$T0" 100)"; takt "$B"; R2="$(zaehle '^wb-revive')"
JETZT="$(plus "$T0" 320)"; takt "$B"; R3="$(zaehle '^wb-revive')"
JETZT="$(plus "$T0" 640)"; takt "$B"; R4="$(zaehle '^wb-revive')"
[ "$R1 $R2 $R3 $R4" = "1 1 2 2" ] && ok "G: wb-revive zweimal, mit Abstand (300 s)" || bad "G: Wiederbelebungen" "$R1 $R2 $R3 $R4"
grep -q "^wb-revive $PG$" "$LOG" && ok "G: wb-revive bekommt den Pane der Aufgabe" || bad "G: wb-revive Argument" "$(grep wb-revive "$LOG")"
[ "$(vj "$(vd "$P" "$G1")" '(v["stand"], v["grund"])')" = "('steckt', 'Hauptagent weg')" ] \
  && ok "G: danach steckt (Hauptagent weg)" || bad "G: Stand" "$(vj "$(vd "$P" "$G1")" '(v["stand"], v["grund"])')"
abschnitt "G2: gelungene Wiederbelebung stellt die Sicherung über die Inbox zu"
JETZT="$T0"; B="$(basis_neu)"; P="$B/p1"
G2="$(neu "$B" "$P")"; takt "$B"; PG="$(pane_von "$P" "$G2")"
kill "$(pane_pid "$PG")"; warte_auf '! pane_lebt "$PG"'
touch "$STEUER/revive.echt"; JETZT="$(plus "$T0" 10)"; takt "$B"
pane_lebt "$PG" && [ "$(stand "$P" "$G2")" = "läuft" ] && [ "$(arten "$P" "$G2" geweckt)" = 1 ] \
  && ok "G2: Pane lebt wieder, Stand läuft, Verlauf 'geweckt'" || bad "G2: Wiederbelebung" "$(stand "$P" "$G2")"
grep -q "inbox-text $PG .*Sicherung: du hast nichts entschieden" "$LOG" && ok "G2: Sicherungsnachricht nach der Wiederbelebung" || bad "G2: Sicherung" "$(grep inbox "$LOG")"

# ==========================================================================
abschnitt "H: Nachtfenster"
B="$(basis_neu)"; einstellen "$B" '{"nachtfenster": "23:00-07:00"}'
TAG="$(ortszeit 0 12 0)"; NACHT="$(ortszeit 0 23 30)"; MORGEN="$(ortszeit 1 7 30)"; ENDE="$(ortszeit 1 7 0)"
JETZT="$TAG"
N1="$(neu "$B" "$B/p1" --nachtmodus pausieren)"; takt "$B"
N2="$(neu "$B" "$B/p2" --nachtmodus pausieren)"; N3="$(neu "$B" "$B/p3" --nachtmodus weiter-lokal)"
JETZT="$NACHT"; takt "$B"
[ "$(stand "$B/p1" "$N1")|$(feld "$B/p1" "$N1" weckzeit)" = "pausiert (Nacht)|$ENDE" ] \
  && ok "H: laufende 'pausieren'-Aufgabe -> pausiert (Nacht), Weckzeit = Ende des Fensters" || bad "H: N1" "$(stand "$B/p1" "$N1") / $(feld "$B/p1" "$N1" weckzeit) (erwartet $ENDE)"
[ "$(grep -c 'inbox-text .*Nachtpause' "$LOG")" = 1 ] && ok "H: Nachtpause an den Hauptagenten zugestellt" || bad "H: Nachtpause" "$(grep inbox "$LOG")"
[ "$(stand "$B/p2" "$N2")|$(letzter_grund "$B/p2" "$N2")" = "offen|Nacht" ] && ok "H: offene 'pausieren'-Aufgabe startet nachts nicht (Grund 'Nacht')" \
  || bad "H: N2" "$(stand "$B/p2" "$N2") / $(letzter_grund "$B/p2" "$N2")"
[ "$(stand "$B/p3" "$N3")" = "läuft" ] && ok "H: offene 'weiter-lokal'-Aufgabe startet im Fenster" || bad "H: N3" "$(stand "$B/p3" "$N3")"
JETZT="$(plus "$NACHT" 60)"; takt "$B"
[ "$(grep -c 'inbox-text .*Nachtpause' "$LOG")" = 1 ] && [ "$(arten "$B/p2" "$N2" nicht-gestartet)" = 1 ] \
  && ok "H: im Fenster nichts doppelt (Nachtpause einmal, Grund einmal)" || bad "H: Doppelungen"
JETZT="$MORGEN"; takt "$B"
[ "$(stand "$B/p1" "$N1")|$(feld "$B/p1" "$N1" weckzeit)|$(arten "$B/p1" "$N1" geweckt)" = "läuft|None|1" ] \
  && grep -q "inbox-text .*Weckzeit erreicht" "$LOG" && ok "H: am Morgen geweckt: Inbox-Nachricht, Stand läuft, Weckzeit leer" \
  || bad "H: Wecken am Morgen" "$(stand "$B/p1" "$N1") / $(feld "$B/p1" "$N1" weckzeit)"
abschnitt "H2: Reset-Zeit im Nachtfenster weckt eine 'pausieren'-Aufgabe erst am Morgen"
B="$(basis_neu)"; einstellen "$B" '{"nachtfenster": "23:00-07:00"}'
JETZT="$(ortszeit 0 12 0)"
R="$(neu "$B" "$B/p1" --nachtmodus pausieren)"; takt "$B"
budget 2 "{\"ts\":\"$JETZT\",\"alter_s\":60,\"five_hour_pct\":100,\"five_hour_resets_at\":\"$(ortszeit 0 23 45)\",\"five_hour_resets_at_epoch\":0,\"seven_day_pct\":50,\"erlaubt_pct\":0,\"tageslimit_erreicht\":false,\"fuenf_stunden_erreicht\":true}"
wecker "$B" "$R" "$JETZT" limit; takt "$B"
[ "$(stand "$B/p1" "$R")|$(feld "$B/p1" "$R" weckzeit)" = "pausiert (Kontingent)|$(ortszeit 1 7 0)" ] \
  && ok "H2: Weckzeit auf das Fensterende verschoben" || bad "H2: Weckzeit" "$(stand "$B/p1" "$R") / $(feld "$B/p1" "$R" weckzeit)"

# ==========================================================================
abschnitt "I: Lebenszeichen -- Fehlschlag setzt steckt (Umgebung), Rückkehr stellt den Stand her"
# Der Merker liegt in der Zustandsdatei: nach einer gelungenen Probe ist die
# nächste erst eine Stunde später fällig, nach einem Fehlschlag in jedem Takt.
T0="2026-09-10T12:00:00Z"; JETZT="$T0"
B="$(basis_neu)"
L="$(neu "$B" "$B/p1")"; takt "$B"
echo 1 > "$STEUER/claude.rc"; JETZT="$(plus "$T0" 1800)"; takt "$B"
[ "$(stand "$B/p1" "$L")" = "läuft" ] && ok "I: innerhalb der Stunde nach einer gelungenen Probe keine neue" || bad "I: Probe zu früh" "$(stand "$B/p1" "$L")"
JETZT="$(plus "$T0" 3700)"; takt "$B"
[ "$(vj "$(vd "$B/p1" "$L")" '(v["stand"], v["grund"], v["steckt_vorher"])')" = "('steckt', 'Umgebung', 'läuft')" ] \
  && ok "I: claude -p scheitert -> steckt (Umgebung), steckt_vorher = läuft" || bad "I: steckt" "$(vj "$(vd "$B/p1" "$L")" '(v["stand"], v["grund"], v["steckt_vorher"])')"
JETZT="$(plus "$T0" 3710)"; O="$(neu "$B" "$B/p2")"; takt "$B"
[ "$(stand "$B/p2" "$O")" = "steckt" ] && [ "$(zaehle '^claude-start')" = 1 ] && ok "I: in eine ungeprüfte Umgebung startet nichts" || bad "I: Start trotz Fehlschlag" "$(stand "$B/p2" "$O")"
rm -f "$STEUER/claude.rc"; JETZT="$(plus "$T0" 3720)"; takt "$B"
[ "$(stand "$B/p1" "$L")" = "läuft" ] && ok "I: Probe gelingt -> zurück auf 'läuft'" || bad "I: Rückkehr" "$(stand "$B/p1" "$L")"
abschnitt "I2: nachsehen wiederholt die erste Probe, bevor steckt gesetzt wird"
B="$(basis_neu)"
L="$(neu "$B" "$B/p1")"; takt "$B"
printf '1\n0\n' > "$STEUER/claude.folge"
wt "$B" nachsehen > "$B/nachsehen.log" 2>&1
warte_auf '[ -s "$B/.claude/workbench/vorrat/.traeger.pid" ]'
[ "$(stand "$B/p1" "$L")" = "läuft" ] && ok "I2: erste Probe scheitert, Wiederholung gelingt, keine Aufgabe steckt" || bad "I2: Stand" "$(stand "$B/p1" "$L") $(cat "$B/nachsehen.log")"
grep -q "abgelöst gestartet\|über wb-nohup" "$B/nachsehen.log" && ok "I2: nachsehen startet den Träger abgelöst, weil noch Arbeit ansteht" || bad "I2: kein Start" "$(cat "$B/nachsehen.log")"
wt "$B" stop >/dev/null 2>&1
[ ! -f "$B/.claude/workbench/vorrat/.traeger.pid" ] && ok "I2: stop beendet den abgelösten Träger" || bad "I2: PID-Datei blieb"

# ==========================================================================
abschnitt "J: nachsehen endet sofort bei leerem Vorrat"
B="$(basis_neu)"; T_A="$(date +%s)"
AUS="$(wt "$B" nachsehen 2>&1)"; RC=$?; T_D=$(( $(date +%s) - T_A ))
[ "$RC" -eq 0 ] && printf '%s' "$AUS" | grep -q "nichts, das ohne den Nutzer weiterkommt" && [ "$T_D" -lt 20 ] \
  && ok "J: Exit 0, Hinweis, Ende nach ${T_D}s" || bad "J: nachsehen" "rc=$RC ${T_D}s $AUS"
[ ! -f "$B/.claude/workbench/vorrat/.traeger.pid" ] && ok "J: keine PID-Datei" || bad "J: PID-Datei liegt"

# ==========================================================================
abschnitt "K: start, zweiter start, stop, SIGTERM"
B="$(basis_neu)"; budget 2
K="$(neu "$B" "$B/p1")"
PIDDATEI="$B/.claude/workbench/vorrat/.traeger.pid"
# Die PID steht in der Datei: $! waere die Subshell der Shell-Funktion wt, nicht der Traeger.
wt "$B" start --vordergrund > "$B/start.log" 2>&1 &
warte_auf '[ -s "$PIDDATEI" ]'; TP="$(cat "$PIDDATEI" 2>/dev/null)"
[ -n "$TP" ] && kill -0 "$TP" 2>/dev/null && ok "K: PID-Datei nennt einen lebenden Träger ($TP)" || bad "K: PID-Datei" "$(cat "$B/start.log")"
AUS="$(wt "$B" start --vordergrund 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$AUS" | grep -q "läuft schon" && ok "K: zweiter start: Exit 0 mit Hinweis" || bad "K: zweiter start" "rc=$RC $AUS"
[ "$(wt "$B" status --json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["laeuft"], d["pid"])')" = "True $TP" ] \
  && ok "K: status --json zeigt den laufenden Träger" || bad "K: status" "$(wt "$B" status --json)"
if [ "$(uname)" = Darwin ]; then
  warte_auf 'grep -q "^caffeinate -i -w $TP$" "$LOG"' && ok "K: macOS: caffeinate -i -w <eigene PID>" || bad "K: caffeinate" "$(grep caffeinate "$LOG")"
  CAF="$(cat "$STEUER/caffeinate.pid" 2>/dev/null)"
fi
wt "$B" stop >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && [ ! -f "$PIDDATEI" ] && ! kill -0 "$TP" 2>/dev/null \
  && ok "K: stop beendet den Träger und räumt die PID-Datei" || bad "K: stop" "rc=$RC"
[ "$(uname)" != Darwin ] || { warte_auf '! kill -0 "$CAF" 2>/dev/null' && ok "K: caffeinate endet mit dem Träger" || bad "K: caffeinate lebt weiter" "$CAF"; }
wt "$B" start --vordergrund > "$B/start2.log" 2>&1 &
warte_auf '[ -s "$PIDDATEI" ]'; TP2="$(cat "$PIDDATEI" 2>/dev/null)"
kill -TERM "$TP2"; warte_auf '! kill -0 "$TP2" 2>/dev/null'
[ ! -f "$PIDDATEI" ] && ! kill -0 "$TP2" 2>/dev/null \
  && ok "K: SIGTERM beendet sauber, PID-Datei weg" || bad "K: SIGTERM"
wait
[ "$(stand "$B/p1" "$K")|$(letzter_grund "$B/p1" "$K")" = "offen|Kontingent" ] && ok "K: die Schleife hat getaktet (Grund steht im Verlauf)" || bad "K: Verlauf" "$(letzter_grund "$B/p1" "$K")"

# ==========================================================================
abschnitt "L: lokaler Hauptagent"
B="$(basis_neu)"
Q="$(neu "$B" "$B/p1" --hauptagent qwen3.5-4b:medium)"; takt "$B"
[ "$(vj "$(vd "$B/p1" "$Q")" '(v["stand"], v["grund"])')" = "('wartet auf den Nutzer', 'lokaler Hauptagent noch nicht gemessen')" ] \
  && ok "L: ohne lokalerHauptagentGemessen: wartet auf den Nutzer mit Grund" || bad "L: Stand ungemessen" "$(vj "$(vd "$B/p1" "$Q")" '(v["stand"], v["grund"])')"
[ "$(zaehle '^pi ')$(zaehle '^wb-belegung')" = "00" ] && ok "L: weder pi noch Speicherbuchung angefasst" || bad "L: pi/wb-belegung gerufen"
einstellen "$B" '{"lokalerHauptagentGemessen": true}'
P2="$B/p2"; mkdir -p "$P2"; git -C "$P2" init -q; env HOME="$TESTHOME" git -C "$P2" commit -q --allow-empty -m init
Q2="$(neu "$B" "$P2" --hauptagent qwen3.5-4b:medium)"; takt "$B"
# Modellkennung, Provider und Gewicht kommen aus der Registry, nicht aus dem
# Test: am 2026-09-20 wechselte der Alias 'lmgamma' von MLX auf Enginex (anderer
# Provider, anderes Gewicht), und ein fest eingetippter Wert haette hier einen
# Fehlschlag gemeldet, wo die Umstellung richtig durchgereicht wurde. Geprueft
# wird also weiterhin, DASS der Traeger vor dem Start bucht und die pi-Zeile aus
# dem Auftrag baut -- nur die Zahlen dafuer holt der Test sich dort, wo sie
# gepflegt werden.
eval "$(python3 -c "import json
m = next(m for m in json.load(open('$REPO/models.default.json'))['models'] if m['id'] == 'qwen3.5-4b')  # Kit: shipped local model
print('REF=%s' % m['modelRef'])
print('PROV=%s' % m['provider'])
print('GEW=%s' % float(m.get('gewichteGb') or 16.0))  # wb-traeger's default without gewichteGb")"
[ "$(stand "$P2" "$Q2")" = "läuft" ] && ok "L: mit Messung: lokaler Hauptagent läuft" || bad "L: Stand gemessen" "$(stand "$P2" "$Q2") $(tail -3 "$B/takt.log")"
grep -q -- "^wb-belegung nimm --gewichte-gb $GEW --modell $REF --kontext 131072 --zweck Hauptagent $Q2" "$LOG" \
  && ok "L: ein großes Modell zur Zeit: Speicherbuchung vor dem Start" || bad "L: wb-belegung" "$(grep wb-belegung "$LOG")"
warte_auf "[ \"\$(zaehle '^pi-start')\" = 1 ]"
grep -q -- "^pi --provider $PROV --model $REF --thinking medium -p --session-dir $P2/.companion/auftraege/$Q2.sitzung --session-id $Q2 " "$LOG" \
  && ! grep -q -- "--continue" "$LOG" && ok "L: erster Zug: pi-Zeile aus dem Auftrag, ohne --continue" || bad "L: pi-Zeile" "$(grep '^pi ' "$LOG")"
grep -q "pi-start pid=.* env WB_AUFGABE_ID=$Q2" "$LOG" && ok "L: Zug bekommt WB_AUFGABE_ID" || bad "L: Umgebung im Zug"
ZPID="$(python3 -c "import json;print(json.load(open('$B/.claude/workbench/vorrat/.traeger.zustand.json'))['lokaler_zug']['$Q2']['pid'])")"
warte_auf '! kill -0 "$ZPID" 2>/dev/null'
echo notiz > "$P2/notiz.txt"; echo fremd > "$P2/fremd.txt"
# Befund 7: '.' von Hand in pfade (wb-aufgabe lehnt es ab); der Commit darf es nicht stagen.
python3 - "$(vd "$P2" "$Q2")" <<'PY'
import json, sys
p = sys.argv[1]; v = json.load(open(p)); v["pfade"] = [".", "notiz.txt"]; json.dump(v, open(p, "w"), ensure_ascii=False)
PY
wa "$B" verlauf "$Q2" weiter "weiter mit dem nächsten Schritt" >/dev/null 2>&1
takt "$B"
[ "$(git -C "$P2" log -1 --name-only --format=)" = "notiz.txt" ] && git -C "$P2" status --porcelain | grep -q '^?? fremd.txt' \
  && ok "L: Zugende committet genau die gültigen Pfade aus 'pfade' ('.' bleibt draußen)" || bad "L: Commit" "$(git -C "$P2" log -1 --name-only --format=) / $(git -C "$P2" status --porcelain)"
grep -q "^wb-belegung gib k-1$" "$LOG" && ok "L: Risiko 12: Buchung des ersten Zugs mit ihrer Kennung freigegeben" || bad "L: gib" "$(grep wb-belegung "$LOG")"
warte_auf "[ \"\$(zaehle '^pi-start')\" = 2 ]"
[ "$(grep '^pi ' "$LOG" | tail -1 | grep -c -- '--continue')" = 1 ] && grep -q "^pi .*Nächster Zug" "$LOG" \
  && ok "L: 'weiter' startet den nächsten Zug mit --continue" || bad "L: zweiter Zug" "$(grep '^pi ' "$LOG" | tail -1)"
[ "$(grep '^pi-start' "$LOG" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')" = 2 ] && ok "L: je Zug ein eigener Prozess" || bad "L: Prozesse" "$(grep '^pi-start' "$LOG")"
[ "$(zaehle '^wb-belegung nimm')" = 2 ] && ok "L: jeder Zug bucht vorher" || bad "L: nimm je Zug" "$(zaehle '^wb-belegung nimm')"
abschnitt "L2: Risiko 12 -- kein neuer lokaler Zug, solange der alte lebt"
B="$(basis_neu)"; einstellen "$B" '{"lokalerHauptagentGemessen": true}'
echo 8 > "$STEUER/pi.schlaf"
Q3="$(neu "$B" "$B/p1" --hauptagent qwen3.5-4b:medium)"; takt "$B"
warte_auf "[ \"\$(zaehle '^pi-start')\" = 1 ]"
wa "$B" stand "$Q3" "pausiert (Weckzeit)" --weckzeit 2000-01-01T00:00:00Z >/dev/null 2>&1
takt "$B"
[ "$(zaehle '^pi-start')" = 1 ] && [ "$(letzter_grund "$B/p1" "$Q3")" = "Zug läuft noch" ] \
  && ok "L2: Wecken bei lebendem Zug startet keinen zweiten pi-Prozess" || bad "L2: zweiter Zug" "$(zaehle '^pi-start') / $(letzter_grund "$B/p1" "$Q3")"
pkill -f "$TESTHOME/.local/bin/pi" 2>/dev/null; rm -f "$STEUER/pi.schlaf"

# ==========================================================================
abschnitt "M: status und Maschinen"
B="$(basis_neu)"
X="$(neu "$B" "$B/p1")"
[ "$(wt "$B" status --json | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['laeuft'], '$X' in d['aufgaben'].get('offen', []), 'lebenszeichen' in d, 'pausenschalter' in d)")" = "False True True True" ] \
  && ok "M: status --json: läuft, Aufgaben je Stand, Lebenszeichen, Pausenschalter" || bad "M: status --json" "$(wt "$B" status --json)"
printf '{"laeuft": true, "maschine": "host2"}\n' > "$STEUER/ssh-status.json"
[ "$(wt "$B" status --json --alle-maschinen | python3 -c 'import json,sys;print(json.load(sys.stdin)["maschinen_status"]["host2"]["laeuft"])')" = True ] \
  && grep -q "^ssh -o BatchMode=yes -o ConnectTimeout=5 host2 PATH=.* wb-traeger status --json" "$LOG" \
  && ok "M: --alle-maschinen holt den Status des fremden Trägers per ssh" || bad "M: Fernabruf" "$(grep '^ssh' "$LOG")"
wt "$B" status | grep -q "läuft nicht" && ok "M: Klartext-Status" || bad "M: Klartext"
B0="$(basis_neu)"; printf '{"agents": {"nachtfenster": "00:00-00:00", "taktSekunden": 1}}\n' > "$B0/.claude/workbench/settings.json"
wt "$B0" status | grep -q "^wb-traeger this machine: " \
  && [ "$(wt "$B0" status --json --alle-maschinen | python3 -c 'import json,sys;print(json.load(sys.stdin)["maschinen_status"])')" = "{}" ] \
  && ok "M: kit: ohne agents.maschinen nur diese Maschine ('this machine'), kein Fernabruf" \
  || bad "M: kit: Vorgabe eine Maschine" "$(wt "$B0" status; wt "$B0" status --json --alle-maschinen)"
mkdir -p "$B0/p0"; X0="$(wa "$B0" anlegen "$B0/p0" --ziel "Ziel $MARKE" --fertig gruen 2>/dev/null | tail -1)"
[ "$(python3 -c "import json;print(json.load(open('$B0/.claude/workbench/vorrat/$X0.json'))['maschine'])" 2>/dev/null)" = "mac" ] \
  && ok "M: kit: neue Aufgabe ohne --maschine laeuft auf dieser Maschine" || bad "M: kit: Vorgabemaschine" "$X0"
Y="$(neu "$B" "$B/p2" --maschine host2)"; takt "$B"
grep -q "^ssh -o BatchMode=yes -o ConnectTimeout=5 host2 PATH=\$HOME/.local/bin:\$PATH wb-aufgabe aufnehmen $B/p2 $Y" "$LOG" \
  && [ ! -e "$B/.claude/workbench/vorrat/$Y.json" ] && [ "$(arten "$B/p2" "$Y" verschoben)" = 1 ] \
  && ok "M: Aufgabe für host2 per ssh 'wb-aufgabe aufnehmen' übergeben, Eintrag hier entfernt" || bad "M: Aufnahme" "$(grep aufnehmen "$LOG")"
OA="$B/p2/.companion/auftraege"
grep -q "^scp -q -o BatchMode=yes $OA/$Y.json $OA/$Y.verlauf.json host2:$OA/$" "$LOG" \
  && grep -q "wb-aufgabe aufnehmen $B/p2 $Y --maschine host2$" "$LOG" \
  && ok "M: Befund 6: Auftrag und Verlauf per scp ins selbe Verzeichnis, aufnehmen mit --maschine host2" \
  || bad "M: scp/--maschine" "$(grep -E '^scp|aufnehmen' "$LOG")"

# ==========================================================================
abschnitt "N: Fable ohne Freigabe startet mit Opus"
if python3 -c "import json,sys;sys.exit(0 if any(m.get('alias')=='fable51' for m in json.load(open('$REPO/models.default.json'))['models']) else 1)"; then
  B="$(basis_neu)"
  F="$(neu "$B" "$B/p1" --hauptagent fable51:high)"; takt "$B"
  [ "$(stand "$B/p1" "$F")" = "läuft" ] && grep -q -- "--model claude-opus-5 --effort high -n $F" "$LOG" \
    && [ "$(vj "$(vd "$B/p1" "$F")" 'next((e.get("grund") for e in E if e["art"]=="fallback-gewechselt"), "")')" = "Fable-Sperre" ] \
    && ok "N: Start mit opus5, Wechsel steht mit Grund im Verlauf" || bad "N: Fable" "$(grep '^claude --model' "$LOG")"
else
  ok "N: kein fable51 in der Registry, Fall entfällt"
fi

# ==========================================================================
# ==========================================================================
# Nachzug nach dem Reviewer-Pass (Auftrag traeger Nr. 2): je Befund ein Fall,
# gebaut nach den Belegen D1 bis D10 des Reviewers.
abschnitt "P: Befund 1 -- nur eine Freigabe mit passendem Hash startet (D1, D2)"
B="$(basis_neu)"; mkdir -p "$B/p1"
F1="$(wa "$B" anlegen "$B/p1" --ziel "D1 $MARKE" --fertig x --maschine mac 2>/dev/null | tail -1)"
python3 - "$B/p1/.companion/auftraege/$F1.json" <<'PY'
import json, sys
p = sys.argv[1]; a = json.load(open(p)); a["approval"] = {"gefaelscht": True}; json.dump(a, open(p, "w"))
PY
F2="$(neu "$B" "$B/p2")"
python3 - "$B/p2/.companion/auftraege/$F2.json" <<'PY'
import json, sys
p = sys.argv[1]; a = json.load(open(p)); a["freigaben"]["fable"] = True; a["hauptagent"]["model"] = "fable51"
json.dump(a, open(p, "w"))
PY
takt "$B"
[ "$(vj "$(vd "$B/p1" "$F1")" '(v["stand"], v["grund"])')|$(vj "$(vd "$B/p2" "$F2")" '(v["stand"], v["grund"])')" \
  = "('wartet auf den Nutzer', 'Freigabe ungültig')|('wartet auf den Nutzer', 'Freigabe ungültig')" ] \
  && [ "$(zaehle '^claude-start')" = 0 ] && ok "P: gefälschte und nachträglich geänderte Freigabe: wartet auf den Nutzer, kein Start" \
  || bad "P: Freigabe" "$(vj "$(vd "$B/p1" "$F1")" '(v["stand"], v["grund"])') $(vj "$(vd "$B/p2" "$F2")" '(v["stand"], v["grund"])') starts=$(zaehle '^claude-start')"
[ "$(letzter_grund "$B/p2" "$F2")" = "Freigabe ungültig" ] && ok "P: Nichtstart-Grund 'Freigabe ungültig' im Verlauf" || bad "P: Grund" "$(letzter_grund "$B/p2" "$F2")"
F3="$(neu "$B" "$B/p3")"; takt "$B"; PF="$(pane_von "$B/p3" "$F3")"
kill "$(pane_pid "$PF")"; warte_auf '! pane_lebt "$PF"'
python3 - "$B/p3/.companion/auftraege/$F3.json" <<'PY'
import json, sys
p = sys.argv[1]; a = json.load(open(p)); a["goal"] += " (nachträglich geändert)"; json.dump(a, open(p, "w"))
PY
wa "$B" stand "$F3" "pausiert (Weckzeit)" --weckzeit 2000-01-01T00:00:00Z >/dev/null 2>&1; takt "$B"
[ "$(stand "$B/p3" "$F3")" = "wartet auf den Nutzer" ] && [ "$(zaehle '^claude-start')" = 1 ] \
  && ok "P: auch das Wecken prüft die Freigabe" || bad "P: Wecken" "$(stand "$B/p3" "$F3") starts=$(zaehle '^claude-start')"

abschnitt "Q: Befund 2 -- Fable nach der Weckzeit startet wieder mit opus5 (D3)"
if python3 -c "import json,sys;sys.exit(0 if any(m.get('alias')=='fable51' for m in json.load(open('$REPO/models.default.json'))['models']) else 1)"; then
  B="$(basis_neu)"
  FQ="$(neu "$B" "$B/p1" --hauptagent fable51:high)"; takt "$B"; PQ="$(pane_von "$B/p1" "$FQ")"
  kill "$(pane_pid "$PQ")"; warte_auf '! pane_lebt "$PQ"'
  wa "$B" stand "$FQ" "pausiert (Weckzeit)" --weckzeit 2000-01-01T00:00:00Z >/dev/null 2>&1; takt "$B"
  [ "$(zaehle '^claude-start')" = 2 ] && [ "$(grep -c -- '--model claude-opus-5 ' "$LOG")" = 2 ] && ! grep -q -- '--model claude-fable' "$LOG" \
    && [ "$(arten "$B/p1" "$FQ" fallback-gewechselt)" = 2 ] && [ "$(stand "$B/p1" "$FQ")" = "läuft" ] \
    && ok "Q: nach dem Wecken opus5, zweiter Eintrag fallback-gewechselt" || bad "Q: Fable-Weckweg" "$(grep '^claude --model' "$LOG")"
else
  ok "Q: kein fable51 in der Registry, Fall entfällt"
fi

abschnitt "R: Befund 3 -- Repo belegt durch weiterarbeitenden Hauptagenten und über Symlink (D4, D10)"
B="$(basis_neu)"; P="$B/proj-r"
RA="$(neu "$B" "$P")"; takt "$B"; PR="$(pane_von "$P" "$RA")"
wa "$B" stand "$RA" "wartet auf den Nutzer" >/dev/null 2>&1
RC_="$(neu "$B" "$P")"; takt "$B"
[ "$(stand "$P" "$RC_")|$(letzter_grund "$P" "$RC_")" = "offen|Repo belegt durch Aufgabe $RA" ] && [ "$(zaehle '^claude-start')" = 1 ] \
  && ok "R: D4: lebender Hauptagent unter 'wartet auf den Nutzer' belegt das Repo" || bad "R: D4" "$(stand "$P" "$RC_") / $(letzter_grund "$P" "$RC_")"
ln -s "$P" "$B/alias-r"
RE="$(neu "$B" "$B/alias-r")"; takt "$B"
[ "$(stand "$B/alias-r" "$RE")|$(letzter_grund "$B/alias-r" "$RE")" = "offen|Repo belegt durch Aufgabe $RA" ] && [ "$(zaehle '^claude-start')" = 1 ] \
  && ok "R: D10: derselbe Ordner über einen Symlink ist belegt" || bad "R: D10" "$(stand "$B/alias-r" "$RE") / $(letzter_grund "$B/alias-r" "$RE")"
kill "$(pane_pid "$PR")"; warte_auf '! pane_lebt "$PR"'
wa "$B" worker "$RA" setzen w1 --rolle tester --zustand arbeitet >/dev/null 2>&1; takt "$B"
[ "$(zaehle '^claude-start')" = 1 ] && ok "R: ohne lebenden Hauptagenten belegt ein arbeitender Worker das Repo weiter" || bad "R: Worker" "$(zaehle '^claude-start')"
wa "$B" worker "$RA" entfernen w1 >/dev/null 2>&1; takt "$B"
[ "$(stand "$P" "$RC_")" = "läuft" ] && ok "R: ist nichts mehr am Werk, startet die nächste" || bad "R: Freigabe des Repos" "$(stand "$P" "$RC_")"

abschnitt "S: Befund 4 -- die Sicherung weckt keinen arbeitenden Hauptagenten; wach --bis (D5)"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"; B="$(basis_neu)"; P="$B/p1"
SS="$(neu "$B" "$P")"; takt "$B"
wecker "$B" "$SS" "$(plus "$T0" 10)" zugende
JETZT="$(plus "$T0" 30)"; wa "$B" verlauf "$SS" notiz "neuer Zug, arbeite an Teil 2" >/dev/null 2>&1
JETZT="$(plus "$T0" 40)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 0 ] && ok "S: D5: Verlaufseintrag nach dem Wecker -> keine Sicherung" || bad "S: D5" "$(zaehle '^inbox-text')"
touch "$B/gespraech.jsonl"; printf '%s\n' "$B/gespraech.jsonl" > "$STEUER/transcript"
JETZT="$(plus "$T0" 100)"; wecker "$B" "$SS" "$JETZT" zugende; JETZT="$(plus "$T0" 110)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 0 ] && ok "S: Gesprächsdatei seit dem Wecker geändert -> keine Sicherung" || bad "S: Gesprächsdatei" "$(zaehle '^inbox-text')"
rm -f "$STEUER/transcript"
JETZT="$(plus "$T0" 200)"; wecker "$B" "$SS" "$JETZT" zugende; JETZT="$(plus "$T0" 210)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && ok "S: ohne Zeichen von Arbeit greift sie" || bad "S: Gegenprobe" "$(zaehle '^inbox-text')"
JETZT="$(plus "$T0" 1300)"; wa "$B" verlauf "$SS" wach "ScheduleWakeup in zehn Minuten" --bis "$(plus "$T0" 1900)" >/dev/null 2>&1
JETZT="$(plus "$T0" 1310)"; wecker "$B" "$SS" "$JETZT" zugende; JETZT="$(plus "$T0" 1320)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && ok "S: wach --bis gilt bis zur genannten Zeit als Entscheidung" || bad "S: wach" "$(zaehle '^inbox-text')"
JETZT="$(plus "$T0" 2000)"; wecker "$B" "$SS" "$JETZT" zugende; JETZT="$(plus "$T0" 2010)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 2 ] && ok "S: nach 'bis' greift die Sicherung wieder" || bad "S: nach wach" "$(zaehle '^inbox-text')"

abschnitt "T: Befund 5 -- der Träger endet (D6, D6b), drei Fehlversuche, Eintrag ohne Maschine"
B="$(basis_neu)"
# anlegen weist ein unbekanntes Modell ab (Abschnitt AJ); eines, das nach der Freigabe aus
# der Registry verschwindet, erreicht den Träger trotzdem -- nachgestellt durch Umschreiben
# und eine neue Freigabe.
TG="$(neu "$B" "$B/p1")"; modell_setzen "$B/p1" "$TG" gibtsnicht
( wt "$B" start --vordergrund > "$B/start.log" 2>&1 ) & J=$!
warte_auf '! kill -0 "$J" 2>/dev/null'
! kill -0 "$J" 2>/dev/null && [ ! -e "$B/.claude/workbench/vorrat/.traeger.pid" ] \
  && [ "$(vj "$(vd "$B/p1" "$TG")" '(v["stand"], v["grund"])')" = "('wartet auf den Nutzer', 'Modell nicht in der Registry: gibtsnicht')" ] \
  && ok "T: D6: nie startbare Aufgabe wartet auf den Nutzer, der Träger endet von selbst" \
  || bad "T: D6" "$(vj "$(vd "$B/p1" "$TG")" '(v["stand"], v["grund"])') lebt=$(kill -0 "$J" 2>/dev/null && echo ja)"
kill "$J" 2>/dev/null; wait "$J" 2>/dev/null
B="$(basis_neu)"; echo 255 > "$STEUER/ssh.rc"
TY="$(neu "$B" "$B/p1" --maschine host2)"
( wt "$B" start --vordergrund > "$B/start.log" 2>&1 ) & J=$!
warte_auf '! kill -0 "$J" 2>/dev/null'
! kill -0 "$J" 2>/dev/null && [ "$(vj "$(vd "$B/p1" "$TY")" '(v["stand"], v["grund"])')" = "('steckt', 'Umgebung')" ] \
  && ok "T: D6b: unerreichbare Zielmaschine hält den Träger nicht am Leben" || bad "T: D6b" "$(vj "$(vd "$B/p1" "$TY")" '(v["stand"], v["grund"])')"
kill "$J" 2>/dev/null; wait "$J" 2>/dev/null
rm -f "$STEUER/ssh.rc"; : > "$LOG"
B="$(basis_neu)"; echo 1 > "$STEUER/ssh-aufnehmen.rc"
TZ="$(neu "$B" "$B/p1" --maschine host2)"
takt "$B"; takt "$B"; S2="$(stand "$B/p1" "$TZ")"; takt "$B"; takt "$B"
[ "$S2|$(stand "$B/p1" "$TZ")|$(zaehle 'wb-aufgabe aufnehmen')" = "offen|steckt|3" ] \
  && ok "T: nach drei gescheiterten Übergaben steckt (Umgebung), kein vierter Versuch" || bad "T: drei Versuche" "$S2 $(stand "$B/p1" "$TZ") $(zaehle 'wb-aufgabe aufnehmen')"
rm -f "$STEUER/ssh-aufnehmen.rc"
B="$(basis_neu)"; TO="$(neu "$B" "$B/p1")"
python3 - "$B/.claude/workbench/vorrat/$TO.json" <<'PY'
import json, sys
p = sys.argv[1]; e = json.load(open(p)); del e["maschine"]; json.dump(e, open(p, "w"))
PY
takt "$B"
[ "$(stand "$B/p1" "$TO")" = "läuft" ] && ok "T: Hinweis 17: Eintrag ohne Maschine startet als eigener" || bad "T: ohne Maschine" "$(stand "$B/p1" "$TO")"

abschnitt "V: Befund 8 -- sitzung gesehen höchstens je fünf Minuten"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"; B="$(basis_neu)"
SV="$(neu "$B" "$B/p1")"; takt "$B"; G1="$(vj "$(vd "$B/p1" "$SV")" 'v["hauptagent_sitzung"]["zuletzt_gesehen"]')"
JETZT="$(plus "$T0" 60)"; takt "$B"; G2="$(vj "$(vd "$B/p1" "$SV")" 'v["hauptagent_sitzung"]["zuletzt_gesehen"]')"
JETZT="$(plus "$T0" 400)"; takt "$B"; G3="$(vj "$(vd "$B/p1" "$SV")" 'v["hauptagent_sitzung"]["zuletzt_gesehen"]')"
[ "$G1" = "$T0" ] && [ "$G2" = "$T0" ] && [ "$G3" = "$(plus "$T0" 400)" ] \
  && ok "V: kein Stempel nach 60 s, einer nach 400 s" || bad "V: gesehen" "$G1 $G2 $G3"

abschnitt "W: Risiko 9 -- eine verwaiste PID-Datei wird übernommen"
B="$(basis_neu)"; budget 2; WK="$(neu "$B" "$B/p1")"
PIDDATEI="$B/.claude/workbench/vorrat/.traeger.pid"
sleep 60 & TOT=$!; kill "$TOT"; wait "$TOT" 2>/dev/null; echo "$TOT" > "$PIDDATEI"
wt "$B" start --vordergrund > "$B/start.log" 2>&1 &
warte_auf '[ "$(cat "$PIDDATEI" 2>/dev/null)" != "$TOT" ] && [ -s "$PIDDATEI" ]'
TP="$(cat "$PIDDATEI" 2>/dev/null)"
[ "$TP" != "$TOT" ] && kill -0 "$TP" 2>/dev/null && ok "W: tote PID $TOT übernommen, Träger $TP läuft" || bad "W: Übernahme" "$(cat "$B/start.log")"
wt "$B" stop >/dev/null 2>&1; wait

abschnitt "X: Hinweis 15 -- nach nachsehen prüft der abgelöste Träger nicht noch einmal"
B="$(basis_neu)"; XL="$(neu "$B" "$B/p1")"; takt "$B"
rm -f "$B/.claude/workbench/vorrat/.traeger.zustand.json"; : > "$LOG"
wt "$B" nachsehen > "$B/nachsehen.log" 2>&1
warte_auf '[ -s "$B/.claude/workbench/vorrat/.traeger.pid" ]'; sleep 3
[ "$(zaehle '^claude -p ok')" = 1 ] && ok "X: eine Probe je Anstoß" || bad "X: Proben" "$(zaehle '^claude -p ok')"
wt "$B" stop >/dev/null 2>&1

abschnitt "Y: Hinweise 18, 19 -- Eintrag ohne projekt beendet den Träger nicht; Zustellung aus der Zukunft"
B="$(basis_neu)"; Y1="$(neu "$B" "$B/p1")"; Y2="$(neu "$B" "$B/p2")"
python3 - "$B/.claude/workbench/vorrat/$Y1.json" <<'PY'
import json, sys
p = sys.argv[1]; e = json.load(open(p)); del e["projekt"]; json.dump(e, open(p, "w"))
PY
takt "$B"
[ "$(stand "$B/p2" "$Y2")" = "läuft" ] && [ "$(stand "$B/p1" "$Y1")" = "steckt" ] \
  && vj "$(vd "$B/p1" "$Y1")" 'v["grund"]' | grep -q "^Umgebung: " && grep -q "Aufgabe $Y1" "$B/.claude/workbench/vorrat/.traeger.log" \
  && ok "Y: Ausnahme nur für diese Aufgabe (steckt, Fehlertext als Grund, .traeger.log), die nächste startet" \
  || bad "Y: Ausnahme je Aufgabe" "$(stand "$B/p1" "$Y1") / $(vj "$(vd "$B/p1" "$Y1")" 'v["grund"]') / $(stand "$B/p2" "$Y2")"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"; B="$(basis_neu)"
YZ="$(neu "$B" "$B/p1")"; takt "$B"
JETZT="2099-01-01T00:00:00Z"; wa "$B" verlauf "$YZ" zustellung "aus der Zukunft" --kennung "sicherung-$YZ-zukunft" >/dev/null 2>&1
JETZT="$(plus "$T0" 60)"; wecker "$B" "$YZ" "$JETZT" zugende; JETZT="$(plus "$T0" 70)"; takt "$B"
[ "$(zaehle '^inbox-text')" = 1 ] && ok "Y: ein Zeitstempel in der Zukunft sperrt die Sicherung nicht" || bad "Y: Zukunft" "$(zaehle '^inbox-text')"

abschnitt "Z: Risiko 13 -- systemd-Unit"
U="$REPO/systemd/wb-traeger.service"
grep -qx "Type=exec" "$U" && ! grep -q "^Type=oneshot" "$U" && grep -qx "KillMode=process" "$U" \
  && ok "Z: Type=exec, kein oneshot, KillMode=process" || bad "Z: Unit" "$(grep -E 'Type|Kill' "$U")"

abschnitt "AA: Companion -- status je Standwechsel, Zustellung verbucht"
B="$(basis_neu)"; AA="$(neu "$B" "$B/p1")"
takt "$B"
[ "$(stand "$B/p1" "$AA")" = "läuft" ] && ok "AA: Aufgabe läuft" || bad "AA: Stand" "$(stand "$B/p1" "$AA")"
grep -q "companion-call status $AA --stand laeuft" "$LOG" && ok "AA: wb-companion status mit task_state laeuft aufgerufen" \
  || bad "AA: companion-call fehlt" "$(grep companion-call "$LOG")"
companion_eintraege() { vj "$(vd "$1" "$2")" '[(e["art"], e.get("kennung", "")[-6:], e["text"][:70]) for e in E if e["art"].startswith("companion")]'; }
[ "$(grep -c "^companion-call status $AA --stand laeuft" "$LOG")" = 1 ] \
  && [ "$(vj "$(vd "$B/p1" "$AA")" 'sum(1 for e in E if e["art"]=="companion" and "(laeuft)" in e["text"])')" = 1 ] \
  && ok "AA: Aufrufstelle und Standwechsel-Phase im selben Takt ergeben für 'laeuft' genau eine Meldung" \
  || bad "AA: Doppelmeldung" "$(grep companion-call "$LOG") / $(companion_eintraege "$B/p1" "$AA")"
[ "$(arten "$B/p1" "$AA" companion)" -ge 1 ] && ok "AA: mindestens ein Verlaufseintrag 'companion'" || bad "AA: kein companion-Eintrag"
echo "$(letzter_companion_text "$B/p1" "$AA")" | grep -q "Companion gemeldet" \
  && ok "AA: letzter companion-Eintrag meldet Zustellung" || bad "AA: Text" "$(letzter_companion_text "$B/p1" "$AA")"
ANZAHL1="$(grep -c '^companion-call' "$LOG")"
takt "$B"
ANZAHL2="$(grep -c '^companion-call' "$LOG")"
[ "$ANZAHL2" = "$ANZAHL1" ] && ok "AA: unveränderter Stand wird im nächsten Takt nicht erneut gemeldet (Kennung)" \
  || bad "AA: erneute Meldung ohne Standwechsel" "$ANZAHL1 -> $ANZAHL2"

abschnitt "AB: Companion -- Nichtzustellung verbucht, Takt läuft weiter"
B="$(basis_neu)"; AB="$(neu "$B" "$B/p1")"
companion_rc 3
takt "$B"
[ "$(stand "$B/p1" "$AB")" = "läuft" ] && ok "AB: Aufgabe startet trotz nicht erreichbarem Companion -- der Takt bricht nicht" \
  || bad "AB: Stand" "$(stand "$B/p1" "$AB")"
echo "$(letzter_companion_text "$B/p1" "$AB")" | grep -q "nicht erreichbar" \
  && ok "AB: letzter companion-Eintrag meldet Nichtzustellung" || bad "AB: Text" "$(letzter_companion_text "$B/p1" "$AB")"
[ "$(vj "$(vd "$B/p1" "$AB")" 'next((e.get("grund") for e in reversed(E) if e["art"]=="companion-fehlgeschlagen"), None)')" = "nicht zugestellt" ] \
  && ok "AB: Grund 'nicht zugestellt'" || bad "AB: Grund fehlt oder falsch"
[ "$(arten "$B/p1" "$AB" companion-fehlgeschlagen)" -ge 1 ] && ok "AB: Fehlschlag steht ohne Erfolgsquittung im Verlauf" \
  || bad "AB: Fehlschlag-Verlauf fehlt"
[ "$(grep -c "^companion-call status $AB --stand laeuft" "$LOG")" = 1 ] \
  && ok "AB: ein gescheiterter Versuch wird im selben Takt nicht sofort wiederholt" || bad "AB: Versuche im ersten Takt" "$(grep companion-call "$LOG")"
takt "$B"
[ "$(grep -c "^companion-call status $AB --stand laeuft" "$LOG")" = 2 ] \
  && [ "$(vj "$(vd "$B/p1" "$AB")" 'sum(1 for e in E if e["art"]=="companion-fehlgeschlagen" and "(laeuft)" in e["text"])')" = 1 ] \
  && [ "$(arten "$B/p1" "$AB" companion)" = 0 ] \
  && ok "AB: der nächste Takt versucht dieselbe Lage erneut, verbucht den Fehlschlag aber nicht zweimal" \
  || bad "AB: Wiederholung ohne Erfolg" "$(grep companion-call "$LOG") / $(companion_eintraege "$B/p1" "$AB")"
companion_rc 0
takt "$B"
[ "$(grep -c "^companion-call status $AB --stand laeuft" "$LOG")" = 3 ] && [ "$(arten "$B/p1" "$AB" companion)" = 1 ] \
  && ok "AB: nach Fehlschlägen wird später erfolgreich gemeldet und quittiert" || bad "AB: Erfolg nach Fehlschlag" "$(grep companion-call "$LOG")"
takt "$B"
[ "$(grep -c "^companion-call status $AB --stand laeuft" "$LOG")" = 3 ] \
  && ok "AB: nach der Quittung meldet der nächste Takt dieselbe Lage nicht noch einmal" || bad "AB: Meldung nach Quittung" "$(grep companion-call "$LOG")"

abschnitt "AC: Companion -- wartet auf den Nutzer sendet zusätzlich frage"
B="$(basis_neu)"; AC="$(neu "$B" "$B/p1")"
takt "$B"
wa "$B" frage "$AC" --text "Weiter machen?" --option ja --option nein --empfehlung ja >/dev/null
takt "$B"
[ "$(stand "$B/p1" "$AC")" = "wartet auf den Nutzer" ] && ok "AC: Stand wartet auf den Nutzer" || bad "AC: Stand" "$(stand "$B/p1" "$AC")"
grep -q "companion-call frage $AC --text" "$LOG" && grep -q -- "--titel Ziel" "$LOG" \
  && ok "AC: frage trägt den vollständigen Status in einem Aufruf" || bad "AC: frage-Aufruf fehlt" "$(grep companion-call "$LOG")"
grep -q "Optionen: ja (Empfehlung), nein" "$LOG" && ok "AC: Fragetext trägt Optionen mit Empfehlung zuerst" \
  || bad "AC: Fragetext" "$(grep 'companion-call frage' "$LOG")"

abschnitt "AD: Companion -- zur Abnahme sendet zusätzlich bericht mit Ergebnispfad"
B="$(basis_neu)"; AD="$(neu "$B" "$B/p1")"
takt "$B"
ergebnispfad_setzen "$B/p1" "$AD" "/tmp/ergebnis-$AD.md"
wa "$B" stand "$AD" "zur Abnahme" --grund fertig >/dev/null 2>&1
takt "$B"
[ "$(stand "$B/p1" "$AD")" = "zur Abnahme" ] && ok "AD: Stand zur Abnahme" || bad "AD: Stand" "$(stand "$B/p1" "$AD")"
grep -q "companion-call bericht $AD --pfad /tmp/ergebnis-$AD.md" "$LOG" && grep -q -- "--titel Ziel" "$LOG" && ok "AD: bericht mit vollständigem Status und Ergebnispfad aufgerufen" \
  || bad "AD: bericht-Aufruf fehlt" "$(grep companion-call "$LOG")"

abschnitt "AE: Pausenschalter -- Trägers eigene Zustellung (Sicherung) geht mit --absender traeger und WB_VORRAT weiter"
T0="2026-09-10T12:00:00Z"; JETZT="$T0"
B="$(basis_neu)"; AE="$(neu "$B" "$B/p1")"; takt "$B"
: > "$B/.claude/workbench/vorrat/.agentverkehr-pause"
wecker "$B" "$AE" "$T0" zugende; takt "$B"
[ "$(zaehle 'inbox-text')" -ge 1 ] && ok "AE: die Sicherung wurde trotz gesetztem Schalter zugestellt" || bad "AE: keine Zustellung geloggt" "$(cat "$LOG")"
grep -q "absender=--absender-traeger" "$LOG" && ok "AE: Zustellung mit --absender traeger" || bad "AE: absender fehlt" "$(grep inbox-text "$LOG")"
grep -q "vorrat=$B/.claude/workbench/vorrat" "$LOG" \
  && ok "AE: WB_VORRAT zeigt auf denselben Vorrat wie 'wb-traeger status' (derselbe Schalter)" || bad "AE: vorrat fehlt" "$(grep inbox-text "$LOG")"

abschnitt "AF: Antwort-Kette -- dieselbe Zustellung wie Sicherung/Nachtpause/Wecken, gleich wer wb-aufgabe antwort ruft"
B="$(basis_neu)"; AF="$(neu "$B" "$B/p1")"
takt "$B"
PANE="$(pane_von "$B/p1" "$AF")"
pane_lebt "$PANE" && ok "AF: Hauptagent-Pane lebt" || bad "AF: Pane lebt nicht" "$PANE"
wa "$B" frage "$AF" --text "weiter?" --option ja --option nein --empfehlung ja >/dev/null
[ "$(stand "$B/p1" "$AF")" = "wartet auf den Nutzer" ] && ok "AF: Stand wartet auf den Nutzer nach der Frage" \
  || bad "AF: Stand nach frage" "$(stand "$B/p1" "$AF")"
wa "$B" antwort "$AF" "ja, weiter" --mensch-beleg "$BELEG" >/dev/null
[ "$(stand "$B/p1" "$AF")" = "offen" ] \
  && ok "AF: wb-aufgabe antwort setzt den Stand auf 'offen' -- derselbe Weg, ob der Companion oder ein Mensch antwort ruft" \
  || bad "AF: Stand nach antwort" "$(stand "$B/p1" "$AF")"
: > "$LOG"
takt "$B"
[ "$(stand "$B/p1" "$AF")" = "läuft" ] && ok "AF: die offene Aufgabe läuft wieder" || bad "AF: Stand nach dem Takt" "$(stand "$B/p1" "$AF")"
[ "$(pane_von "$B/p1" "$AF")" = "$PANE" ] && ok "AF: derselbe Pane wird weiterbenutzt, kein neuer Start" \
  || bad "AF: Pane gewechselt" "$(pane_von "$B/p1" "$AF") statt $PANE"
grep -q "inbox-text $PANE sock=$SOCK" "$LOG" \
  && ok "AF: die Entscheidung geht über wb-inbox sende an den Pane -- dieselbe Zustellungskette wie Sicherung/Nachtpause/Wecken (Schritt 2)" \
  || bad "AF: keine Zustellung an den Pane" "$(grep inbox "$LOG")"
grep -q "absender=--absender-traeger" "$LOG" && ok "AF: mit --absender traeger, wie jede Trägerzustellung" || bad "AF: absender fehlt" "$(grep inbox-text "$LOG")"
tmux -L "$SOCK" kill-server 2>/dev/null

abschnitt "AG: Vertragsgrenze -- langer erster Zielsatz bleibt unter 200 Zeichen"
LANGER_SATZ="$(python3 -c 'print("x" * 240 + ". Zweiter Satz.")')"
KURZ="$(python3 -c 'import importlib.machinery,importlib.util,sys;p=sys.argv[1];sys.path.insert(0,__import__("os").path.dirname(p));l=importlib.machinery.SourceFileLoader("wb_traeger_test",p);s=importlib.util.spec_from_loader(l.name,l);m=importlib.util.module_from_spec(s);l.exec_module(m);print(m._erster_satz(sys.argv[2]))' "$REPO/wb-traeger" "$LANGER_SATZ")"
[ "${#KURZ}" = 200 ] && ok "AG: _erster_satz deckelt auch einen langen ersten Satz auf 200 Zeichen" \
  || bad "AG: Titelgrenze" "${#KURZ} Zeichen"

abschnitt "AH: Fehler 1/2 -- inbox_senden mit seinem echten Argumentvektor gegen den echten wb-inbox (kein Schirm)"
# Der Schirm-wb-inbox oben nimmt jede Reihenfolge an; hier liegt der echte wb-inbox vorn im
# PATH. Pane gibt es keinen (der Testserver ist abgeräumt): ein Aufruf, den der Parser annimmt,
# endet mit "keine lebende Claude-Sitzung" (rc 1), ein falsch gebauter mit der Aufrufzeile (rc 2).
B="$(basis_neu)"; V="$B/.claude/workbench/vorrat"
mkdir -p "$TESTHOME/echt"; ln -sf "$REPO/wb-inbox" "$TESTHOME/echt/wb-inbox"
inbox_echt() {
  env HOME="$TESTHOME" PATH="$TESTHOME/echt:$PFAD" WB_TMUX_SOCKET="$SOCK" \
    python3 - "$REPO/wb-traeger" "$V" "$1" <<'PY'
import importlib.machinery, importlib.util, os, sys
pfad, vorrat, pid = sys.argv[1:4]
sys.path.insert(0, os.path.dirname(pfad))
l = importlib.machinery.SourceFileLoader("wb_traeger_ah", pfad)
s = importlib.util.spec_from_loader(l.name, l); m = importlib.util.module_from_spec(s); l.exec_module(m)
if pid:
    # "selbst": dieser Prozess ist der Träger (seine Befehlszeile nennt wb-traeger).
    with open(os.path.join(vorrat, ".traeger.pid"), "w") as f:
        f.write("%s\n" % (os.getpid() if pid == "selbst" else pid))
ctx = {"vorrat": vorrat, "protokoll": []}
print("ok=%s %s" % (m.inbox_senden(ctx, "20260911-ah", "%99999", "Hallo"), " ".join(ctx["protokoll"])))
PY
}
AUS="$(inbox_echt "")"
echo "$AUS" | grep -q "rc=1" && echo "$AUS" | grep -q "keine lebende Claude-Sitzung" && ! echo "$AUS" | grep -q "Aufruf:" \
  && ok "AH: der echte wb-inbox-Parser nimmt den Vektor des Trägers an und kommt bis zur Sitzungssuche" \
  || bad "AH: Parser" "$AUS"
printf '{"seit": "2026-09-11T00:00:00Z", "grund": "Test"}\n' > "$V/.agentverkehr-pause"
AUS="$(inbox_echt selbst)"
echo "$AUS" | grep -q "keine lebende Claude-Sitzung" && ! echo "$AUS" | grep -q "zurückgehalten" \
  && ok "AH: bei gesetztem Schalter geht der Träger selbst (PID-Datei, Elternkette) durch" || bad "AH: Träger bei Pause" "$AUS"
sleep 30 & FREMD=$!
AUS="$(inbox_echt "$FREMD")"
kill "$FREMD" 2>/dev/null; wait "$FREMD" 2>/dev/null || true
echo "$AUS" | grep -q "rc=4" && echo "$AUS" | grep -q "zurückgehalten" \
  && ok "AH: derselbe Aufruf ohne Träger in der Elternkette wird trotz --absender traeger zurückgehalten" || bad "AH: fremde PID" "$AUS"
rm -f "$V/.agentverkehr-pause" "$V/.traeger.pid"

abschnitt "AI: Fehler 3 -- Entprellung vergleicht mit der letzten Meldung, eine Rückkehr zum alten Stand geht wieder hinaus"
AUS="$(env HOME="$TESTHOME" PATH="$PFAD" python3 - "$REPO/wb-traeger" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
l = importlib.machinery.SourceFileLoader("wb_traeger_ai", sys.argv[1])
s = importlib.util.spec_from_loader(l.name, l); m = importlib.util.module_from_spec(s); l.exec_module(m)
Z = {"auftrag": {"goal": "Ziel."}, "verlauf": {"stand": "läuft", "grund": "gestartet", "verlauf": []}}
aufrufe, quittungen = [], []
m.wb_aufgabe = lambda ctx, a: (0, json.dumps(Z), "")
m.laufe = lambda befehl, frist=60, env=None: aufrufe.append(befehl) or (0, "", "")
m.verlauf_schreiben = lambda ctx, id_, art, text, grund=None, kennung=None: quittungen.append((art, kennung)) or True
def melde(ereignis):
    m.melden_kontext_setzen({"vorrat": "/nonexistent", "protokoll": []})
    vorher = len(aufrufe); m.melden("20260911-ai", ereignis); return len(aufrufe) - vorher
erst = melde("start")
k_laeuft = quittungen[-1][1]
Z["verlauf"]["verlauf"] = [{"art": "companion", "kennung": k_laeuft}]
gleich = melde("stand:läuft")
Z["verlauf"]["verlauf"].append({"art": "companion", "kennung": "companion-20260911-ai-steckt"})
rueckkehr = melde("stand:läuft")
print("erst=%d gleich=%d rueckkehr=%d" % (erst, gleich, rueckkehr))
PY
)"
[ "$AUS" = "erst=1 gleich=0 rueckkehr=1" ] \
  && ok "AI: anderer Ereignistext bei gleicher Lage meldet nicht; läuft, steckt, läuft meldet wieder" || bad "AI: Entprellung" "$AUS"

abschnitt "AJ: Nachtrag -- Hauptagent als Alias (sonnet5): anlegen speichert die Kennung, der Träger startet"
B="$(basis_neu)"; AJ="$(neu "$B" "$B/p1" --hauptagent sonnet5:high)"
[ "$(auftrag_modell "$B/p1" "$AJ")" = "claude-sonnet-5" ] && ok "AJ: anlegen --hauptagent sonnet5:high speichert claude-sonnet-5" \
  || bad "AJ: gespeichertes Modell" "'$(auftrag_modell "$B/p1" "$AJ")'"
takt "$B"
[ "$(stand "$B/p1" "$AJ")" = "läuft" ] && ok "AJ: der Träger startet die Aufgabe, statt 'Modell nicht in der Registry' zu melden" \
  || bad "AJ: Start mit Alias" "$(vj "$(vd "$B/p1" "$AJ")" '(v["stand"], v["grund"])')"
B="$(basis_neu)"; AJ2="$(neu "$B" "$B/p1")"; modell_setzen "$B/p1" "$AJ2" sonnet5
takt "$B"
[ "$(stand "$B/p1" "$AJ2")" = "läuft" ] && ok "AJ: ein schon gespeicherter Alias (Aufgabe von vor dem Fix) wird im Träger aufgelöst" \
  || bad "AJ: gespeicherter Alias" "$(vj "$(vd "$B/p1" "$AJ2")" '(v["stand"], v["grund"])')"
AUS="$(wa "$B" anlegen "$B/p2" --ziel "Unbekannt $MARKE" --fertig x --maschine mac --hauptagent gibtsnicht:high 2>&1)"; RC=$?
[ "$RC" = 2 ] && echo "$AUS" | grep -q "nicht in der Registry" \
  && ok "AJ: anlegen weist ein Modell ab, das weder Kennung noch Alias ist" || bad "AJ: unbekanntes Modell" "rc=$RC / $AUS"
tmux -L "$SOCK" kill-server 2>/dev/null

abschnitt "AK: Nr. 3 -- Trust-Dialog: wb-vertrauen vor jedem neuen Claude-Hauptagenten"
grund_von() { vj "$(vd "$1" "$2")" '(v["stand"], v["grund"])'; }
B="$(basis_neu)"; AK="$(neu "$B" "$B/p1")"
echo eintragbar > "$STEUER/vertrauen"
takt "$B"
Z_PRUEF="$(grep -n "^wb-vertrauen $B/p1 --pruefen$" "$LOG" | head -1 | cut -d: -f1)"
Z_EIN="$(grep -n "^wb-vertrauen $B/p1$" "$LOG" | head -1 | cut -d: -f1)"
[ "$(stand "$B/p1" "$AK")" = "läuft" ] && pane_lebt "$(pane_von "$B/p1" "$AK")" && [ -n "$Z_PRUEF" ] && [ -n "$Z_EIN" ] \
  && [ "$Z_PRUEF" -lt "$Z_EIN" ] \
  && ok "AK: eintragbar: erst --pruefen, dann eintragen, dann gestartet" \
  || bad "AK: eintragbar" "$(grund_von "$B/p1" "$AK") / $(grep wb-vertrauen "$LOG")"
tmux -L "$SOCK" kill-server 2>/dev/null; : > "$LOG"

B="$(basis_neu)"; AK2="$(neu "$B" "$B/p1")"
echo abgelehnt > "$STEUER/vertrauen"
takt "$B"
[ "$(grund_von "$B/p1" "$AK2")" = "('wartet auf den Nutzer', 'Projekt nicht vertraut: $B/p1')" ] \
  && [ "$(vj "$(vd "$B/p1" "$AK2")" 'next((e["text"] for e in reversed(E) if e["art"]=="nicht-gestartet"), "")')" = "Projekt nicht vertraut: $B/p1" ] \
  && ok "AK: abgelehnt: wartet auf den Nutzer, Nichtstart-Grund im Verlauf" || bad "AK: abgelehnt" "$(grund_von "$B/p1" "$AK2")"
! grep -q "^wb-vertrauen $B/p1$" "$LOG" && [ -z "$(tmux -L "$SOCK" list-sessions 2>/dev/null)" ] && [ -z "$(pane_von "$B/p1" "$AK2")" ] \
  && ok "AK: abgelehnt: nichts eingetragen, keine Sitzung gespawnt" || bad "AK: Spawn trotz Ablehnung" "$(tmux -L "$SOCK" list-sessions 2>&1) / $(grep wb-vertrauen "$LOG")"

T0="2026-09-10T12:00:00Z"; JETZT="$T0"; rm -f "$STEUER/vertrauen"
B="$(basis_neu)"; AK3="$(neu "$B" "$B/p1")"; takt "$B"; PK="$(pane_von "$B/p1" "$AK3")"
kill "$(pane_pid "$PK")"; warte_auf '! pane_lebt "$PK"'
echo abgelehnt > "$STEUER/vertrauen"; : > "$LOG"; JETZT="$(plus "$T0" 10)"; takt "$B"
[ "$(zaehle '^wb-revive')" = 0 ] && [ "$(grund_von "$B/p1" "$AK3")" = "('wartet auf den Nutzer', 'Projekt nicht vertraut: $B/p1')" ] \
  && ok "AK: Wiederbelebung prüft zuerst: kein wb-revive, wartet auf den Nutzer" \
  || bad "AK: Wiederbelebung" "revive=$(zaehle '^wb-revive') / $(grund_von "$B/p1" "$AK3")"
tmux -L "$SOCK" kill-server 2>/dev/null

JETZT=""; rm -f "$STEUER/vertrauen"
B="$(basis_neu)"; AK4="$(neu "$B" "$B/p1")"; takt "$B"; PK="$(pane_von "$B/p1" "$AK4")"
kill "$(pane_pid "$PK")"; warte_auf '! pane_lebt "$PK"'
wa "$B" stand "$AK4" "pausiert (Weckzeit)" --weckzeit 2000-01-01T00:00:00Z >/dev/null 2>&1
echo abgelehnt > "$STEUER/vertrauen"; : > "$LOG"; takt "$B"
grep -q "^wb-vertrauen $B/p1 --pruefen$" "$LOG" && [ "$(grund_von "$B/p1" "$AK4")" = "('wartet auf den Nutzer', 'Projekt nicht vertraut: $B/p1')" ] \
  && ! pane_lebt "$(pane_von "$B/p1" "$AK4")" \
  && ok "AK: Wecken bei toter Sitzung prüft zuerst: wartet auf den Nutzer, kein neuer Pane" \
  || bad "AK: Wecken" "$(grund_von "$B/p1" "$AK4") / $(grep wb-vertrauen "$LOG")"
tmux -L "$SOCK" kill-server 2>/dev/null

echo
echo "-- O: die echte Umgebung blieb unberührt --"
[ ! -e "$HOME/.claude/workbench/vorrat/.traeger.pid" ] && ok "O: keine PID-Datei im echten Vorrat" || bad "O: echte PID-Datei"
[ -z "$(pgrep -f "$BASISROOT" 2>/dev/null)" ] && ok "O: kein Träger aus dem Test läuft noch" || bad "O: Prozesse übrig" "$(pgrep -fl "$BASISROOT")"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
