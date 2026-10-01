#!/usr/bin/env bash
# Install Quassel (local dictation) offline, without sudo, from kit/offline/quassel.
# Usage: install.sh [--model small-q5_1|medium-q5_0]
# Keyboard-level features (global Ctrl+Meta hotkey, typing into windows) additionally need
# root-steps.sh once; without it, use `work-kit-quassel-dictate` on a desktop shortcut (see README);
# on GNOME the install binds Ctrl+Alt+D for it (shortcut.sh --ensure).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../00-python/lib.sh
. "$HERE/../00-python/lib.sh"

MODEL="small-q5_1"
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="${2:?--model needs a value}"; shift ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) kit_die "unknown option: $1"; exit 2 ;;
  esac
  shift
done

MARK="work-kit:80-quassel"
OFF="$KIT_OFFLINE/quassel"
KQ="${QUASSEL_KIT_HOME:-$KIT_DATA_DIR/quassel}"
BIN="$KIT_BIN_DIR"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/quassel"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
fail() { kit_die "$*"; exit 1; }
# shellcheck source=names.sh
. "$HERE/names.sh"

# --- checks -----------------------------------------------------------------------------
[ "$(id -u)" != 0 ] || fail "run as your normal user, not as root"
[ "$(uname -s)/$(uname -m)" = "Linux/x86_64" ] || [ -n "${QUASSEL_KIT_ANY_HOST:-}" ] \
  || fail "this module targets Linux x86_64"
[ -d "$OFF" ] || fail "missing $OFF (run build/build-offline.sh on the build host)"
[ -f "$OFF/models/ggml-$MODEL.bin" ] || fail "model $MODEL is not in $OFF/models"
kit_log "checking offline files against fetch.lock"
KIT_OFFLINE="$KIT_OFFLINE" bash "$HERE/fetch.sh" --verify >/dev/null \
  || fail "offline/quassel does not match fetch.lock; run: bash $HERE/fetch.sh --verify"
kit_require_uv || exit 1

# An install over a kit from before the rename (old names: see names.sh): stop the old
# units first; their files are moved away at the end (step 7), once the new ones are in place.
quassel_legacy_stop

# write_marked <target> <mode>: write stdin to target; an existing file without our marker is
# backed up first (user edits are never lost).
write_marked() {
  local target="$1" mode="$2" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [ -e "$target" ] && ! grep -q "$MARK" "$target" 2>/dev/null; then kit_backup "$target" 80-quassel; fi
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
  chmod "$mode" "$target"
}

extract_deb() { # deb dest
  if command -v dpkg-deb >/dev/null 2>&1; then dpkg-deb -x "$1" "$2"; return; fi
  local t
  t="$(mktemp -d)"
  (cd "$t" && ar x "$1") && tar -xf "$t"/data.tar.* -C "$2"
  rm -rf "$t"
}

mkdir -p "$KQ" "$BIN"

# --- 1. Python environment (PySide6 for the control center and the pill) --------------------
kit_log "1/7 Python venv with PySide6 (offline)"
if [ ! -x "$KQ/venv/bin/python" ]; then
  UV_PYTHON_DOWNLOADS=never kit_uv venv --quiet --python "$KIT_PYTHON_VERSION" "$KQ/venv" \
    || fail "cannot create the venv (is 00-python installed?)"
fi
# shellcheck disable=SC2086  # QUASSEL_KIT_PIP_ARGS is a word list on purpose
UV_PYTHON_DOWNLOADS=never kit_uv pip install --quiet --offline --no-index \
  --python "$KQ/venv/bin/python" --find-links "$OFF/wheels" --require-hashes \
  ${QUASSEL_KIT_PIP_ARGS:-} -r "$HERE/requirements.lock" || fail "cannot install PySide6 from $OFF/wheels"
kit_fix_lock_perms

# --- 2. App source (Quassel release, unchanged) -------------------------------------------
kit_log "2/7 Quassel app"
app_tar="$(find "$OFF/app" -name 'quassel-*.tar.gz' | head -n 1)"
rm -rf "$KQ/app.new" && mkdir -p "$KQ/app.new"
tar -xzf "$app_tar" -C "$KQ/app.new" --strip-components=1
find "$KQ/app.new" -mindepth 1 -maxdepth 1 ! -name quassel ! -name assets ! -name LICENSE \
  ! -name bin ! -name systemd ! -name desktop ! -name README.md -exec rm -rf {} +
bash "$HERE/patch-app.sh" "$KQ/app.new" >/dev/null || fail "cannot apply the name mapping to the app (patch-app.sh)"
rm -rf "$KQ/app" && mv "$KQ/app.new" "$KQ/app"
mkdir -p "$KQ/libexec"
install -m 0755 "$HERE/bin/quassel_dictate.py" "$KQ/libexec/quassel_dictate.py"
install -m 0755 "$HERE/bin/quassel_center.py" "$KQ/libexec/quassel_center.py"

