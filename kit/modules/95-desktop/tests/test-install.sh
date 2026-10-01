#!/usr/bin/env bash
# Installer logic of 95-desktop against stub dconf/gsettings/gnome-shell (tests/stubs) and fake
# offline artifacts in a scratch HOME. Runs on Linux and macOS; it does not prove that GNOME
# loads the extensions or that the Linux binaries run (manual VM checklist in docs/desktop.md).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap '[ -n "${KEEP_W:-}" ] && echo "kept $W" || rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
export KIT_KEYBOARD_FILE=/dev/null # the machine's own layout must not change the key names

# ---- fake offline tree --------------------------------------------------------------------
OFF="$W/offline/desktop"
mkzip() { # mkzip <out.zip> <uuid> <shell versions json> <schema id>
  local d="$W/z/$2"; rm -rf "$d"; mkdir -p "$d/schemas" "$(dirname "$1")"
  printf '{"uuid": "%s", "name": "fake", "shell-version": [%s]}\n' "$2" "$3" >"$d/metadata.json"
  printf '<schemalist><schema id="%s" path="/x/"></schema></schemalist>\n' "$4" >"$d/schemas/$4.gschema.xml"
  python3 -c 'import os,sys,zipfile
z=zipfile.ZipFile(sys.argv[1],"w")
for r,_,fs in os.walk(sys.argv[2]):
  for f in fs: p=os.path.join(r,f); z.write(p,os.path.relpath(p,sys.argv[2]))' "$1" "$d"
}
for g in 46 50; do
  mkzip "$OFF/extensions/$g/tilingshell@ferrarodomenico.com.zip" tilingshell@ferrarodomenico.com '"45","46","47","48","49","50"' org.gnome.shell.extensions.tilingshell
  mkzip "$OFF/extensions/$g/paperwm@paperwm.github.com.zip" paperwm@paperwm.github.com '"45","46","47","48","49","50"' org.gnome.shell.extensions.paperwm
  mkzip "$OFF/extensions/$g/tactile@lundal.io.zip" tactile@lundal.io '"45","46","47","48","49","50","51"' org.gnome.shell.extensions.tactile
  mkzip "$OFF/extensions/$g/just-perfection-desktop@just-perfection.zip" just-perfection-desktop@just-perfection '"45","46","47","48","49","50","51"' org.gnome.shell.extensions.just-perfection
  mkzip "$OFF/extensions/$g/clipboard-indicator@tudmotu.com.zip" clipboard-indicator@tudmotu.com '"46","47","48","49","50"' org.gnome.shell.extensions.clipboard-indicator
done
mkzip "$OFF/extensions/42/forge@jmmaranan.com.zip" forge@jmmaranan.com '"40","41","42","43","44"' org.gnome.shell.extensions.forge
mkzip "$OFF/extensions/42/tilingshell@ferrarodomenico.com.zip" tilingshell@ferrarodomenico.com '"42","43","44"' org.gnome.shell.extensions.tilingshell
mkzip "$OFF/extensions/42/space-bar@luchrioh.zip" space-bar@luchrioh '"42","43","44"' org.gnome.shell.extensions.space-bar.behavior
mkzip "$OFF/extensions/42/just-perfection-desktop@just-perfection.zip" just-perfection-desktop@just-perfection '"42","43","44"' org.gnome.shell.extensions.just-perfection
mkzip "$OFF/extensions/42/clipboard-indicator@tudmotu.com.zip" clipboard-indicator@tudmotu.com '"42","43","44"' org.gnome.shell.extensions.clipboard-indicator
mkzip "$OFF/extensions/46/space-bar@luchrioh.zip" space-bar@luchrioh '"46","47","48","49"' org.gnome.shell.extensions.space-bar.behavior
mkzip "$OFF/extensions/50/space-bar@luchrioh.zip" space-bar@luchrioh '"50"' org.gnome.shell.extensions.space-bar.behavior

P="$W/pk"; mkdir -p "$P/fonts" "$OFF/fonts" "$OFF/apps" "$OFF/bin" "$OFF/nvim"
for f in JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFont-Bold.ttf JetBrainsMonoNerdFontMono-Regular.ttf OFL.txt; do echo x >"$P/fonts/$f"; done
tar -cJf "$OFF/fonts/JetBrainsMono-nerd-3.5.1.tar.xz" -C "$P/fonts" .
cat >"$OFF/apps/Ghostty-1.3.1-x86_64.AppImage" <<'EOF'
#!/bin/sh
# like Ghostty 1.3 (uruntime): unpack to AppDir/ plus a squashfs-root -> AppDir link
if [ "$1" = --appimage-extract ]; then mkdir -p AppDir; ln -s ./AppDir squashfs-root; printf '#!/bin/sh\necho fake ghostty "$@"\n' >AppDir/AppRun; chmod +x AppDir/AppRun; echo x >AppDir/ghostty.png; fi
EOF
mkexe() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\necho "%s fake"\n' "$2" >"$1"; chmod +x "$1"; }
mkexe "$P/lg/lazygit" lazygit; tar -czf "$OFF/bin/lazygit_0.65.1_linux_x86_64.tar.gz" -C "$P/lg" lazygit
mkexe "$P/bt/btop/bin/btop" btop; tar -czf "$OFF/bin/btop-1.4.7-x86_64-unknown-linux-musl.tar.gz" -C "$P/bt" ./btop
mkexe "$P/ff/fastfetch-linux-amd64/usr/bin/fastfetch" fastfetch; tar -czf "$OFF/bin/fastfetch-2.68.1-linux-amd64.tar.gz" -C "$P/ff" fastfetch-linux-amd64
mkexe "$P/zj/zellij" zellij; tar -czf "$OFF/bin/zellij-0.45.1-no-web-x86_64-unknown-linux-musl.tar.gz" -C "$P/zj" zellij
mkexe "$P/nv/nvim-linux-x86_64/bin/nvim" nvim; tar -czf "$OFF/bin/nvim-0.12.5-linux-x86_64.tar.gz" -C "$P/nv" nvim-linux-x86_64
mkdir -p "$P/mini/mini.nvim-0.18.0/lua/mini"; echo 'return {}' >"$P/mini/mini.nvim-0.18.0/lua/mini/basics.lua"
tar -czf "$OFF/nvim/mini.nvim-0.18.0.tar.gz" -C "$P/mini" mini.nvim-0.18.0
mkexe "$P/zd/zed.app/bin/zed" zed; mkdir -p "$P/zd/zed.app/share/applications"
printf '[Desktop Entry]\nName=Zed\nExec=zed %%U\nTryExec=zed\nIcon=zed\n' >"$P/zd/zed.app/share/applications/dev.zed.Zed.desktop"
tar -czf "$OFF/apps/zed-1.21.0-linux-x86_64.tar.gz" -C "$P/zd" zed.app

# Ghostty software OpenGL: fake Arch packages (only when zstd exists here)
if command -v zstd >/dev/null 2>&1; then
  mkpkg() { # mkpkg <name> <license dir> <lib files...>
    local n="$1" lic="$2" d="$W/pkg/$1"; shift 2
    mkdir -p "$d/usr/lib" "$d/usr/share/licenses/$lic" "$OFF/gl"
    for f in "$@"; do echo "$f" >"$d/usr/lib/$f"; done
    echo license >"$d/usr/share/licenses/$lic/COPYING"; echo x >"$d/usr/lib/libunrelated.so.1"
    tar -cf - -C "$d" usr | zstd -q -o "$OFF/gl/$n-x86_64.pkg.tar.zst"
  }
  mkpkg mesa-26.0.1-1 mesa libgallium-26.0.1-arch1.1.so libGLX_mesa.so.0
  mkpkg llvm-libs-21.1.8-1 llvm-libs libLLVM.so.21.1 libLTO.so.21.1
  mkpkg libdrm-2.4.131-1 libdrm libdrm_intel.so.1 libdrm.so.2
  mkpkg libedit-20251016_3.1-1 libedit libedit.so.0
  mkpkg ncurses-6.5-4 ncurses libncursesw.so.6 libncurses++w.so.6
fi

# ---- environment -----------------------------------------------------------------------------
fresh_home() { # fresh_home <name>: new HOME, dconf db with some existing user settings
  export HOME="$W/$1"; mkdir -p "$HOME"
  export KIT_BIN_DIR="$HOME/.local/bin" KIT_DATA_DIR="$HOME/.local/share/work-kit" XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export FAKE_DB="$W/$1.db" FAKE_LOCKS="$W/$1.locks" FAKE_DEFAULTS="$W/defaults"
  : >"$FAKE_LOCKS"
  cat >"$FAKE_DB" <<'EOF'
/org/gnome/shell/enabled-extensions=['user-own@example.org']
/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/']
/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/binding='<Control><Alt>d'
/org/gnome/desktop/interface/gtk-theme='Yaru-dark'
/org/gnome/desktop/wm/keybindings/close=['<Alt>F4']
EOF
  cp "$FAKE_DB" "$W/$1.orig"
}
cat >"$W/defaults" <<'EOF'
/org/gnome/shell/disable-user-extensions=false
/org/gnome/shell/allow-extension-installation=true
/org/gnome/desktop/wm/keybindings/show-desktop=['<Primary><Super>d', '<Primary><Alt>d', '<Super>d']
/org/gnome/desktop/wm/keybindings/move-to-workspace-left=['<Super><Shift>Page_Up', '<Super><Shift>KP_Prior', '<Super><Shift><Alt>Left', '<Control><Shift><Alt>Left']
/org/gnome/desktop/wm/keybindings/move-to-workspace-right=['<Super><Shift>Page_Down', '<Super><Shift>KP_Next', '<Super><Shift><Alt>Right', '<Control><Shift><Alt>Right']
EOF
export KIT_OFFLINE="$W/offline"
export PATH="$HERE/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
export FAKE_GNOME=46
export XDG_SESSION_TYPE=x11 # sections A-F and K assume a shell that can be restarted; W covers Wayland
# shellcheck disable=SC2329  # used inside check strings
db() { awk -v k="$1=" 'index($0,k)==1 {print substr($0,length(k)+1); exit}' "$FAKE_DB"; }
KB=/org/gnome/desktop/wm/keybindings
CK=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings

