#!/usr/bin/env bash
# test-harness-mise-wrapper.sh -- ein mise-Wrapper in ~/.local/bin darf den Start
# eines Harness nicht in eine Endlosschleife schicken.
#
# ANLASS (2026-09-18, host2): nach dem Omarchy-Update um 17:54 (mise 2026.9.1 ->
# 2026.9.9, omarchy 4.0.4, laut /var/log/pacman.log) starteten codex- und
# opencode-Worker nicht mehr. Omarchy legt fuer jedes ueber `mise` verwaltete
# Werkzeug einen Wrapper nach ~/.local/bin, der sein Programm UEBER DEN PATH
# aufruft:
#
#     mise use -g "codex" || exit 1
#     exec mise x "codex" -- "codex" "$@"
#
# wb-harness-run stellt ~/.local/bin im Pane nach vorn (die Werkbank-Werkzeuge
# muessen dort erreichbar sein) -- und damit findet dieser Wrapper wieder sich
# selbst. Der Orchestrator auf host2 sah nur: "Startprogramme laufen in der
# Worker-Umgebung in eine Endlosschleife", alle Worker liefen ersatzweise ueber
# Claude.
#
# GEPRUEFT WIRD, mit einem erfundenen Harness 'fakeharness' und einer mise-Attrappe:
#   A  Gegenprobe: der Wrapper ALLEIN, mit ~/.local/bin vorn im PATH, laeuft
#      wirklich in die Schleife (sonst misst dieser Test nichts).
#   B  wb-harness-run startet trotzdem das ECHTE Programm und kehrt zurueck.
#   C  Es sagt im Klartext, dass es am Wrapper vorbeigestartet hat.
#   D  Ohne Wrapper (normales Programm in ~/.local/bin) bleibt alles wie vorher --
#      kein Symlink-Verzeichnis, kein Hinweis.
#
# ISOLATION: eigenes HOME, eigene Kopien der Skripte, eine Attrappe fuer `wb-state`
# (wb-harness-run ruft ausschliesslich `$HOME/.local/bin/wb-state models resolve`)
# und eine fuer `mise`. Kein tmux, kein echtes Werkzeug, kein Netz.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-misewrapper.XXXXXX")" && pwd)"
BIN="$TESTHOME/.local/bin"
ECHTDIR="$TESTHOME/echt"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() {
  case "$TESTHOME" in
    /tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: '$TESTHOME' sieht nicht nach mktemp aus, nichts geloescht" >&2 ;;
  esac
}
trap cleanup EXIT

mkdir -p "$BIN" "$ECHTDIR" "$TESTHOME/work"
cp "$REPO/wb-harness-run" "$BIN/wb-harness-run"; chmod +x "$BIN/wb-harness-run"

# Das ECHTE Programm: meldet sich und endet. Es liegt NICHT im PATH -- nur `mise
# which` kennt seinen Pfad, genau wie im Betrieb.
cat >"$ECHTDIR/fakeharness" <<'EOF'
#!/bin/bash
echo "ECHTES-PROGRAMM gestartet: $*"
EOF
chmod +x "$ECHTDIR/fakeharness"

# Der Wrapper, buchstabengetreu in der Form, die Omarchy schreibt.
cat >"$BIN/fakeharness" <<'EOF'
#!/bin/bash
mise use -g "fakeharness" || exit 1
exec mise x "fakeharness" -- "fakeharness" "$@"
EOF
chmod +x "$BIN/fakeharness"

