#!/usr/bin/env bash
# test-chat-hook-datei-nur-bei-bedarf.sh -- ~/.claude/workbench/chat-zuordnung.sh
# entsteht nur fuer einen Harness, der ueberhaupt ueber einen Hook zugeordnet
# wird.
#
# BEFUND (11.08., von der Nachlese empfohlen): die Installation legte die
# Datei an (mkdir -p, Heredoc-Schreiben), BEVOR sie prueft, ob der Harness
# session.zuordnung=hook traegt -- die Pruefung stand erst im Python-Rumpf
# danach, der bei "zuordnung != hook" zwar nichts mehr in eine Hook-Konfiguration
# eintraegt, die Datei selbst aber schon auf der Platte liegen hatte. Fuer die
# dreizehn Harnesse, die nie ueber einen Hook zugeordnet werden ('claude' ist
# der einzige mit zuordnung=hook), entstand ~/.claude/workbench/ samt Datei,
# ohne dass sie je gebraucht wuerde.
#
# Die vorhandene Suite test-chat-hook-installation.sh (Aussage 5) prueft nur,
# dass KEIN Eintrag in einer Hook-Konfiguration landet -- nicht, dass die Datei
# selbst gar nicht erst entsteht. Genau diese Luecke deckt diese Suite, auf
# BEIDEN Ebenen: dem Werkzeug, das die Pruefung jetzt traegt
# (shell/wb-chat-hook-install), und dem Aufrufer, den der Befund urspruenglich
# nannte (shell/wb-harness-run, das seit dem 11.08. an das Werkzeug delegiert).
#
# DIE FUENF AUSSAGEN:
#   1  wb-chat-hook-install legt fuer einen NICHT hook-basierten Harness weder
#      die Datei noch das umgebende Verzeichnis an.
#   2  wb-chat-hook-install legt fuer einen hook-basierten Harness die Datei
#      weiterhin an (Gegenprobe -- die Reihenfolge aendert das Verhalten fuer
#      diesen Fall nicht).
#   3  Derselbe Unterschied gilt durch wb-harness-run hindurch, den Aufrufer,
#      den der urspruengliche Befund nannte.
#   4  Ein Harness ohne lesbaren Registry-Eintrag legt ebenfalls nichts an.
#   5  Ein zweiter Lauf fuer denselben nicht hook-basierten Harness bleibt
#      weiterhin ohne Datei -- kein verzoegertes Anlegen beim zweiten Versuch.
#
# ISOLATION: eigenes HOME, eigenes TMPDIR, ein STUB fuer `wb-state` (wie in
# test-chat-hook-installation.sh) -- kein echter Harness, kein echter
# tmux-Server, keine Datei der laufenden Sitzung wird angefasst.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$REPO/shell/wb-chat-hook-install"
LAUF="$REPO/shell/wb-harness-run"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-chathookdatei.XXXXXX")" && pwd)"
export TMPDIR="$TESTHOME/tmp"
mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/.claude" "$TMPDIR"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== chat-zuordnung.sh entsteht nur bei Bedarf =="
echo "Geprueft: $INSTALL, $LAUF"

[ -x "$INSTALL" ] || { echo "UEBERSPRUNGEN: $INSTALL fehlt"; exit 77; }
[ -x "$LAUF" ] || { echo "UEBERSPRUNGEN: $LAUF fehlt"; exit 77; }

# --- der wb-state-Stub: beantwortet nur "harness get" -------------------------
cat > "$TESTHOME/.local/bin/wb-state" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "models resolve")
    printf 'harness\t%s\n' "$WB_TEST_HARNESS"
    printf 'cmd\t/usr/bin/true\n'
    ;;
  "harness get")
    if [ -n "${WB_TEST_HJSON:-}" ]; then cat "$WB_TEST_HJSON"; fi
    ;;
esac
exit 0
STUB
chmod +x "$TESTHOME/.local/bin/wb-state"

HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"
WBDIR="$TESTHOME/.claude/workbench"