# ---- A: GNOME 46, clean install, rerun, uninstall ----------------------------------------------
fresh_home a
mkdir -p "$HOME/.config/ghostty"; echo "font-size = 14" >"$HOME/.config/ghostty/config"
# files of the user in the way: lazygit (replaced by desk_put), nvim (replaced by a link)
mkdir -p "$KIT_BIN_DIR"; echo "user lazygit" >"$KIT_BIN_DIR/lazygit"; echo "user nvim" >"$KIT_BIN_DIR/nvim"
BK="$KIT_DATA_DIR/backups/95-desktop"
# shellcheck disable=SC2329  # used inside check strings
beside() { find "$HOME" -name '*.bak-*' ! -path "$KIT_DATA_DIR/backups/*" | grep . >/dev/null; }
# shellcheck disable=SC2329  # used inside check strings
nbak() { find "$BK" -name '*.bak-*' ! -name '*.origin' 2>/dev/null | wc -l | tr -d ' '; }
out="$(bash "$MOD/install.sh" --tiler tilingshell 2>&1)" || { bad "A install exits 0"; printf '%s\n' "$out"; }
check "A no .bak beside any file" "! beside"
check "A user files backed up below the kit data dir, with .origin" "b=\$(ls '$BK/.local/bin/' | grep '^lazygit.bak-[0-9]*\$') && grep -q 'user lazygit' '$BK/.local/bin/'\$b && [ \"\$(cat '$BK/.local/bin/'\$b.origin)\" = '$KIT_BIN_DIR/lazygit' ] && ls '$BK/.local/bin/' | grep -q '^nvim.bak-[0-9]*\$' && [ \"\$(nbak)\" = 2 ]"
check "A dconf backup written" "ls '$KIT_DATA_DIR/desktop/backup/' | grep -q dconf-original.ini"
check "A Super+W closes, Alt+F4 kept" "[ \"\$(db $KB/close)\" = \"['<Super>w', '<Alt>F4']\" ]"
check "A Super+Escape system menu" "grep -q \"command='$KIT_BIN_DIR/kit-desk power'\" '$FAKE_DB'"
check "A Super+Alt+Space kit menu" "grep -q \"command='$KIT_BIN_DIR/kit-desk menu'\" '$FAKE_DB'"
check "A Super+Comma notifications, Super+V kept" "[ \"\$(db /org/gnome/shell/keybindings/toggle-message-tray)\" = \"['<Super>comma', '<Super>v', '<Super>m']\" ]"
check "A Super+Ctrl+V clipboard history" "[ \"\$(db /org/gnome/shell/extensions/clipboard-indicator/toggle-menu)\" = \"['<Super><Control>v']\" ]"
check "A clipboard kept in memory, extension keys cleared" "[ \"\$(db /org/gnome/shell/extensions/clipboard-indicator/cache-only-favorites)\" = true ] && [ \"\$(db /org/gnome/shell/extensions/clipboard-indicator/next-entry)\" = '@as []' ]"
check "A move to monitor on Super+Shift+Alt+arrows (tiler owns Super+Shift+arrows)" "[ \"\$(db $KB/move-to-monitor-left)\" = \"['<Super><Shift><Alt>Left']\" ]"
check "A Super+Ctrl+D freed from Ubuntu's show-desktop" "[ \"\$(db $KB/show-desktop)\" = \"['<Primary><Alt>d', '<Super>d']\" ]"
check "A Super+Shift+Alt+Left/Right freed from move-to-workspace" "[ \"\$(db $KB/move-to-workspace-left)\" = \"['<Super><Shift>Page_Up', '<Super><Shift>KP_Prior', '<Control><Shift><Alt>Left']\" ] && [ \"\$(db $KB/move-to-workspace-right)\" = \"['<Super><Shift>Page_Down', '<Super><Shift>KP_Next', '<Control><Shift><Alt>Right']\" ]"
check "A lock on Super+Ctrl+L, Super+L = next layout" "[ \"\$(db /org/gnome/settings-daemon/plugins/media-keys/screensaver)\" = \"['<Super><Control>l']\" ] && [ \"\$(db /org/gnome/shell/extensions/tilingshell/cycle-layouts)\" = \"['<Super>l']\" ]"
check "A Tiling Shell layouts: main and stack selected" "db /org/gnome/shell/extensions/tilingshell/layouts-json | grep -q '\"id\":\"Main and stack\"' && [ \"\$(db /org/gnome/shell/extensions/tilingshell/selected-layouts)\" = \"[['Main and stack'], ['Main and stack'], ['Main and stack'], ['Main and stack'], ['Main and stack'], ['Main and stack']]\" ]"
check "A welcome autostart entry" "grep -q 'kit-desk welcome' '$HOME/.config/autostart/work-kit-desktop-welcome.desktop'"
check "A install.conf records tiler and clipboard" "grep -qx tiler_active=1 '$KIT_DATA_DIR/desktop/state/install.conf' && grep -qx clipboard=1 '$KIT_DATA_DIR/desktop/state/install.conf'"
check "A Super+1 workspace 1" "[ \"\$(db $KB/switch-to-workspace-1)\" = \"['<Super>1']\" ]"
check "A Super+Shift+6 moves to 6" "[ \"\$(db $KB/move-to-workspace-6)\" = \"['<Super><Shift>6']\" ]"
check "A no workspace 7 binding (6 workspaces)" "[ -z \"\$(db $KB/switch-to-workspace-7)\" ]"
check "A 6 fixed workspaces" "[ \"\$(db /org/gnome/desktop/wm/preferences/num-workspaces)\" = 6 ] && [ \"\$(db /org/gnome/mutter/dynamic-workspaces)\" = false ]"
check "A Super+Tab next workspace" "db $KB/switch-to-workspace-right | grep -q \"'<Super>Tab'\""
check "A Super+Space launcher: the overview with its search (GNOME's Super+S kept), app grid stays on Super+A" "[ \"\$(db /org/gnome/shell/keybindings/toggle-overview)\" = \"['<Super>space', '<Super>s']\" ] && [ -z \"\$(db /org/gnome/shell/keybindings/toggle-application-view)\" ]"
check "A Super alone does nothing (overlay key off)" "[ \"\$(db /org/gnome/mutter/overlay-key)\" = \"''\" ] && grep -qx superkey=off '$KIT_DATA_DIR/desktop/state/install.conf'"
check "A compact launcher: overview without dash and workspace thumbnails" "[ \"\$(db /org/gnome/shell/extensions/just-perfection/dash)\" = false ] && [ \"\$(db /org/gnome/shell/extensions/just-perfection/workspace)\" = false ]"
check "A click on a Space Bar workspace number switches, no overview" "[ \"\$(db /org/gnome/shell/extensions/space-bar/behavior/toggle-overview)\" = false ]"
# shellcheck disable=SC2034  # used inside the check strings
a_keys="$("$KIT_BIN_DIR/kit-desk" keys)"
check "A key list: no 'Super alone' row, Super+Space is the launcher, stuck hint names Super+Space" "! grep -qE '^SUPER +Overview' <<<\"\$a_keys\" && grep -qE '^SUPER \\+ SPACE +Launcher: type to search apps' <<<\"\$a_keys\" && grep -q 'Stuck? Super+Space opens the launcher' <<<\"\$a_keys\""
# shellcheck disable=SC2034  # used inside the check strings
a_w60="$("$KIT_BIN_DIR/kit-desk" keys --width 60)"
check "A key list --width 60: lines fit, texts wrap at word boundaries with a hanging indent" "! awk 'length > 60' <<<\"\$a_w60\" | grep -q . && grep -qE '^ {31}[^ ]' <<<\"\$a_w60\" && [ \"\$(tr -s ' \\n' '  ' <<<\"\$a_w60\")\" = \"\$(tr -s ' \\n' '  ' <<<\"\$a_keys\")\" ]"
check "A Super+Space freed from input switch" "! db $KB/switch-input-source | grep -q \"'<Super>space'\""
check "A dock Super+N cleared" "[ \"\$(db /org/gnome/shell/keybindings/switch-to-application-1)\" = '@as []' ]"
check "A Tiling Shell focus Super+Left" "[ \"\$(db /org/gnome/shell/extensions/tilingshell/focus-window-left)\" = \"['<Super>Left']\" ]"
check "A Tiling Shell swap Super+Shift+Left" "[ \"\$(db /org/gnome/shell/extensions/tilingshell/move-window-left)\" = \"['<Super><Shift>Left']\" ]"
check "A no gap at the screen edge, 2 px between windows, focus border 2 px" "[ \"\$(db /org/gnome/shell/extensions/tilingshell/inner-gaps)\" = 'uint32 2' ] && [ \"\$(db /org/gnome/shell/extensions/tilingshell/outer-gaps)\" = 'uint32 0' ] && [ \"\$(db /org/gnome/shell/extensions/tilingshell/window-border-width)\" = 'uint32 2' ] && grep -qx border=2 '$KIT_DATA_DIR/desktop/state/install.conf'"
check "A GNOME half tiling freed" "[ \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" = '@as []' ]"
check "A extensions enabled, user extension kept" "db /org/gnome/shell/enabled-extensions | grep -q tilingshell@ferrarodomenico.com && db /org/gnome/shell/enabled-extensions | grep -q user-own@example.org"
check "A Ubuntu dock and tiling assistant disabled" "db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && db /org/gnome/shell/disabled-extensions | grep -q tiling-assistant@ubuntu.com"
check "A extension unpacked with compiled schemas" "[ -f '$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com/schemas/gschemas.compiled' ]"
check "A Super+Return custom shortcut" "grep -q \"work-kit-desk-01/binding='<Super>Return'\" '$FAKE_DB' && grep -q \"work-kit-desk-01/command='$KIT_BIN_DIR/kit-desk term'\" '$FAKE_DB'"
check "A quassel shortcut kept in list" "db $CK | grep -q work-kit-quassel && db $CK | grep -q work-kit-desk-01"
check "A caps = compose" "db /org/gnome/desktop/input-sources/xkb-options | grep -q compose:caps"
check "A font installed, Mono/Propo variants dropped" "ls '$HOME/.local/share/fonts/work-kit-JetBrainsMonoNerd' | grep -q NerdFont-Regular.ttf && ! ls '$HOME/.local/share/fonts/work-kit-JetBrainsMonoNerd' | grep -q NerdFontMono"
check "A monospace font set" "db /org/gnome/desktop/interface/monospace-font-name | grep -q 'JetBrainsMono Nerd Font'"
check "A ghostty wrapper runs extracted AppRun" "'$KIT_BIN_DIR/ghostty' --x | grep -q 'fake ghostty --x'"
check "A own ghostty config kept" "grep -q 'font-size = 14' '$HOME/.config/ghostty/config'"
check "A TUIs installed" "'$KIT_BIN_DIR/lazygit' | grep -q lazygit && '$KIT_BIN_DIR/btop' | grep -q btop && '$KIT_BIN_DIR/fastfetch' | grep -q fastfetch"
check "A zellij/zed only on request" "[ ! -e '$KIT_BIN_DIR/zellij' ] && [ ! -e '$KIT_BIN_DIR/zed' ]"
check "A nvim linked and config placed" "'$KIT_BIN_DIR/nvim' | grep -q nvim && grep -q work-kit '$HOME/.config/nvim/init.lua'"
check "A theme everforest rendered" "grep -q '#2d353b' '$HOME/.config/work-kit/desktop/theme/ghostty.conf' && ! grep -q '{{' '$HOME/.config/work-kit/desktop/theme/ghostty.conf'"
check "A nvim palette written" "grep -q 'base00 = \"#2d353b\"' '$HOME/.config/nvim/lua/work-kit/palette.lua'"
check "A btop theme selected" "grep -q 'color_theme = \"work-kit\"' '$HOME/.config/btop/btop.conf'"
# shellcheck disable=SC2329  # used inside check strings
uri_file() { local u; u="$(db "$1")"; u="${u#\'}"; u="${u%\'}"; case "$u" in file:///*) u="${u#file://}"; u="${u//%20/ }"; [ -f "$u" ] && printf '%s' "$u" ;; esac; }
check "A picture-uri and picture-uri-dark point to an existing file (not the home dir)" "f=\$(uri_file /org/gnome/desktop/background/picture-uri) && [ -n \"\$f\" ] && grep -q '#2d353b' \"\$f\" && [ -n \"\$(uri_file /org/gnome/desktop/background/picture-uri-dark)\" ]"
check "A dark scheme + solid background" "[ \"\$(db /org/gnome/desktop/interface/color-scheme)\" = \"'prefer-dark'\" ] && [ \"\$(db /org/gnome/desktop/background/primary-color)\" = \"'#2d353b'\" ]"
check "A no accent-color key on GNOME 46" "[ -z \"\$(db /org/gnome/desktop/interface/accent-color)\" ]"
keys_out="$("$KIT_BIN_DIR/kit-desk" keys)"
check "A kit-desk keys prints the table" "grep -q 'Swap window left' <<<\"\$keys_out\" && grep -q 'SUPER + 1..6' <<<\"\$keys_out\""
check "A US layout: Super+= named EQUAL, no German note" "grep -q 'SUPER + EQUAL  *Wider main area' <<<\"\$keys_out\" && ! grep -q 'German keyboard' <<<\"\$keys_out\""
dconf write /org/gnome/desktop/input-sources/mru-sources "[('xkb', 'de'), ('xkb', 'us')]"
# shellcheck disable=SC2034  # used inside the check string
keys_de="$("$KIT_BIN_DIR/kit-desk" keys)"
dconf reset /org/gnome/desktop/input-sources/mru-sources
check "A German input source active: the + key named PLUS, note on the German keys" "grep -q 'SUPER + PLUS  *Wider main area' <<<\"\$keys_de\" && grep -q 'German keyboard layout: PLUS is the + key' <<<\"\$keys_de\" && grep -q 'SUPER + MINUS  *Narrower main area' <<<\"\$keys_de\""
printf 'XKBLAYOUT="de,us"\n' >"$W/keyboard"
# shellcheck disable=SC2034  # used inside the check string
keys_sys="$(KIT_KEYBOARD_FILE="$W/keyboard" "$KIT_BIN_DIR/kit-desk" keys)"
check "A no input source set: the system layout (de) decides" "grep -q 'SUPER + PLUS  *Wider main area' <<<\"\$keys_sys\""
check "A GNOME binds Super+plus (German + key, US = key), not Super+equal (German Super+0)" "! grep -q '<Super>equal' '$FAKE_DB'"
check "A kit-desk welcome runs once" "'$KIT_BIN_DIR/kit-desk' welcome >/dev/null 2>&1; [ -f '$KIT_DATA_DIR/desktop/state/welcome-shown' ]"
check "A kit-desk power menu cancels cleanly" "echo | KIT_DESK_TTY=1 '$KIT_BIN_DIR/kit-desk' power >/dev/null 2>&1"
check "A kit-desk theme --list" "[ \"\$('$KIT_BIN_DIR/kit-desk' theme --list | wc -l | tr -d ' ')\" = 10 ]"
j1="$(wc -l <"$KIT_DATA_DIR/desktop/state/dconf-journal.tsv")"
cp "$FAKE_DB" "$W/a.after1"
bash "$MOD/install.sh" --tiler tilingshell >/dev/null 2>&1 || bad "A rerun exits 0"
check "A rerun leaves dconf unchanged" "cmp -s '$W/a.after1' '$FAKE_DB'"
check "A rerun adds no journal lines" "[ \"\$(wc -l <'$KIT_DATA_DIR/desktop/state/dconf-journal.tsv')\" = '$j1' ]"
check "A rerun makes no new backups" "! beside && [ \"\$(nbak)\" = 2 ]"
check "A Just Perfection's enable-animations journaled before it starts" "grep -q '^/org/gnome/desktop/interface/enable-animations	unset' '$KIT_DATA_DIR/desktop/state/dconf-journal.tsv'"
# a kit update changes the module's own files: re-install replaces them without backups
UPD="$W/upd"; rm -rf "$UPD"; mkdir -p "$UPD"; cp -R "$MOD" "$UPD/95-desktop"
echo '# updated' >>"$UPD/95-desktop/bin/kit-desk"
KIT_ROOT="$MOD/../.." bash "$UPD/95-desktop/install.sh" --tiler tilingshell >/dev/null 2>&1 || bad "A install of an updated kit exits 0"
check "A updated kit: kit-desk replaced, no backup of our own file" "grep -q '^# updated' '$KIT_BIN_DIR/kit-desk' && ! beside && [ \"\$(nbak)\" = 2 ]"
dconf write /org/gnome/desktop/interface/enable-animations true # what Just Perfection does at start
"$KIT_BIN_DIR/kit-desk" theme tokyo-night >/dev/null
check "A theme switch: background file of the new theme, old one removed" "f=\$(uri_file /org/gnome/desktop/background/picture-uri) && grep -q '#1a1b26' \"\$f\" && [ \"\$(ls '$HOME/.config/work-kit/desktop/theme/' | grep -c '^background-')\" = 1 ]"
check "A theme switch to tokyo-night" "grep -q '#1a1b26' '$HOME/.config/work-kit/desktop/theme/alacritty.toml' && [ \"\$(db /org/gnome/desktop/interface/gtk-theme)\" = \"'Yaru-dark'\" ]"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "A uninstall exits 0"
check "A uninstall restores dconf exactly" "diff <(sort '$W/a.orig') <(sort '$FAKE_DB') >/dev/null"
check "A uninstall puts the user's files back, backups gone" "grep -q 'user lazygit' '$KIT_BIN_DIR/lazygit' && grep -q 'user nvim' '$KIT_BIN_DIR/nvim' && [ ! -L '$KIT_BIN_DIR/nvim' ] && [ \"\$(nbak)\" = 0 ] && ! find '$BK' -name '*.origin' | grep -q ."
check "A uninstall removes files" "[ ! -e '$KIT_BIN_DIR/kit-desk' ] && [ ! -d '$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com' ] && [ ! -e '$HOME/.config/nvim/init.lua' ]"
check "A uninstall keeps own ghostty config" "grep -q 'font-size = 14' '$HOME/.config/ghostty/config'"
check "A backups kept" "[ -f '$KIT_DATA_DIR/desktop/backup/dconf-original.ini' ]"
check "A uninstall twice is harmless" "bash '$MOD/uninstall.sh' >/dev/null 2>&1"

# ---- B: IT policy: user extensions disabled + locked, close key locked ----------------------------
fresh_home b
echo "/org/gnome/shell/disable-user-extensions=true" >>"$FAKE_DB"; cp "$FAKE_DB" "$W/b.orig"
printf '%s\n' /org/gnome/shell/disable-user-extensions /org/gnome/shell/enabled-extensions $KB/close >"$FAKE_LOCKS"
out="$(bash "$MOD/install.sh" 2>&1)" || bad "B install exits 0 despite policy"
check "B report names the policy" "grep -q 'user extensions disabled and locked' <<<\"\$out\""
check "B report names locked keys" "grep -q 'locked by policy, not changed: $KB/close' <<<\"\$out\""
check "B no extension installed" "[ ! -d '$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com' ]"
check "B locked close key unchanged" "[ \"\$(db $KB/close)\" = \"['<Alt>F4']\" ]"
check "B GNOME half tiling kept without tiler" "[ -z \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" ]"
check "B no tiler: Super+Shift+arrows keep move-to-monitor" "[ \"\$(db $KB/move-to-monitor-left)\" = \"['<Super><Shift><Alt>Left', '<Super><Shift>Left']\" ]"
check "B no clipboard key without the extension" "[ -z \"\$(db /org/gnome/shell/extensions/clipboard-indicator/toggle-menu)\" ]"
check "B other keys still applied" "[ \"\$(db $KB/switch-to-workspace-2)\" = \"['<Super>2']\" ]"
bash "$MOD/uninstall.sh" >/dev/null 2>&1
check "B uninstall restores dconf exactly" "diff <(sort '$W/b.orig') <(sort '$FAKE_DB') >/dev/null"

