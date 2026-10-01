#!/usr/bin/env bash
# Rename to work-kit-quassel-* and the upgrade path from the old names. Needs no offline files, no
# root and no systemd: systemctl, gsettings, id and the root tools are fakes in a scratch PATH.
# Usage: bash tests/test-rename.sh
# Env:   QUASSEL_APP_SRC  an unpacked Quassel app release (dir with quassel/, desktop/); patched
#                         as a copy to check patch-app.sh against the real source.
# shellcheck disable=SC2015,SC2016,SC2034  # "A && ok || bad"; quoted conditions; sourced vars
set -uo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- A. patch-app.sh on a synthetic app tree -------------------------------------------------
mk_app() { # dir
  mkdir -p "$1/quassel" "$1/desktop"
  cat >"$1/quassel/center.py" <<'PY'
UNITS_START = ["quasseld", "quassel-server", "quassel-pill"]
UNITS_STOP = ["quasseld", "quassel-server", "quassel-ydotoold"]
ICON = "~/.local/share/icons/hicolor/scalable/apps/quassel-voice.svg"
def icon(): return QIcon.fromTheme("quassel-voice")
app.setDesktopFileName("quassel")
PY
  cat >"$1/quassel/pill_qt.py" <<'PY'
CENTER_CMD = os.environ.get("QUASSEL_CENTER_CMD", "quassel-type").split()
subprocess.run(["systemctl", "--user", "start", "quasseld",
                "quassel-server"], check=False)
PY
  cat >"$1/quassel/pill.py" <<'PY'
KWIN_PLUGIN = "quassel-pill-follow"
.quassel-pill {{ background: transparent; }}
self.pillbox.add_css_class("quassel-pill")
subprocess.Popen(["quassel-type"])
PY
  printf 'SERVICE = "quassel-server.service"\n' >"$1/quassel/whisperclient.py"
  printf 'log("quassel-daemon gestartet")\nRUNDIR = os.path.join(XDG, "quassel")\n' >"$1/quassel/daemon.py"
  cat >"$1/desktop/quassel.desktop.in" <<'D'
[Desktop Entry]
Name=Quassel
Exec=@HOME@/.local/bin/quassel-type
Icon=@HOME@/.local/share/icons/hicolor/scalable/apps/quassel-voice.svg
StartupWMClass=quassel
[Desktop Action start]
Exec=@HOME@/.local/bin/quassel-ctl start
D
}
A="$W/app"; mk_app "$A"
bash "$MOD/patch-app.sh" "$A" >"$W/patch.log" 2>&1 && ok "patch-app.sh succeeds on the synthetic tree" || { bad "patch-app.sh"; cat "$W/patch.log"; }
check "units renamed in center.py" 'grep -q "UNITS_START = \[\"work-kit-quassel-daemon\", \"work-kit-quassel-server\", \"work-kit-quassel-pill\"\]" "$A/quassel/center.py" && grep -q "\"work-kit-quassel-ydotoold\"" "$A/quassel/center.py"'
check "icon name and desktop file name renamed" 'grep -q "fromTheme(\"work-kit-quassel\")" "$A/quassel/center.py" && grep -q "apps/work-kit-quassel.svg" "$A/quassel/center.py" && grep -q "setDesktopFileName(\"work-kit-quassel\")" "$A/quassel/center.py"'
check "pill command and default center command renamed" 'grep -q "\"work-kit-quassel-type\"" "$A/quassel/pill_qt.py" && grep -q "Popen(\[\"work-kit-quassel-type\"\])" "$A/quassel/pill.py"'
check "whisper service renamed" 'grep -q "work-kit-quassel-server.service" "$A/quassel/whisperclient.py"'
check "GTK CSS class and KWin plugin name untouched" 'grep -q "add_css_class(\"quassel-pill\")" "$A/quassel/pill.py" && grep -q "quassel-pill-follow" "$A/quassel/pill.py"'
check "log text, run dir and window class untouched" 'grep -q "quassel-daemon gestartet" "$A/quassel/daemon.py" && grep -q "\"quassel\")" "$A/quassel/daemon.py" && grep -q "^StartupWMClass=quassel$" "$A/desktop/quassel.desktop.in"'
check "desktop template renamed" 'grep -q "^Exec=@HOME@/.local/bin/work-kit-quassel-type$" "$A/desktop/quassel.desktop.in" && grep -q "work-kit-quassel-ctl start" "$A/desktop/quassel.desktop.in" && grep -q "apps/work-kit-quassel.svg" "$A/desktop/quassel.desktop.in"'
bash "$MOD/patch-app.sh" "$A" >/dev/null 2>&1 && ok "patch-app.sh is idempotent" || bad "patch-app.sh second run"
B="$W/app-new-literal"; mk_app "$B"; printf 'X = ["quassel-ydotoold", "%s"]\n' quassel-voice >"$B/quassel/newmod.py"
# a literal in a file the script does not rewrite must make it fail, not pass silently
if bash "$MOD/patch-app.sh" "$B" >"$W/left.log" 2>&1; then bad "leftover old name must fail"; else grep -q "newmod.py" "$W/left.log" && ok "leftover old name in another file fails and is named" || { bad "leftover message"; cat "$W/left.log"; }; fi
if [ -n "${QUASSEL_APP_SRC:-}" ] && [ -d "$QUASSEL_APP_SRC/quassel" ]; then
  R="$W/app-real"; mkdir -p "$R"; cp -R "$QUASSEL_APP_SRC/quassel" "$QUASSEL_APP_SRC/desktop" "$R/"
  if bash "$MOD/patch-app.sh" "$R" >"$W/real.log" 2>&1; then
    ok "patch-app.sh on the real app source"
    ( cd "$R" && python3 -m py_compile quassel/center.py quassel/pill.py quassel/pill_qt.py quassel/whisperclient.py ) \
      && ok "patched app modules still compile" || bad "patched app modules do not compile"
  else bad "patch-app.sh on the real app source"; cat "$W/real.log"; fi
