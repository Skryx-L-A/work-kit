#!/usr/bin/env bash
# Install, re-install and uninstall into a throwaway HOME; checks files, markers and backups.
# Linux: bash tests/smoke_install.sh
# macOS (layout only; Linux binaries are not run):
#   QUASSEL_KIT_ANY_HOST=1 QUASSEL_KIT_PIP_ARGS="--python-platform x86_64-manylinux_2_28" \
#   UV_PYTHON_INSTALL_DIR=~/.local/share/uv/python bash tests/smoke_install.sh
# Needs KIT_OFFLINE (default: kit/offline) with a complete quassel/ folder.
# shellcheck disable=SC2016,SC2034  # check() evaluates its quoted condition later
set -euo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_OFFLINE="${KIT_OFFLINE:-$(cd "$MOD/../.." && pwd)/offline}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share"
export UV_CACHE_DIR="$T/uv-cache"
unset QUASSEL_KIT_HOME KIT_BIN_DIR KIT_DATA_DIR
export QUASSEL_KIT_NO_SHORTCUT=1     # never touch the tester's own GNOME settings
mkdir -p "$HOME/.local/bin" "$T/fake"
# systemctl is a recording stub: the test must never stop the tester's own user services
export SC_LOG="$T/systemctl.log"; : >"$SC_LOG"
printf '#!/bin/sh\necho "$*" >>"$SC_LOG"\ncase "$*" in "--user is-enabled --quiet quasseld") exit 0 ;; esac\nexit 0\n' >"$T/fake/systemctl"
chmod +x "$T/fake/systemctl"
export PATH="$T/fake:$PATH"
KQ="$HOME/.local/share/work-kit/quassel"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/work-kit-quassel-ctl"   # a user's own file at a new name
# an install from before the rename: marked launchers, units, desktop entry, icon, and one foreign file
MK="work-kit:80-quassel"; UD="$XDG_CONFIG_HOME/systemd/user"
mkdir -p "$UD" "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/icons/hicolor/scalable/apps"
for n in quasseld quassel-type quassel-pill quassel-dictate; do printf '#!/bin/sh\n# %s\n' "$MK" >"$HOME/.local/bin/$n"; done
printf '#!/bin/sh\necho not-ours\n' >"$HOME/.local/bin/quassel-ctl"
for u in quasseld quassel-server quassel-pill quassel-ydotoold; do printf '# %s\n[Service]\n' "$MK" >"$UD/$u.service"; done
printf '[Desktop Entry]\n# %s\n' "$MK" >"$XDG_DATA_HOME/applications/quassel.desktop"
: >"$XDG_DATA_HOME/icons/hicolor/scalable/apps/quassel-voice.svg"

bash "$MOD/install.sh" >"$T/install1.log" 2>&1 || { cat "$T/install1.log"; exit 1; }
check "venv has PySide6" '[ -d "$KQ/venv/lib/python3.12/site-packages/PySide6" ]'
check "app package" '[ -f "$KQ/app/quassel/daemon.py" ] && [ -f "$KQ/app/quassel/pill_qt.py" ]'
check "app uses the prefixed unit names" 'grep -q "\"work-kit-quassel-daemon\"" "$KQ/app/quassel/center.py" && ! grep -rq "\"quasseld\"" "$KQ/app/quassel"'
check "engine wrapper" '[ -x "$KQ/engine/cpu/run-server.sh" ] && [ -f "$KQ/engine/cpu/whisper-server" ]'
check "models" '[ -s "$KQ/models/ggml-small-q5_1.bin" ] && [ -s "$KQ/models/ggml-medium-q5_0.bin" ] && [ -s "$KQ/models/ggml-silero-v5.1.2.bin" ]'
check "ydotool 1.0.4" '[ -x "$KQ/bin/ydotool" ] && [ -x "$KQ/bin/ydotoold" ]'
check "unpacked tools" '[ -x "$KQ/sysroot/usr/bin/wl-copy" ] && [ -x "$KQ/sysroot/usr/bin/xclip" ] && [ -x "$KQ/tools/notify-send" ]'
check "qt fallback libs" '[ -e "$KQ/qtlib/libxcb-cursor.so.0" ]'
for f in work-kit-quassel-daemon work-kit-quassel-type work-kit-quassel-pill work-kit-quassel-ctl work-kit-quassel-dictate; do
  check "launcher $f" 'grep -q work-kit:80-quassel "$HOME/.local/bin/$f"'
done
check "user file backed up" 'ls "$HOME"/.local/share/work-kit/backups/80-quassel/work-kit-quassel-ctl.bak-* >/dev/null 2>&1'
for u in work-kit-quassel-daemon work-kit-quassel-server work-kit-quassel-pill work-kit-quassel-ydotoold; do
  check "unit $u" '[ -f "$XDG_CONFIG_HOME/systemd/user/$u.service" ]'
