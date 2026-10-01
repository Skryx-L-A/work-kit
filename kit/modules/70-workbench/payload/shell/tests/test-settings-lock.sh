#!/bin/bash
# test-settings-lock.sh — proves wb-state and the VS Code extension actually
# lock each other out on ~/.claude/workbench/settings.json, the one file both
# sides write (SPEC / WORKBENCH-V2-PLAN.md 8.3).
#
# Until 2026-08-04 wb-state took a flock AND the extension's mkdir lock
# (settings.json.lock.d) around every write; the flock never protected
# anything once mkdir already covered both processes, and it implied a second,
# genuinely cross-language lock kind was available where none is: Node has no
# built-in flock(2) binding, macOS ships no `flock` CLI (unlike Linux
# util-linux — checked on this machine, absent), and a native addon would tie
# the extension to VS Code's bundled Node ABI per platform for a lock mkdir
# already gives for free. So both sides now share exactly one lock kind: the
# extension's mkdir-based directory lock. This suite does not check that the
# code LOOKS right — it forces real concurrent writers from both languages at
# the same file and measures whether a write is ever lost or the file is ever
# caught half-written on disk.
#
# ISOLATION (rules in ~/.claude/regeln/tests-und-eingriffe.md):
#   * `unset TMUX TMUX_PANE` before anything else — this suite touches no tmux
#     session, but wb-state reads TMUX_PANE for its change-log actor field, and
#     a leaked live pane would leak into that field.
#   * own HOME: mktemp -d. The real ~/.claude/workbench/settings.json is never
#     opened here; a stray write there is the definition of a broken test.
#   * repo scripts are COPIED into an isolated $BIN under that HOME, never the
#     scripts under ~/.local/bin — this suite proves the REPO state, so a
#     stale deploy elsewhere cannot fake a pass.
#   * trap cleans up the background reader loop and the temp HOME on any exit.
#
# Run:  shell/tests/test-settings-lock.sh   (from the repo, or anywhere)
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
EXT_SETTINGS="$(cd "$REPO/.." && pwd)/extension/src/settings.ts"
[ -f "$EXT_SETTINGS" ] || { echo "extension/src/settings.ts nicht gefunden unter $EXT_SETTINGS" >&2; exit 1; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-settings-lock-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"
mkdir -p "$BIN" "$TESTHOME/.claude/workbench"
cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
WBS="$BIN/wb-state"
SETTINGS_FILE="$TESTHOME/.claude/workbench/settings.json"
LOCKDIR="$TESTHOME/.claude/workbench/locks"
LOCK_D="$LOCKDIR/settings.json.lock.d"

READER_PID=""
cleanup() {
  [ -n "$READER_PID" ] && kill "$READER_PID" >/dev/null 2>&1
  [ -n "$READER_PID" ] && wait "$READER_PID" 2>/dev/null
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

echo "Geprueft: Repo-Stand aus $REPO (wb-state), $EXT_SETTINGS (Extension)"

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "node nicht gefunden — Test kann nicht laufen." >&2
  exit 1
fi

# Node harness: writes N keys named '<prefix>_<pid>_<i>' through the
# extension's real writeSetting()/withLock() — the same code path
# settingsView.ts calls, not a re-implementation of it.
cat > "$TESTHOME/ext_writer.mjs" <<EOF
import { writeSetting } from '$EXT_SETTINGS';
const [prefix, nStr] = process.argv.slice(2);
const n = parseInt(nStr, 10);
for (let i = 0; i < n; i++) {
  await writeSetting(prefix + '_' + process.pid + '_' + i, i);
}
EOF

write_shell_batch() {   # write_shell_batch <prefix> <count> <writer-id>
  # $$ stays the PARENT shell's PID even inside a backgrounded subshell, and
  # this box's /bin/bash is 3.2 (no $BASHPID, that needs bash 4+) — every
  # concurrently-backgrounded call would collide on the same prefix and
  # silently UNDER-count on purpose-built keys without an explicit id.
  local prefix="$1" n="$2" wid="$3" i
  for ((i = 0; i < n; i++)); do
    "$WBS" settings set "${prefix}_${wid}_${i}" "$i" >/dev/null
  done
}

# ── Test A: real concurrent writers from both languages ─────────────────────
# 4 shell writers x 15 keys + 4 node writers x 15 keys = 120 unique keys, all
# hammering the same settings.json at once. A background reader parses the
# file in a tight loop for the whole run: any half-written file (the tmp+
# rename step caught mid-flight) shows up as a JSON parse error there, and any
# lock that fails to exclude the other language shows up as a missing key
# below (a lost read-modify-write silently drops whatever the loser wrote).
echo '{}' > "$SETTINGS_FILE"
rm -f "$TESTHOME/reader-bad.log"

(
  while true; do
    python3 -c "
import json, sys
try:
    json.load(open('$SETTINGS_FILE'))
except Exception as e:
    sys.exit(1)
" || echo "bad parse at $(date +%s.%N)" >> "$TESTHOME/reader-bad.log"
  done
) &
READER_PID=$!

SH_WRITERS=4; SH_PER=15
EXT_WRITERS=4; EXT_PER=15
pids=()
for w in $(seq 1 "$SH_WRITERS"); do
  write_shell_batch shKey "$SH_PER" "$w" &
  pids+=($!)
done
for _ in $(seq 1 "$EXT_WRITERS"); do
  "$NODE_BIN" --no-warnings "$TESTHOME/ext_writer.mjs" extKey "$EXT_PER" &
  pids+=($!)
done

all_ok=1
for p in "${pids[@]}"; do
  wait "$p" || all_ok=0
done
[ "$all_ok" -eq 1 ] && ok "A: alle Schreiber-Prozesse beendeten sich fehlerfrei" \
  || bad "A: mindestens ein Schreiber-Prozess brach ab"

kill "$READER_PID" >/dev/null 2>&1; wait "$READER_PID" 2>/dev/null; READER_PID=""

if [ -s "$TESTHOME/reader-bad.log" ]; then
  bad "A: Datei war zwischendurch halb geschrieben / kaputt" "$(cat "$TESTHOME/reader-bad.log" | wc -l | tr -d ' ') Fehllesungen"
else
  ok "A: Datei blieb waehrend des gesamten Laufs gueltiges JSON (nie halb geschrieben)"
fi

read -r sh_count ext_count total_count < <(python3 -c "
import json
d = json.load(open('$SETTINGS_FILE'))
sh = sum(1 for k in d if k.startswith('shKey_'))
ext = sum(1 for k in d if k.startswith('extKey_'))
print(sh, ext, len(d))
")
expect_sh=$((SH_WRITERS * SH_PER))
expect_ext=$((EXT_WRITERS * EXT_PER))
[ "$sh_count" -eq "$expect_sh" ] && ok "A: alle $expect_sh Schluessel von wb-state ueberlebten" \
  || bad "A: wb-state-Schluessel verloren" "erwartet $expect_sh, gefunden $sh_count"
[ "$ext_count" -eq "$expect_ext" ] && ok "A: alle $expect_ext Schluessel der Extension ueberlebten" \
  || bad "A: Extension-Schluessel verloren" "erwartet $expect_ext, gefunden $ext_count"
[ "$total_count" -eq $((expect_sh + expect_ext)) ] && ok "A: keine Seite hat die andere ueberschrieben" \
  || bad "A: Gesamtzahl der Schluessel stimmt nicht" "erwartet $((expect_sh + expect_ext)), gefunden $total_count"

leftover_tmp=$(find "$TESTHOME/.claude/workbench" -maxdepth 1 -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
leftover_pytmp=$(find "$TESTHOME/.claude/workbench" -maxdepth 1 -name 'tmp*' -not -name 'settings.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$leftover_tmp" -eq 0 ] && [ "$leftover_pytmp" -eq 0 ] && ok "A: keine liegengebliebene Temporaerdatei (jede Schreibung endete mit rename/replace)" \
  || bad "A: Temporaerdatei(en) liegengeblieben" "*.tmp=$leftover_tmp tmp*=$leftover_pytmp"

[ ! -e "$LOCK_D" ] && ok "A: kein Sperrordner blieb nach dem Lauf liegen" \
  || bad "A: Sperrordner blieb liegen" "$LOCK_D existiert noch"

# ── Test B: a lock dir left by a crashed writer must not block forever ──────
# Simulates the exact scenario the task calls out: an OLD settings.json.lock.d
# from a session that died mid-write, still present after the switch to the
# unified lock. Both sides use the same staleness threshold (10s); this
# backdates the lock well past it and checks that a write proceeds quickly
# instead of hanging for the full 60s hard-timeout fallback.
test_stale_takeover() {   # test_stale_takeover <label> <write-command...>
  local label="$1"; shift
  echo '{}' > "$SETTINGS_FILE"
  mkdir -p "$LOCKDIR"
  rm -rf "$LOCK_D"
  mkdir "$LOCK_D"
  touch -t 202601010000 "$LOCK_D"   # far older than the 10s staleness threshold
  local start end elapsed
  start=$(date +%s)
  "$@" >/dev/null 2>&1
  local rc=$?
  end=$(date +%s)
  elapsed=$((end - start))
  [ "$rc" -eq 0 ] && [ "$elapsed" -le 15 ] && ok "B ($label): abgestuerzter Sperrordner wurde binnen ${elapsed}s uebernommen" \
    || bad "B ($label): Schreiben nach altem Sperrordner haengt oder schlaegt fehl" "rc=$rc elapsed=${elapsed}s"
  [ ! -e "$LOCK_D" ] && ok "B ($label): Sperrordner nach der Schreibung wieder weg" \
    || bad "B ($label): Sperrordner blieb liegen" "$LOCK_D existiert noch"
}

test_stale_takeover "wb-state" "$WBS" settings set afterStale ok
test_stale_takeover "Extension" "$NODE_BIN" --no-warnings "$TESTHOME/ext_writer.mjs" staleExt 1

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
