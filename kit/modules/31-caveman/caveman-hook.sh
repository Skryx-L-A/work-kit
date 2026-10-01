#!/bin/sh
# Claude Code hook wrapper for caveman.  Usage: caveman-hook.sh activate|track
#   activate  SessionStart hook: writes the flag file, prints the caveman rules as context
#   track     UserPromptSubmit hook: per-turn reminder, handles "stop caveman"
# With node: runs the pinned upstream hook unchanged (all levels, /caveman commands).
# Without node: same rules from the pinned SKILL.md, level full only.
# A hook must never fail a session: every path ends with exit 0.

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
UP="$HERE/upstream"
CDIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
FLAG="$CDIR/.caveman-active"

case "${1:-}" in
  activate) JS=caveman-activate.js ;;
  track) JS=caveman-mode-tracker.js ;;
  *) exit 0 ;;
esac

if [ "$1" = activate ] && command -v node >/dev/null 2>&1 && [ -f "$UP/src/hooks/$JS" ]; then
  exec node "$UP/src/hooks/$JS"
fi

# --- no node: minimal shell version, level full ---
if [ "$1" = activate ]; then
  SKILL="$UP/skills/caveman/SKILL.md"
  [ -f "$SKILL" ] || exit 0
  if [ ! -L "$FLAG" ]; then
    (umask 077; mkdir -p "$CDIR" && printf full > "$FLAG.$$" && mv -f "$FLAG.$$" "$FLAG") 2>/dev/null
  fi
  printf 'CAVEMAN MODE ACTIVE — level: full\n\n'
  # Same filter as the upstream hook: no frontmatter, only the row and examples of the level.
  awk -v lvl=full '
    NR == 1 && /^---[ \t]*$/ { fm = 1; next }
    fm == 1 { if ($0 ~ /^---[ \t]*$/) fm = 2; next }
    !started && /^[ \t]*$/ { next }
    { started = 1 }
    /^\|[ \t]*\*\*[^ *|]+\*\*[ \t]*\|/ {
      row = $0; sub(/^\|[ \t]*\*\*/, "", row); sub(/\*\*.*/, "", row)
      if (row == lvl) print
      next
    }
    /^- [^ :]+:[ \t]/ {
      k = $0; sub(/^- /, "", k); sub(/:.*/, "", k)
      if (k == lvl) print
      next
    }
    { print }
  ' "$SKILL"
  exit 0
fi

# track
# Keep this hook cheap: it runs once for every prompt. Do not start Node or an interpreter here.
# The JSON hook payload is normally one line; these common explicit opt-out phrases preserve the
# command without parsing arbitrary prompt content.
INPUT=$(cat 2>/dev/null)
case "$INPUT" in
  *"stop caveman"*|*"Stop caveman"*|*"disable caveman"*|*"Disable caveman"*|*"turn off caveman"*|*"Turn off caveman"*|*"caveman off"*|*"Caveman off"*)
  [ -L "$FLAG" ] || rm -f "$FLAG"
  exit 0
  ;;
esac
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"CAVEMAN MODE ACTIVE (full). Drop articles/filler/pleasantries/hedging. Fragments OK. Code/commits/security: write normal."}}'
fi
exit 0