# ---- P: PaperWM: Omarchy keys on PaperWM actions; its own key overrides are handed back ---------
fresh_home p; export FAKE_GNOME=50
bash "$MOD/install.sh" --tiler paperwm --skip fonts,terminal,tuis,nvim >/dev/null 2>&1 || bad "P install exits 0"
PK=/org/gnome/shell/extensions/paperwm/keybindings
check "P Super+Return left to the terminal (PaperWM new-window cleared)" "[ \"\$(db $PK/new-window)\" = '@as []' ] && grep -q \"binding='<Super>Return'\" '$FAKE_DB'"
check "P Super+T floats, Super+F full screen, Super+Alt+F full width" "[ \"\$(db $PK/toggle-scratch)\" = \"['<Super>t']\" ] && [ \"\$(db $PK/paper-toggle-fullscreen)\" = \"['<Super>f']\" ] && [ \"\$(db $PK/toggle-maximize-width)\" = \"['<Super><Alt>f']\" ]"
check "P Super+Shift+arrows move, Super+Shift+Alt+arrows to the next monitor" "[ \"\$(db $PK/move-left)\" = \"['<Super><Shift>Left', '<Super><Shift>comma']\" ] && [ \"\$(db $PK/move-monitor-right)\" = \"['<Super><Shift><Alt>Right', '<Super><Shift><Control>Right']\" ]"
check "P Super+plus wider, drift keys (German Super+8 / Super+9) cleared" "[ \"\$(db $PK/resize-w-inc)\" = \"['<Super>plus']\" ] && [ \"\$(db $PK/drift-left)\" = '@as []' ] && [ \"\$(db $PK/drift-right)\" = '@as []' ]"
check "P kit keys not taken (Super+Escape, Super+Comma, Super+Tab, Super+Ctrl+B)" "for k in toggle-scratch-layer switch-previous live-alt-tab toggle-top-and-position-bar switch-down-workspace; do [ \"\$(db $PK/\$k)\" = '@as []' ] || exit 1; done"
# what PaperWM does at start: save and empty conflicting GNOME keys (one the kit journaled, one it did not)
dconf write /org/gnome/shell/extensions/paperwm/restore-keybinds "'{\"cancel-input-capture\":{\"bind\":\"[\\\\\"<Super><Shift>Escape\\\\\"]\",\"schema_id\":\"org.gnome.mutter.keybindings\"},\"switch-applications\":{\"bind\":\"[\\\\\"<Super>Tab\\\\\"]\",\"schema_id\":\"org.gnome.desktop.wm.keybindings\"}}'"
dconf write /org/gnome/mutter/keybindings/cancel-input-capture '@as []'
bash "$MOD/uninstall.sh" >/dev/null 2>&1
check "P uninstall leaves a one-time GNOME login script" "[ -f '$HOME/.config/autostart/work-kit-desktop-restore.desktop' ] && [ -f '$KIT_DATA_DIR/desktop-restore-gnome/restore.sh' ]"
# what PaperWM and Just Perfection do when they stop in the running session, after uninstall.sh
dconf write /org/gnome/mutter/keybindings/cancel-input-capture "['<Super><Shift>Escape']"
dconf write /org/gnome/desktop/interface/enable-animations true
dconf write /org/gnome/mutter/workspaces-only-on-primary true
dconf write /org/gnome/shell/extensions/space-bar/appearance/application-styles "'x'"
bash "$KIT_DATA_DIR/desktop-restore-gnome/restore.sh" # next login
check "P after the login script dconf equals the original (PaperWM keys settled)" "diff <(sort '$W/p.orig') <(sort '$FAKE_DB') >/dev/null"
check "P login script removed itself" "[ ! -e '$HOME/.config/autostart/work-kit-desktop-restore.desktop' ] && [ ! -e '$KIT_DATA_DIR/desktop-restore-gnome' ]"
export FAKE_GNOME=46

