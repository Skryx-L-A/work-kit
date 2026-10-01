#!/usr/bin/env bash
# test-pi-worker-chat-werkstatt.sh -- die Werkstatt einer Chat-Sitzung wirkt
# NICHT auf Aufrufer ausserhalb der Chat-Sitzung zurueck (Reviewbefund 2 vom
# 12.08.).
#
# DER BEFUND. Eine Werkstatt traegt das Praefix `wb-`, weil `find_pane` in
# pi-worker und `wb-close` darauf filtern. Genau dadurch fiel sie in die
# ZIEL-Suche von `pi-worker`:
#
#   Stufe 4 verlangt GENAU EINE `wb-*`-Session. Sobald eine Chat-Sitzung offen
#   war, waren es zwei, und ein `claude-worker` aus einem gewoehnlichen Terminal
#   endete mit „Ziel-Workbench nicht eindeutig bestimmbar".
#   Stufe 3 nimmt die ANGEHAENGTE `wb-*`-Session. Hatte der Mensch gerade zu
#   einem Chat-Worker gewechselt, war das die Werkstatt -- und ein danach von
#   aussen gestarteter Worker landete in ihr.
#
# GEPRUEFT WIRD DIE ECHTE FUNKTION, nicht eine Nachstellung: `wb_kandidaten` und
# `chat_werkstaetten` werden aus shell/pi-worker HERAUSGELESEN und hier
# ausgefuehrt. Ein Test, der die Suchreihenfolge noch einmal abschreibt, prueft
# nur die Abschrift.
#
# DIE ZUSAGEN:
#   1  Ohne Chat-Werkstatt findet die Suche die eine Workbench -- wie bisher.
#   2  EINE OFFENE CHAT-WERKSTATT MACHT EXTERNE AUFRUFE NICHT MEHRDEUTIG:
#      daneben bleibt genau eine Workbench uebrig, und sie wird gefunden.
#   3  EINE ANGEHAENGTE WERKSTATT FAENGT FREMDE WORKER NICHT: Stufe 3 nimmt die
#      angehaengte Workbench, nicht die angehaengte Werkstatt.
#   4  Sind ALLE `wb-*`-Sessions Werkstaetten, gibt es kein Ziel -- und die
#      Meldung sagt, dass Werkstaetten uebergangen wurden.
#   5  Die Erkennung haengt an der OPTION, nicht am Namen: eine echte
#      Terminal-Sitzung eines Ordners namens `chat-…` bleibt sichtbar.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME aus mktemp -d,
# kein Spawn eines echten Workers, keine fremde Session.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-werkstatt-ziel-$$"
TESTHOME="$(mktemp -d)"
SHIM="$TESTHOME/.shim"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