# Die mise-Attrappe: `use -g` tut nichts, `which` nennt das echte Programm,
# `x <tool> -- <befehl...>` fuehrt aus, was nach '--' steht -- und sucht es wie das
# echte mise ueber den PATH, wenn dort kein Pfad steht. Genau daraus entsteht die
# Schleife.
cat >"$BIN/mise" <<EOF
#!/bin/bash
case "\$1" in
  use)   exit 0 ;;
  which) echo "$ECHTDIR/fakeharness"; exit 0 ;;
  x)     shift; while [ \$# -gt 0 ] && [ "\$1" != "--" ]; do shift; done; shift; exec "\$@" ;;
esac
exit 1
EOF
chmod +x "$BIN/mise"

# wb-state-Attrappe: liefert genau den Block, den wb-harness-run erwartet
# (Tabulator zwischen Schluessel und Wert).
printf '#!/bin/bash\nprintf "harness\\tfakeharness\\ncmd\\tcd %s && exec fakeharness --model testmodell\\n"\n' \
  "$TESTHOME/work" >"$BIN/wb-state"
chmod +x "$BIN/wb-state"

echo "== test-harness-mise-wrapper: der Start darf nicht in den eigenen Wrapper laufen =="
echo "   HOME: $TESTHOME"
echo

mit_frist() {   # <sekunden> <programm...> -- 124 bei Ablauf, portabel ohne coreutils-timeout
  local frist="$1"; shift
  "$@" &
  local kind=$!
  ( sleep "$frist"; kill -9 "$kind" 2>/dev/null ) &
  local wache=$!
  local rc=0
  wait "$kind" 2>/dev/null || rc=$?
  kill -9 "$wache" 2>/dev/null
  wait "$wache" 2>/dev/null
  return "$rc"
}

echo "-- A: Gegenprobe -- der Wrapper allein laeuft wirklich in die Schleife --"
A_LOG="$TESTHOME/a.log"
mit_frist 8 env HOME="$TESTHOME" PATH="$BIN:/usr/bin:/bin" \
  bash -c "exec >\"$A_LOG\" 2>&1; fakeharness --model testmodell"
rc=$?
if [ "$rc" -ne 0 ] && ! grep -q "ECHTES-PROGRAMM" "$A_LOG" 2>/dev/null; then
  ok "A: der Wrapper kommt allein nie zum echten Programm (nach 8 s abgebrochen, rc=$rc) -- die Falle ist echt"
else
  bad "A: der Wrapper lief von allein durch (rc=$rc) -- dieser Test misst dann nichts: $(tail -2 "$A_LOG" 2>/dev/null)"
fi

echo
echo "-- B/C: wb-harness-run startet am Wrapper vorbei --"
B_LOG="$TESTHOME/b.log"
mit_frist 20 env HOME="$TESTHOME" PATH="/usr/bin:/bin" \
  bash -c "exec >\"$B_LOG\" 2>&1; \"$BIN/wb-harness-run\" --model testmodell --role worker"
rc=$?
if [ "$rc" -eq 0 ]; then
  ok "B: wb-harness-run kehrt zurueck, statt in der Schleife zu haengen"
else
  bad "B: wb-harness-run endete mit rc=$rc (124/137 = Frist abgelaufen, also Schleife): $(tail -3 "$B_LOG" 2>/dev/null)"
fi
if grep -q "ECHTES-PROGRAMM gestartet: --model testmodell" "$B_LOG" 2>/dev/null; then
  ok "B: das ECHTE Programm lief, mit seinen Argumenten"
else
  bad "B: das echte Programm kam nie dran: $(tail -3 "$B_LOG" 2>/dev/null)"
fi
if grep -q "mise-Wrapper" "$B_LOG" 2>/dev/null; then
  ok "C: der Umweg steht im Klartext im Protokoll, statt still zu geschehen"
else
  bad "C: kein Hinweis auf den Wrapper-Umweg: $(tail -3 "$B_LOG" 2>/dev/null)"
fi

echo
echo "-- D: ohne Wrapper bleibt alles, wie es war --"
rm -rf "$TESTHOME/.local/state/wb-harness-bin"
cp "$ECHTDIR/fakeharness" "$BIN/fakeharness"     # jetzt das echte Programm, kein Wrapper
D_LOG="$TESTHOME/d.log"
mit_frist 20 env HOME="$TESTHOME" PATH="/usr/bin:/bin" \
  bash -c "exec >\"$D_LOG\" 2>&1; \"$BIN/wb-harness-run\" --model testmodell --role worker"
rc=$?
if [ "$rc" -eq 0 ] && grep -q "ECHTES-PROGRAMM" "$D_LOG" 2>/dev/null; then
  ok "D: der normale Fall startet unveraendert"
else
  bad "D: der normale Start ging schief (rc=$rc): $(tail -3 "$D_LOG" 2>/dev/null)"
fi
if grep -q "mise-Wrapper" "$D_LOG" 2>/dev/null; then
  bad "D: der Wrapper-Hinweis erscheint, obwohl gar keiner da ist"
else
  ok "D: kein Wrapper-Hinweis, wo kein Wrapper ist"
fi
if [ -d "$TESTHOME/.local/state/wb-harness-bin" ]; then
  bad "D: ein Symlink-Verzeichnis wurde angelegt, obwohl nichts umzubiegen war"
else
  ok "D: kein Symlink-Verzeichnis angelegt"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