# ---- T: Tactile: Ubuntu's Tiling Assistant keeps Super+arrows (half tiling, maximize) ----------
fresh_home t; export FAKE_GNOME=50
cp "$FAKE_DB" "$W/t.orig"
bash "$MOD/install.sh" --tiler tactile --skip fonts,terminal,tuis,nvim --defer no >/dev/null 2>&1 || bad "T install exits 0"
check "T Tiling Assistant stays, GNOME tiling keys untouched with Tactile" "! db /org/gnome/shell/disabled-extensions | grep -q tiling-assistant && [ -z \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" ] && [ -z \"\$(db $KB/maximize)\" ]"
check "T key table explains Tactile's Super+T" "'$KIT_BIN_DIR/kit-desk' keys | grep 'Tactile grid' >/dev/null"
bash "$MOD/uninstall.sh" >/dev/null 2>&1; bash "$KIT_DATA_DIR/desktop-restore-gnome/restore.sh" 2>/dev/null || true
check "T uninstall restores dconf exactly" "diff <(sort '$W/t.orig') <(sort '$FAKE_DB') >/dev/null"
export FAKE_GNOME=46

# ---- KT: the kit tiler (default): installed from the module, Omarchy keys in its own schema ------
fresh_home kt; export FAKE_GNOME=50
AT=/org/gnome/shell/extensions/kit-tiling
bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim --defer no >/dev/null 2>&1 || bad "KT install exits 0"
check "KT kit tiler installed from the module folder and enabled, Tiling Shell not" "[ -f '$HOME/.local/share/gnome-shell/extensions/kit-tiling@work-kit/extension.js' ] && [ -f '$HOME/.local/share/gnome-shell/extensions/kit-tiling@work-kit/schemas/gschemas.compiled' ] && db /org/gnome/shell/enabled-extensions | grep -q kit-tiling@work-kit && [ ! -d '$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com' ]"
check "KT focus and swap keys in the kit tiler's schema" "[ \"\$(db $AT/focus-window-left)\" = \"['<Super>Left']\" ] && [ \"\$(db $AT/move-window-down)\" = \"['<Super><Shift>Down']\" ] && [ -z \"\$(db /org/gnome/shell/extensions/tilingshell/focus-window-left)\" ]"
check "KT Super+Shift+Alt+arrows go to the kit tiler, not GNOME's move-to-monitor" "[ \"\$(db $AT/window-to-monitor-right)\" = \"['<Super><Shift><Alt>Right']\" ] && [ \"\$(db $KB/move-to-monitor-right)\" = '@as []' ]"
check "KT float, next layout, monocle, main area narrower / wider" "[ \"\$(db $AT/untile-window)\" = \"['<Super>t']\" ] && [ \"\$(db $AT/cycle-layouts)\" = \"['<Super>l']\" ] && [ \"\$(db $AT/span-window-all-tiles)\" = \"['<Super><Control>f']\" ] && [ \"\$(db $AT/shrink-main)\" = \"['<Super>minus']\" ] && [ \"\$(db $AT/grow-main)\" = \"['<Super>plus']\" ]"
check "KT Tiling Assistant's own Super+arrow keys emptied (a failed live disable keeps them)" "[ \"\$(db /org/gnome/shell/extensions/tiling-assistant/tile-left-half)\" = '@as []' ] && [ \"\$(db /org/gnome/shell/extensions/tiling-assistant/tile-maximize)\" = '@as []' ]"
check "KT dock not fixed (no reserved strip even if its live disable fails), no auto-maximize" "[ \"\$(db /org/gnome/shell/extensions/dash-to-dock/dock-fixed)\" = false ] && [ \"\$(db /org/gnome/mutter/auto-maximize)\" = false ]"
check "KT GNOME's own half tiling freed, Tiling Assistant off, lock on Super+Ctrl+L" "[ \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" = '@as []' ] && db /org/gnome/shell/disabled-extensions | grep -q tiling-assistant && [ \"\$(db /org/gnome/settings-daemon/plugins/media-keys/screensaver)\" = \"['<Super><Control>l']\" ]"
# shellcheck disable=SC2034  # used inside the check string
kt_keys="$("$KIT_BIN_DIR/kit-desk" keys)"
check "KT key table: kit tiler rows active" "grep -q 'Wider main area' <<<\"\$kt_keys\" && ! grep -q 'kit tiler only' <<<\"\$kt_keys\" && grep -q 'Toggle floating (again: back into the tiles)' <<<\"\$kt_keys\""
cp "$FAKE_DB" "$W/kt.after1"; kj="$(wc -l <"$KIT_DATA_DIR/desktop/state/dconf-journal.tsv")"
bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim --defer no >/dev/null 2>&1 || bad "KT rerun exits 0"
check "KT rerun: dconf and journal unchanged" "cmp -s '$W/kt.after1' '$FAKE_DB' && [ \"\$(wc -l <'$KIT_DATA_DIR/desktop/state/dconf-journal.tsv')\" = '$kj' ]"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "KT uninstall exits 0"
bash "$KIT_DATA_DIR/desktop-restore-gnome/restore.sh" >/dev/null 2>&1 || true
check "KT uninstall (and login script) restore dconf exactly, extension gone" "diff <(sort '$W/kt.orig') <(sort '$FAKE_DB') >/dev/null && [ ! -d '$HOME/.local/share/gnome-shell/extensions/kit-tiling@work-kit' ]"
# KT3: Wayland deferral; Ubuntu's Tiling Assistant puts GNOME's Super+Left back while it stops
fresh_home kt3; export FAKE_GNOME=50
mkdir -p "$W/tastop"
cat >"$W/tastop/gnome-extensions" <<'EOF2'
#!/bin/sh
# the tiler runs; the Tiling Assistant, asked for its state after the disable, restores its originals
[ "$1" = info ] || exit 0
if [ "$2" = tiling-assistant@ubuntu.com ]; then dconf reset /org/gnome/mutter/keybindings/toggle-tiled-left; printf '  %s\n  State: INACTIVE\n' "$2"
else printf '  %s\n  State: ACTIVE\n' "$2"; fi
EOF2
chmod +x "$W/tastop/gnome-extensions"
bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim --defer yes >/dev/null 2>&1 || bad "KT3 install exits 0"
PATH="$W/tastop:$PATH" "$KIT_BIN_DIR/kit-desk" finish-login >/dev/null 2>&1 || bad "KT3 finish-login exits 0"
check "KT3 finish-login writes GNOME's tiling keys again after the assistant stopped" "[ \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" = '@as []' ] && [ \"\$(db $AT/focus-window-left)\" = \"['<Super>Left']\" ]"
T="$(printf '\t')"
# KT4: Ubuntu's Tiling Assistant ran before the install: it held GNOME's tiling keys (empty) and saved
# the originals in its overridden-settings; the kit journals those originals and writes anyway
fresh_home kt4; export FAKE_GNOME=50
cat >>"$FAKE_DB" <<'EOF2'
/org/gnome/mutter/keybindings/toggle-tiled-left=@as []
/org/gnome/desktop/wm/keybindings/maximize=@as []
/org/gnome/shell/extensions/tiling-assistant/overridden-settings={'org.gnome.mutter.edge-tiling': <@mb nothing>, 'org.gnome.desktop.wm.keybindings.maximize': <['<Super>Up']>, 'org.gnome.mutter.keybindings.toggle-tiled-left': <@mb nothing>}
EOF2
bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim --defer yes >/dev/null 2>&1 || bad "KT4 install exits 0"
check "KT4 GNOME's tiling keys queued although already empty" "grep -q 'toggle-tiled-left' '$KIT_DATA_DIR/desktop/state/pending-login.tsv' && grep -q 'wm/keybindings/maximize' '$KIT_DATA_DIR/desktop/state/pending-login.tsv'"
check "KT4 originals journaled from the assistant's record" "grep -q \"^/org/gnome/mutter/keybindings/toggle-tiled-left${T}unset\" '$KIT_DATA_DIR/desktop/state/dconf-journal.tsv' && grep -qF \"/org/gnome/desktop/wm/keybindings/maximize${T}set${T}['<Super>Up']\" '$KIT_DATA_DIR/desktop/state/dconf-journal.tsv'"
PATH="$W/tastop:$PATH" "$KIT_BIN_DIR/kit-desk" finish-login >/dev/null 2>&1 || bad "KT4 finish-login exits 0"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "KT4 uninstall exits 0"
check "KT4 uninstall puts GNOME's originals back (not the assistant's empty lists)" "[ -z \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" ] && [ \"\$(db $KB/maximize)\" = \"['<Super>Up']\" ]"
fresh_home kt2; export FAKE_GNOME=46
out="$(bash "$MOD/install.sh" --tiler tilingshell --skip fonts,terminal,tuis,nvim --defer no 2>&1)" || bad "KT2 install exits 0"
# shellcheck disable=SC2034  # used inside the check string
kt2_keys="$("$KIT_BIN_DIR/kit-desk" keys)"
check "KT2 with Tiling Shell the kit tiler rows are marked, no kit tiler keys" "grep -q 'Wider main area (kit tiler only)' <<<\"\$kt2_keys\" && [ -z \"\$(db $AT/shrink-main)\" ]"
if command -v node >/dev/null 2>&1; then
  check "KT layout math (tests/test-layout.mjs, node)" "node '$HERE/test-layout.mjs' >/dev/null"
elif command -v gjs >/dev/null 2>&1; then
  check "KT layout math (tests/test-layout.mjs, gjs)" "gjs -m '$HERE/test-layout.mjs' >/dev/null"
else
  echo "skip KT layout math: neither node nor gjs on PATH (run: node tests/test-layout.mjs)"
fi
export FAKE_GNOME=46

# ---- C: GNOME versions: 50 exact, 48 -> 46 zips, 51 -> 50 zips (Space Bar 50-only is skipped) --------
for g in 50 48 51; do
  fresh_home "c$g"; export FAKE_GNOME=$g
  out="$(bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim 2>&1)" || bad "C$g install exits 0"
  case "$g" in
    50) check "C50 Space Bar from the 50 zip" "grep -q '\"50\"' '$HOME/.local/share/gnome-shell/extensions/space-bar@luchrioh/metadata.json'"
        check "C50 accent-color set" "[ \"\$(db /org/gnome/desktop/interface/accent-color)\" = \"'green'\" ]" ;;
    48) check "C48 Space Bar from the 46 zip" "grep -q '\"48\"' '$HOME/.local/share/gnome-shell/extensions/space-bar@luchrioh/metadata.json'" ;;
    51) check "C51 Space Bar skipped (no GNOME 51 support)" "grep -q 'space-bar@luchrioh: zip does not support GNOME 51' <<<\"\$out\" && [ ! -d '$HOME/.local/share/gnome-shell/extensions/space-bar@luchrioh' ]"
        check "C51 kit tiler skipped too (46-50 only)" "grep -q 'kit-tiling@work-kit: zip does not support GNOME 51' <<<\"\$out\""
        check "C51 GNOME tiling keys kept" "[ -z \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" ]" ;;
  esac
done
export FAKE_GNOME=46

# ---- D: alternative tiler, optional parts, dry run, no GNOME ---------------------------------------
fresh_home d
bash "$MOD/install.sh" --tiler paperwm --with zellij,zed --workspaces 10 --skip input >/dev/null 2>&1 || bad "D install exits 0"
check "D PaperWM enabled, no Tiling Shell" "db /org/gnome/shell/enabled-extensions | grep -q paperwm && ! db /org/gnome/shell/enabled-extensions | grep -q tilingshell"
check "D PaperWM 2 px between windows, no margins" "[ \"\$(db /org/gnome/shell/extensions/paperwm/window-gap)\" = 2 ] && [ \"\$(db /org/gnome/shell/extensions/paperwm/horizontal-margin)\" = 0 ]"
check "D Super+0 is workspace 10" "[ \"\$(db $KB/switch-to-workspace-10)\" = \"['<Super>0']\" ]"
check "D zellij and zed installed" "[ -x '$KIT_BIN_DIR/zellij' ] && [ -L '$KIT_BIN_DIR/zed' ] && grep -q 'Exec=.*zed.app/bin/zed' '$HOME/.local/share/applications/dev.zed.Zed.desktop'"
check "D --skip input leaves xkb alone" "[ -z \"\$(db /org/gnome/desktop/input-sources/xkb-options)\" ]"
fresh_home e
bash "$MOD/install.sh" --dry-run >/dev/null 2>&1 || bad "E dry run exits 0"
check "E dry run changes no dconf key" "cmp -s '$W/e.orig' '$FAKE_DB'"
check "E dry run writes no files" "[ ! -e '$HOME/.local' ] && [ ! -e '$HOME/.config' ]"
fresh_home f
mkdir -p "$W/nognome"; for s in dconf gsettings; do ln -sf "$HERE/stubs/$s" "$W/nognome/$s"; done
PATH="$W/nognome:/usr/bin:/bin" bash "$MOD/install.sh" >"$W/f.out" 2>&1 || bad "F install without GNOME exits 0"
check "F report says: no desktop changes" "grep -q 'no window manager changes' '$W/f.out'"
check "F no dconf change" "cmp -s '$W/f.orig' '$FAKE_DB'"
check "F terminal tools still installed" "[ -x '$KIT_BIN_DIR/lazygit' ] && [ -f '$HOME/.config/work-kit/desktop/theme/ghostty.conf' ]"

check "D apt.sh reports missing 01-prereqs item" "! bash '$MOD/apt.sh' --print alacritty >/dev/null 2>&1 || grep -q '^alacritty' '$MOD/../01-prereqs/items.conf'"