else
  echo "skip patch-app.sh on the real app source (set QUASSEL_APP_SRC)"
fi

# --- B. names.sh: upgrade over an old install ------------------------------------------------
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_DATA_HOME="$W/home/.local/share"
unset KIT_DATA_DIR KIT_BIN_DIR QUASSEL_KIT_HOME
mkdir -p "$HOME/.local/bin" "$XDG_CONFIG_HOME/systemd/user" "$XDG_DATA_HOME/applications" "$W/fake"
export GS_DIR="$W/gs" SC_LOG="$W/systemctl.log"
: >"$SC_LOG"
cat >"$W/fake/systemctl" <<'F'
#!/bin/sh
echo "$*" >>"$SC_LOG"
case "$*" in
  "--user is-enabled --quiet quasseld") [ -f "$SC_ENABLED" ] && exit 0 || exit 1 ;;
esac
exit 0
F
cat >"$W/fake/gsettings" <<'F'
#!/bin/sh
d="$GS_DIR"; mkdir -p "$d"
f="$d/$(echo "$2 $3" | tr '/ :' '___')"
case "$1" in
  get) [ -f "$f" ] && cat "$f" || echo "@as []" ;;
  set) printf '%s\n' "$4" >"$f" ;;
  reset-recursively) : ;;
esac
F
chmod +x "$W/fake/systemctl" "$W/fake/gsettings"
export SC_ENABLED="$W/daemon-enabled"
PATH="$W/fake:$PATH"

# shellcheck source=../../00-python/lib.sh
. "$MOD/../00-python/lib.sh"
MARK="work-kit:80-quassel"
BIN="$KIT_BIN_DIR"; UNITS="$XDG_CONFIG_HOME/systemd/user"; APPS="$XDG_DATA_HOME/applications"
ICONS="$XDG_DATA_HOME/icons/hicolor"; HERE="$MOD"
# shellcheck source=../names.sh
. "$MOD/names.sh"

check "new and old name lists are disjoint" '[ -z "$(comm -12 <(printf "%s\n" $QK_BINS $QK_UNITS | sort) <(printf "%s\n" $OLD_BINS $OLD_UNITS | sort))" ]'
check "every new command and unit carries the prefix" '! printf "%s\n" $QK_BINS $QK_UNITS | grep -qv "^work-kit-quassel-"'
check "no new name is used by Quassel IRC packages" '! printf "%s\n" $QK_BINS $QK_UNITS $QK_DESKTOP | grep -qxE "quasselcore|quasselclient|quassel|quassel.desktop|quasselclient.desktop|quasselcore.service|quassel-core.service"'

