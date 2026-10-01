# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this file
# Shared by install.sh and uninstall.sh of 16-harness-clis. Source it, do not execute it.
# Needs only bash, coreutils, tar, grep, sed, awk.

HC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HC_HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
KIT_BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
KIT_DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
HC_OFF="$KIT_OFFLINE/harness-clis"
HC_LOCKDIR="${HC_LOCKDIR:-$HC_HERE/lock}"
HC_DATA="$KIT_DATA_DIR/harness-clis"
HC_STATE="$KIT_DATA_DIR/state/16-harness-clis.list"     # lines: <harness> <version>
HC_MARK="work-kit:16-harness-clis"
# shellcheck source=pins.conf source-path=SCRIPTDIR
. "$HC_HERE/pins.conf"

# Order matters: it is the install order and the order of the default set.
HC_ALL="claude codex opencode copilot gemini pi aider"
# Default set of `install.sh` without arguments: edit this line (or set KIT_HARNESS_CLIS) to
# limit what the stick installs to the tools the company approved.
HC_DEFAULT="${KIT_HARNESS_CLIS:-$HC_ALL}"

hc_log() { printf '[harness-clis] %s\n' "$*"; }
hc_warn() { printf '[harness-clis] WARNING: %s\n' "$*" >&2; }
hc_die() { printf '[harness-clis] ERROR: %s\n' "$*" >&2; exit 1; }

hc_known() { case " $HC_ALL " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

hc_version() { # harness -> pinned version
  case "$1" in
    claude) echo "$CLAUDE_VERSION" ;;
    codex) echo "$CODEX_VERSION" ;;
    opencode) echo "$OPENCODE_VERSION" ;;
    copilot) echo "$COPILOT_VERSION" ;;
    gemini) echo "$GEMINI_VERSION" ;;
    pi) echo "$PI_VERSION" ;;
    aider) echo "$AIDER_VERSION" ;;
  esac
}

hc_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

hc_lock_lines() { grep -vhE '^[[:space:]]*(#|$)' "$HC_LOCKDIR/artifacts.lock" 2>/dev/null || true; }

# hc_artifact <harness>: path of the harness's artifact under offline/harness-clis (lock/artifacts.lock)
hc_artifact() { hc_lock_lines | awk -v p="$1/" 'index($2, p) == 1 { print $2; exit }'; }

# hc_verify <relpath>: the file exists and matches the locked sha256
hc_verify() {
  local want
  want="$(hc_lock_lines | awk -v p="$1" '$2 == p { print $1; exit }')"
  [ -n "$want" ] || { hc_warn "$1 is not listed in lock/artifacts.lock"; return 1; }
  [ -f "$HC_OFF/$1" ] || { hc_warn "missing $HC_OFF/$1 (run the build step: 16-harness-clis/fetch.sh)"; return 1; }
  [ "$(hc_sha256 "$HC_OFF/$1")" = "$want" ] || { hc_warn "checksum mismatch: $HC_OFF/$1"; return 1; }
}

hc_ts() { date +%Y%m%d%H%M%S; }

# hc_backup <path>: move a foreign file to $KIT_DATA_DIR/backups/16-harness-clis/<name>.bak-<ts> and
# record the original path in <name>.bak-<ts>.origin. Nothing is left beside the original.
hc_backup() {
  local dir b
  dir="$KIT_DATA_DIR/backups/16-harness-clis"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(hc_ts)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  hc_log "backup: $1 -> $b"
}

# hc_ours <path>: a link into HC_DATA or a wrapper this module wrote
hc_ours() {
  local t
  if [ -L "$1" ]; then
    t="$(readlink "$1")"
    case "$t" in "$HC_DATA"/*) return 0 ;; esac
    return 1
  fi
  [ -f "$1" ] && grep -q "$HC_MARK" "$1" 2>/dev/null
}

# hc_link <name> <target>: KIT_BIN_DIR/<name> -> target; a foreign file is moved to the backups dir (hc_backup)
hc_link() {
  local dst="$KIT_BIN_DIR/$1"
  mkdir -p "$KIT_BIN_DIR"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$2" ]; then return 0; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if hc_ours "$dst"; then rm -f "$dst"
    else hc_backup "$dst"; fi
  fi
  ln -s "$2" "$dst"
}

hc_state_version() { [ -f "$HC_STATE" ] && awk -v h="$1" '$1 == h { v = $2 } END { print v }' "$HC_STATE"; return 0; }
hc_state_names() { [ -f "$HC_STATE" ] && awk '{ print $1 }' "$HC_STATE"; return 0; }
hc_state_set() { # harness version
  mkdir -p "$(dirname "$HC_STATE")"
  { [ -f "$HC_STATE" ] && awk -v h="$1" '$1 != h' "$HC_STATE"; echo "$1 $2"; } >"$HC_STATE.new"
  mv "$HC_STATE.new" "$HC_STATE"
}
hc_state_del() {
  [ -f "$HC_STATE" ] || return 0
  awk -v h="$1" '$1 != h' "$HC_STATE" >"$HC_STATE.new" && mv "$HC_STATE.new" "$HC_STATE"
  [ -s "$HC_STATE" ] || rm -f "$HC_STATE"
}