# ---- W: GNOME on Wayland: dock and tiler keys wait for the next login ---------------------------------
AS="$HOME/.config/autostart"
fresh_home w
export XDG_SESSION_TYPE=wayland
out="$(bash "$MOD/install.sh" --tiler tilingshell 2>&1)" || { bad "W install exits 0"; printf '%s\n' "$out"; }
AS="$HOME/.config/autostart"; PEND="$KIT_DATA_DIR/desktop/state/pending-login.tsv"
check "W extensions enabled at once" "db /org/gnome/shell/enabled-extensions | grep -q tilingshell@ferrarodomenico.com"
check "W Ubuntu Dock and desktop icons still enabled" "! db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && ! db /org/gnome/shell/disabled-extensions | grep -q ding@rastersoft.com"
check "W tiling assistant not yet disabled" "! db /org/gnome/shell/disabled-extensions | grep -q tiling-assistant@ubuntu.com"
check "W GNOME half tiling and maximize untouched" "[ -z \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" ] && [ -z \"\$(db $KB/maximize)\" ] && [ -z \"\$(db /org/gnome/mutter/edge-tiling)\" ]"
check "W tiler keys not yet written" "[ -z \"\$(db /org/gnome/shell/extensions/tilingshell/focus-window-left)\" ]"
check "W Super+L still locks, Super+Shift+arrows still move to monitor" "db /org/gnome/settings-daemon/plugins/media-keys/screensaver | grep -q \"'<Super>l'\" && db $KB/move-to-monitor-left | grep -q \"'<Super><Shift>Left'\""
check "W kit shortcuts and settings applied now" "[ \"\$(db $KB/switch-to-workspace-2)\" = \"['<Super>2']\" ] && [ \"\$(db /org/gnome/mutter/dynamic-workspaces)\" = false ]"
check "W one-shot autostart entry (login mode)" "grep -qx 'Exec=$KIT_BIN_DIR/kit-desk finish-login --login' '$AS/work-kit-desktop-finish-login.desktop'"
check "W queue lists the dock and the tiler keys" "grep -q 'ubuntu-dock@ubuntu.com' '$PEND' && grep -q 'tilingshell/focus-window-left' '$PEND' && grep -q 'toggle-tiled-left' '$PEND'"
check "W report says what is pending" "grep -q 'PENDING until the next login' <<<\"\$out\" && grep -q 'Ubuntu Dock and desktop icons stay on' <<<\"\$out\" && grep -q 'Log out and back in: the extensions load and the pending changes apply' <<<\"\$out\""
check "W report file keeps it for kit-desk status" "grep -q 'PENDING until the next login' '$KIT_DATA_DIR/desktop/state/last-report.txt'"
check "W install.conf marks pending_login" "grep -qx pending_login=1 '$KIT_DATA_DIR/desktop/state/install.conf' && grep -qx defer_anchor=tilingshell@ferrarodomenico.com '$KIT_DATA_DIR/desktop/state/install.conf'"
# shellcheck disable=SC2034  # used inside the check string
st="$("$KIT_BIN_DIR/kit-desk" status)"
check "W kit-desk status shows the pending changes" "grep -q '^PENDING until the next login' <<<\"\$st\" && grep -q 'Ubuntu Dock and desktop icons stay on' <<<\"\$st\" && grep -q 'Applied automatically at the next login' <<<\"\$st\""
cp "$FAKE_DB" "$W/w.before"; cp "$PEND" "$W/w.pend"
bash "$MOD/install.sh" --tiler tilingshell >/dev/null 2>&1 || bad "W rerun exits 0"
check "W rerun before login: same dconf, same queue" "cmp -s '$W/w.before' '$FAKE_DB' && cmp -s '$W/w.pend' '$PEND'"
# the login: the tiling extension runs (stub gnome-extensions), autostart applies the queue once
mkdir -p "$W/live"
# shellcheck disable=SC2016  # literal stub script text
printf '#!/bin/sh\n[ "$1" = info ] && printf "  %%s\\n  State: ACTIVE\\n" "$2"\n' >"$W/live/gnome-extensions"; chmod +x "$W/live/gnome-extensions"
mkdir -p "$W/broken"
# shellcheck disable=SC2016  # literal stub script text
printf '#!/bin/sh\n[ "$1" = info ] && printf "  %%s\\n  State: ERROR\\n" "$2"\n' >"$W/broken/gnome-extensions"; chmod +x "$W/broken/gnome-extensions"
# shellcheck disable=SC2034  # used inside the check string
fl_out="$(PATH="$W/broken:$PATH" KIT_DESK_FINISH_WAIT=12 "$KIT_BIN_DIR/kit-desk" finish-login 2>&1)" && bad "W finish-login refuses when the tiler did not load"
check "W tiler failed: dock stays, queue and dconf untouched, entry kept for the next login" "cmp -s '$W/w.before' '$FAKE_DB' && [ -s '$PEND' ] && [ -e '$AS/work-kit-desktop-finish-login.desktop' ] && grep -q 'changes not applied' '$KIT_DATA_DIR/desktop/state/last-report.txt'"
check "W by hand: says to run it inside the desktop session, logs the states" "grep -q 'Run this inside the desktop session' <<<\"\$fl_out\" && grep -q 'state after 0s: ERROR' '$KIT_DATA_DIR/desktop/state/finish-login.log'"
# shellcheck disable=SC2034  # used inside the check string
st="$("$KIT_BIN_DIR/kit-desk" status)"
check "W status still says pending, and how to apply by hand" "grep -q 'Applied automatically at the next login' <<<\"\$st\" && grep -q 'Still pending after a login? Run in a terminal of the desktop session: kit-desk finish-login' <<<\"\$st\" && grep -q 'Last runs' <<<\"\$st\""
# the owner's VM (2026-09-27): early in the login gnome-extensions failed (exit 2, the shell's extension
# service not up yet); set -e ended finish-login without a word. Now it waits and applies.
mkdir -p "$W/slow"
cat >"$W/slow/gnome-extensions" <<'EOF2'
#!/bin/sh
# fails the first 3 calls like a shell that is still starting, then the extension runs
n="$(cat "$SLOW_COUNT" 2>/dev/null || echo 0)"; echo $((n + 1)) >"$SLOW_COUNT"
if [ "$n" -lt 3 ]; then echo "Failed to connect to GNOME Shell" >&2; exit 2; fi
[ "$1" = info ] && printf '  %s\n  State: ACTIVE\n' "$2"
exit 0
EOF2
chmod +x "$W/slow/gnome-extensions"
mkdir "$KIT_DATA_DIR/desktop/state/finish-login.lock"
PATH="$W/live:$PATH" "$KIT_BIN_DIR/kit-desk" finish-login --login >/dev/null 2>&1 || bad "W finish-login with a run in progress exits 0"
check "W a second run while one runs changes nothing" "cmp -s '$W/w.before' '$FAKE_DB' && [ -s '$PEND' ] && grep -q 'another finish-login is running' '$KIT_DATA_DIR/desktop/state/finish-login.log'"
rmdir "$KIT_DATA_DIR/desktop/state/finish-login.lock"
# shellcheck disable=SC2034  # used inside the check string
fl_out="$(PATH="$W/slow:$PATH" SLOW_COUNT="$W/slow/n" KIT_DESK_FINISH_WAIT=20 "$KIT_BIN_DIR/kit-desk" finish-login --login 2>&1)" || bad "W login run with a slow shell exits 0"
check "W slow shell: waited, applied, logged, quiet at the login" "[ ! -e '$PEND' ] && db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && grep -q 'state after 0s: unknown' '$KIT_DATA_DIR/desktop/state/finish-login.log' && grep -q 'done: queue applied, autostart entry removed' '$KIT_DATA_DIR/desktop/state/finish-login.log' && ! grep -q 'state after' <<<\"\$fl_out\" && [ ! -e '$KIT_DATA_DIR/desktop/state/finish-login.lock' ]"
check "W after login: dock and ding disabled, tiling assistant disabled" "db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && db /org/gnome/shell/disabled-extensions | grep -q ding@rastersoft.com && db /org/gnome/shell/disabled-extensions | grep -q tiling-assistant@ubuntu.com"
check "W after login: tiler keys and freed GNOME keys" "[ \"\$(db /org/gnome/shell/extensions/tilingshell/focus-window-left)\" = \"['<Super>Left']\" ] && [ \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" = '@as []' ] && [ \"\$(db /org/gnome/mutter/edge-tiling)\" = false ]"
check "W after login: Super+L is the layout key, lock on Super+Ctrl+L" "[ \"\$(db /org/gnome/settings-daemon/plugins/media-keys/screensaver)\" = \"['<Super><Control>l']\" ]"
check "W after login: queue and autostart entry gone, install.conf cleared" "[ ! -e '$PEND' ] && [ ! -e '$AS/work-kit-desktop-finish-login.desktop' ] && grep -qx pending_login=0 '$KIT_DATA_DIR/desktop/state/install.conf' && ! grep -q finish-login '$KIT_DATA_DIR/desktop/state/files.tsv'"
# shellcheck disable=SC2034  # used inside the check string
st="$("$KIT_BIN_DIR/kit-desk" status)"
check "W status: nothing pending any more" "! grep -q '^PENDING' <<<\"\$st\""
"$KIT_BIN_DIR/kit-desk" finish-login >/dev/null 2>&1 || bad "W second finish-login exits 0"
cp "$FAKE_DB" "$W/w.after"
bash "$MOD/install.sh" --tiler tilingshell >/dev/null 2>&1 || bad "W rerun after login exits 0"
check "W rerun after login changes nothing and queues nothing" "cmp -s '$W/w.after' '$FAKE_DB' && [ ! -e '$PEND' ] && [ ! -e '$AS/work-kit-desktop-finish-login.desktop' ]"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "W uninstall exits 0"
check "W uninstall restores dconf exactly (login run included)" "diff <(sort '$W/w.orig') <(sort '$FAKE_DB') >/dev/null"

# W2: uninstall while the login step is still pending (never logged in again)
fresh_home w2
bash "$MOD/install.sh" --tiler tilingshell >/dev/null 2>&1 || bad "W2 install exits 0"
check "W2 autostart entry and queue present" "[ -f '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ] && [ -s '$KIT_DATA_DIR/desktop/state/pending-login.tsv' ]"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "W2 uninstall exits 0"
check "W2 uninstall removes the pending autostart entry and restores dconf" "[ ! -e '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ] && [ ! -d '$KIT_DATA_DIR/desktop/state' ] && diff <(sort '$W/w2.orig') <(sort '$FAKE_DB') >/dev/null"
# W3: the entry is removed even when the state directory is already gone
fresh_home w3
mkdir -p "$HOME/.config/autostart"; touch "$HOME/.config/autostart/work-kit-desktop-finish-login.desktop"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "W3 uninstall exits 0"
check "W3 stray pending entry removed without state" "[ ! -e '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ]"

# W4: --defer no on Wayland, an already running tiler, --defer yes on X11, dry run
fresh_home w4
bash "$MOD/install.sh" --tiler tilingshell --defer no >/dev/null 2>&1 || bad "W4 install exits 0"
check "W4 --defer no: dock off at once, no entry" "db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && [ ! -e '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ] && [ ! -e '$KIT_DATA_DIR/desktop/state/pending-login.tsv' ]"
fresh_home w5
out="$(PATH="$W/live:$PATH" bash "$MOD/install.sh" --tiler tilingshell 2>&1)" || bad "W5 install exits 0"
check "W5 extension already live on Wayland: applied at once" "db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && [ ! -e '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ] && ! grep -q PENDING <<<\"\$out\""
export XDG_SESSION_TYPE=x11
fresh_home w6
out="$(bash "$MOD/install.sh" --tiler tilingshell 2>&1)" || bad "W6 install exits 0"
check "W6 X11: dock off at once, no pending entry, restart hint" "db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && [ ! -e '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ] && grep -q 'Alt+F2, r' <<<\"\$out\""
fresh_home w7
bash "$MOD/install.sh" --tiler tilingshell --defer yes >/dev/null 2>&1 || bad "W7 install exits 0"
check "W7 --defer yes on X11: dock kept until finish-login" "! db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && [ -f '$HOME/.config/autostart/work-kit-desktop-finish-login.desktop' ]"
export XDG_SESSION_TYPE=wayland
fresh_home w8
out="$(bash "$MOD/install.sh" --tiler tilingshell --dry-run 2>&1)" || bad "W8 dry run exits 0"
check "W8 dry run on Wayland: no change, no file, says what waits" "cmp -s '$W/w8.orig' '$FAKE_DB' && [ ! -e '$HOME/.config' ] && grep -q 'at next login: add /org/gnome/shell/disabled-extensions ubuntu-dock@ubuntu.com' <<<\"\$out\""
fresh_home w9
bash "$MOD/install.sh" --tiler none >/dev/null 2>&1 || bad "W9 install exits 0"
check "W9 --tiler none on Wayland: dock still waits for the login" "! db /org/gnome/shell/disabled-extensions | grep -q ubuntu-dock@ubuntu.com && grep -q ubuntu-dock@ubuntu.com '$KIT_DATA_DIR/desktop/state/pending-login.tsv'"
fresh_home w10
bash "$MOD/install.sh" --tiler tilingshell --keep-dock >/dev/null 2>&1 || bad "W10 install exits 0"
check "W10 --keep-dock: dock never queued, tiler keys still wait" "! grep -q ubuntu-dock@ubuntu.com '$KIT_DATA_DIR/desktop/state/pending-login.tsv' && grep -q tilingshell/focus-window-left '$KIT_DATA_DIR/desktop/state/pending-login.tsv'"
export XDG_SESSION_TYPE=x11

# ---- K: KDE Plasma 5 and 6 (stub kreadconfig/kwriteconfig/kpackagetool/plasmashell) ----------------
mkdir -p "$OFF/kde"; echo fake >"$OFF/kde/krohnkite-0.8.1.kwinscript"; echo fake >"$OFF/kde/krohnkite-0.9.9.2.kwinscript"
mkdir -p "$W/kde6"; for t in kwriteconfig kreadconfig kpackagetool; do ln -sf "$HERE/stubs/${t}5" "$W/kde6/${t}6"; done
# shellcheck disable=SC2329  # used inside check strings
kdb() { awk -v k="$1=" 'index($0,k)==1 {print substr($0,length(k)+1); exit}' "$FAKE_KDB"; }
T="$(printf '\t')"
for pv in 5 6; do
  fresh_home "k$pv"; export FAKE_KDB="$W/k$pv.kdb" FAKE_PLASMA=$pv
  g=org.kde.krunner.desktop; [ "$pv" = 6 ] && g="services>org.kde.krunner.desktop"
  if [ "$pv" = 5 ]; then
    printf '%s\n' "kglobalshortcutsrc|kwin|Window Close=Alt+F4,Alt+F4,Close Window" \
      "kglobalshortcutsrc|$g|_launch=Alt+Space${T}Alt+F2${T}Search,Alt+Space${T}Alt+F2${T}Search,KRunner" \
      "kglobalshortcutsrc|$g|_k_friendly_name=KRunner" "kwinrc|Desktops|Number=4" >"$FAKE_KDB"
  else
    printf '%s\n' "kglobalshortcutsrc|kwin|Window Close=Alt+F4,Alt+F4,Close Window" "kwinrc|Desktops|Number=4" >"$FAKE_KDB"
  fi
  sort "$FAKE_KDB" >"$W/k$pv.kdb.orig"; cp "$FAKE_DB" "$W/k$pv.dconf.orig"
  out="$(PATH="$W/kde6:$PATH" XDG_CURRENT_DESKTOP=KDE bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim 2>&1)" || bad "K$pv install exits 0"
  check "K$pv takes the KDE path" "grep -q 'desktop: KDE Plasma $pv -> KDE path' <<<\"\$out\""
  check "K$pv no dconf change" "cmp -s '$W/k$pv.dconf.orig' '$FAKE_DB'"
  check "K$pv Krohnkite installed and enabled, no gap at the edge, 2 px between windows" "[ -f '$HOME/.local/share/kwin/scripts/krohnkite/package' ] && [ \"\$(kdb 'kwinrc|Plugins|krohnkiteEnabled')\" = true ] && [ \"\$(kdb 'kwinrc|Script-krohnkite|screenGapLeft')\" = 0 ] && [ \"\$(kdb 'kwinrc|Script-krohnkite|tileLayoutGap')\" = 2 ]"
  check "K$pv Meta alone does nothing" "[ \"\$(kdb 'kwinrc|ModifierOnlyShortcuts|Meta')\" = '' ] && grep -q '^kwinrc|ModifierOnlyShortcuts|Meta=' '$FAKE_KDB'"
  check "K$pv 6 workspaces" "[ \"\$(kdb 'kwinrc|Desktops|Number')\" = 6 ]"
  check "K$pv 17 launchers and a login hook" "[ \"\$(ls '$HOME/.local/share/applications' | grep -c '^work-kit-desk-')\" = 17 ] && [ -f '$HOME/.config/plasma-workspace/env/work-kit-desktop-keys.sh' ]"
  check "K$pv shortcuts untouched until the next login" "[ \"\$(kdb 'kglobalshortcutsrc|kwin|Window Close')\" = 'Alt+F4,Alt+F4,Close Window' ]"
  PATH="$W/kde6:$PATH" "$KIT_BIN_DIR/kit-desk" kde-keys >/dev/null 2>&1 || bad "K$pv kde-keys exits 0"
  check "K$pv Super+W closes, Alt+F4 kept" "[ \"\$(kdb 'kglobalshortcutsrc|kwin|Window Close')\" = 'Meta+W${T}Alt+F4,none,Close Window' ]"
  check "K$pv Super+Shift+2 with US and German symbols" "kdb 'kglobalshortcutsrc|kwin|Window to Desktop 2' | grep -qF 'Meta+Shift+2${T}Meta+@${T}Meta+\"'"
  gw="Krohnkite: Grow Width"; gh="Krohnkite: Grow Height"; [ "$pv" = 6 ] && { gw=KrohnkitegrowWidth; gh=KrohnkiteGrowHeight; }
  sh="Krohnkite: Shrink Height"; [ "$pv" = 6 ] && sh=KrohnkiteShrinkHeight
  check "K$pv US layout: wider on Meta+=, taller on Meta++ (Shift+=), lower on Meta+_ (Shift+-), zoom off Meta++" "kdb 'kglobalshortcutsrc|kwin|$gw' | grep -q '^Meta+=,' && kdb 'kglobalshortcutsrc|kwin|$gh' | grep -q '^Meta++,' && kdb 'kglobalshortcutsrc|kwin|$sh' | grep -q '^Meta+_,' && kdb 'kglobalshortcutsrc|kwin|view_zoom_in' | grep -q '^none,'"
  cp "$FAKE_KDB" "$W/k$pv.kdb.us"
  PATH="$W/kde6:$PATH" "$KIT_BIN_DIR/kit-desk" kde-keys >/dev/null 2>&1 || bad "K$pv kde-keys again exits 0"
  check "K$pv kde-keys runs once per layout" "cmp -s '$W/k$pv.kdb.us' '$FAKE_KDB'"
  printf '[Layout]\nLayoutList=de,us\nUse=true\n' >"$HOME/.config/kxkbrc"
  PATH="$W/kde6:$PATH" "$KIT_BIN_DIR/kit-desk" kde-keys >/dev/null 2>&1 || bad "K$pv kde-keys for de exits 0"
  check "K$pv German layout: wider on Meta++ (the + key), taller on Meta+* (Shift and +), zoom off Meta++" "kdb 'kglobalshortcutsrc|kwin|$gw' | grep -q '^Meta++,' && kdb 'kglobalshortcutsrc|kwin|$gh' | grep -q '^Meta+\*,' && kdb 'kglobalshortcutsrc|kwin|$sh' | grep -q '^Meta+_,' && kdb 'kglobalshortcutsrc|kwin|view_zoom_in' | grep -q '^none,' && grep -q ' de$' '$KIT_DATA_DIR/desktop/state/kde-keys-applied'"
  # shellcheck disable=SC2034  # used inside the check string
  keys_de="$("$KIT_BIN_DIR/kit-desk" keys)"
  check "K$pv kit-desk keys names the German keys" "grep -q 'SUPER + PLUS  *Wider window' <<<\"\$keys_de\" && grep -q 'SUPER + SHIFT + PLUS  *Taller window' <<<\"\$keys_de\""
  rm -f "$HOME/.config/kxkbrc"
  nf=3; [ "$pv" = 6 ] && nf=1
  check "K$pv no launcher name splits the value" "[ \"\$(grep -c 'work-kit-desk-.*|_launch=' '$FAKE_KDB')\" = 17 ] && ! grep 'work-kit-desk-.*|_launch=' '$FAKE_KDB' | awk -F, 'NF!=$nf' | grep -q ."
  if [ "$pv" = 5 ]; then
    check "K5 KRunner on Super+Space keeps its name" "[ \"\$(kdb 'kglobalshortcutsrc|$g|_launch')\" = 'Meta+Space${T}Alt+Space${T}Alt+F2${T}Search,none,KRunner' ] && [ \"\$(kdb 'kglobalshortcutsrc|$g|_k_friendly_name')\" = KRunner ]"
    check "K5 Krohnkite focus uses its Plasma 5 name" "[ \"\$(kdb 'kglobalshortcutsrc|kwin|Krohnkite: Left')\" = 'Meta+Left,none,Krohnkite: Left' ]"
  else
    check "K6 KRunner on Super+Space (services group)" "[ \"\$(kdb 'kglobalshortcutsrc|$g|_launch')\" = 'Meta+Space${T}Alt+Space${T}Alt+F2${T}Search' ]"
    check "K6 Meta+Tab taken from Walk Through Windows (journaled), Alt+Tab kept" "[ \"\$(kdb 'kglobalshortcutsrc|kwin|Walk Through Windows')\" = 'Alt+Tab,none,Walk Through Windows' ]"
    check "K6 Krohnkite focus uses its Plasma 6 id" "[ \"\$(kdb 'kglobalshortcutsrc|kwin|KrohnkiteFocusLeft')\" = 'Meta+Left,none,Krohnkite: Left' ]"
  fi
  # shellcheck disable=SC2034  # used inside the check string
  keys_out="$("$KIT_BIN_DIR/kit-desk" keys)"
  check "K$pv kit-desk keys shows the KDE table" "grep -q 'KRunner' <<<\"\$keys_out\""
  PATH="$W/kde6:$PATH" bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "K$pv uninstall exits 0"
  check "K$pv uninstall leaves a one-time login restore" "[ -f '$HOME/.config/plasma-workspace/env/work-kit-desktop-restore.sh' ] && [ ! -e '$HOME/.config/plasma-workspace/env/work-kit-desktop-keys.sh' ]"
  PATH="$W/kde6:$PATH" bash "$KIT_DATA_DIR/desktop-restore/restore.sh" >/dev/null 2>&1 || bad "K$pv restore script exits 0"
  check "K$pv KDE config restored exactly" "diff '$W/k$pv.kdb.orig' <(sort '$FAKE_KDB') >/dev/null"
  check "K$pv restore hook removed itself, Krohnkite removed" "[ ! -e '$HOME/.config/plasma-workspace/env/work-kit-desktop-restore.sh' ] && [ ! -d '$HOME/.local/share/kwin/scripts/krohnkite' ]"
done
# K6 without kpackagetool (a minimal Plasma install): the .kwinscript zip is unpacked directly
fresh_home k6n; export FAKE_KDB="$W/k6n.kdb" FAKE_PLASMA=6
printf '%s\n' "kwinrc|Desktops|Number=4" >"$FAKE_KDB"
mkdir -p "$W/kde6n" "$W/ks/contents/code"; for t in kwriteconfig kreadconfig; do ln -sf "$HERE/stubs/${t}5" "$W/kde6n/${t}6"; done
echo '{"KPackageStructure": "KWin/Script", "KPlugin": {"Id": "krohnkite"}}' >"$W/ks/metadata.json"; echo '// fake' >"$W/ks/contents/code/main.js"
rm -f "$OFF/kde/krohnkite-0.9.9.2.kwinscript"
python3 -c 'import os,sys,zipfile
z=zipfile.ZipFile(sys.argv[1],"w")
for r,_,fs in os.walk(sys.argv[2]):
  for f in fs: p=os.path.join(r,f); z.write(p,os.path.relpath(p,sys.argv[2]))' "$OFF/kde/krohnkite-0.9.9.2.kwinscript" "$W/ks"
PATH="$W/kde6n:$PATH" XDG_CURRENT_DESKTOP=KDE bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim >/dev/null 2>&1 || bad "K6n install exits 0"
check "K6n Krohnkite unpacked without kpackagetool and enabled" "[ -f '$HOME/.local/share/kwin/scripts/krohnkite/metadata.json' ] && [ -f '$HOME/.local/share/kwin/scripts/krohnkite/contents/code/main.js' ] && [ \"\$(kdb 'kwinrc|Plugins|krohnkiteEnabled')\" = true ]"
PATH="$W/kde6n:$PATH" bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "K6n uninstall exits 0"
check "K6n uninstall removes the unpacked Krohnkite" "[ ! -d '$HOME/.local/share/kwin/scripts/krohnkite' ]"
unset FAKE_KDB FAKE_PLASMA
# K5w: Krohnkite 0.8.1 gets the guard for Wayland windows (client.basicUnit is X11 only in KWin 5.27)
fresh_home k5w; export FAKE_KDB="$W/k5w.kdb" FAKE_PLASMA=5
printf '%s\n' "kwinrc|Desktops|Number=4" >"$FAKE_KDB"
mkdir -p "$W/kde5w" "$W/ks5/contents/code"
for f in "$HERE"/stubs/*; do case "$f" in */kpackagetool5) ;; *) ln -sf "$f" "$W/kde5w/"; esac; done
echo '{"KPackageStructure": "KWin/Script", "KPlugin": {"Id": "krohnkite"}}' >"$W/ks5/metadata.json"
printf '%s\n' '        else {' '            if (!(this.client.basicUnit.width === 1 && this.client.basicUnit.height === 1))' '                x();' >"$W/ks5/contents/code/script.js"
cp "$OFF/kde/krohnkite-0.8.1.kwinscript" "$W/k081.bak"; rm -f "$OFF/kde/krohnkite-0.8.1.kwinscript"
python3 -c 'import os,sys,zipfile
z=zipfile.ZipFile(sys.argv[1],"w")
for r,_,fs in os.walk(sys.argv[2]):
  for f in fs: p=os.path.join(r,f); z.write(p,os.path.relpath(p,sys.argv[2]))' "$OFF/kde/krohnkite-0.8.1.kwinscript" "$W/ks5"
