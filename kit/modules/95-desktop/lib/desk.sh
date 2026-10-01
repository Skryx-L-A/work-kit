# shellcheck shell=bash
# Shared helpers of module 95-desktop (sourced by install.sh, uninstall.sh and kit-desk).
# Every dconf change goes through kd_write / kd_list_add / kd_list_remove, which journal the
# original value first, so uninstall.sh can put back exactly what was there before.
# Plain bash 3.2+ (no associative arrays), coreutils, sed, grep.
# shellcheck disable=SC2034  # paths are used by the scripts that source this file

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
KIT_DATA="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
DESK_DATA="$KIT_DATA/desktop"
DESK_STATE="$DESK_DATA/state"
DESK_SHARE="$DESK_DATA/share"
DESK_BACKUP="$DESK_DATA/backup"
DESK_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/desktop"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
JOURNAL="$DESK_STATE/dconf-journal.tsv"
LISTJ="$DESK_STATE/dconf-lists.tsv"
FILES="$DESK_STATE/files.tsv"
CONFIGS="$DESK_STATE/config-hashes.tsv"
REPORT="$DESK_STATE/last-report.txt"
PENDING="$DESK_STATE/pending-login.tsv"
FINISH_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/work-kit-desktop-finish-login.desktop"
KD_DEFER=0
DRY_RUN="${DRY_RUN:-0}"
TAB="$(printf '\t')"

log() { printf '[desktop] %s\n' "$*"; }
warn() { printf '[desktop] WARNING: %s\n' "$*" >&2; }
die() { printf '[desktop] ERROR: %s\n' "$*" >&2; exit 1; }
report() { log "$*"; [ "$DRY_RUN" = 1 ] || printf '%s\n' "$*" >>"$REPORT"; }
run() { if [ "$DRY_RUN" = 1 ]; then log "dry-run: $*"; else "$@"; fi; }
stamp() { date +%Y%m%d%H%M%S; }

desk_init_state() {
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$DESK_STATE" "$DESK_BACKUP"
  touch "$JOURNAL" "$LISTJ" "$FILES" "$CONFIGS"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---- GNOME detection -------------------------------------------------------------------
gnome_major() {
  have gnome-shell || return 1
  gnome-shell --version 2>/dev/null | sed -n 's/^GNOME Shell \([0-9][0-9]*\).*/\1/p'
}

# ---- desktop detection ------------------------------------------------------------------
# Desktops of the Ubuntu flavours that 95-desktop does not support: XDG_CURRENT_DESKTOP entry,
# session process, and the name shown to the user. Checked before GNOME, because Budgie reports
# "Budgie:GNOME", GNOME Flashback "GNOME-Flashback:GNOME" and Unity "Unity:Unity7:ubuntu".
DESK_UNSUPPORTED='budgie|budgie-panel|Budgie (Ubuntu Budgie)
x-cinnamon|cinnamon|Cinnamon (Ubuntu Cinnamon)
cinnamon|cinnamon|Cinnamon (Ubuntu Cinnamon)
mate|mate-session|MATE (Ubuntu MATE)
xfce|xfce4-session|Xfce (Xubuntu)
lxqt|lxqt-session|LXQt (Lubuntu)
lxde|lxsession|LXDE
unity|unity-panel-service|Unity (Ubuntu Unity)
ukui|ukui-session|UKUI (Ubuntu Kylin)
gnome-flashback|gnome-flashback|GNOME Flashback (no GNOME Shell)
pantheon|gala|Pantheon
deepin|startdde|Deepin
enlightenment|enlightenment|Enlightenment
lomiri|lomiri|Lomiri'
DESK_NAME=""

# desk_detect: sets DESK_KIND to gnome | kde | other | unsupported (DESK_NAME then names the
# desktop; no subshell, so both survive): the running session first, then the running session
# processes, then what is installed
desk_detect() {
  local cur c key proc name
  cur="$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$cur" ]; then
    for c in $(printf '%s' "$cur" | tr ':' ' '); do
      while IFS='|' read -r key proc name; do
        [ "$c" = "$key" ] && { DESK_NAME="$name"; DESK_KIND=unsupported; return; }
      done <<<"$DESK_UNSUPPORTED"
    done
    case ":$cur:" in
      *:gnome:*|*:ubuntu:*|*gnome*) DESK_KIND=gnome; return ;;
      *:kde:*|*plasma*) DESK_KIND=kde; return ;;
    esac
    DESK_NAME="${XDG_CURRENT_DESKTOP}"; DESK_KIND=unsupported; return
  fi
  if have pgrep; then
    if pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1; then DESK_KIND=gnome; return; fi
    if pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then DESK_KIND=kde; return; fi
    while IFS='|' read -r key proc name; do
      # the kernel keeps 15 characters of a process name (unity-panel-service)
      pgrep -u "$(id -u)" -x "$(printf '%.15s' "$proc")" >/dev/null 2>&1 && { DESK_NAME="$name"; DESK_KIND=unsupported; return; }
    done <<<"$DESK_UNSUPPORTED"
  fi
  if have gnome-shell; then DESK_KIND=gnome; return; fi
  if have plasmashell; then DESK_KIND=kde; return; fi
  while IFS='|' read -r key proc name; do
    have "$proc" && { DESK_NAME="$name"; DESK_KIND=unsupported; return; }
  done <<<"$DESK_UNSUPPORTED"
  DESK_KIND=other
}
DESK_KIND=""