# old install: marked launchers, units, desktop, icons, a drop-in and an old shortcut
for n in $OLD_BINS; do printf '#!/bin/sh\n# %s (generated)\necho old-%s\n' "$MARK" "$n" >"$BIN/$n"; chmod +x "$BIN/$n"; done
for u in $OLD_UNITS; do printf '# %s\n[Service]\nExecStart=/bin/true\n' "$MARK" >"$UNITS/$u.service"; done
mkdir -p "$UNITS/quasseld.service.d"; printf '[Service]\nEnvironment=MINE=1\n' >"$UNITS/quasseld.service.d/my.conf"
printf '[Desktop Entry]\nName=Quassel\n# %s\n' "$MARK" >"$APPS/quassel.desktop"
mkdir -p "$ICONS/scalable/apps" "$ICONS/48x48/apps"
: >"$ICONS/scalable/apps/quassel-voice.svg"; : >"$ICONS/48x48/apps/quassel-voice.png"
SC="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/"
f="$GS_DIR/$(echo "$SC command" | tr '/ :' '___')"; mkdir -p "$GS_DIR"
printf "'%s'\n" "$HOME/.local/bin/quassel-dictate toggle" >"$f"
printf "'<Super>d'\n" >"$GS_DIR/$(echo "$SC binding" | tr '/ :' '___')"
touch "$SC_ENABLED"
export DICT_LOG="$W/dictate.log"
printf '#!/bin/sh\n# %s\necho "$@" >>"$DICT_LOG"\n' "$MARK" >"$BIN/quassel-dictate"

quassel_legacy_stop
check "old daemon enable state recorded" '[ "$LEGACY_DAEMON_ENABLED" = 1 ]'
check "all four old units stopped" 'for u in $OLD_UNITS; do grep -qx -- "--user stop $u" "$SC_LOG" || exit 1; done'
check "all four old units disabled" 'for u in $OLD_UNITS; do grep -qx -- "--user disable $u" "$SC_LOG" || exit 1; done'
check "running old dictation cancelled" 'grep -qx cancel "$DICT_LOG"'
quassel_legacy_remove >"$W/rm.log" 2>&1
check "old launchers gone from PATH dir" 'for n in $OLD_BINS; do [ ! -e "$BIN/$n" ] || exit 1; done'
check "old units and drop-in gone" 'for u in $OLD_UNITS; do [ ! -e "$UNITS/$u.service" ] || exit 1; done; [ ! -e "$UNITS/quasseld.service.d" ]'
check "old desktop entry and icons gone" '[ ! -e "$APPS/quassel.desktop" ] && [ ! -e "$ICONS/scalable/apps/quassel-voice.svg" ] && [ ! -e "$ICONS/48x48/apps/quassel-voice.png" ]'
BK="$KIT_DATA_DIR/backups/80-quassel"
check "old files backed up with origin" 'for n in $OLD_BINS; do ls "$BK/$n".bak-* >/dev/null 2>&1 || exit 1; done; grep -qx "$BIN/quasseld" "$BK"/quasseld.bak-*.origin'
check "drop-in directory backed up" 'grep -rq "MINE=1" "$BK"/quasseld.service.d.bak-*/my.conf'
check "systemd reloaded after removal" 'grep -qx -- "--user daemon-reload" "$SC_LOG"'
nb="$(find "$KIT_DATA_DIR" -type f | wc -l)"
quassel_legacy_stop; quassel_legacy_remove >/dev/null 2>&1
check "second run changes nothing" '[ "$(find "$KIT_DATA_DIR" -type f | wc -l)" = "$nb" ]'

quassel_legacy_shortcut >"$W/sc.log" 2>&1
check "old GNOME shortcut points at the new command" 'grep -q "work-kit-quassel-dictate toggle" "$f"'
check "shortcut keeps its key binding" 'grep -q "<Super>d" "$GS_DIR/$(echo "$SC binding" | tr "/ :" "___")"'

