#!/usr/bin/env bash
# Real install.sh / uninstall.sh over an old-name install, in a throwaway HOME, with a synthetic
# offline folder (tiny fake app, engine, models, wheels), a stub uv and a recording systemctl.
# No network, no root, no real service is touched. Needs: bash, tar, perl.
# Usage: bash tests/test-upgrade.sh
# Env:   QUASSEL_OLD_MODULE  a checkout of the module from before the rename (dir with install.sh);
#                            its install.sh creates the old install instead of hand-made fixtures:
#                            git archive <rev> kit/modules/80-quassel | tar -x -C <dir>
# shellcheck disable=SC2015,SC2016,SC2034  # "A && ok || bad"; quoted conditions
set -uo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_SRC="$(cd "$MOD/../.." && pwd)"
W="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

for t in tar perl; do command -v "$t" >/dev/null 2>&1 || { echo "skip: $t not found"; exit 0; }; done

# --- a kit tree with the module under test, and a fake offline folder -------------------------------
make_kit() { # dest module-src
  mkdir -p "$1/modules" "$1/lib"
  cp -R "$KIT_SRC/modules/00-python" "$1/modules/"
  cp -R "$KIT_SRC/lib/kit-python" "$1/lib/"
  cp -R "$2" "$1/modules/80-quassel"
  rm -rf "$1/modules/80-quassel/tests"
  printf '#!/bin/sh\nexit 0\n' >"$1/modules/80-quassel/fetch.sh"      # offline files are fake here
}
OFFL="$W/offline/quassel"
mkdir -p "$OFFL/app" "$OFFL/engine" "$OFFL/models" "$OFFL/bin" "$OFFL/debs" "$OFFL/wheels" "$W/src/quassel-x"
S="$W/src/quassel-x"
mkdir -p "$S/quassel" "$S/desktop" "$S/assets/icons" "$S/bin" "$S/systemd"
cat >"$S/quassel/center.py" <<'PY'
UNITS_START = ["quasseld", "quassel-server", "quassel-pill"]
app.setDesktopFileName("quassel")
PY
: >"$S/quassel/daemon.py"; : >"$S/quassel/pill_qt.py"; : >"$S/LICENSE"; : >"$S/README.md"
printf 'x' >"$S/assets/quassel.svg"; printf 'x' >"$S/assets/icons/quassel-48.png"
cat >"$S/desktop/quassel.desktop.in" <<'D'
[Desktop Entry]
Name=Quassel
Exec=@HOME@/.local/bin/quassel-type
Icon=@HOME@/.local/share/icons/hicolor/scalable/apps/quassel-voice.svg
StartupWMClass=quassel
Actions=start;stop;

[Desktop Action start]
Exec=@HOME@/.local/bin/quassel-ctl start
D
tar -czf "$OFFL/app/quassel-x.tar.gz" -C "$W/src" quassel-x
mkdir -p "$W/eng/cpu"; printf '#!/bin/sh\n' >"$W/eng/cpu/whisper-server"; chmod +x "$W/eng/cpu/whisper-server"
tar -czf "$OFFL/engine/quassel-engine-linux-cpu-x86_64.tar.gz" -C "$W/eng" cpu
: >"$OFFL/models/ggml-small-q5_1.bin"; : >"$OFFL/models/ggml-silero-v5.1.2.bin"; echo m >"$OFFL/models/ggml-small-q5_1.bin"
printf '#!/bin/sh\n' >"$OFFL/bin/ydotool"; cp "$OFFL/bin/ydotool" "$OFFL/bin/ydotoold"
mkdir -p "$W/deb/usr/bin"; printf '#!/bin/sh\n' >"$W/deb/usr/bin/xclip"; chmod +x "$W/deb/usr/bin/xclip"
tar -czf "$OFFL/debs/fake.deb" -C "$W/deb" usr      # a "deb" that the dpkg-deb stub below unpacks

# --- sandbox ---------------------------------------------------------------------------------------------
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_DATA_HOME="$W/home/.local/share"
unset QUASSEL_KIT_HOME KIT_BIN_DIR KIT_DATA_DIR KIT_OFFLINE
mkdir -p "$HOME/.local/bin" "$W/fake"
export QUASSEL_KIT_ANY_HOST=1 QUASSEL_KIT_PIP_ARGS=""
export QUASSEL_KIT_NO_SHORTCUT=1     # never touch the tester's own GNOME settings (test-shortcut.sh covers it)
export SC_LOG="$W/systemctl.log"; : >"$SC_LOG"
cat >"$W/fake/systemctl" <<'F'
#!/bin/sh
echo "$*" >>"$SC_LOG"
case "$*" in "--user is-enabled --quiet quasseld") [ -f "$SC_ENABLED" ] && exit 0 || exit 1 ;; esac
exit 0
F
export SC_ENABLED="$W/daemon-enabled"
# uv stub: `venv` makes a python stand-in, `pip install` does nothing
cat >"$HOME/.local/bin/uv" <<'F'
#!/bin/sh
case "$1" in
  venv) for a in "$@"; do d="$a"; done; mkdir -p "$d/bin"; printf '#!/bin/sh\n' >"$d/bin/python"; chmod +x "$d/bin/python" ;;