cleanup() {
  trap "" PIPE
  [ -n "${HAENGER:-}" ] && kill "$HAENGER" 2>/dev/null
  [ -n "$TMUX_REAL" ] && tmux_socket_beenden_ohne_reste "$SOCKET"
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM HUP PIPE

echo "== Chat-Werkstatt und die Ziel-Suche von pi-worker (Socket $SOCKET) =="

[ -n "$TMUX_REAL" ] || ueberspringen "tmux nicht im PATH"
[ -f "$REPO/shell/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"

mkdir -p "$SHIM"
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# --- Die ECHTEN Funktionen aus pi-worker herausloesen -----------------------------
# Von der Zeile mit 'wb_kandidaten() {' bis zum Ende von 'chat_werkstaetten'.
AUSZUG="$TESTHOME/ziel.sh"
awk '/^wb_kandidaten\(\) \{/,/^\}$/' "$REPO/shell/pi-worker" > "$AUSZUG"
awk '/^chat_werkstaetten\(\) \{/,/^\}$/' "$REPO/shell/pi-worker" >> "$AUSZUG"
if ! grep -q 'wb_kandidaten' "$AUSZUG" || ! grep -q 'chat_werkstaetten' "$AUSZUG"; then
  bad "wb_kandidaten/chat_werkstaetten nicht aus shell/pi-worker herauszuloesen"
  echo "  bestanden: $pass, fehlgeschlagen: $fail"; exit 1
fi
ok "die geprueften Funktionen stammen aus shell/pi-worker selbst"

# Die Ziel-Suche, Stufen 3 und 4 -- WOERTLICH wie im Original, nur ohne die
# Stufen 0 bis 2, die hier nichts zu suchen haben (kein WB_SESSION, kein
# TMUX_PANE, keine Ahnenreihe in einer wb-Session).
cat >> "$AUSZUG" <<'ZIELEOF'
ziel() {
  TARGET=""
  [ -z "$TARGET" ] && TARGET=$(wb_kandidaten 1 | head -1)
  if [ -z "$TARGET" ]; then
    n=$(wb_kandidaten 0 | grep -c . || true)
    [ "$n" = "1" ] && TARGET=$(wb_kandidaten 0)
  fi
  [ -z "$TARGET" ] && { echo "KEIN-ZIEL"; return; }
  echo "$TARGET"
}
ZIELEOF

frage() { PATH="$SHIM:$PATH" bash -c "source '$AUSZUG'; ziel"; }
werkstaetten() { PATH="$SHIM:$PATH" bash -c "source '$AUSZUG'; chat_werkstaetten | tr '\n' ' '"; }

tm() { "$TMUX_REAL" -L "$SOCKET" "$@"; }

# Eine Testsession bekommt IMMER einen laufenden Befehl. Eine Session mit blosser
# Shell endet unterwegs -- und ein Test, dem die Sessions unter der Hand
# wegsterben, misst nicht die Ziel-Suche, sondern seine eigene Aufraeumung.
sitzung() { tm -f /dev/null new-session -d -s "$1" -x 80 -y 24 'while :; do sleep 3600; done'; }

# --- 1: die eine Workbench, ohne Werkstatt ---------------------------------------
sitzung wb-projekt-aaa111
ZIEL="$(frage)"
echo "      | ohne Werkstatt: $ZIEL"
[ "$ZIEL" = "wb-projekt-aaa111" ] \
  && ok "ohne Chat-Werkstatt findet die Suche die eine Workbench" \
  || bad "gefunden wurde '$ZIEL' statt wb-projekt-aaa111"

# --- 2: eine offene Werkstatt macht es NICHT mehrdeutig --------------------------
sitzung wb-chat-projekt-9f2a1c
tm set-option -t wb-chat-projekt-9f2a1c @wb_chat 1
ZIEL="$(frage)"
echo "      | mit offener Werkstatt: $ZIEL   (Werkstaetten: $(werkstaetten))"
[ "$ZIEL" = "wb-projekt-aaa111" ] \
  && ok "eine offene Chat-Werkstatt macht externe Aufrufe nicht mehrdeutig" \
  || bad "gefunden wurde '$ZIEL' -- die Werkstatt zaehlt noch mit"

# Und die Gegenprobe: OHNE die Marke waere es mehrdeutig. Das belegt, dass die
# Zusage oben wirklich an der Marke haengt und nicht am Zufall.
tm set-option -t wb-chat-projekt-9f2a1c -u @wb_chat
ZIEL_OHNE="$(frage)"
tm set-option -t wb-chat-projekt-9f2a1c @wb_chat 1
echo "      | Gegenprobe ohne Marke: $ZIEL_OHNE"
[ "$ZIEL_OHNE" = "KEIN-ZIEL" ] \
  && ok "Gegenprobe: ohne die Marke waere der Aufruf mehrdeutig -- die Marke wirkt" \
  || bad "auch ohne Marke kam '$ZIEL_OHNE' heraus -- die Zusage prueft nichts"

# --- 3: eine ANGEHAENGTE Werkstatt faengt keine fremden Worker -------------------
# Ein Client haengt an der Werkstatt -- genau die Lage, in der jemand gerade zu
# einem Chat-Worker gewechselt ist.
#
# `attach` braucht ein Terminal, und aus einem tmux-Pane DESSELBEN Servers geht
# es ohnehin nicht (Verschachtelung). `script` gibt dem Aufruf ein
# Pseudoterminal, ohne dass ein Fenster entsteht -- der Client ist echt, und
# `#{session_attached}` zaehlt ihn.
if ! command -v script >/dev/null 2>&1; then
  # Auf Fedora/Nobara liegt 'script' in einem EIGENEN Paket
  # ('util-linux-script'), nicht im Kern-util-linux -- dieser Rechner traegt
  # es nicht (Befund 2026-08-21, `dnf provides '*/bin/script'` nennt es
  # ausdruecklich als separates RPM). Nachruesten: 'sudo dnf install
  # util-linux-script'. Nur diese eine Zusage ist betroffen, der Rest der
  # Suite braucht kein Pseudoterminal.
  ok "3: uebersprungen -- 'script' fehlt auf dieser Maschine (nachruesten: sudo dnf install util-linux-script)"
else
  TERM=xterm script -q /dev/null "$TMUX_REAL" -L "$SOCKET" attach -t wb-chat-projekt-9f2a1c \
    >/dev/null 2>&1 &
  HAENGER=$!
  deadline=$((SECONDS + 10))
  while [ $SECONDS -lt $deadline ]; do
    ANGEHAENGT="$(tm list-sessions -F '#{session_attached} #{session_name}' | awk '$1>=1{print $2}' | tr '\n' ' ')"
    case "$ANGEHAENGT" in *wb-chat-projekt-9f2a1c*) break ;; esac
    sleep 0.3
  done
  echo "      | angehaengt: ${ANGEHAENGT:-<nichts>}"
  case "$ANGEHAENGT" in
    *wb-chat-projekt-9f2a1c*)
      ZIEL="$(frage)"
      echo "      | Ziel bei angehaengter Werkstatt: $ZIEL"
      [ "$ZIEL" != "wb-chat-projekt-9f2a1c" ] \
        && ok "eine angehaengte Werkstatt faengt fremde Worker nicht" \
        || bad "der Worker waere in der Chat-Werkstatt gelandet" ;;
    *)
      bad "die Werkstatt liess sich nicht anhaengen -- Zusage 3 ungeprueft" ;;
  esac
