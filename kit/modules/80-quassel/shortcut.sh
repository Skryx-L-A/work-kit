#!/usr/bin/env bash
# Bind `work-kit-quassel-dictate toggle` to a GNOME keyboard shortcut (user settings, no root).
# Usage: shortcut.sh [--binding '<Control><Alt>d'] [--ensure] | --remove | --show
#   --ensure: set the shortcut only when none is set yet (install.sh uses it; keeps a key you chose)
# Other desktops: add a custom shortcut by hand that runs: ~/.local/bin/work-kit-quassel-dictate toggle
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
BINDING='<Control><Alt>d'
MODE="set"
ENSURE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --binding) BINDING="${2:?--binding needs a value}"; shift ;;
    --ensure) ENSURE=1 ;;
    --remove) MODE=remove ;;
    --show) MODE=show ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v gsettings >/dev/null 2>&1 || {
  echo "gsettings not found (not GNOME). Add a custom shortcut by hand:"
  echo "  command: $HOME/.local/bin/work-kit-quassel-dictate toggle"
  exit 1
}

SCHEMA=org.gnome.settings-daemon.plugins.media-keys
KEY=custom-keybindings
PATH_ID=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/
ITEM="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$PATH_ID"

# gsettings prints "@as []" or "['/a/', '/b/']"; edit the list without dropping other entries.
edit_list() { # add|remove
  local py
  py="$(kit_find_python || true)"
  [ -n "$py" ] || py="${QUASSEL_KIT_HOME:-${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/quassel}/venv/bin/python"
  [ -x "$py" ] || { echo "shortcut.sh: $(kit_python_hint)" >&2; return 1; }
  "$py" - "$1" "$PATH_ID" "$(gsettings get "$SCHEMA" "$KEY")" <<'PY'
import ast, sys
op, item, raw = sys.argv[1], sys.argv[2], sys.argv[3].strip()
if raw.startswith("@as"):
    raw = raw[3:].strip()
items = list(ast.literal_eval(raw)) if raw else []
if op == "add" and item not in items:
    items.append(item)
if op == "remove":
    items = [i for i in items if i != item]
print("[" + ", ".join(repr(i) for i in items) + "]")
PY
}

# A GNOME window-manager or shell shortcut on the same keys (Ubuntu: "show desktop" on Ctrl+Alt+D)
# wins over a custom shortcut: take our keys out of it (other keys of that action stay) and note the
# old value, so --remove can put it back when nobody changed it since.
FREED="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/quassel/shortcut-freed.tsv"
WM_SCHEMAS="org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings org.gnome.mutter.keybindings org.gnome.mutter.wayland.keybindings"
conflicts() { # free <binding> | restore
  local py
  py="$(kit_find_python || true)"
  [ -n "$py" ] || py="${QUASSEL_KIT_HOME:-${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/quassel}/venv/bin/python"
  [ -x "$py" ] || return 0
  mkdir -p "$(dirname "$FREED")"
  "$py" - "$1" "${2:-}" "$FREED" $WM_SCHEMAS <<'PY'
import ast, os, re, subprocess, sys
op, binding, state, schemas = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]

def norm(acc):
    mods = re.findall(r"<([^>]+)>", acc)
    key = re.sub(r"<[^>]+>", "", acc).strip().lower()
    mods = {("control" if m.lower() in ("primary", "ctrl", "control") else m.lower()) for m in mods}
    return (frozenset(mods), key)

def items(raw):
    raw = raw.strip()
    if raw.startswith("@as"):
        raw = raw[3:].strip()
    try:
        v = ast.literal_eval(raw)
    except (ValueError, SyntaxError):
        return None
    return list(v) if isinstance(v, (list, tuple)) else None

def fmt(lst):
    return "[" + ", ".join(repr(i) for i in lst) + "]" if lst else "@as []"

def gs(*args):
    return subprocess.run(["gsettings", *args], capture_output=True, text=True)

lines = open(state).read().splitlines() if os.path.exists(state) else []
if op == "free":
    want = norm(binding)
    known = {tuple(l.split("\t")[:2]) for l in lines}
    for schema in schemas:
        r = gs("list-recursively", schema)
        if r.returncode != 0:
            continue
        for line in r.stdout.splitlines():
            parts = line.split(" ", 2)
            if len(parts) < 3 or parts[0] != schema:
                continue
            key, raw = parts[1], parts[2]
            cur = items(raw)
            if not cur or not any(norm(a) == want for a in cur):
                continue
            new = [a for a in cur if norm(a) != want]
            if gs("set", schema, key, fmt(new)).returncode == 0:
                if (schema, key) not in known:
                    lines.append("\t".join((schema, key, fmt(cur), fmt(new))))
                print("freed %s from %s %s" % (binding, schema.rsplit(".", 1)[-1], key))
    if lines:
        open(state, "w").write("\n".join(lines) + "\n")
elif op == "restore":
    for l in lines:
        schema, key, old, new = l.split("\t")
        cur = items(gs("get", schema, key).stdout)
        if cur is not None and cur == items(new):
            gs("set", schema, key, old)
    if os.path.exists(state):
        os.remove(state)
PY
}

case "$MODE" in
  show)
    gsettings get "$SCHEMA" "$KEY"
    gsettings get "$ITEM" binding 2>/dev/null || true ;;
  remove)
    new_list="$(edit_list remove)" || exit 1
    gsettings set "$SCHEMA" "$KEY" "$new_list"
    gsettings reset-recursively "$ITEM" 2>/dev/null || true
    conflicts restore || true
    echo "shortcut removed" ;;
  set)
    if [ "$ENSURE" = 1 ] && gsettings get "$SCHEMA" "$KEY" | grep -qF "$PATH_ID"; then
      cur="$(gsettings get "$ITEM" binding 2>/dev/null | tr -d "'\"")"
      if [ -n "$cur" ]; then echo "shortcut already set: $cur"; conflicts free "$cur" || true; exit 0; fi
    fi
    new_list="$(edit_list add)" || exit 1   # before any change: without python nothing is set
    gsettings set "$ITEM" name 'Quassel dictate (clipboard)'
    gsettings set "$ITEM" command "$HOME/.local/bin/work-kit-quassel-dictate toggle"
    gsettings set "$ITEM" binding "$BINDING"
    gsettings set "$SCHEMA" "$KEY" "$new_list"
    echo "shortcut $BINDING -> work-kit-quassel-dictate toggle"
    echo "press once to record, again to stop; the text is then in the clipboard (Ctrl+V)"
    conflicts free "$BINDING" || true ;;
esac