esac
exit 0
F
cat >"$W/fake/gsettings" <<'F'
#!/bin/sh
exit 1
F
printf '#!/bin/sh\n[ "$1" = -x ] && exec tar -xzf "$2" -C "$3"\nexit 1\n' >"$W/fake/dpkg-deb"
chmod +x "$W/fake/systemctl" "$HOME/.local/bin/uv" "$W/fake/gsettings" "$W/fake/dpkg-deb"
export PATH="$W/fake:$PATH"
UD="$XDG_CONFIG_HOME/systemd/user"; BK="$HOME/.local/share/work-kit/backups/80-quassel"
run_install() { # kit-dir logfile
  KIT_OFFLINE="$W/offline" bash "$1/modules/80-quassel/install.sh" >"$2" 2>&1
}

# --- 1. the old install -----------------------------------------------------------------------------------
MK="work-kit:80-quassel"
if [ -n "${QUASSEL_OLD_MODULE:-}" ] && [ -f "$QUASSEL_OLD_MODULE/install.sh" ]; then
  make_kit "$W/oldkit" "$QUASSEL_OLD_MODULE"
  run_install "$W/oldkit" "$W/old-install.log" && ok "old-name install.sh ran" || { bad "old install"; tail -n 20 "$W/old-install.log"; }
  check "old install really made the old names" '[ -f "$HOME/.local/bin/quasseld" ] && [ -f "$UD/quassel-server.service" ] && [ -f "$XDG_DATA_HOME/applications/quassel.desktop" ]'
else
  mkdir -p "$UD" "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
  for n in quasseld quassel-type quassel-pill quassel-ctl quassel-dictate; do printf '#!/bin/sh\n# %s\n' "$MK" >"$HOME/.local/bin/$n"; chmod +x "$HOME/.local/bin/$n"; done
  for u in quasseld quassel-server quassel-pill quassel-ydotoold; do printf '# %s\n[Service]\n' "$MK" >"$UD/$u.service"; done
  printf '[Desktop Entry]\n# %s\n' "$MK" >"$XDG_DATA_HOME/applications/quassel.desktop"
  : >"$XDG_DATA_HOME/icons/hicolor/scalable/apps/quassel-voice.svg"
fi
touch "$SC_ENABLED"                                  # the user had enabled quasseld
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/quassel-irc-helper"   # unrelated file next to ours
: >"$SC_LOG"

# --- 2. install the new kit over it --------------------------------------------------------------------------
make_kit "$W/newkit" "$MOD"
run_install "$W/newkit" "$W/install.log" && ok "install.sh over the old install" || { bad "install.sh"; tail -n 20 "$W/install.log"; }
KQ="$HOME/.local/share/work-kit/quassel"
for f in work-kit-quassel-daemon work-kit-quassel-type work-kit-quassel-pill work-kit-quassel-ctl work-kit-quassel-dictate; do
  check "new launcher $f" 'grep -q "$MK" "$HOME/.local/bin/$f"'
done
for u in work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill work-kit-quassel-ydotoold; do
  check "new unit $u" 'grep -q "$MK" "$UD/$u.service"'
done
check "unit files reference the new commands and units" 'grep -q "ExecStart=$HOME/.local/bin/work-kit-quassel-daemon" "$UD/work-kit-quassel-daemon.service" && grep -q "Wants=work-kit-quassel-ydotoold.service work-kit-quassel-pill.service" "$UD/work-kit-quassel-daemon.service"'
check "work-kit-quassel-type starts the kit center script, which is installed" 'grep -q "libexec/quassel_center.py" "$HOME/.local/bin/work-kit-quassel-type" && [ -x "$KQ/libexec/quassel_center.py" ]'
check "launchers point the app at the new center command" 'grep -q "QUASSEL_CENTER_CMD=\"$HOME/.local/bin/work-kit-quassel-type\"" "$HOME/.local/bin/work-kit-quassel-pill"'
check "work-kit-quassel-ctl uses the new units" 'grep -q "start work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill" "$HOME/.local/bin/work-kit-quassel-ctl" && ! grep -q "quasseld" "$HOME/.local/bin/work-kit-quassel-ctl"'
check "installed app is patched" 'grep -q "\"work-kit-quassel-daemon\"" "$KQ/app/quassel/center.py" && grep -q "setDesktopFileName(\"work-kit-quassel\")" "$KQ/app/quassel/center.py"'
check "desktop entry and icon under the new names" 'grep -q "Exec=$HOME/.local/bin/work-kit-quassel-type" "$XDG_DATA_HOME/applications/work-kit-quassel.desktop" && grep -q "work-kit-quassel-dictate toggle" "$XDG_DATA_HOME/applications/work-kit-quassel.desktop" && [ -f "$XDG_DATA_HOME/icons/hicolor/scalable/apps/work-kit-quassel.svg" ] && grep -q "apps/work-kit-quassel.svg" "$XDG_DATA_HOME/applications/work-kit-quassel.desktop"'
check "no old launcher, unit, desktop entry or icon left" 'for n in quasseld quassel-type quassel-pill quassel-ctl quassel-dictate; do [ ! -e "$HOME/.local/bin/$n" ] || exit 1; done; for u in quasseld quassel-server quassel-pill quassel-ydotoold; do [ ! -e "$UD/$u.service" ] || exit 1; done; [ ! -e "$XDG_DATA_HOME/applications/quassel.desktop" ] && [ ! -e "$XDG_DATA_HOME/icons/hicolor/scalable/apps/quassel-voice.svg" ]'
check "old units were stopped and disabled" 'for u in quasseld quassel-server quassel-pill quassel-ydotoold; do grep -qx -- "--user stop $u" "$SC_LOG" && grep -qx -- "--user disable $u" "$SC_LOG" || exit 1; done'
check "old daemon was enabled: the new one is enabled" 'grep -qx -- "--user enable work-kit-quassel-daemon" "$SC_LOG"'
check "old files are in the backups" 'ls "$BK"/quasseld.bak-* "$BK"/quassel-server.service.bak-* "$BK"/quassel.desktop.bak-* >/dev/null 2>&1'
check "an unrelated file next to ours stays" '[ -f "$HOME/.local/bin/quassel-irc-helper" ]'
nb="$(find "$HOME" -name '*.bak-*' | wc -l)"
run_install "$W/newkit" "$W/install2.log" && ok "second install.sh run" || { bad "second install"; tail -n 20 "$W/install2.log"; }
check "second run makes no new backups" '[ "$(find "$HOME" -name "*.bak-*" | wc -l)" = "$nb" ]'

