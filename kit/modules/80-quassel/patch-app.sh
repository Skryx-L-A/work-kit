#!/usr/bin/env bash
# Rename the unit, launcher and icon names inside the extracted Quassel app source.
# Usage: patch-app.sh <app dir>       (called by install.sh; the app tarball itself is not changed)
#
# The app calls `systemctl --user start quasseld quassel-server ...`, starts `quassel-type` and
# looks up the icon "quassel-voice" by literal strings. Those names collide with Quassel IRC
# packages, so the kit installs them as work-kit-quassel-* (see names.sh). Only complete quoted
# string literals and the desktop template are rewritten; UI texts, the app name and the config
# and data directory names stay. The script fails when an old name is still present afterwards.
set -euo pipefail

APP="${1:?usage: patch-app.sh <app dir>}"
[ -d "$APP/quassel" ] || { echo "patch-app.sh: $APP/quassel not found" >&2; exit 1; }

rewrite() { # file: apply the name mapping with perl (same result on GNU and BSD systems)
  perl -pi -e '
    s/"quasseld"/"work-kit-quassel-daemon"/g;
    s/"quassel-server"/"work-kit-quassel-server"/g;
    s/"quassel-server\.service"/"work-kit-quassel-server.service"/g;
    s/"quassel-ydotoold"/"work-kit-quassel-ydotoold"/g;
    s/(?<!add_css_class\()"quassel-pill"/"work-kit-quassel-pill"/g;   # not the GTK CSS class
    s/"quassel-type"/"work-kit-quassel-type"/g;
    s/"quassel-voice"/"work-kit-quassel"/g;
    s#apps/quassel-voice\.svg#apps/work-kit-quassel.svg#g;
    s/setDesktopFileName\("quassel"\)/setDesktopFileName("work-kit-quassel")/g;
  ' "$1"
}

for f in center.py pill.py pill_qt.py whisperclient.py; do
  [ -f "$APP/quassel/$f" ] && rewrite "$APP/quassel/$f"
done

tpl="$APP/desktop/quassel.desktop.in"
if [ -f "$tpl" ]; then
  perl -pi -e '
    s#/\.local/bin/quassel-type#/.local/bin/work-kit-quassel-type#;
    s#/\.local/bin/quassel-ctl #/.local/bin/work-kit-quassel-ctl #;
    s#apps/quassel-voice\.svg#apps/work-kit-quassel.svg#;
  ' "$tpl"
fi

# Nothing may still use an old name.
left="$(grep -rnE '"(quasseld|quassel-server(\.service)?|quassel-ydotoold|quassel-pill|quassel-type|quassel-voice)"|setDesktopFileName\("quassel"\)|bin/quassel-(type|ctl)|apps/quassel-voice' \
  "$APP/quassel" "$APP/desktop" 2>/dev/null | grep -v -e '\.pyc' -e add_css_class || true)"
if [ -n "$left" ]; then
  echo "patch-app.sh: old names remain (app version changed? update patch-app.sh):" >&2
  printf '%s\n' "$left" >&2
  exit 1
fi
grep -q '"work-kit-quassel-daemon"' "$APP/quassel/center.py" 2>/dev/null \
  || { echo "patch-app.sh: expected names not found in center.py" >&2; exit 1; }
echo "patch-app.sh: unit, launcher and icon names renamed in $APP"