PATH="$W/kde5w:/usr/bin:/bin:/usr/sbin:/sbin" XDG_CURRENT_DESKTOP=KDE bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim >/dev/null 2>&1 || bad "K5w install exits 0"
check "K5w Krohnkite 0.8.1: guard for Wayland windows" "grep -qF 'if (this.client.basicUnit && !(this.client.basicUnit.width === 1' '$HOME/.local/share/kwin/scripts/krohnkite/contents/code/script.js' && [ ! -e '$HOME/.local/share/kwin/scripts/krohnkite/contents/code/script.js.kit-orig' ]"
PATH="$W/kde5w:/usr/bin:/bin:/usr/sbin:/sbin" bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "K5w uninstall exits 0"
mv "$W/k081.bak" "$OFF/kde/krohnkite-0.8.1.kwinscript"
unset FAKE_KDB FAKE_PLASMA

# ---- U: desktops of other Ubuntu flavours: the module skips and changes nothing ------------------
for xd in XFCE LXQt MATE Budgie:GNOME X-Cinnamon Unity:Unity7:ubuntu GNOME-Flashback:GNOME; do
  fresh_home "u-${xd%%:*}"
  u0="$(find "$HOME" | sort | cksum)"
  out="$(XDG_CURRENT_DESKTOP=$xd bash "$MOD/install.sh" 2>&1)"; rc=$?
  check "U $xd: exit 0, marker line for kit/install, nothing written" "[ $rc = 0 ] && grep -q '^KIT_MODULE_SKIPPED: desktop .* is not supported' <<<\"\$out\" && [ \"\$(find '$HOME' | sort | cksum)\" = '$u0' ] && cmp -s '$W/u-${xd%%:*}.orig' '$FAKE_DB'"
  check "U $xd: module check passes (--unsupported)" "XDG_CURRENT_DESKTOP=$xd bash '$MOD/install.sh' --unsupported >/dev/null"