done
check "old units were stopped, disabled and removed" 'for u in quasseld quassel-server quassel-pill quassel-ydotoold; do grep -qx -- "--user stop $u" "$SC_LOG" && grep -qx -- "--user disable $u" "$SC_LOG" && [ ! -e "$UD/$u.service" ] || exit 1; done'
check "old daemon was enabled: new one enabled" 'grep -qx -- "--user enable work-kit-quassel-daemon" "$SC_LOG"'
check "old launchers and desktop entry gone" '[ ! -e "$HOME/.local/bin/quasseld" ] && [ ! -e "$HOME/.local/bin/quassel-dictate" ] && [ ! -e "$XDG_DATA_HOME/applications/quassel.desktop" ] && [ ! -e "$XDG_DATA_HOME/icons/hicolor/scalable/apps/quassel-voice.svg" ]'
check "old files backed up" 'ls "$HOME"/.local/share/work-kit/backups/80-quassel/quasseld.bak-* "$HOME"/.local/share/work-kit/backups/80-quassel/quassel.desktop.bak-* >/dev/null 2>&1'
check "foreign file under an old name untouched" 'grep -q not-ours "$HOME/.local/bin/quassel-ctl"'
check "server.env points into kit" 'grep -q "^SERVER_BIN=$KQ/engine/cpu/run-server.sh" "$XDG_CONFIG_HOME/quassel/server.env"'
SENV="$XDG_CONFIG_HOME/quassel/server.env"; SSTATE="$KQ/server.env.kit-sha256"
out="$(bash "$MOD/install.sh" 2>&1)"
check "current server.env default is kept as is" 'grep -q "keeping .*server.env (current kit default)" <<<"$out"'
# an older kit default (other value), recorded as the kit's own: the update refreshes it
sed -i.tmp 's/^WHISPER_DECODE=.*/WHISPER_DECODE=-old/' "$SENV" && rm -f "$SENV.tmp"
{ command -v sha256sum >/dev/null && sha256sum "$SENV" || shasum -a 256 "$SENV"; } | cut -d' ' -f1 >"$SSTATE"
out="$(bash "$MOD/install.sh" 2>&1)"
check "untouched older server.env default is refreshed" 'grep -q "refreshed .*server.env" <<<"$out" && ! grep -q "WHISPER_DECODE=-old" "$SENV"'
printf '\n# mine\n' >>"$SENV"
out="$(bash "$MOD/install.sh" 2>&1)"
check "edited server.env is kept and gets kit-new" 'grep -q "# mine" "$SENV" && [ -f "$SENV.kit-new" ] && grep -q "kept your" <<<"$out"'
rm -f "$SSTATE" "$SENV.kit-new"; printf 'FOREIGN=1\n' >"$SENV"
bash "$MOD/install.sh" >/dev/null
check "pre-existing foreign server.env is kept" '[ "$(cat "$SENV")" = "FOREIGN=1" ] && [ ! -e "$SENV.kit-new" ]'
check "desktop entry" 'grep -q work-kit-quassel-dictate "$XDG_DATA_HOME/applications/work-kit-quassel.desktop" && grep -q "Exec=.*/work-kit-quassel-type" "$XDG_DATA_HOME/applications/work-kit-quassel.desktop"'
check "icon" '[ -f "$XDG_DATA_HOME/icons/hicolor/scalable/apps/work-kit-quassel.svg" ]'

# Restore a kit-owned default so uninstall keeps its established behaviour.
rm -f "$SENV"
bash "$MOD/install.sh" >/dev/null

nbak="$(find "$HOME" -name '*.bak-*' | wc -l)"
bash "$MOD/install.sh" >"$T/install2.log" 2>&1 || { cat "$T/install2.log"; exit 1; }
check "backup records the original path" 'grep -qx "$HOME/.local/bin/work-kit-quassel-ctl" "$HOME"/.local/share/work-kit/backups/80-quassel/work-kit-quassel-ctl.bak-*.origin'
check "no .bak-* beside the original" '[ -z "$(ls "$HOME/.local/bin" | grep "\.bak-" || true)" ]'
check "re-install makes no new backups" '[ "$(find "$HOME" -name "*.bak-*" | wc -l)" = "$nbak" ]'
check "re-install keeps server.env" 'grep -q "keeping" "$T/install2.log"'

bash "$MOD/uninstall.sh" >"$T/uninstall.log" 2>&1 || { cat "$T/uninstall.log"; exit 1; }
check "data dir removed" '[ ! -e "$KQ" ]'
check "launchers removed" '[ ! -e "$HOME/.local/bin/work-kit-quassel-daemon" ] && [ ! -e "$HOME/.local/bin/work-kit-quassel-dictate" ]'
check "units removed" '[ -z "$(ls "$XDG_CONFIG_HOME/systemd/user" 2>/dev/null)" ]'
check "server.env removed" '[ ! -e "$XDG_CONFIG_HOME/quassel/server.env" ]'
check "user backup kept" 'ls "$HOME"/.local/share/work-kit/backups/80-quassel/work-kit-quassel-ctl.bak-* >/dev/null 2>&1'

echo "failures: $fails"
[ "$fails" = 0 ]