fi

# --- 5: die Erkennung haengt an der OPTION, nicht am Namen -----------------------
# Ein Ordner namens `chat-foo` ergibt bei wb-code `wb-chat-foo-<md5>`: DIESELBE
# Namensform wie eine Werkstatt. Ohne Marke ist sie eine gewoehnliche Workbench
# und muss sichtbar bleiben.
[ -n "${HAENGER:-}" ] && kill "$HAENGER" 2>/dev/null
tm kill-session -t wb-projekt-aaa111
sitzung wb-chat-foo-bbb222
ZIEL="$(frage)"
echo "      | echte Terminal-Sitzung mit chat-Namen: $ZIEL"
[ "$ZIEL" = "wb-chat-foo-bbb222" ] \
  && ok "eine echte Sitzung eines Ordners 'chat-…' bleibt sichtbar (Option statt Name)" \
  || bad "gefunden wurde '$ZIEL' -- der Name allein hat entschieden"

# --- 4: nur Werkstaetten heisst kein Ziel ---------------------------------------
tm kill-session -t wb-chat-foo-bbb222
ZIEL="$(frage)"
echo "      | nur noch Werkstaetten: $ZIEL"
[ "$ZIEL" = "KEIN-ZIEL" ] \
  && ok "sind alle wb-*-Sessions Werkstaetten, gibt es kein Ziel" \
  || bad "gefunden wurde '$ZIEL' -- eine Werkstatt wurde doch genommen"
case "$(werkstaetten)" in
  *wb-chat-projekt-9f2a1c*) ok "die Meldung kann die uebergangenen Werkstaetten benennen" ;;
  *) bad "chat_werkstaetten nennt sie nicht: $(werkstaetten)" ;;
esac

echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ] || exit 1