done
out="$(XDG_CURRENT_DESKTOP=XFCE bash "$MOD/install.sh" 2>&1)" || true
check "U message names the flavour" "grep -q 'Xfce (Xubuntu)' <<<\"\$out\""
check "U GNOME: --unsupported exits 1 (a real failure stays a failure)" "! XDG_CURRENT_DESKTOP=ubuntu:GNOME bash '$MOD/install.sh' --unsupported >/dev/null 2>&1"
fresh_home u-none
out="$(XDG_CURRENT_DESKTOP=XFCE bash "$MOD/install.sh" --desktop none --skip fonts,nvim 2>&1)" || bad "U --desktop none on Xfce exits 0"
check "U --desktop none on Xfce: terminal parts, no dconf change" "[ -x '$KIT_BIN_DIR/lazygit' ] && cmp -s '$W/u-none.orig' '$FAKE_DB'"
# no session variable, not running, only installed: an Xfce laptop over SSH
fresh_home u-ssh
mkdir -p "$W/xfceonly"; for s in dconf gsettings; do ln -sf "$HERE/stubs/$s" "$W/xfceonly/$s"; done
printf '#!/bin/sh\nexit 0\n' >"$W/xfceonly/xfce4-session"; chmod +x "$W/xfceonly/xfce4-session"
out="$(env -u XDG_CURRENT_DESKTOP PATH="$W/xfceonly:/usr/bin:/bin" bash "$MOD/install.sh" 2>&1)" || bad "U installed Xfce exits 0"
check "U installed Xfce only (SSH): skipped" "grep -q 'Xfce (Xubuntu)' <<<\"\$out\" && [ ! -e '$HOME/.local' ]"

# ---- F42: GNOME 42 (Ubuntu 22.04): Forge instead of the kit tiler, all its keys taken over -------------
fresh_home f42; export FAKE_GNOME=42
FG=/org/gnome/shell/extensions/forge
out="$(bash "$MOD/install.sh" --skip fonts,terminal,tuis,nvim --defer no 2>&1)" || bad "F42 install exits 0"
check "F42 report: kit tiler needs 45, Forge instead" "grep -q 'GNOME 42 gets Forge' <<<\"\$out\""
check "F42 Forge, Space Bar, Just Perfection, Clipboard Indicator from the 42 zips, no kit tiler" "db /org/gnome/shell/enabled-extensions | grep -q forge@jmmaranan.com && db /org/gnome/shell/enabled-extensions | grep -q space-bar@luchrioh && db /org/gnome/shell/enabled-extensions | grep -q clipboard-indicator && [ ! -d '$HOME/.local/share/gnome-shell/extensions/kit-tiling@work-kit' ] && grep -q '\"42\"' '$HOME/.local/share/gnome-shell/extensions/forge@jmmaranan.com/metadata.json'"
check "F42 2 px gap and focus border, Omarchy keys on Forge's actions" "[ \"\$(db $FG/window-gap-size)\" = 'uint32 2' ] && [ \"\$(db $FG/focus-border-size)\" = 'uint32 2' ] && [ \"\$(db $FG/keybindings/window-focus-left)\" = \"['<Super>Left']\" ] && [ \"\$(db $FG/keybindings/window-swap-down)\" = \"['<Super><Shift>Down']\" ] && [ \"\$(db $FG/keybindings/window-toggle-float)\" = \"['<Super>t']\" ]"
check "F42 Forge's own Super+Return, Super+W, Super+H/J/K/L keys emptied" "[ \"\$(db $FG/keybindings/window-swap-last-active)\" = '@as []' ] && [ \"\$(db $FG/keybindings/prefs-tiling-toggle)\" = '@as []' ] && [ \"\$(db $FG/keybindings/window-move-left)\" = '@as []' ]"
check "F42 Forge wider on Super+plus, Space Bar's previous workspace on the key above Tab" "[ \"\$(db $FG/keybindings/window-resize-right-increase)\" = \"['<Super>plus']\" ] && [ \"\$(db /org/gnome/shell/extensions/space-bar/shortcuts/activate-previous-key)\" = \"['<Super>Above_Tab']\" ]"
check "F42 GNOME's half tiling freed for Forge's Super+arrows" "[ \"\$(db /org/gnome/mutter/keybindings/toggle-tiled-left)\" = '@as []' ] && [ \"\$(db $KB/maximize)\" = '@as []' ]"
# shellcheck disable=SC2034  # used inside the check string
f42_keys="$("$KIT_BIN_DIR/kit-desk" keys)"
check "F42 key table knows Forge (Super+J, Super+G listed as working)" "grep -q 'Toggle floating (Forge)' <<<\"\$f42_keys\" && grep -q 'Toggle split direction (Forge)' <<<\"\$f42_keys\" && grep -q 'tiler=forge' '$KIT_DATA_DIR/desktop/state/install.conf'"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "F42 uninstall exits 0"
bash "$KIT_DATA_DIR/desktop-restore-gnome/restore.sh" >/dev/null 2>&1 || true
check "F42 uninstall restores dconf exactly, Forge gone" "diff <(sort '$W/f42.orig') <(sort '$FAKE_DB') >/dev/null && [ ! -d '$HOME/.local/share/gnome-shell/extensions/forge@jmmaranan.com' ]"
export FAKE_GNOME=46

# ---- GL: Ghostty's software OpenGL pack -----------------------------------------------------------
if command -v zstd >/dev/null 2>&1; then
  fresh_home gl
  out="$(bash "$MOD/install.sh" --skip tuis,nvim,fonts --defer no 2>&1)" || bad "GL install exits 0"
  G="$KIT_DATA_DIR/desktop/apps/ghostty-gl"
  check "GL the five libraries and their licences, nothing else" "[ -f '$G/libgallium-26.0.1-arch1.1.so' ] && [ -f '$G/libLLVM.so.21.1' ] && [ -f '$G/libdrm_intel.so.1' ] && [ -f '$G/libedit.so.0' ] && [ -f '$G/libncursesw.so.6' ] && [ -f '$G/licenses/mesa/COPYING' ] && [ ! -e '$G/libLTO.so.21.1' ] && [ ! -e '$G/libunrelated.so.1' ] && [ ! -e '$G/libdrm.so.2' ]"
  check "GL ghostty wrapper uses the pack only with state/ghostty-sw" "grep -q 'ghostty-sw' '$KIT_BIN_DIR/ghostty' && grep -q 'SHARUN_EXTRA_LIBRARY_PATH=\"$G\"' '$KIT_BIN_DIR/ghostty'"
  check "GL report names the pack" "grep -q 'Ghostty software OpenGL (llvmpipe' <<<\"\$out\""
  bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "GL uninstall exits 0"
  check "GL uninstall removes the pack" "[ ! -e '$G' ]"
fi

# ---- H: --help / -h print the header only and act on nothing ------------------------------------
fresh_home h
snap() { { find "$HOME" "$KIT_OFFLINE" -print 2>/dev/null | sort; cat "$FAKE_DB"; } | cksum; }
h0="$(snap)"; hok=1; hbad=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  o="$(eval "$c" 2>&1)" || { hok=0; hbad="$hbad [$c: exit]"; continue; }
  case "$o" in *"set -euo"*|*"HERE="*|*"KIT_DATA="*) hok=0; hbad="$hbad [$c: code in help]" ;; esac
  printf '%s' "$o" | grep -qi 'usage\|kit-desk' || { hok=0; hbad="$hbad [$c: no usage]"; }