# --- 3. Speech engine and models ----------------------------------------------------------
kit_log "3/7 whisper.cpp engine (CPU) and models"
rm -rf "$KQ/engine" && mkdir -p "$KQ/engine"
tar -xzf "$OFF/engine/quassel-engine-linux-cpu-x86_64.tar.gz" -C "$KQ/engine"
write_marked "$KQ/engine/cpu/run-server.sh" 0755 <<'EOF'
#!/usr/bin/env bash
# work-kit:80-quassel: bundled libraries apply to this process only
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$here${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/whisper-server" "$@"
EOF
mkdir -p "$KQ/models"
for f in "$OFF"/models/*.bin; do
  t="$KQ/models/$(basename "$f")"
  [ -f "$t" ] && cmp -s "$f" "$t" && continue
  rm -f "$t"
  ln "$f" "$t" 2>/dev/null || cp "$f" "$t"      # hard link saves ~0.7 GB on the same disk
done

# --- 4. Helper tools: ydotool 1.0.4, clipboard, notifications (unpacked, not apt-installed) -
kit_log "4/7 helper tools under $KQ"
mkdir -p "$KQ/bin"
install -m 0755 "$OFF/bin/ydotool" "$OFF/bin/ydotoold" "$KQ/bin/"
rm -rf "$KQ/sysroot" "$KQ/tools" "$KQ/qtlib" && mkdir -p "$KQ/sysroot" "$KQ/tools" "$KQ/qtlib"
for deb in "$OFF"/debs/*.deb; do extract_deb "$deb" "$KQ/sysroot"; done
# Release-specific replacements (debs/<codename>/, e.g. jammy: glibc 2.35) go over the noble set.
codename="$( (. /etc/os-release 2>/dev/null; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}") )"
if [ -n "$codename" ] && [ -d "$OFF/debs/$codename" ]; then
  for deb in "$OFF/debs/$codename"/*.deb; do
    [ -f "$deb" ] || continue
    # the noble build of the same library must not win the soname symlink
    name="$(basename "$deb" | cut -d_ -f1)"
    case "$name" in libxcb-cursor0) rm -f "$KQ/sysroot/usr/lib/x86_64-linux-gnu"/libxcb-cursor.so.* ;; esac
    extract_deb "$deb" "$KQ/sysroot"
  done
fi
LIBDIR="$KQ/sysroot/usr/lib/x86_64-linux-gnu"
for tool in wl-copy wl-paste xclip notify-send curl; do
  [ -x "$KQ/sysroot/usr/bin/$tool" ] || continue
  write_marked "$KQ/tools/$tool" 0755 <<EOF
#!/bin/sh
# $MARK: fallback, used only when the system has no $tool
LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "$KQ/sysroot/usr/bin/$tool" "\$@"
EOF
done
for so in "$LIBDIR"/libxcb-cursor.so.* "$LIBDIR"/libxcb-image.so.* \
          "$LIBDIR"/libxcb-render-util.so.* "$LIBDIR"/libxcb-util.so.*; do
  [ -e "$so" ] && ln -sf "$so" "$KQ/qtlib/"
done

# --- 5. Launchers in ~/.local/bin ------------------------------------------------------------
kit_log "5/7 launchers in $BIN"
launcher() { # name, command line after the shared environment, [help text]
  local help=""
  # Quassel's daemon, typing and pill entry points have no help option and start at once.
  [ -z "${3:-}" ] || help="case \"\${1:-}\" in -h|--help) echo '$3'; exit 0 ;; esac"
  write_marked "$BIN/$1" 0755 <<EOF
#!/usr/bin/env bash
# $MARK (generated; re-run install.sh instead of editing)
$help
KQ="$KQ"
export PYTHONPATH="\$KQ/app\${PYTHONPATH:+:\$PYTHONPATH}"
export PATH="\$KQ/bin:\$PATH:\$KQ/tools"
export QUASSEL_CENTER_CMD="$BIN/work-kit-quassel-type"
ldc="\$(command -v ldconfig || echo /sbin/ldconfig)"
if ! "\$ldc" -p 2>/dev/null | grep -q 'libxcb-cursor.so.0 '; then   # Qt needs it on X11
  export LD_LIBRARY_PATH="\$KQ/qtlib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
fi
$2
EOF
}
# shellcheck disable=SC2016  # expanded inside the generated launchers
{
  launcher work-kit-quassel-daemon 'exec "$KQ/venv/bin/python" -m quassel.daemon "$@"' \
    'usage: work-kit-quassel-daemon   Quassel hotkey daemon (normally started by work-kit-quassel-ctl start / systemd)'
  launcher work-kit-quassel-type 'exec "$KQ/venv/bin/python" "$KQ/libexec/quassel_center.py" "$@"' \
    'usage: work-kit-quassel-type   opens the Quassel control center (the app menu entry; the daemon opens it too)'
  launcher work-kit-quassel-pill 'exec "$KQ/venv/bin/python" -m quassel.pill_qt "$@"' \
    'usage: work-kit-quassel-pill   on-screen recording indicator (started by work-kit-quassel-ctl start)'
  launcher work-kit-quassel-dictate 'exec "$KQ/venv/bin/python" "$KQ/libexec/quassel_dictate.py" "$@"'
}
write_marked "$BIN/work-kit-quassel-ctl" 0755 <<EOF
#!/usr/bin/env bash
# $MARK: work-kit-quassel-ctl [toggle|start|stop|status]
set -u
cmd="\${1:-toggle}"
usage() {
  cat <<'USAGE'
usage: work-kit-quassel-ctl [toggle|start|stop|status]
  toggle   start Quassel when it is stopped, stop it when it runs (default)
  start    start the hotkey daemon, speech server and on-screen pill
  stop     stop all Quassel services
  status   show each service; exit 0 when any runs, 3 when none runs
  -h, --help   this text
USAGE
}
running() { systemctl --user is-active --quiet work-kit-quassel-daemon; }
case "\$cmd" in toggle) if running; then cmd=stop; else cmd=start; fi ;; esac
case "\$cmd" in
  -h|--help|help) usage; exit 0 ;;
  status)
    any=1
    for u in work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill; do
      st="\$(systemctl --user is-active "\$u" 2>/dev/null)" || true
      printf '%-24s %s\\n' "\$u" "\${st:-unknown}"
      [ "\$st" = active ] && any=0
    done
    [ "\$any" = 0 ] && exit 0
    exit 3 ;;
  start)
    if [ ! -w /dev/uinput ]; then
      echo "Keyboard access is not set up (see root-steps.sh). Starting only the speech server;" >&2
      echo "use 'work-kit-quassel-dictate toggle' on a desktop shortcut." >&2
      exec systemctl --user start work-kit-quassel-server
    fi
    systemctl --user start work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill ;;
  stop) systemctl --user stop work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-ydotoold work-kit-quassel-pill ;;
  *) usage >&2; exit 2 ;;
esac
EOF

# --- 6. Settings and systemd user units ---------------------------------------------------
kit_log "6/7 server.env and systemd user units"
mkdir -p "$CONF"
threads="$(nproc 2>/dev/null || echo 4)"; [ "$threads" -gt 8 ] && threads=8
SENV="$CONF/server.env"
SENV_STATE="$KQ/server.env.kit-sha256"
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
senv_new="$(mktemp)"
trap 'rm -f "$senv_new"' EXIT
cat >"$senv_new" <<EOF
SERVER_BIN=$KQ/engine/cpu/run-server.sh
MODEL_PATH=$KQ/models/ggml-$MODEL.bin
WHISPER_THREADS=$threads
WHISPER_DECODE=-nf
VAD_MODEL=$KQ/models/ggml-silero-v5.1.2.bin
EOF
old_hash="$(cat "$SENV_STATE" 2>/dev/null || true)"
if [ ! -e "$SENV" ]; then
  mv "$senv_new" "$SENV"
  sha256_of "$SENV" >"$SENV_STATE"
  kit_log "wrote $SENV"
elif [ -n "$old_hash" ] && [ "$(sha256_of "$SENV")" = "$old_hash" ] && cmp -s "$senv_new" "$SENV"; then
  rm -f "$senv_new"
  kit_log "keeping $SENV (current kit default)"
elif [ -n "$old_hash" ] && [ "$(sha256_of "$SENV")" = "$old_hash" ]; then
  mv "$senv_new" "$SENV"
  sha256_of "$SENV" >"$SENV_STATE"
  kit_log "refreshed $SENV (kit default)"
elif [ -n "$old_hash" ]; then
  mv "$senv_new" "$SENV.kit-new"
  kit_log "kept your $SENV; new kit default written to $SENV.kit-new"
else
  rm -f "$senv_new"
  kit_log "keeping pre-existing $SENV (no kit default state)"
fi
trap - EXIT

unit() { write_marked "$UNITS/$1" 0644; }
unit work-kit-quassel-server.service <<EOF
# $MARK
[Unit]
Description=Whisper.cpp speech-to-text server (for Quassel)

[Service]
Type=simple
EnvironmentFile=-%h/.config/quassel/server.env
ExecStart=/bin/sh -c 'exec "\${SERVER_BIN}" -m "\$MODEL_PATH" -t "\${WHISPER_THREADS:-4}" \${WHISPER_DECODE:--nf} \${VAD_MODEL:+--vad --vad-model "\$VAD_MODEL"} --host 127.0.0.1 --port 8765 -l auto -nt'
Restart=on-failure
RestartSec=3
EOF
unit work-kit-quassel-ydotoold.service <<EOF
# $MARK
[Unit]
Description=ydotoold (virtual keyboard for Quassel, needs root-steps.sh)
ConditionPathIsReadWrite=/dev/uinput

[Service]
Type=simple
ExecStart=$KQ/bin/ydotoold --socket-path=%t/.ydotool_socket --socket-perm=0600
Restart=on-failure
RestartSec=3
EOF
unit work-kit-quassel-daemon.service <<EOF
# $MARK
[Unit]
Description=Quassel daemon (hotkey detection for voice typing, needs root-steps.sh)
Wants=work-kit-quassel-ydotoold.service work-kit-quassel-pill.service
After=work-kit-quassel-ydotoold.service

[Service]
Type=simple
ExecStart=$BIN/work-kit-quassel-daemon
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
unit work-kit-quassel-pill.service <<EOF
# $MARK
[Unit]
Description=Quassel pill overlay

[Service]
Type=simple
ExecStart=$BIN/work-kit-quassel-pill
Restart=on-failure
RestartSec=3
EOF
if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null; then
  :
else
  kit_warn "systemctl --user is not available; the speech server must be started by hand"
fi

# --- 7. Launcher entry and icons ------------------------------------------------------------
kit_log "7/7 application entry"
{
  sed "s|@HOME@/.local/bin|$BIN|g; s|@HOME@|$HOME|g" "$KQ/app/desktop/quassel.desktop.in" \
    | sed 's/^Actions=.*/Actions=start;stop;dictate;/' \
    | sed 's|^Comment=.*|Comment=Local voice typing, fully offline / Lokale Spracheingabe, offline|'
  printf '\n[Desktop Action dictate]\nName=Dictate to clipboard (start/stop)\nExec=%s toggle\n' "$BIN/work-kit-quassel-dictate"
  printf '# %s\n' "$MARK"
} | write_marked "$APPS/work-kit-quassel.desktop" 0644
mkdir -p "$ICONS/scalable/apps"
install -m 0644 "$KQ/app/assets/quassel.svg" "$ICONS/scalable/apps/work-kit-quassel.svg"
for sz in 48 64 128 256; do
  [ -f "$KQ/app/assets/icons/quassel-$sz.png" ] || continue
  mkdir -p "$ICONS/${sz}x${sz}/apps"
  install -m 0644 "$KQ/app/assets/icons/quassel-$sz.png" "$ICONS/${sz}x${sz}/apps/work-kit-quassel.png"