# ---- keyboard layout -----------------------------------------------------------------------
# kb_layout <gnome|kde>: de for a German or Austrian QWERTZ layout, else us. GNOME: the active input
# source (first of mru-sources, else of sources); KDE: the first layout of kxkbrc when layouts are
# configured there; both fall back to the system layout (/etc/default/keyboard). KIT_KB_LAYOUT
# overrides (tests). Only the key names and KDE's shifted keys depend on it: GNOME binds key
# symbols, which follow the active layout by themselves.
kb_layout() {
  local l="${KIT_KB_LAYOUT:-}" f="${XDG_CONFIG_HOME:-$HOME/.config}/kxkbrc" v
  if [ -z "$l" ] && [ "$1" = kde ] && [ -f "$f" ] && grep -q '^Use=true' "$f"; then
    l="$(sed -n 's/^LayoutList=//p' "$f" | head -n 1)"
  fi
  if [ -z "$l" ] && [ "$1" = gnome ] && have gsettings; then
    for v in mru-sources sources; do
      l="$(gsettings get org.gnome.desktop.input-sources "$v" 2>/dev/null | sed -n "s/^[^(]*('xkb', '\([^']*\)'.*/\1/p")"
      [ -n "$l" ] && break
    done
  fi
  [ -n "$l" ] || l="$(sed -n 's/^XKBLAYOUT=//p' "${KIT_KEYBOARD_FILE:-/etc/default/keyboard}" 2>/dev/null | tr -d '"' | head -n 1)"
  case "$l" in de*|at*) echo de ;; *) echo us ;; esac
}