hjson() { # hjson <datei> <id> <zuordnung>
  cat > "$1" <<JSON
{"id": "$2", "session": {"via": "sessionFile", "ort": "~/x/{sessionId}.jsonl",
 "format": "claude-transcript", "zuordnung": "$3", "live": true, "eingabe": "pane",
 "zeigtNicht": [], "probe": {"datum": "2026-08-11", "beleg": "Test"},
 "hook": {"style": "claude-settings-json", "file": "~/.claude/settings.json",
  "event": "SessionStart", "matcher": "startup|resume", "timeout": 5}}}
JSON
}

install() { # install <harness-id> <json-datei|leer>
  env HOME="$TESTHOME" WB_TEST_HJSON="${2:-}" bash "$INSTALL" "$1" 2>&1
}

lauf() { # lauf <harness-id> <json-datei> -> die Ausgabe des Laufs (ueber wb-harness-run)
  env HOME="$TESTHOME" TMPDIR="$TMPDIR" WB_TEST_HARNESS="$1" WB_TEST_HJSON="$2" \
    bash "$LAUF" --model testmodell --role worker --dir "$TESTHOME" 2>&1
}

printf '%s\n' '{"model":"opus"}' > "$TESTHOME/.claude/settings.json"

echo
echo "-- 1: wb-chat-hook-install, nicht hook-basierter Harness --"
hjson "$TESTHOME/h-cwd.json" testcwd cwd
install testcwd "$TESTHOME/h-cwd.json" >/dev/null
if [ ! -e "$HAKEN" ] && [ ! -d "$WBDIR" ]; then
  ok "1: weder Datei noch Verzeichnis entstehen fuer einen Harness mit zuordnung=cwd"
else
  bad "1: $WBDIR wurde angelegt, obwohl der Harness keinen Hook braucht"
fi

echo
echo "-- 2: Gegenprobe, hook-basierter Harness --"
hjson "$TESTHOME/h-hook.json" testhook hook
install testhook "$TESTHOME/h-hook.json" >/dev/null
[ -x "$HAKEN" ] && ok "2: fuer einen hook-basierten Harness entsteht die Datei weiterhin" \
  || bad "2: $HAKEN fehlt -- die Reihenfolge hat den Normalfall mitgenommen"
rm -f "$HAKEN"
rmdir "$WBDIR" 2>/dev/null || true

echo
echo "-- 3: derselbe Unterschied durch wb-harness-run, den urspruenglich genannten Aufrufer --"
lauf testcwd "$TESTHOME/h-cwd.json" >/dev/null
if [ ! -e "$HAKEN" ] && [ ! -d "$WBDIR" ]; then
  ok "3: wb-harness-run legt fuer zuordnung=cwd ebenfalls nichts an"
else
  bad "3: wb-harness-run hat $WBDIR trotzdem angelegt"
fi
lauf testhook "$TESTHOME/h-hook.json" >/dev/null
[ -x "$HAKEN" ] && ok "3: und legt fuer zuordnung=hook weiterhin an -- die Gegenprobe traegt auch hier" \
  || bad "3: wb-harness-run hat fuer zuordnung=hook nichts mehr angelegt"
rm -f "$HAKEN"
rmdir "$WBDIR" 2>/dev/null || true

echo
echo "-- 4: kein lesbarer Registry-Eintrag --"
install testleer "" >/dev/null
if [ ! -e "$HAKEN" ] && [ ! -d "$WBDIR" ]; then
  ok "4: ohne Registry-Eintrag entsteht ebenfalls nichts"
else
  bad "4: $WBDIR wurde trotz fehlendem Registry-Eintrag angelegt"
fi

echo
echo "-- 5: ein zweiter Lauf fuer den nicht hook-basierten Harness bleibt ohne Datei --"
install testcwd "$TESTHOME/h-cwd.json" >/dev/null
if [ ! -e "$HAKEN" ] && [ ! -d "$WBDIR" ]; then
  ok "5: auch beim zweiten Lauf entsteht nichts nachtraeglich"
else
  bad "5: der zweite Lauf hat $WBDIR doch noch angelegt"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