done <<EOF2
bash "$MOD/install.sh" --help
bash "$MOD/install.sh" -h
bash "$MOD/install.sh" --tiler --help
bash "$MOD/install.sh" --desktop gnome --help
bash "$MOD/uninstall.sh" --help
bash "$MOD/uninstall.sh" -h
bash "$MOD/apt.sh" --help
bash "$MOD/fetch.sh" --help
bash "$MOD/bin/kit-desk" --help
bash "$MOD/bin/kit-desk" -h
bash "$MOD/bin/kit-desk" help
bash "$MOD/bin/kit-desk" theme --help
bash "$MOD/bin/kit-desk" welcome --help
bash "$MOD/bin/kit-desk" finish-login -h
EOF2
check "H every --help/-h prints the header only (no code lines)${hbad}" "[ $hok = 1 ]"
check "H --help/-h changed no file and no dconf key" "[ \"\$(snap)\" = '$h0' ]"
check "H kit-desk with an unknown command exits 2" "! bash '$MOD/bin/kit-desk' no-such-command >/dev/null 2>&1"

# ---- N: a launch key whose app is missing says so on screen (owner walkthrough 2026-09-27) ----------
fresh_home n
mkdir -p "$W/nb"
cat >"$W/nb/notify-send" <<'EOF2'
#!/bin/sh
printf '%s\n' "$*" >>"$NOTES"
EOF2
printf '#!/bin/sh\necho "fake alacritty $*"\n' >"$W/nb/alacritty"; chmod +x "$W/nb/notify-send" "$W/nb/alacritty"
export NOTES="$W/n.notes"; : >"$NOTES"
kd() { PATH="$W/nb:$HERE/stubs:/usr/bin:/bin" KIT_DESK_SHARE="$MOD" DISPLAY=:9 bash "$MOD/bin/kit-desk" "$@"; }
if ! PATH=/usr/bin:/bin command -v google-chrome microsoft-edge chromium chromium-browser brave-browser firefox xdg-settings >/dev/null 2>&1; then
  kd browser >/dev/null 2>&1 && bad "N browser without a browser fails"
  check "N no browser: a notification says so" "grep -q 'No web browser installed' '$NOTES'"
else echo "skip N browser: this machine has a browser"; fi
if ! PATH=/usr/bin:/bin command -v nautilus dolphin xdg-open >/dev/null 2>&1; then
  kd files >/dev/null 2>&1 && bad "N files without a file manager fails"
  check "N no file manager: a notification says so" "grep -q 'No file manager installed' '$NOTES'"
else echo "skip N files: this machine has a file manager"; fi
kd term -e nosuch-tool-kit >/dev/null 2>&1 && bad "N a missing program in a terminal fails"
check "N missing program: notification, no terminal opened for nothing" "grep -q 'nosuch-tool-kit is not installed' '$NOTES'"
KIT_DESK_EDITOR=nosuch-editor EDITOR=nosuch-editor2 kd editor >/dev/null 2>&1 && bad "N editor without an editor fails"
check "N no editor: a notification says so" "grep -q 'No text editor installed' '$NOTES'"
check "N an installed program still opens in the terminal" "[ \"\$(kd term -e sh -c true 2>/dev/null)\" = 'fake alacritty -e sh -c true' ]"
check "N Super+Shift+F goes through kit-desk files" "grep -q '^SUPER + SHIFT + F|File manager|custom:@BIN@/kit-desk files\$' '$MOD/keys.tsv'"
unset NOTES

# ---- U: update path of the user config files 95 writes (owner decision 2026-09-27, Q3) ---------------
# an untouched kit default moves with a new kit, a file the user changed stays (the new default goes
# next to it as .kit-new), a file that was there before 95 stays untouched
fresh_home u
mkdir -p "$HOME/.config/ghostty"; echo "font-size = 15" >"$HOME/.config/ghostty/config"
cp "$HOME/.config/ghostty/config" "$W/u.ghostty"
bash "$MOD/install.sh" --tiler kit --with zellij >/dev/null 2>&1 || bad "U install exits 0"
CH="$KIT_DATA_DIR/desktop/state/config-hashes.tsv"
ZJ="$HOME/.config/zellij/config.kdl"; NV="$HOME/.config/nvim/init.lua"; GH="$HOME/.config/ghostty/config"
check "U hashes noted for the files 95 wrote, not for the user's own" "grep -q \"^$NV$(printf '\t')\" '$CH' && grep -q \"^$ZJ$(printf '\t')\" '$CH' && ! grep -q \"^$GH$(printf '\t')\" '$CH'"
echo "// my own zellij line" >>"$ZJ"
UPD2="$W/upd2"; rm -rf "$UPD2"; mkdir -p "$UPD2"; cp -R "$MOD" "$UPD2/95-desktop"
echo '-- kit v2' >>"$UPD2/95-desktop/config/nvim/init.lua"
echo '// kit v2' >>"$UPD2/95-desktop/config/zellij/config.kdl"
echo '# kit v2' >>"$UPD2/95-desktop/config/ghostty/config"
u_out="$(KIT_ROOT="$MOD/../.." bash "$UPD2/95-desktop/install.sh" --tiler kit --with zellij 2>&1)" || bad "U install of an updated kit exits 0"
check "U untouched kit default refreshed to the new kit default" "grep -q -- '-- kit v2' '$NV' && [ ! -e '$NV.kit-new' ] && grep -q 'updated $NV to the new kit default' <<<\"\$u_out\""
check "U user-edited file kept, the new kit default next to it as .kit-new" "grep -q 'my own zellij line' '$ZJ' && ! grep -q 'kit v2' '$ZJ' && grep -q 'kit v2' '$ZJ.kit-new' && ! grep -q 'my own' '$ZJ.kit-new'"
check "U one line in the install output for the kept file" "[ \"\$(grep -c 'kit-new' <<<\"\$u_out\")\" = 1 ] && grep -q 'kept your changed $ZJ; the new kit default is in $ZJ.kit-new' <<<\"\$u_out\""
check "U file from before 95 untouched, no .kit-new" "cmp -s '$W/u.ghostty' '$GH' && [ ! -e '$GH.kit-new' ] && grep -q 'kept your $GH (not replaced)' <<<\"\$u_out\""
check "U no backups for the replaced kit default" "! beside && [ \"\$(find '$KIT_DATA_DIR/backups/95-desktop/.config/nvim' -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' ')\" = 0 ]"
u_out2="$(KIT_ROOT="$MOD/../.." bash "$UPD2/95-desktop/install.sh" --tiler kit --with zellij 2>&1)" || bad "U rerun exits 0"
check "U rerun: the refreshed default stays, the edited file still kept" "grep -q -- '-- kit v2' '$NV' && ! grep -q updated <<<\"\$u_out2\" && grep -q 'my own zellij line' '$ZJ' && grep -q 'kit v2' '$ZJ.kit-new'"
# the user takes over the new default by hand: the .kit-new goes, and later kit versions move again
cp "$ZJ.kit-new" "$ZJ"
KIT_ROOT="$MOD/../.." bash "$UPD2/95-desktop/install.sh" --tiler kit --with zellij >/dev/null 2>&1 || bad "U rerun after taking the default exits 0"
check "U file equal to the kit default again: .kit-new removed, hash noted again" "[ ! -e '$ZJ.kit-new' ] && grep -q \"^$ZJ$(printf '\t')\$(shasum -a 256 '$ZJ' | cut -d' ' -f1)\\\$\" '$CH'"
# an install from before the hashes (95 wrote the file, nothing noted): treated as changed, kept
awk -F '\t' -v p="$NV" '$1 != p' "$CH" >"$CH.t" && mv "$CH.t" "$CH"
echo '-- kit v3' >>"$UPD2/95-desktop/config/nvim/init.lua"
KIT_ROOT="$MOD/../.." bash "$UPD2/95-desktop/install.sh" --tiler kit --with zellij >/dev/null 2>&1 || bad "U install without a noted hash exits 0"
check "U 95's file without a noted hash: kept, new default as .kit-new" "! grep -q 'kit v3' '$NV' && grep -q 'kit v3' '$NV.kit-new'"
bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "U uninstall exits 0"
check "U uninstall removes the .kit-new files and keeps the file from before 95" "[ ! -e '$NV.kit-new' ] && [ ! -e '$ZJ.kit-new' ] && cmp -s '$W/u.ghostty' '$GH'"

# ---- F40: shared lists: items others add after the first install survive reinstall and uninstall -------
# (test VM 2026-09-27: after a kit update the custom shortcut list held only work-kit-desk-*; the dictation
# shortcut of 80-quassel, added after the first 95 install, was gone)
XK=/org/gnome/desktop/input-sources/xkb-options
for sess in x11 wayland; do
  fresh_home "f40$sess"; export XDG_SESSION_TYPE=$sess
  # the first install sees no custom shortcut, no xkb option and only the user's own extension
  awk -v k="$CK" 'index($0,k)!=1' "$FAKE_DB" >"$FAKE_DB.t" && mv "$FAKE_DB.t" "$FAKE_DB"
  bash "$MOD/install.sh" --tiler kit >/dev/null 2>&1 || bad "F40 $sess first install exits 0"
  check "F40 $sess first install journaled the shortcut list as unset" "grep -q \"^$CK$(printf '\t')unset\" '$KIT_DATA_DIR/desktop/state/dconf-journal.tsv'"
  # added by others before the next login (the login step is still queued on Wayland)
  dconf write "$CK" "$(db "$CK" | sed "s|]\$|, '$CK/work-kit-quassel/']|")"
  dconf write "$CK/work-kit-quassel/binding" "'<Control><Alt>d'"
  dconf write /org/gnome/shell/enabled-extensions "$(db /org/gnome/shell/enabled-extensions | sed "s|]\$|, 'foreign@example.org']|")"
  dconf write "$XK" "['lv3:ralt_switch']"
  [ "$sess" = x11 ] || "$KIT_BIN_DIR/kit-desk" finish-login --force >/dev/null 2>&1
  bash "$MOD/install.sh" --tiler kit >/dev/null 2>&1 || bad "F40 $sess reinstall exits 0"
  [ "$sess" = x11 ] || "$KIT_BIN_DIR/kit-desk" finish-login --force >/dev/null 2>&1
  check "F40 $sess reinstall keeps the foreign shortcut, extension and xkb option" "db $CK | grep -q work-kit-quassel && [ \"\$(db $CK/work-kit-quassel/binding)\" = \"'<Control><Alt>d'\" ] && db /org/gnome/shell/enabled-extensions | grep -q foreign@example.org && db $XK | grep -q lv3:ralt_switch"
  check "F40 $sess reinstall keeps its own items once" "[ \"\$(db $CK | tr ',' '\\n' | grep -c work-kit-desk-)\" = \"\$(grep -c '|custom:' '$MOD/keys.tsv')\" ] && [ \"\$(db /org/gnome/shell/enabled-extensions | tr ',' '\\n' | grep -c kit-tiling@work-kit)\" = 1 ]"
  bash "$MOD/uninstall.sh" >/dev/null 2>&1 || bad "F40 $sess uninstall exits 0"
  check "F40 $sess uninstall removes only its own items" "[ \"\$(db $CK)\" = \"['$CK/work-kit-quassel/']\" ] && [ \"\$(db /org/gnome/shell/enabled-extensions)\" = \"['user-own@example.org', 'foreign@example.org']\" ] && db $XK | grep -q lv3:ralt_switch && ! db $XK | grep -q compose:caps"
done
export XDG_SESSION_TYPE=x11

# ---- G: metadata of the real pinned zips, when fetched ------------------------------------------------
if [ -d "$MOD/../../offline/desktop/extensions" ]; then
  check "G pinned extension zips support their GNOME directory" "KIT_OFFLINE='$MOD/../../offline' bash '$MOD/fetch.sh' --check-meta >/dev/null"
fi
exit "$fail"