done
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true

# Old names (before the rename): back up and remove, keep the user's setup working.
quassel_legacy_remove
quassel_legacy_shortcut
if [ "$LEGACY_DAEMON_ENABLED" = 1 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl --user enable work-kit-quassel-daemon 2>/dev/null \
    && kit_log "work-kit-quassel-daemon enabled (the old daemon was enabled)" \
    || kit_warn "could not enable work-kit-quassel-daemon; run: systemctl --user enable work-kit-quassel-daemon"
fi
quassel_legacy_root_hint

# --- status -------------------------------------------------------------------------------
kit_log "installed: $KQ (model $MODEL)"
if [ -w /dev/uinput ] && id -nG | tr ' ' '\n' | grep -qx input; then
  kit_log "keyboard mode ready: open 'Quassel' and switch it on, or run: work-kit-quassel-ctl start"
else
  # Clipboard mode: on GNOME bind Ctrl+Alt+D right away (user setting, no root; a key the user
  # chose earlier stays). Needs the desktop session's settings service; over ssh or on another
  # desktop the hint below tells what to do by hand. QUASSEL_KIT_NO_SHORTCUT=1 skips it (tests).
  shortcut_done=0
  schemas=""
  [ -z "${QUASSEL_KIT_NO_SHORTCUT:-}" ] && command -v gsettings >/dev/null 2>&1 && schemas="$(gsettings list-schemas 2>/dev/null || true)"
  if printf '%s\n' "$schemas" | grep -qx org.gnome.settings-daemon.plugins.media-keys; then
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && sc_out="$(bash "$HERE/shortcut.sh" --ensure 2>&1)"; then
      shortcut_done=1
      kit_log "clipboard mode (no root): $(printf '%s\n' "$sc_out" | head -n 1); press it to record, again to stop, then paste with Ctrl+V"
    fi
  fi
  [ "$shortcut_done" = 1 ] || kit_log "clipboard mode (no root): bash $HERE/shortcut.sh   # binds work-kit-quassel-dictate to a key"
  kit_log "keyboard mode (hold Ctrl+Meta) needs one-time root steps: see $HERE/README.md"
fi
