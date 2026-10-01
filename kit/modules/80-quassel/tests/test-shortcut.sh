#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# shortcut.sh with a fake gsettings: works without system python3 (kit CPython, then the quassel venv).
set -uo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

export HOME="$W/home"
mkdir -p "$HOME" "$W/bin"
unset KIT_DATA_DIR QUASSEL_KIT_HOME
# fake gsettings: keeps the values in files under $W/gs
cat >"$W/bin/gsettings" <<'G'
#!/bin/sh
d="$GS_DIR"; mkdir -p "$d"
case "$1" in
  get) f="$d/$(echo "$2 $3" | tr '/ :' '___')"; [ -f "$f" ] && cat "$f" || echo "@as []" ;;
  set) f="$d/$(echo "$2 $3" | tr '/ :' '___')"; printf '%s\n' "$4" >"$f" ;;
  reset-recursively) : ;;
  list-recursively) for f in "$d/$2"_*; do [ -f "$f" ] || continue; k="${f##*/}"; k="${k#"$2"_}"; printf '%s %s %s\n' "$2" "$k" "$(cat "$f")"; done ;;
esac
G
chmod +x "$W/bin/gsettings"
export GS_DIR="$W/gs"
REALPY="$(python3 -c 'import sys; print(sys.executable)')"
for t in bash sh env dirname basename cat tr mkdir grep sed; do
  p="$(command -v "$t")" && ln -sf "$p" "$W/bin/$t"
done
list() { cat "$GS_DIR/org.gnome.settings-daemon.plugins.media-keys_custom-keybindings" 2>/dev/null; }

# 1. no python3 on PATH, kit CPython where 00-python puts it
mkdir -p "$HOME/.local/share/uv/python/cpython-3.12.0-test/bin"
ln -s "$REALPY" "$HOME/.local/share/uv/python/cpython-3.12.0-test/bin/python3"
PATH="$W/bin" bash "$MOD/shortcut.sh" >"$W/o1" 2>&1 && grep -q work-kit-quassel "$GS_DIR"/*custom-keybindings && ok "set with the kit CPython" || { bad "set with the kit CPython"; cat "$W/o1"; }
PATH="$W/bin" bash "$MOD/shortcut.sh" --remove >"$W/o2" 2>&1 && ! list | grep -q work-kit-quassel && ok "remove with the kit CPython" || { bad "remove"; cat "$W/o2"; }

# 2. only the quassel venv has python
rm -rf "$HOME/.local/share/uv"
mkdir -p "$HOME/.local/share/work-kit/quassel/venv/bin"
ln -s "$REALPY" "$HOME/.local/share/work-kit/quassel/venv/bin/python"
PATH="$W/bin" bash "$MOD/shortcut.sh" >"$W/o3" 2>&1 && list | grep -q work-kit-quassel && ok "set with the quassel venv python" || { bad "venv fallback"; cat "$W/o3"; }
PATH="$W/bin" bash "$MOD/shortcut.sh" --remove >/dev/null 2>&1

# 2b. --ensure sets a missing shortcut and keeps one that is set (a key the user chose)
PATH="$W/bin" bash "$MOD/shortcut.sh" --ensure >"$W/o5" 2>&1 && list | grep -q work-kit-quassel && ok "--ensure sets a missing shortcut" || { bad "--ensure set"; cat "$W/o5"; }
PATH="$W/bin" bash "$MOD/shortcut.sh" --binding '<Super>q' >/dev/null 2>&1
PATH="$W/bin" bash "$MOD/shortcut.sh" --ensure >"$W/o6" 2>&1 && grep -q '<Super>q' "$GS_DIR"/*binding && grep -q "already set" "$W/o6" && ok "--ensure keeps an existing binding" || { bad "--ensure keep"; cat "$W/o6"; }
PATH="$W/bin" bash "$MOD/shortcut.sh" --remove >/dev/null 2>&1

# 2c. Ubuntu's "show desktop" on Ctrl+Alt+D would win over the custom shortcut: freed on set, back on remove
printf '%s\n' "['<Primary><Alt>d', '<Super>d']" >"$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop"
PATH="$W/bin" bash "$MOD/shortcut.sh" >"$W/o7" 2>&1
grep -qx "\['<Super>d'\]" "$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop" && ok "conflicting show-desktop key freed, Super+D kept" || { bad "conflict freed"; cat "$W/o7" "$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop"; }
head -n 1 "$W/o7" | grep -q "^shortcut <Control><Alt>d" && ok "first output line stays the shortcut line (install log)" || { bad "first line"; cat "$W/o7"; }
grep -q "freed <Control><Alt>d from keybindings show-desktop" "$W/o7" && ok "freeing is reported" || bad "freeing reported"
PATH="$W/bin" bash "$MOD/shortcut.sh" --remove >/dev/null 2>&1
grep -qx "\['<Primary><Alt>d', '<Super>d'\]" "$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop" && ok "remove puts show-desktop back" || { bad "restore"; cat "$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop"; }
rm -f "$GS_DIR/org.gnome.desktop.wm.keybindings_show-desktop"

# 3. no python at all
rm -rf "$HOME/.local/share/work-kit"
if PATH="$W/bin" bash "$MOD/shortcut.sh" >"$W/o4" 2>&1; then bad "no python: must fail"; else grep -q 01-prereqs "$W/o4" && ok "no python: message names 01-prereqs" || { bad "message"; cat "$W/o4"; }; fi
exit "$fail"