# --- 2b. work-kit-quassel-ctl: help and status --------------------------------------------------------------------
CTL="$HOME/.local/bin/work-kit-quassel-ctl"
mkdir -p "$W/ctlfake"
cat >"$W/ctlfake/systemctl" <<'F'
#!/bin/sh
# only "--user is-active <unit>" is answered; SC_ACTIVE lists the running units
[ "$1 $2" = "--user is-active" ] || exit 0
case " $SC_ACTIVE " in *" $3 "*) echo active; exit 0 ;; esac
echo inactive; exit 3
F
chmod +x "$W/ctlfake/systemctl"
: >"$SC_LOG"
for a in -h --help help; do
  out="$("$CTL" $a 2>"$W/ctl.err")"; rc=$?
  check "ctl $a: usage on stdout, exit 0" '[ "$rc" = 0 ] && grep -q "^usage: work-kit-quassel-ctl \[toggle|start|stop|status\]" <<<"$out" && grep -q "status" <<<"$out" && [ ! -s "$W/ctl.err" ]'
done
check "ctl help started and stopped nothing" '[ ! -s "$SC_LOG" ]'
out="$("$CTL" bogus 2>&1 >/dev/null)"; rc=$?
check "ctl unknown verb: usage on stderr, exit 2" '[ "$rc" = 2 ] && grep -q "usage: work-kit-quassel-ctl" <<<"$out"'
out="$(SC_ACTIVE="" PATH="$W/ctlfake:$PATH" "$CTL" status)"; rc=$?
check "ctl status, nothing running: all three units listed, exit 3" '[ "$rc" = 3 ] && grep -q "work-kit-quassel-daemon *inactive" <<<"$out" && grep -q "work-kit-quassel-server *inactive" <<<"$out" && grep -q "work-kit-quassel-pill *inactive" <<<"$out"'
out="$(SC_ACTIVE="work-kit-quassel-server" PATH="$W/ctlfake:$PATH" "$CTL" status)"; rc=$?
check "ctl status, server running: exit 0" '[ "$rc" = 0 ] && grep -q "work-kit-quassel-server *active" <<<"$out" && grep -q "work-kit-quassel-daemon *inactive" <<<"$out"'

# --- 3. uninstall removes new and old names ----------------------------------------------------------------------
printf '#!/bin/sh\n# %s\n' "$MK" >"$HOME/.local/bin/quassel-type"          # an old file that came back
printf '# %s\n[Service]\n' "$MK" >"$UD/quassel-pill.service"
bash "$W/newkit/modules/80-quassel/uninstall.sh" >"$W/uninstall.log" 2>&1 && ok "uninstall.sh" || { bad "uninstall.sh"; tail -n 20 "$W/uninstall.log"; }
check "uninstall removes new names" 'for f in work-kit-quassel-daemon work-kit-quassel-type work-kit-quassel-pill work-kit-quassel-ctl work-kit-quassel-dictate; do [ ! -e "$HOME/.local/bin/$f" ] || exit 1; done; [ -z "$(ls "$UD" 2>/dev/null)" ] && [ ! -e "$XDG_DATA_HOME/applications/work-kit-quassel.desktop" ] && [ ! -e "$XDG_DATA_HOME/icons/hicolor/scalable/apps/work-kit-quassel.svg" ] && [ ! -e "$KQ" ]'
check "uninstall removes leftover old names" '[ ! -e "$HOME/.local/bin/quassel-type" ] && [ ! -e "$UD/quassel-pill.service" ]'
check "uninstall keeps the unrelated file" '[ -f "$HOME/.local/bin/quassel-irc-helper" ]'
exit "$fail"
