# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this file
# Shared by install.sh and uninstall.sh of 01-prereqs. Source it, do not execute it.
# Needs only bash, coreutils, grep, sed, awk (all in every Ubuntu install).

PQ_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$PQ_HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
KIT_BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
KIT_DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
PQ_OFF="$KIT_OFFLINE/prereqs"
PQ_DATA="$KIT_DATA_DIR/prereqs"          # unpacked packages, toolchain sysroot, python, node, state
PQ_ROOT="$PQ_DATA/root"
PQ_SYSROOT="$PQ_DATA/sysroot"
PQ_STATE="$PQ_DATA/installed"            # lines: <item> <user|sudo>
PQ_VSCODE="$KIT_DATA_DIR/vscode"
PQ_APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
PQ_MARK="work-kit:01-prereqs"

pq_log() { printf '[prereqs] %s\n' "$*"; }
pq_warn() { printf '[prereqs] WARNING: %s\n' "$*" >&2; }
pq_die() { printf '[prereqs] ERROR: %s\n' "$*" >&2; exit 1; }

# pq_backup FILE: move FILE to $KIT_DATA_DIR/backups/01-prereqs/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
pq_backup() {
  local dir b
  dir="$KIT_DATA_DIR/backups/01-prereqs"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  pq_log "backup: $1 -> $b"
}

# pq_items: print "id|default|user|packages|commands|description" per item, fields trimmed.
pq_items() {
  grep -vE '^[[:space:]]*(#|$)' "$PQ_HERE/items.conf" \
    | awk -F'|' '{ for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
                   printf "%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6 }'
}

pq_field() { # pq_field <item> <n>: field n (1-based) of an item, empty if the item is unknown
  pq_items | awk -F'|' -v id="$1" -v n="$2" '$1 == id { print $n; exit }'
}

pq_known() { pq_items | cut -d'|' -f1 | grep -qx -- "$1"; }

pq_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# pq_codename: Ubuntu release codename of this machine (UBUNTU_CODENAME covers derivatives).
pq_codename() {
  [ -n "${PREREQS_CODENAME:-}" ] && { echo "$PREREQS_CODENAME"; return; }
  [ -r /etc/os-release ] || return 0
  (
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  )
}

# pq_is_ours <file>: file is a wrapper or entry this module wrote.
pq_is_ours() { [ -f "$1" ] && grep -q "$PQ_MARK" "$1" 2>/dev/null; }

pq_state_items() { [ -f "$PQ_STATE" ] && awk '{ print $1 }' "$PQ_STATE" | sort -u; return 0; }
pq_state_mode() { [ -f "$PQ_STATE" ] && awk -v i="$1" '$1 == i { m = $2 } END { print m }' "$PQ_STATE"; return 0; }
pq_state_fingerprint() { [ -f "$PQ_STATE" ] && awk -v i="$1" '$1 == i { f = $3 } END { print f }' "$PQ_STATE"; return 0; }
pq_state_set() { # item mode fingerprint
  mkdir -p "$PQ_DATA"
  { [ -f "$PQ_STATE" ] && awk -v i="$1" '$1 != i' "$PQ_STATE"; echo "$1 $2${3:+ $3}"; } >"$PQ_STATE.new"
  mv "$PQ_STATE.new" "$PQ_STATE"
}
pq_state_del() {
  [ -f "$PQ_STATE" ] || return 0
  awk -v i="$1" '$1 != i' "$PQ_STATE" >"$PQ_STATE.new" && mv "$PQ_STATE.new" "$PQ_STATE"
}
