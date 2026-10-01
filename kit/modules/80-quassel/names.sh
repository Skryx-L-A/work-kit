#!/usr/bin/env bash
# Names installed by 80-quassel and the migration from the names used before the rename.
# Sourced by install.sh and uninstall.sh (not run on its own).
#
# The Quassel IRC project ships `quasselcore`, `quasselclient`, `quassel.desktop` and the icon
# "quassel"; the voice-typing app "Quassel" used generic names next to them. Everything the
# kit installs into the user's PATH, systemd user units, launcher and icon theme now carries the
# prefix work-kit-quassel-. The app name "Quassel" in texts stays.
#
# The sourcing script sets: MARK, BIN, UNITS, APPS, ICONS, HERE (and has kit_log/kit_backup).

# Current names.
QK_BINS="work-kit-quassel-daemon work-kit-quassel-type work-kit-quassel-pill work-kit-quassel-ctl work-kit-quassel-dictate"
QK_UNITS="work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill work-kit-quassel-ydotoold"
QK_DESKTOP="work-kit-quassel.desktop"
QK_ICON="work-kit-quassel"

# Names before the rename (kit versions up to 2026-09-25). Only files that carry our marker are
# touched under these names; the same file names may belong to a real Quassel IRC install.
OLD_BINS="quasseld quassel-type quassel-pill quassel-ctl quassel-dictate"
OLD_UNITS="quasseld quassel-server quassel-pill quassel-ydotoold"
OLD_DESKTOP="quassel.desktop"
OLD_ICON="quassel-voice"
OLD_RULE_NAME="80-quassel-uinput.rules"
OLD_MODS_NAME="quassel-uinput.conf"

LEGACY_DAEMON_ENABLED=0

# is_ours <file>: an existing regular file with our marker.
is_ours() { [ -f "$1" ] && grep -q "$MARK" "$1" 2>/dev/null; }

# quassel_legacy_stop: stop and disable the old units, cancel a running old dictation. Run
# before the files below the data directory are replaced. Records whether the old daemon
# was enabled (LEGACY_DAEMON_ENABLED=1) so the new one can be enabled in its place.
quassel_legacy_stop() {
  local u any=0
  for u in $OLD_UNITS; do is_ours "$UNITS/$u.service" && any=1; done
  if [ "$any" = 1 ] && command -v systemctl >/dev/null 2>&1; then
    is_ours "$UNITS/quasseld.service" && systemctl --user is-enabled --quiet quasseld 2>/dev/null \
      && LEGACY_DAEMON_ENABLED=1
    for u in $OLD_UNITS; do
      is_ours "$UNITS/$u.service" || continue
      systemctl --user stop "$u" 2>/dev/null
      systemctl --user disable "$u" 2>/dev/null
    done
  fi
  if is_ours "$BIN/quassel-dictate"; then "$BIN/quassel-dictate" cancel >/dev/null 2>&1 || true; fi
  return 0
}

# quassel_legacy_remove: move the old launchers, units (with drop-in directories), desktop
# entry and icons out of the way. Files go to backups/80-quassel/ (kit_backup) so that edits
# the user made survive; files without our marker are left where they are.
quassel_legacy_remove() {
  local n u f
  for n in $OLD_BINS; do is_ours "$BIN/$n" && kit_backup "$BIN/$n" 80-quassel; done
  for u in $OLD_UNITS; do
    is_ours "$UNITS/$u.service" || continue
    kit_backup "$UNITS/$u.service" 80-quassel
    [ -d "$UNITS/$u.service.d" ] && kit_backup "$UNITS/$u.service.d" 80-quassel
  done
  is_ours "$APPS/$OLD_DESKTOP" && kit_backup "$APPS/$OLD_DESKTOP" 80-quassel
  # The icon name quassel-voice is shared with the app's own installer (~/.local/lib/quassel).
  if [ ! -d "$HOME/.local/lib/quassel" ]; then
    rm -f "$ICONS/scalable/apps/$OLD_ICON.svg"
    for f in "$ICONS"/*/apps/"$OLD_ICON".png; do [ -e "$f" ] && rm -f "$f"; done
  fi
  command -v systemctl >/dev/null 2>&1 && { systemctl --user daemon-reload 2>/dev/null || true; }
  return 0
}

# quassel_legacy_shortcut: a GNOME shortcut made by shortcut.sh before the rename runs the old
# command; point it at the new one and keep its key binding.
quassel_legacy_shortcut() {
  command -v gsettings >/dev/null 2>&1 || return 0
  local item cmd binding
  item="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/"
  cmd="$(gsettings get "$item" command 2>/dev/null)" || return 0
  case "$cmd" in
    *"/quassel-dictate "*)
      binding="$(gsettings get "$item" binding 2>/dev/null | tr -d "'")"
      if [ -n "$binding" ]; then bash "$HERE/shortcut.sh" --binding "$binding" >/dev/null
      else bash "$HERE/shortcut.sh" >/dev/null; fi
      kit_log "GNOME shortcut now runs work-kit-quassel-dictate" ;;
  esac
  return 0
}

# quassel_legacy_root_hint: the udev rule and module list of root-steps.sh have new names too.
quassel_legacy_root_hint() {
  local etc="${QUASSEL_ETC:-/etc}"
  if [ -e "$etc/udev/rules.d/$OLD_RULE_NAME" ] || [ -e "$etc/modules-load.d/$OLD_MODS_NAME" ]; then
    kit_log "old root files found: run once 'sudo bash $HERE/root-steps.sh' to move them to the new names"
  fi
  return 0
}