# ---- dconf / gsettings access ------------------------------------------------------------
# Paths are dconf paths (/org/gnome/...). Without the dconf CLI the path is mapped to a
# GSettings schema and key; extension schemas are looked up in the installed extensions.
gs_target() { # path -> "schema<TAB>key<TAB>schemadir"
  local path="$1" dir key schema sdir="" f
  dir="${path%/*}"; key="${path##*/}"
  case "$dir" in
    /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/*)
      schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$dir/" ;;
    *) schema="$(printf '%s' "${dir#/}" | tr '/' '.')" ;;
  esac
  case "$schema" in
    org.gnome.shell.extensions.*)
      for f in "$EXT_DIR"/*/schemas/*.gschema.xml; do
        [ -f "$f" ] || continue
        if grep -q "id=\"$schema\"" "$f"; then sdir="$(dirname "$f")"; break; fi
      done ;;
  esac
  printf '%s\t%s\t%s\n' "$schema" "$key" "$sdir"
}

gs() { # gs <schemadir> <gsettings args...>
  local sdir="$1"; shift
  if [ -n "$sdir" ]; then gsettings --schemadir "$sdir" "$@"; else gsettings "$@"; fi
}

kd_read() { # prints the user value, empty when unset (dconf) / the effective value (gsettings)
  local t schema key sdir
  if have dconf; then dconf read "$1" 2>/dev/null; return 0; fi
  have gsettings || return 0
  t="$(gs_target "$1")"; IFS="$TAB" read -r schema key sdir <<<"$t"
  gs "$sdir" get "$schema" "$key" 2>/dev/null || true
}

# kd_effective: user value or, when unset, the schema default (via gsettings when possible)
kd_effective() {
  local v t schema key sdir
  v="$(kd_read "$1")"
  if [ -z "$v" ] && have gsettings; then
    t="$(gs_target "$1")"; IFS="$TAB" read -r schema key sdir <<<"$t"
    v="$(gs "$sdir" get "$schema" "$key" 2>/dev/null || true)"
  fi
  printf '%s' "$v"
}

# kd_writable: false only when GSettings positively reports a locked key
kd_writable() {
  local t schema key sdir w
  have gsettings || return 0
  t="$(gs_target "$1")"; IFS="$TAB" read -r schema key sdir <<<"$t"
  w="$(gs "$sdir" writable "$schema" "$key" 2>/dev/null || echo unknown)"
  [ "$w" != "false" ]
}

LOCKED_KEYS=""
kd_journal() { # record the original value once
  local path="$1" v
  [ "$DRY_RUN" = 1 ] && return 0
  grep -q "^$path$TAB" "$JOURNAL" 2>/dev/null && return 0
  v="$(kd_read "$path")"
  # dconf distinguishes "unset" (schema default); gsettings only knows the effective value
  if [ -z "$v" ]; then printf '%s\tunset\t\n' "$path" >>"$JOURNAL"
  else printf '%s\tset\t%s\n' "$path" "$v" >>"$JOURNAL"; fi
}

# kd_defer <op> <path> <value>: with KD_DEFER=1 a change is queued instead of made; `kit-desk
# finish-login` replays the queue at the next login (op: write | add | remove).
kd_defer() {
  if ! kd_writable "$2"; then
    LOCKED_KEYS="$LOCKED_KEYS $2"; report "locked by policy, not changed: $2"; return 1
  fi
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: at next login: $1 $2 $3"; return 0; fi
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$PENDING"
}

kd_write() { # kd_write <path> <gvariant value>; returns 1 when locked or failed
  local path="$1" value="$2" t schema key sdir
  # KD_FORCE=1: write (or queue) even when the key already has the value (a value another
  # extension holds only while it runs)
  [ "$KD_DEFER" = 1 ] && { [ "${KD_FORCE:-0}" = 1 ] || [ "$(kd_read "$path")" != "$value" ]; } &&
    { kd_defer write "$path" "$value"; return; }
  if ! kd_writable "$path"; then
    LOCKED_KEYS="$LOCKED_KEYS $path"; report "locked by policy, not changed: $path"; return 1
  fi
  [ "${KD_FORCE:-0}" != 1 ] && [ "$(kd_read "$path")" = "$value" ] && return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: set $path = $value"; return 0; fi
  kd_journal "$path"
  if have dconf; then
    dconf write "$path" "$value" 2>/dev/null && return 0
  elif have gsettings; then
    t="$(gs_target "$path")"; IFS="$TAB" read -r schema key sdir <<<"$t"
    gs "$sdir" set "$schema" "$key" "$value" 2>/dev/null && return 0
  fi
  LOCKED_KEYS="$LOCKED_KEYS $path"; report "could not write (locked or schema missing): $path"
  return 1
}

kd_reset() { # used by uninstall
  local t schema key sdir
  if have dconf; then dconf reset "$1" 2>/dev/null || true; return 0; fi
  have gsettings || return 0
  t="$(gs_target "$1")"; IFS="$TAB" read -r schema key sdir <<<"$t"
  gs "$sdir" reset "$schema" "$key" 2>/dev/null || true
}

kd_raw_write() { # write without journal (uninstall)
  local t schema key sdir
  if have dconf; then dconf write "$1" "$2" 2>/dev/null; return; fi
  t="$(gs_target "$1")"; IFS="$TAB" read -r schema key sdir <<<"$t"
  gs "$sdir" set "$schema" "$key" "$2" 2>/dev/null
}

# ---- string lists (GVariant "as") ------------------------------------------------------
gv_items() { # "['a', 'b']" -> one item per line
  printf '%s' "$1" | sed -e 's/^@as //' -e 's/^\[//' -e 's/\]$//' | tr ',' '\n' |
    sed -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*\$//" | grep -v '^[[:space:]]*$' || true
}
gv_list() { # items on stdin -> "['a', 'b']" (or "@as []")
  local out="" item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    out="$out${out:+, }'$item'"
  done
  if [ -z "$out" ]; then printf '@as []'; else printf '[%s]' "$out"; fi
}

kd_list_add() { # kd_list_add <path> <item>
  local path="$1" item="$2" cur
  cur="$(gv_items "$(kd_effective "$path")")"
  printf '%s\n' "$cur" | grep -qxF "$item" && return 0
  if [ "$KD_DEFER" = 1 ]; then kd_defer add "$path" "$item"; return; fi
  if kd_write "$path" "$( { printf '%s\n' "$cur"; printf '%s\n' "$item"; } | gv_list)"; then
    [ "$DRY_RUN" = 1 ] || printf '%s\tadded\t%s\n' "$path" "$item" >>"$LISTJ"
  fi
}

kd_list_remove() {
  local path="$1" item="$2" cur
  cur="$(gv_items "$(kd_effective "$path")")"
  printf '%s\n' "$cur" | grep -qxF "$item" || return 0
  if [ "$KD_DEFER" = 1 ]; then kd_defer remove "$path" "$item"; return; fi
  if kd_write "$path" "$(printf '%s\n' "$cur" | { grep -vxF "$item" || true; } | gv_list)"; then
    [ "$DRY_RUN" = 1 ] || printf '%s\tremoved\t%s\n' "$path" "$item" >>"$LISTJ"
  fi
}

# ---- files ---------------------------------------------------------------------------------
# desk_backup <path>: move <path> to $KIT_DATA/backups/95-desktop/<path relative to $HOME>.bak-<ts>,
# write the original path into <backup>.origin, print the backup path. Nothing lands beside <path>.
DESK_BAK_ROOT="$KIT_DATA/backups/95-desktop"
desk_backup() {
  local path="$1" rel b
  case "$path" in "$HOME"/*) rel="${path#"$HOME"/}" ;; *) rel="${path#/}" ;; esac
  b="$DESK_BAK_ROOT/$rel.bak-$(stamp)"
  while [ -e "$b" ] || [ -L "$b" ]; do b="$b-1"; done
  mkdir -p "$(dirname "$b")"
  mv "$path" "$b"
  printf '%s\n' "$path" >"$b.origin"
  log "backup: $path -> $b" >&2
  printf '%s' "$b"
}

# desk_put <src> <dst>: install a file; an existing different file goes to desk_backup.
desk_put() {
  local src="$1" dst="$2" bak="-"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then return 0; fi
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: install $dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  # a file this module installed earlier (re-run after a kit update) is replaced without a backup;
  # uninstall.sh still knows the user's original from the first record
  if { [ -e "$dst" ] || [ -L "$dst" ]; } && ! grep -q "^$dst$TAB" "$FILES" 2>/dev/null; then
    bak="$(desk_backup "$dst")"
  fi
  rm -f "$dst"
  cp "$src" "$dst"
  desk_record "$dst" "$bak"
}

desk_record() { # remember a created path (and its backup) for uninstall.sh
  [ "$DRY_RUN" = 1 ] && return 0
  grep -q "^$1$TAB" "$FILES" 2>/dev/null || printf '%s\t%s\n' "$1" "${2:--}" >>"$FILES"
}

desk_ours() { grep -q "^$1$TAB" "$FILES" 2>/dev/null; } # desk_ours <path>: this module installed it

desk_hash() { # desk_hash <file>: sha256 of its content
  if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# config-hashes.tsv: <path> TAB <sha256 of the content this module wrote there last>
desk_config_hash() { awk -F '\t' -v p="$1" '$1 == p {h = $2} END {print h}' "$CONFIGS" 2>/dev/null || true; }

desk_config_note() { # desk_config_note <path>: record what this module wrote there now
  [ "$DRY_RUN" = 1 ] && return 0
  local h tmp; h="$(desk_hash "$1")"; tmp="$CONFIGS.new"
  { awk -F '\t' -v p="$1" '$1 != p' "$CONFIGS" 2>/dev/null; printf '%s\t%s\n' "$1" "$h"; } >"$tmp"
  mv "$tmp" "$CONFIGS"
}

# ---- themes --------------------------------------------------------------------------------
theme_get() { # theme_get <theme.toml> <key>
  sed -n "s/^$2 = \"\\(.*\\)\"\$/\\1/p" "$1" | head -n 1
}

theme_render() { # theme_render <theme.toml> <template> <name> -> stdout
  local toml="$1" tpl="$2" name="$3" line key val out
  out="$(cat "$tpl")"
  while IFS= read -r line; do
    case "$line" in \#*|'') continue ;; esac
    key="${line%% = *}"; val="${line#* = \"}"; val="${val%\"}"
    out="${out//\{\{ $key \}\}/$val}"
  done <"$toml"
  out="${out//\{\{ name \}\}/$name}"
  printf '%s\n' "$out"
}