# foreign files under the old names are never touched
for n in $OLD_BINS; do printf '#!/bin/sh\necho not-ours\n' >"$BIN/$n"; done
printf '[Service]\nExecStart=/bin/false\n' >"$UNITS/quasseld.service"
printf '[Desktop Entry]\nName=Quassel IRC\n' >"$APPS/quassel.desktop"
: >"$SC_LOG"
quassel_legacy_stop; quassel_legacy_remove >/dev/null 2>&1
check "foreign launchers, unit and desktop entry stay" 'grep -q not-ours "$BIN/quasseld" && grep -q not-ours "$BIN/quassel-ctl" && [ -f "$UNITS/quasseld.service" ] && grep -q "Quassel IRC" "$APPS/quassel.desktop"'
check "foreign units are not stopped or disabled" '! grep -q "stop\|disable" "$SC_LOG"'
rm -f "$BIN"/quassel* "$UNITS/quasseld.service" "$APPS/quassel.desktop"
# the app's own installer shares the icon name quassel-voice: keep the icon then
mkdir -p "$HOME/.local/lib/quassel"; : >"$ICONS/scalable/apps/quassel-voice.svg"
quassel_legacy_remove >/dev/null 2>&1
check "icon kept when the app was installed another way" '[ -e "$ICONS/scalable/apps/quassel-voice.svg" ]'
rm -rf "$HOME/.local/lib/quassel"

# --- C. root-steps.sh: old and new file names ---------------------------------------------------
ETCD="$W/etc"; mkdir -p "$ETCD/udev/rules.d" "$ETCD/modules-load.d"
: >"$ETCD/udev/rules.d/80-quassel-uinput.rules"; : >"$ETCD/modules-load.d/quassel-uinput.conf"
out="$(QUASSEL_ETC="$ETCD" bash "$MOD/root-steps.sh" --check 2>&1)"
check "--check reports the old files" 'printf "%s" "$out" | grep -q "old udev rule" && printf "%s" "$out" | grep -q "old module config"'
check "--check names the new file" 'printf "%s" "$out" | grep -q "80-work-kit-quassel-uinput.rules"'
QUASSEL_ETC="$ETCD" quassel_legacy_root_hint >"$W/hint.log" 2>&1
check "install hint for old root files" 'grep -q "root-steps.sh" "$W/hint.log"'
# run as "root" with fake id and fake system tools
for t in gpasswd usermod modprobe udevadm; do printf '#!/bin/sh\nexit 0\n' >"$W/fake/$t"; chmod +x "$W/fake/$t"; done
cat >"$W/fake/id" <<'F'
#!/bin/sh
case "$1" in -u) echo 0 ;; -un) echo tester ;; -nG) echo "tester input" ;; *) echo 0 ;; esac
F
chmod +x "$W/fake/id"
SUDO_USER=tester QUASSEL_ETC="$ETCD" bash "$MOD/root-steps.sh" --yes >"$W/apply.log" 2>&1 \
  && ok "root-steps.sh apply runs (fake root)" || { bad "root-steps.sh apply"; cat "$W/apply.log"; }
check "apply writes the new names and removes the old ones" '[ -s "$ETCD/udev/rules.d/80-work-kit-quassel-uinput.rules" ] && [ -f "$ETCD/modules-load.d/work-kit-quassel-uinput.conf" ] && [ ! -e "$ETCD/udev/rules.d/80-quassel-uinput.rules" ] && [ ! -e "$ETCD/modules-load.d/quassel-uinput.conf" ]'
: >"$ETCD/udev/rules.d/80-quassel-uinput.rules"
SUDO_USER=tester QUASSEL_ETC="$ETCD" bash "$MOD/root-steps.sh" --undo >"$W/undo.log" 2>&1 \
  && ok "root-steps.sh --undo runs (fake root)" || { bad "root-steps.sh --undo"; cat "$W/undo.log"; }
check "--undo removes new and old names" '[ -z "$(find "$ETCD" -type f)" ]'

# --- D. no old name is left in what this module installs -------------------------------------------
old='(?<![\w-])(quasseld|quassel-(type|pill|ctl|dictate|server|ydotoold|voice)|quassel\.desktop(?!\.in))(?![\w-])'
for f in install.sh shortcut.sh root-steps.sh bin/quassel_dictate.py bin/quassel_center.py; do
  hits="$(perl -ne "print \"\$ARGV:\$.: \$_\" if /$old/" "$MOD/$f")"
  [ -z "$hits" ] && ok "no old name in $f" || { bad "old name in $f"; printf '%s\n' "$hits"; }
done
exit "$fail"
