#!/usr/bin/env bash
# One-time root steps for Quassel's keyboard mode. Optional: without them, Quassel runs in
# clipboard mode (work-kit-quassel-dictate on a desktop shortcut). Nothing here downloads anything.
#
# Usage: sudo bash root-steps.sh [--yes]     apply (asks before changing anything)
#        sudo bash root-steps.sh --undo      revert all three steps
#        bash root-steps.sh --check          show the current state, no root needed
#
# What it changes and why:
#   1. Adds your user to the group "input".
#      Quassel's daemon reads /dev/input/event* to detect the Ctrl+Meta hotkey in every app.
#      SECURITY: every program running as your user can then read all keyboard input
#      (including passwords) and all mice/touchpads. On a managed laptop, ask IT first.
#   2. Installs /etc/udev/rules.d/80-work-kit-quassel-uinput.rules (group "input" may use /dev/uinput)
#      and /etc/modules-load.d/work-kit-quassel-uinput.conf (load the uinput module at boot).
#      ydotoold needs /dev/uinput to type the text into the focused window.
#      SECURITY: programs of group "input" can then inject keystrokes.
#   3. Loads the uinput module now and reloads udev rules.
# Log out and back in once afterwards, so the group membership takes effect.
set -euo pipefail

ETC="${QUASSEL_ETC:-/etc}"          # tests point this at a scratch directory
RULE="$ETC/udev/rules.d/80-work-kit-quassel-uinput.rules"
MODS="$ETC/modules-load.d/work-kit-quassel-uinput.conf"
# Names used before the rename; removed on apply and on --undo.
OLD_RULE="$ETC/udev/rules.d/80-quassel-uinput.rules"
OLD_MODS="$ETC/modules-load.d/quassel-uinput.conf"
RULE_TEXT='KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"'

MODE=apply
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --undo) MODE=undo ;;
    --check) MODE=check ;;
    -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# SUDO_USER only counts when really running as root; otherwise it may be stale or foreign.
if [ "$(id -u)" = 0 ]; then TARGET_USER="${SUDO_USER:-$(id -un)}"; else TARGET_USER="$(id -un)"; fi

state() {
  local g="no" r="no" m="no" u="no"
  id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx input && g="yes"
  [ -f "$RULE" ] && r="yes"
  [ -f "$MODS" ] && m="yes"
  [ -e /dev/uinput ] && u="yes"
  echo "user $TARGET_USER in group input: $g"
  echo "udev rule $RULE: $r"
  echo "module config $MODS: $m"
  [ -f "$OLD_RULE" ] && echo "old udev rule $OLD_RULE: yes (apply or --undo removes it)"
  [ -f "$OLD_MODS" ] && echo "old module config $OLD_MODS: yes (apply or --undo removes it)"
  echo "/dev/uinput present: $u"
  if [ "$(id -un)" = "$TARGET_USER" ]; then
    [ -w /dev/uinput ] && echo "/dev/uinput writable in this session: yes" \
      || echo "/dev/uinput writable in this session: no (log out and in after applying)"
  fi
}

if [ "$MODE" = check ]; then state; exit 0; fi
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo bash $0 ${MODE/apply/}" >&2; exit 1; }
[ "$TARGET_USER" != root ] || { echo "run via sudo from your normal user account" >&2; exit 1; }

if [ "$MODE" = undo ]; then
  gpasswd -d "$TARGET_USER" input 2>/dev/null || true
  rm -f "$RULE" "$MODS" "$OLD_RULE" "$OLD_MODS"
  udevadm control --reload-rules 2>/dev/null || true
  echo "reverted. Log out and back in to drop the group membership."
  exit 0
fi

sed -n '9,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
echo
if [ "$YES" != 1 ]; then
  printf 'Apply these changes for user %s? [y/N] ' "$TARGET_USER"
  read -r answer
  case "$answer" in y|Y|yes) ;; *) echo "nothing changed"; exit 1 ;; esac
fi

usermod -aG input "$TARGET_USER"
mkdir -p "$(dirname "$RULE")" "$(dirname "$MODS")"
printf '%s\n' "$RULE_TEXT" >"$RULE"
printf 'uinput\n' >"$MODS"
rm -f "$OLD_RULE" "$OLD_MODS"
modprobe uinput 2>/dev/null || echo "note: modprobe uinput failed (module may be built in)"
udevadm control --reload-rules && udevadm trigger /dev/uinput 2>/dev/null || true
echo
state
echo
echo "Done. Log out and back in once, then: work-kit-quassel-ctl start"
