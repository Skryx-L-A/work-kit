#!/usr/bin/env bash
# Remove what install.sh added. Settings in ~/.config/quassel and the dictation history in
# ~/.local/share/quassel stay unless --purge. Root steps are reverted separately:
#   sudo bash root-steps.sh --undo
# Removes the current names (work-kit-quassel-*) and the names used before the rename.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../00-python/lib.sh
. "$HERE/../00-python/lib.sh"

MARK="work-kit:80-quassel"
KQ="${QUASSEL_KIT_HOME:-$KIT_DATA_DIR/quassel}"
BIN="$KIT_BIN_DIR"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/quassel"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
# shellcheck source=names.sh
. "$HERE/names.sh"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

quassel_legacy_stop        # old names, only what carries our marker
if command -v systemctl >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # QK_UNITS is a word list
  systemctl --user stop $QK_UNITS 2>/dev/null
  systemctl --user disable work-kit-quassel-daemon 2>/dev/null
fi
"$KIT_BIN_DIR/work-kit-quassel-dictate" cancel 2>/dev/null

# remove only files that carry our marker
rm_marked() { [ -f "$1" ] && grep -q "$MARK" "$1" && rm -f "$1" && kit_log "removed $1"; }
for f in $QK_BINS; do rm_marked "$KIT_BIN_DIR/$f"; done
for u in $QK_UNITS; do rm_marked "$UNITS/$u.service"; done
rm_marked "$APPS/$QK_DESKTOP"
quassel_legacy_remove      # old names: backed up, then removed (also reloads systemd)
command -v systemctl >/dev/null 2>&1 && { systemctl --user daemon-reload 2>/dev/null || true; }

# icons are ours only if the app is not installed some other way
if [ ! -d "$HOME/.local/lib/quassel" ]; then
  rm -f "$ICONS/scalable/apps/$QK_ICON.svg" "$ICONS"/*/apps/"$QK_ICON".png
fi

# server.env points into $KQ; drop it only when it does
if [ -f "$CONF/server.env" ] && grep -q "^SERVER_BIN=$KQ/" "$CONF/server.env"; then
  rm -f "$CONF/server.env" && kit_log "removed $CONF/server.env"
fi

if command -v gsettings >/dev/null 2>&1 \
   && gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null \
      | grep -q work-kit-quassel; then
  bash "$HERE/shortcut.sh" --remove
fi

rm -rf "$KQ" && kit_log "removed $KQ"
if [ "$PURGE" = 1 ]; then
  rm -rf "$CONF" "${XDG_DATA_HOME:-$HOME/.local/share}/quassel"
  kit_log "removed settings and history"
fi
kit_log "Quassel removed. Root steps (if applied): sudo bash $HERE/root-steps.sh --undo"
