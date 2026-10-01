#!/usr/bin/env bash
# Module 95-desktop: make Ubuntu's desktop behave like Omarchy. Offline, no sudo, user level.
# GNOME: policy check -> dconf backup -> files (fonts, terminal, TUIs, nvim) -> extensions ->
# keybindings and settings -> theme -> report. Every dconf change is journaled for uninstall.sh.
# KDE Plasma 5/6: the same files, then Krohnkite tiling, kglobalshortcutsrc keys, KWin settings and
# an auto-hiding panel (lib/kde.sh, every KConfig change journaled). Other desktops: files only.
#
# Usage: install.sh [options]
#   --dry-run              print what would change, change nothing
#   --desktop NAME         auto (default) | gnome | kde | none (files only, no desktop changes).
#                          auto on another desktop (Xfce, LXQt, MATE, Budgie, Cinnamon, ...): the module
#                          is skipped and changes nothing; none still installs the terminal parts there
#   --check                only print the policy report (GNOME version, locks, extensions)
#   --tiler NAME           kit (default: kit-tiling, one window fills the screen, two split it,
#                          three or more make main + stack) | tilingshell | paperwm | tactile | forge | none.
#                          GNOME 42-44 (Ubuntu 22.04): the kit tiler needs GNOME 45+, so kit means Forge there
#                          (automatic tiling like Hyprland's dwindle layout)
#   --workspaces N         fixed workspaces, 1-10 (default 6)
#   --theme NAME           default everforest; list: kit-desk theme --list
#   --with LIST            add optional parts: zellij,zed
#   --skip LIST            leave out parts: extensions,clipboard,keys,settings,input,fonts,terminal,tuis,nvim,
#                          theme,wallpaper,welcome,superkey (superkey: Super alone keeps opening the overview;
#                          default: Super alone does nothing, like Omarchy)
#   --border PX            visible border between tiled windows, 0-8 px (default 2; 0 = none, windows touch).
#                          The kit tiler draws it around every tiled window, the focused one in the theme's
#                          accent colour; other tilers get a gap of that width (and their own focus border)
#   --keep-dock            keep Ubuntu Dock and desktop icons (KDE: the panel stays visible)
#   --defer MODE           auto (default) | yes | no. GNOME on Wayland loads new extensions only at the
#                          next login: auto then keeps the dock and GNOME's own tiling until then and
#                          applies the changes that belong to the new extensions at that login
#                          (one-shot autostart entry, kit-desk finish-login). X11 or an extension
#                          that is already live: applied at once.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
SRC="$KIT_OFFLINE/desktop"
# shellcheck source=lib/desk.sh
. "$HERE/lib/desk.sh"
# shellcheck source=lib/kde.sh
. "$HERE/lib/kde.sh"

# help acts on nothing, wherever it stands (also after an option that takes a value)
for a in "$@"; do case "$a" in -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;; esac; done
UNSUPPORTED_ONLY=0 DESKTOP=auto TILER=kit WORKSPACES=6 THEME=everforest WITH="" SKIP="" KEEP_DOCK=0 CHECK_ONLY=0 BORDER=2 DEFER=auto DEFER_ACTIVE=0 DEFER_ANCHOR=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --check) CHECK_ONLY=1 ;;
    --unsupported) UNSUPPORTED_ONLY=1 ;; # exit 0 only on a desktop this module skips (module.conf check)
    --desktop) DESKTOP="${2:?--desktop needs a value}"; shift ;;
    --tiler) TILER="${2:?--tiler needs a value}"; shift ;;
    --workspaces) WORKSPACES="${2:?--workspaces needs a value}"; shift ;;
    --theme) THEME="${2:?--theme needs a value}"; shift ;;
    --with) WITH="$WITH,${2:?--with needs a value}"; shift ;;
    --skip) SKIP="$SKIP,${2:?--skip needs a value}"; shift ;;
    --keep-dock) KEEP_DOCK=1 ;;
    --defer) DEFER="${2:?--defer needs a value}"; shift ;;
    --border) BORDER="${2:?--border needs a value}"; shift ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done
export DRY_RUN
case "$TILER" in kit|tilingshell|paperwm|tactile|forge|none) ;; *) die "unknown tiler: $TILER" ;; esac
case "$DESKTOP" in auto) desk_detect; DESKTOP="$DESK_KIND" ;; gnome|kde) ;; none|other) DESKTOP=other ;; *) die "unknown desktop: $DESKTOP" ;; esac
# A desktop of another Ubuntu flavour (Xubuntu, Lubuntu, Ubuntu MATE, Ubuntu Budgie, Ubuntu Cinnamon,
# ...): skip the whole module before anything is written. The marker line tells kit/install.
if [ "$DESKTOP" = unsupported ]; then
  [ "$UNSUPPORTED_ONLY" = 1 ] && { echo "unsupported: ${DESK_NAME:-unknown}"; exit 0; }
  SKIP_MSG="desktop ${DESK_NAME:-unknown} is not supported (95-desktop: GNOME Shell 42-50 and KDE Plasma 5/6), module skipped, nothing changed"
  log "$SKIP_MSG"
  log "terminal, font and TUIs without any desktop change: bash $HERE/install.sh --desktop none"
  printf 'KIT_MODULE_SKIPPED: %s\n' "$SKIP_MSG"
  exit 0
fi
[ "$UNSUPPORTED_ONLY" = 1 ] && exit 1
case "$DEFER" in auto|yes|no) ;; *) die "--defer must be auto, yes or no" ;; esac
case "$WORKSPACES" in [1-9]|10) ;; *) die "--workspaces must be 1-10" ;; esac
case "$BORDER" in [0-8]) ;; *) die "--border must be 0-8 (pixels)" ;; esac
[ -f "$HERE/themes/$THEME.toml" ] || die "unknown theme: $THEME (see $HERE/themes)"
want() { case ",$SKIP," in *",$1,"*) return 1 ;; esac; return 0; }
with() { case ",$WITH," in *",$1,"*) return 0 ;; esac; return 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- 1. policy report -------------------------------------------------------------------
GNOME=""; EXT_OK=1; DCONF_OK=1; PLASMA=""
policy_check() {
  if [ "$DESKTOP" = kde ]; then DCONF_OK=0; EXT_OK=0; kde_check; return 0; fi
  if [ "$DESKTOP" = other ]; then
    report "desktop: ${XDG_CURRENT_DESKTOP:-unknown} -> no window manager changes; fonts, terminal, TUIs, nvim and terminal themes only"
    DCONF_OK=0; EXT_OK=0; return 0
  fi
  GNOME="$(gnome_major || true)"
  if [ -z "$GNOME" ]; then
    report "GNOME Shell not found: skipping extensions, keybindings, settings and GNOME theme"
    DCONF_OK=0; EXT_OK=0; return 0
  fi
  report "desktop: GNOME Shell $GNOME -> GNOME path"
  have dconf || report "dconf CLI missing: using gsettings (no full dconf dump; 01-prereqs can add dconf-cli)"
  if ! have dconf && ! have gsettings; then report "neither dconf nor gsettings found"; DCONF_OK=0; EXT_OK=0; return 0; fi
  local v
  v="$(kd_effective /org/gnome/shell/allow-extension-installation)"
  if [ "$v" = "false" ]; then report "policy: allow-extension-installation=false (IT) -> no extensions"; EXT_OK=0; fi
  v="$(kd_effective /org/gnome/shell/disable-user-extensions)"
  if [ "$v" = "true" ] && ! kd_writable /org/gnome/shell/disable-user-extensions; then
    report "policy: user extensions disabled and locked (IT) -> no extensions"; EXT_OK=0
  fi
  if ! kd_writable /org/gnome/shell/enabled-extensions; then
    report "policy: enabled-extensions is locked (IT) -> no extensions"; EXT_OK=0
  fi
  local p locked=""
  for p in /org/gnome/desktop/wm/keybindings/close /org/gnome/mutter/dynamic-workspaces \
           /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings /org/gnome/desktop/interface/color-scheme; do
    kd_writable "$p" || locked="$locked $p"
  done
  [ -z "$locked" ] || report "policy: locked keys:$locked (they stay as IT set them)"
  [ "$EXT_OK" = 1 ] && report "extensions: allowed (user level)"
  return 0
}

kde_check() {
  PLASMA="$(plasma_major)"
  if [ -z "$PLASMA" ]; then report "desktop: KDE, but no Plasma 5/6 tools found -> files only"; DESKTOP=other; return 0; fi
  kde_tools
  report "desktop: KDE Plasma $PLASMA -> KDE path (Krohnkite tiling, kglobalshortcutsrc keys)"
  local t f locked=""
  for t in "$KRC" "$KWC"; do have "$t" || report "$t missing (Plasma $PLASMA tools): the parts that need it are skipped"; done
  have "$KPT" || log "$KPT missing: Krohnkite is unpacked directly"
  [ -n "$QDB" ] || report "qdbus missing: panel auto-hide and live reload skipped (log out and in instead)"
  for f in kwinrc kglobalshortcutsrc kdeglobals; do
    # KDE Kiosk: an "[$i]" marker in a system file makes groups or keys immutable
    # shellcheck disable=SC2016  # the literal Kiosk marker
    if grep -qsF '[$i]' "/etc/xdg/$f" "$KDE_CFG/$f"; then locked="$locked $f"; fi
  done
  [ -z "$locked" ] || report "policy: immutable (Kiosk) entries in:$locked (they stay as IT set them)"
  return 0
}

kde_backup() { # copy of every KDE file we may touch, before the first change
  local d f
  d="$DESK_BACKUP/kde-$(stamp)"
  [ "$DRY_RUN" = 1 ] && { log "dry-run: KDE config backup -> $d"; return 0; }
  mkdir -p "$d"
  for f in kwinrc kglobalshortcutsrc kcminputrc kdeglobals plasma-org.kde.plasma.desktop-appletsrc plasmashellrc; do
    [ -f "$KDE_CFG/$f" ] && cp "$KDE_CFG/$f" "$d/"
  done
  [ -d "$DESK_BACKUP/kde-original" ] || cp -R "$d" "$DESK_BACKUP/kde-original"
  report "KDE config backup: $d"
}

# ---- 2. dconf backup ----------------------------------------------------------------------
backup_dconf() {
  [ "$DCONF_OK" = 1 ] && have dconf || return 0
  local f
  f="$DESK_BACKUP/dconf-$(stamp).ini"
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: dconf dump / > $f"; return 0; fi
  dconf dump / >"$f" || die "dconf dump failed; nothing changed (run from a terminal inside the GNOME session)"
  [ -f "$DESK_BACKUP/dconf-original.ini" ] || cp "$f" "$DESK_BACKUP/dconf-original.ini"
  report "dconf backup: $f"
}

# ---- 3. files -------------------------------------------------------------------------------
need_src() { [ -e "$SRC/$1" ] || { report "missing offline artifact $SRC/$1: skipped"; return 1; }; }

install_bin() { # install_bin <archive> <member suffix> <name>
  local archive="$1" member="$2" name="$3" d="$TMP/x-$3" src
  need_src "$archive" || return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: install $BIN_DIR/$name"; return 0; fi
  mkdir -p "$d" "$BIN_DIR"
  tar -xzf "$SRC/$archive" -C "$d"
  src="$(find "$d" -type f -path "*$member" | head -n 1)"
  [ -n "$src" ] || { report "$member not found in $archive"; return 0; }
  chmod 0755 "$src"
  desk_put "$src" "$BIN_DIR/$name"
  chmod 0755 "$BIN_DIR/$name"
  rm -rf "$d"
}

install_tree() { # install_tree <archive> <top dir in archive> <dest dir>
  local archive="$1" top="$2" dest="$3"
  need_src "$archive" || return 1
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: unpack $archive -> $dest"; return 0; fi
  rm -rf "$TMP/tree" && mkdir -p "$TMP/tree" "$(dirname "$dest")"
  tar -xzf "$SRC/$archive" -C "$TMP/tree"
  [ -d "$TMP/tree/$top" ] || { report "$top missing in $archive"; return 1; }
  rm -rf "$dest"
  mv "$TMP/tree/$top" "$dest"
  desk_record "$dest" -
}

link_bin() { # link_bin <target> <name>
  local dst="$BIN_DIR/$1" target="$2" bak=-
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: link $dst -> $target"; return 0; fi
  mkdir -p "$BIN_DIR"
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$target" ] && return 0
  if [ -e "$dst" ] || [ -L "$dst" ]; then bak="$(desk_backup "$dst")"; fi
  ln -s "$target" "$dst"
  desk_record "$dst" "$bak"
}

# put_config <src> <dst>: a user config file with the kit's default (owner decision 2026-09-27, Q3).
#   absent: the kit default is written and its hash noted (state/config-hashes.tsv);
#   still exactly what 95 wrote last time: replaced by the new kit default (a kit update moves it);
#   written by 95 and changed since (or written before hashes were noted): kept, the new kit default
#   goes next to it as <dst>.kit-new;
#   there before 95 (not written by it): kept, untouched. Returns 1 only in that last case.
put_config() {
  local src="$1" dst="$2" old
  if [ -e "$dst" ] && cmp -s "$src" "$dst"; then
    if desk_ours "$dst"; then desk_config_note "$dst"; [ "$DRY_RUN" = 1 ] || rm -f "$dst.kit-new"; fi
    return 0
  fi
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    desk_put "$src" "$dst" && desk_config_note "$dst"; return 0
  fi
  if ! desk_ours "$dst"; then report "kept your $dst (not replaced)"; return 1; fi
  old="$(desk_config_hash "$dst")"
  if [ -n "$old" ] && [ -f "$dst" ] && [ "$(desk_hash "$dst")" = "$old" ]; then
    desk_put "$src" "$dst" && desk_config_note "$dst"
    [ "$DRY_RUN" = 1 ] || rm -f "$dst.kit-new"
    report "updated $dst to the new kit default (you had not changed it)"; return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: keep your changed $dst, new kit default to $dst.kit-new"; return 0; fi
  cp "$src" "$dst.kit-new"; desk_record "$dst.kit-new" -
  report "kept your changed $dst; the new kit default is in $dst.kit-new"
}

install_fonts() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/work-kit-JetBrainsMonoNerd"
  need_src fonts/JetBrainsMono-nerd-3.5.1.tar.xz || return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: fonts -> $dir"; return 0; fi
  mkdir -p "$dir"
  tar -xJf "$SRC/fonts/JetBrainsMono-nerd-3.5.1.tar.xz" -C "$dir" --wildcards 'JetBrainsMonoNerdFont-*.ttf' 'OFL.txt' 2>/dev/null ||
    tar -xJf "$SRC/fonts/JetBrainsMono-nerd-3.5.1.tar.xz" -C "$dir"
  find "$dir" -type f ! -name 'JetBrainsMonoNerdFont-*.ttf' ! -name 'OFL.txt' ! -name 'LICENSE*' -delete
  desk_record "$dir" -
  if have fc-cache; then fc-cache -f "$dir" >/dev/null 2>&1 || true; fi
  report "font: JetBrainsMono Nerd Font -> $dir"
}

install_terminal() {
  local app="apps/Ghostty-1.3.1-x86_64.AppImage" dest="$DESK_DATA/apps/ghostty" wrapper
  need_src "$app" || return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: Ghostty -> $dest, $BIN_DIR/ghostty"; return 0; fi
  # work dir under $HOME, not /tmp: company images often mount /tmp noexec
  local work="$DESK_DATA/apps/.ghostty-new"
  rm -rf "$work"; mkdir -p "$work"
  cp "$SRC/$app" "$work/ghostty.AppImage"; chmod +x "$work/ghostty.AppImage"
  rm -rf "$dest"
  if (cd "$work" && ./ghostty.AppImage --appimage-extract >/dev/null 2>&1) && [ -x "$work/squashfs-root/AppRun" ]; then
    # uruntime AppImages (Ghostty 1.3) unpack to AppDir/ and add squashfs-root -> AppDir: move the
    # real directory, not the link (the link alone would point at nothing after rm -rf "$work")
    local unpacked="$work/squashfs-root"
    [ -L "$unpacked" ] && unpacked="$(cd "$unpacked" && pwd -P)"
    mv "$unpacked" "$dest"; rm -rf "$work"
    wrapper="exec \"$dest/AppRun\" \"\$@\""
  else
    # no way to unpack here; keep the AppImage and let its runtime unpack on start
    mkdir -p "$dest"; mv "$work/ghostty.AppImage" "$dest/"; rm -rf "$work"
    wrapper="APPIMAGE_EXTRACT_AND_RUN=1 exec \"$dest/ghostty.AppImage\" \"\$@\""
    report "Ghostty AppImage not extracted here (not Linux x86_64?): runs through its runtime"
  fi
  desk_record "$dest" -
  install_ghostty_gl "$dest"
  # with state/ghostty-sw (set by kit-desk term when Ghostty found no OpenGL 4.3) Ghostty loads the
  # shipped llvmpipe first; sharun, the AppImage's loader, puts SHARUN_EXTRA_LIBRARY_PATH before its own libs
  wrapper="[ -f \"$DESK_STATE/ghostty-sw\" ] && [ -d \"$GHOSTTY_GL\" ] && export SHARUN_EXTRA_LIBRARY_PATH=\"$GHOSTTY_GL\"
$wrapper"
  printf '#!/bin/sh\n# Ghostty from work-kit 95-desktop\n%s\n' "$wrapper" >"$TMP/ghostty"
  chmod 0755 "$TMP/ghostty"; desk_put "$TMP/ghostty" "$BIN_DIR/ghostty"; chmod 0755 "$BIN_DIR/ghostty"
  local icon; icon="$(find "$dest" -maxdepth 1 -name '*.png' 2>/dev/null | head -n 1)"
  cat >"$TMP/ghostty.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Ghostty
Comment=Terminal (work-kit)
Exec=$BIN_DIR/ghostty
Icon=${icon:-utilities-terminal}
Terminal=false
Categories=System;TerminalEmulator;
StartupWMClass=com.mitchellh.ghostty
EOF
  desk_put "$TMP/ghostty.desktop" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/work-kit-ghostty.desktop"
  sed "s|@THEME_DIR@|$DESK_CONF/theme|g" "$HERE/config/ghostty/config" >"$TMP/ghostty.config"
  sed "s|@THEME_DIR@|$DESK_CONF/theme|g" "$HERE/config/alacritty/alacritty.toml" >"$TMP/alacritty.toml"
  put_config "$TMP/ghostty.config" "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config" ||
    report "  to use kit themes in Ghostty add: config-file = ?$DESK_CONF/theme/ghostty.conf"
  if have alacritty; then
    put_config "$TMP/alacritty.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml" || true
  fi
  if [ "$DESKTOP" = kde ]; then report "terminal: Ghostty ($BIN_DIR/ghostty); Super+Return falls back to Ghostty with software OpenGL, then Alacritty, then Konsole"
  else report "terminal: Ghostty ($BIN_DIR/ghostty); Super+Return falls back to Ghostty with software OpenGL, then Alacritty, Ptyxis or GNOME Terminal"; fi
}

# Software OpenGL for Ghostty: the AppImage's own Mesa is built without llvmpipe, so without a usable
# GPU (VM, old or missing driver) Ghostty gets softpipe's OpenGL 3.3 and closes. The same Mesa build
# with llvmpipe (OpenGL 4.5) goes to a directory of its own, used only by Ghostty and only after it
# failed once (kit-desk term). No sudo, nothing system-wide.
GHOSTTY_GL="$DESK_DATA/apps/ghostty-gl"
GL_PKGS="mesa-26.0.1-1 llvm-libs-21.1.8-1 libdrm-2.4.131-1 libedit-20251016_3.1-1 ncurses-6.5-4"
install_ghostty_gl() { # install_ghostty_gl <unpacked Ghostty>
  local app="$1" p f work="$DESK_DATA/apps/.ghostty-gl-new"
  for p in $GL_PKGS; do need_src "gl/$p-x86_64.pkg.tar.zst" || { report "Ghostty software OpenGL: not installed"; return 0; }; done
  # the libraries replace the AppImage's Mesa 26.0.1 build; another Ghostty build needs other ones
  if [ -d "$app/shared/lib" ] && [ ! -e "$app/shared/lib/libgallium-26.0.1-arch1.1.so" ]; then
    report "Ghostty software OpenGL: this Ghostty does not bundle Mesa 26.0.1, pack not installed"; return 0
  fi
  have zstd || { report "Ghostty software OpenGL: zstd missing (Ubuntu package zstd), pack not installed"; return 0; }
  rm -rf "$work" "$GHOSTTY_GL"; mkdir -p "$work/licenses"
  local wc="" # GNU tar needs --wildcards for the member patterns, bsdtar (tests on macOS) knows no such flag
  tar --version 2>/dev/null | grep -q GNU && wc=--wildcards
  for p in $GL_PKGS; do
    # shellcheck disable=SC2086  # $wc is empty or one flag
    zstd -dcq "$SRC/gl/$p-x86_64.pkg.tar.zst" | tar -x -C "$work" $wc \
      'usr/lib/libgallium-*.so' 'usr/lib/libLLVM.so.*' 'usr/lib/libdrm_intel.so.*' 'usr/lib/libedit.so.*' \
      'usr/lib/libncursesw.so.6*' 'usr/share/licenses/*' 2>/dev/null || true
  done
  mv "$work"/usr/lib/lib* "$work/" 2>/dev/null || true
  for f in "$work"/usr/share/licenses/*; do [ -d "$f" ] && mv "$f" "$work/licenses/"; done
  rm -rf "${work:?}/usr"
  if [ ! -e "$work/libgallium-26.0.1-arch1.1.so" ] || [ ! -e "$work/libLLVM.so.21.1" ]; then
    rm -rf "$work"; report "Ghostty software OpenGL: unpacking failed, pack not installed"; return 0
  fi
  mv "$work" "$GHOSTTY_GL"
  desk_record "$GHOSTTY_GL" -
  report "Ghostty software OpenGL (llvmpipe, OpenGL 4.5): $GHOSTTY_GL ($(du -sh "$GHOSTTY_GL" | cut -f1)), used when no GPU gives OpenGL 4.3"
}

install_tuis() {
  install_bin bin/lazygit_0.65.1_linux_x86_64.tar.gz /lazygit lazygit
  install_bin bin/btop-1.4.7-x86_64-unknown-linux-musl.tar.gz /bin/btop btop
  install_bin bin/fastfetch-2.68.1-linux-amd64.tar.gz /usr/bin/fastfetch fastfetch
  report "TUIs: lazygit btop fastfetch in $BIN_DIR"
  if with zellij; then
    install_bin bin/zellij-0.45.1-no-web-x86_64-unknown-linux-musl.tar.gz /zellij zellij
    put_config "$HERE/config/zellij/config.kdl" "${XDG_CONFIG_HOME:-$HOME/.config}/zellij/config.kdl" || true
    report "zellij installed"
  fi
}

install_nvim() {
  local dest="$DESK_DATA/apps/nvim" pack="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/work-kit/start/mini.nvim"
  install_tree bin/nvim-0.12.5-linux-x86_64.tar.gz nvim-linux-x86_64 "$dest" || return 0
  link_bin nvim "$dest/bin/nvim"
  install_tree nvim/mini.nvim-0.18.0.tar.gz mini.nvim-0.18.0 "$pack" || true
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  if [ -e "$cfg" ] && ! desk_ours "$cfg/init.lua"; then
    report "kept your $cfg (kit nvim config not installed; mini.nvim is available)"
  else
    put_config "$HERE/config/nvim/init.lua" "$cfg/init.lua" || true
  fi
  report "neovim 0.12.5 ($BIN_DIR/nvim) with offline config (mini.nvim)"
}

install_zed() {
  local dest="$DESK_DATA/apps/zed.app" apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  install_tree apps/zed-1.21.0-linux-x86_64.tar.gz zed.app "$dest" || return 0
  link_bin zed "$dest/bin/zed"
  if [ "$DRY_RUN" != 1 ] && [ -f "$dest/share/applications/dev.zed.Zed.desktop" ]; then
    sed -e "s|^Exec=zed|Exec=$dest/bin/zed|" -e "s|^TryExec=.*|TryExec=$dest/bin/zed|" \
        -e "s|^Icon=.*|Icon=$dest/share/icons/hicolor/512x512/apps/zed.png|" \
        "$dest/share/applications/dev.zed.Zed.desktop" >"$TMP/zed.desktop"
    desk_put "$TMP/zed.desktop" "$apps/dev.zed.Zed.desktop"
  fi
  report "Zed 1.21.0 ($BIN_DIR/zed); telemetry and AI features need network, check Zed settings"
}

# ---- 4. extensions ---------------------------------------------------------------------------
TILER_UUID=""
set_tiler_uuid() {
  # the kit tiler is an ES module extension (GNOME 45+); GNOME 42-44 get Forge, the closest tiler that
  # runs there (owner decision 2026-09-26: nearest working tiler, not a skip)
  if [ "$TILER" = kit ] && [ -n "$GNOME" ] && [ "$GNOME" -lt 45 ]; then
    TILER=forge
    report "tiler: the kit tiler needs GNOME 45 or newer; GNOME $GNOME gets Forge (automatic tiling like Hyprland's dwindle)"
  fi
  case "$TILER" in
    kit) TILER_UUID=kit-tiling@work-kit ;;
    tilingshell) TILER_UUID=tilingshell@ferrarodomenico.com ;;
    paperwm) TILER_UUID=paperwm@paperwm.github.com ;;
    tactile) TILER_UUID=tactile@lundal.io ;;
    forge) TILER_UUID=forge@jmmaranan.com ;;
    *) TILER_UUID="" ;;
  esac
}
CLIP_UUID=clipboard-indicator@tudmotu.com
ALL_TILERS="kit-tiling@work-kit tilingshell@ferrarodomenico.com paperwm@paperwm.github.com tactile@lundal.io forge@jmmaranan.com"
TILER_ACTIVE=0

ext_zip_dir() { # the pinned directory for this GNOME: exact major, else the highest lower one
  local best="" d m
  for d in "$SRC"/extensions/*/; do
    [ -d "$d" ] || continue
    m="$(basename "$d")"
    case "$m" in *[!0-9]*) continue ;; esac
    if [ "$m" -le "$GNOME" ] && { [ -z "$best" ] || [ "$m" -gt "$best" ]; }; then best="$m"; fi
  done
  [ -n "$best" ] && printf '%s' "$SRC/extensions/$best"
}

ext_supports() { # ext_supports <metadata.json> -> GNOME major listed in shell-version?
  tr -d '\n ' <"$1" | sed -n 's/.*"shell-version":\[\([^]]*\)\].*/\1/p' | tr -d '"' |
    tr ',' '\n' | sed 's/\..*//' | grep -qx "$GNOME"
}

install_extension() { # install_extension <uuid>; 0 when installed and supported
  local uuid="$1" zdir zip dest="$EXT_DIR/$1" own="$HERE/extensions/$1"
  # the kit's own extensions ship in the module folder, the others as pinned zips in offline/
  if [ -d "$own" ]; then zip="$own"
  else
    zdir="$(ext_zip_dir)"; zip="$zdir/$uuid.zip"
    if [ -z "$zdir" ] || [ ! -f "$zip" ]; then report "extension $uuid: no pinned zip for GNOME $GNOME"; return 1; fi
  fi
  if [ -f "$dest/metadata.json" ] && ! grep -qx "$uuid" "$DESK_STATE/ext-installed" 2>/dev/null; then
    # installed by the user or by IT: never replaced
    if ext_supports "$dest/metadata.json"; then report "extension $uuid: already installed, kept"; return 0; fi
    report "extension $uuid: an installed copy does not support GNOME $GNOME, left alone"; return 1
  fi
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: install extension $uuid from $zip"; return 0; fi
  rm -rf "$TMP/ext" && mkdir -p "$TMP/ext"
  if [ -d "$zip" ]; then cp -R "$zip/." "$TMP/ext/"; rm -f "$TMP/ext/schemas/gschemas.compiled"
  elif have unzip; then unzip -q -o "$zip" -d "$TMP/ext"
  elif have python3; then python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$TMP/ext"
  else report "extension $uuid: need unzip or python3"; return 1; fi
  if ! ext_supports "$TMP/ext/metadata.json"; then report "extension $uuid: zip does not support GNOME $GNOME, skipped"; return 1; fi
  if [ ! -f "$TMP/ext/schemas/gschemas.compiled" ] && [ -d "$TMP/ext/schemas" ]; then
    if have glib-compile-schemas; then glib-compile-schemas "$TMP/ext/schemas" 2>/dev/null ||
      report "extension $uuid: glib-compile-schemas failed"
    else report "extension $uuid: glib-compile-schemas missing, settings are applied through dconf only"; fi
  fi
  mkdir -p "$EXT_DIR"
  rm -rf "$dest"; mv "$TMP/ext" "$dest"
  desk_record "$dest" -
  grep -qx "$uuid" "$DESK_STATE/ext-installed" 2>/dev/null || echo "$uuid" >>"$DESK_STATE/ext-installed"
  log "extension $uuid installed"
}

session_type() { # wayland | x11; an unknown session counts as Wayland (waiting for the login is the safe side)
  case "${XDG_SESSION_TYPE:-}" in
    wayland|x11) printf '%s' "$XDG_SESSION_TYPE"; return ;;
  esac
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then echo wayland
  elif [ -n "${DISPLAY:-}" ]; then echo x11
  else echo wayland; fi
}

ext_live() { # the running shell already runs <uuid>? (gives it a moment to pick up the enable)
  local n=0 st=""
  have gnome-extensions || return 1
  while [ "$n" -lt 6 ]; do
    st="$(gnome-extensions info "$1" 2>/dev/null | sed -n 's/^ *State: *//p' | head -n 1)"
    case "$st" in ACTIVE|ENABLED) return 0 ;; ''|ERROR*|OUT*|UNINSTALLED) return 1 ;; esac
    sleep 0.5; n=$((n + 1))
  done
  return 1
}

# Wayland cannot restart the shell, so a new extension only loads at the next login. Changes that
# belong to the new extensions then wait for that login instead of leaving a half-converted desktop.
should_defer() { # <uuid the changes depend on>
  case "$DEFER" in yes) return 0 ;; no) return 1 ;; esac
  [ "$(session_type)" = wayland ] || return 1
  # a login already applied the queue for this extension (kit-desk finish-login): the shell runs it
  grep -qx "$1" "$DESK_STATE/login-applied" 2>/dev/null && return 1
  ext_live "$1" && return 1
  return 0
}

setup_extensions() {
  local u enable=""
  if [ "$EXT_OK" != 1 ]; then report "extensions skipped (policy or not GNOME); keybindings still apply"; return 0; fi
  local list="$TILER_UUID space-bar@luchrioh just-perfection-desktop@just-perfection"
  want clipboard && list="$list $CLIP_UUID"
  for u in $list; do
    install_extension "$u" && enable="$enable $u"
  done
  [ -n "$enable" ] || return 0
  # Just Perfection writes enable-animations itself when it starts: record the original first
  case " $enable " in *" just-perfection-desktop@just-perfection "*) kd_journal /org/gnome/desktop/interface/enable-animations ;; esac
  kd_write /org/gnome/shell/disable-user-extensions false || true
  for u in $enable; do
    kd_list_remove /org/gnome/shell/disabled-extensions "$u"
    kd_list_add /org/gnome/shell/enabled-extensions "$u"
    [ "$u" = "$TILER_UUID" ] && TILER_ACTIVE=1
  done
  for u in $ALL_TILERS; do # only one tiler at a time
    [ "$u" = "$TILER_UUID" ] && continue
    if gv_items "$(kd_effective /org/gnome/shell/enabled-extensions)" | grep -qxF "$u"; then
      kd_list_remove /org/gnome/shell/enabled-extensions "$u"
      kd_list_add /org/gnome/shell/disabled-extensions "$u"
    fi
  done
  # the extensions that replace the dock and the tiling keys: what the changes below wait for
  local anchor="${TILER_UUID:-${enable# }}"; anchor="${anchor%% *}"
  if should_defer "$anchor"; then DEFER_ANCHOR="$anchor"; DEFER_ACTIVE=1; KD_DEFER=1; fi
  # Ubuntu's own tiling assistant grabs Super+arrows; it is a system extension, so disable it
  # (not with Tactile: it tiles on demand only, and the assistant is Ubuntu's Super+arrows tiling)
  if [ -n "$TILER_UUID" ] && [ "$TILER" != tactile ]; then
    kd_list_add /org/gnome/shell/disabled-extensions tiling-assistant@ubuntu.com
    # disabled while the shell runs, the assistant can end in state ERROR and keep Super+arrows
    # grabbed until the next login (GNOME 50 VM): empty its own keys too
    for k in tile-left-half tile-right-half tile-maximize restore-window; do
      kd_write "/org/gnome/shell/extensions/tiling-assistant/$k" '@as []' || true
    done
  fi
  if [ "$KEEP_DOCK" = 0 ]; then
    # a dock that is disabled while the shell runs can end in state ERROR (GNOME 50 VM) and keep its
    # reserved strip; a dock that is not fixed reserves no space even then
    kd_write /org/gnome/shell/extensions/dash-to-dock/dock-fixed false || true
    for u in ubuntu-dock@ubuntu.com ding@rastersoft.com; do
      kd_list_remove /org/gnome/shell/enabled-extensions "$u"
      kd_list_add /org/gnome/shell/disabled-extensions "$u"
    done
  fi
  KD_DEFER=0
  if [ "$DEFER_ACTIVE" = 1 ]; then
    report "extensions installed and enabled:$enable (GNOME on Wayland loads them at the next login)"
  else
    report "extensions enabled:$enable (active after log out / log in, on X11 also after Alt+F2, r)"
  fi
}

# Tiling Shell's default layout has 22 % side columns: too narrow on small screens. Ours come first
# (main and stack = the closest to Omarchy's dwindle), Super+L cycles them. A layout list the user
# already changed is left alone.
tilingshell_layouts() {
  local e=/org/gnome/shell/extensions/tilingshell json sel="" n=0 cur ids
  cur="$(kd_read $e/layouts-json)"
  # Tiling Shell stores its own defaults (Layout 1-4) on first start; those count as untouched
  ids="$(printf '%s' "$cur" | grep -o '"id":"[^"]*"' | tr '\n' ' ' || true)"
  if [ -n "$cur" ] && ! grep -q "^$e/layouts-json$TAB" "$JOURNAL" 2>/dev/null &&
     [ "$ids" != '"id":"Layout 1" "id":"Layout 2" "id":"Layout 3" "id":"Layout 4" ' ]; then
    report "Tiling Shell: your own layouts kept"; return 0
  fi
  _tile() { printf '{"x":%s,"y":%s,"width":%s,"height":%s,"groups":[1]}' "$@"; }
  json="[{\"id\":\"Main and stack\",\"tiles\":[$(_tile 0 0 0.6 1),$(_tile 0.6 0 0.4 0.5),$(_tile 0.6 0.5 0.4 0.5)]}"
  json="$json,{\"id\":\"Halves\",\"tiles\":[$(_tile 0 0 0.5 1),$(_tile 0.5 0 0.5 1)]}"
  json="$json,{\"id\":\"Thirds\",\"tiles\":[$(_tile 0 0 0.3333 1),$(_tile 0.3333 0 0.3334 1),$(_tile 0.6667 0 0.3333 1)]}"
  json="$json,{\"id\":\"Grid\",\"tiles\":[$(_tile 0 0 0.5 0.5),$(_tile 0.5 0 0.5 0.5),$(_tile 0 0.5 0.5 0.5),$(_tile 0.5 0.5 0.5 0.5)]}]"
  kd_write $e/layouts-json "'$json'" || return 0
  while [ "$n" -lt "$WORKSPACES" ]; do sel="$sel${sel:+, }['Main and stack']"; n=$((n + 1)); done
  kd_write $e/selected-layouts "[$sel]" || true
}

# PaperWM grabs Super+Return, Super+Escape, Super+T, Super+Comma, Super+F, Super+Shift+F and more by
# default, and at start it empties every GNOME keybinding that shares an accelerator with one of its
# own (restored when it is disabled). Custom shortcuts are not checked, so both grab and PaperWM wins.
# Found in the GNOME 50 VM run: Super+Return opened nothing. Written before its first start.
paperwm_keys() {
  local k=/org/gnome/shell/extensions/paperwm/keybindings name
  # Omarchy meaning on PaperWM's own actions
  kd_write $k/move-left "['<Super><Shift>Left', '<Super><Shift>comma']" || true
  kd_write $k/move-right "['<Super><Shift>Right', '<Super><Shift>period']" || true
  kd_write $k/move-up "['<Super><Shift>Up']" || true
  kd_write $k/move-down "['<Super><Shift>Down']" || true
  kd_write $k/toggle-scratch "['<Super>t']" || true                 # Super+T float (scratch layer)
  kd_write $k/toggle-scratch-window "['<Super><Control>Escape']" || true # show/hide floating windows
  kd_write $k/paper-toggle-fullscreen "['<Super>f']" || true         # Super+F full screen
  kd_write $k/toggle-maximize-width "['<Super><Alt>f']" || true      # Super+Alt+F full width
  kd_write $k/resize-w-inc "['<Super>plus']" || true # Super+- / Super+= (German: Super++) resize, see keys.tsv
  # PaperWM keeps its own space per monitor; GNOME's move-to-monitor does not move a tiled window
  kd_write $k/move-monitor-left "['<Super><Shift><Alt>Left', '<Super><Shift><Control>Left']" || true
  kd_write $k/move-monitor-right "['<Super><Shift><Alt>Right', '<Super><Shift><Control>Right']" || true
  kd_write $k/move-monitor-above "['<Super><Shift><Alt>Up', '<Super><Shift><Control>Up']" || true
  kd_write $k/move-monitor-below "['<Super><Shift><Alt>Down', '<Super><Shift><Control>Down']" || true
  kd_write $k/previous-workspace "['<Super><Control>Tab', '<Super>Above_Tab']" || true # former workspace
  # PaperWM defaults that would take a kit key or disable a GNOME key the kit uses. Its drift keys
  # (Super+[ / Super+]) sit on AltGr+8 / AltGr+9 on German QWERTZ, where GNOME binds them to Super+8 / Super+9
  for name in new-window live-alt-tab live-alt-tab-backward switch-down-workspace switch-up-workspace \
              toggle-top-and-position-bar switch-monitor-right switch-monitor-left switch-monitor-above \
              switch-monitor-below move-space-monitor-right move-space-monitor-left move-space-monitor-above \
              move-space-monitor-below swap-monitor-right swap-monitor-left swap-monitor-above swap-monitor-below \
              toggle-scratch-layer take-window switch-previous barf-out center-vertically drift-left drift-right; do
    kd_write "$k/$name" '@as []' || true
  done
}

# Forge (GNOME 42-44): i3-like automatic tiling. Its defaults use gaps, a focus hint and its own keys on
# Super+Return, Super+W, Super+H/J/K/L, Super+C and more, which are kit keys: every Forge key is
# written, the Omarchy meaning on its actions, empty for the rest.
forge_settings() {
  local e=/org/gnome/shell/extensions/forge k=/org/gnome/shell/extensions/forge/keybindings name
  kd_write $e/window-gap-size "uint32 $BORDER" || true
  kd_write $e/window-gap-hidden-on-single true || true
  kd_write $e/focus-border-toggle "$([ "$BORDER" -gt 0 ] && echo true || echo false)" || true
  kd_write $e/focus-border-size "uint32 $([ "$BORDER" -gt 0 ] && echo "$BORDER" || echo 2)" || true
  kd_write $e/split-border-toggle false || true
  kd_write $e/preview-hint-enabled false || true
  kd_write $e/showtab-decoration-enabled false || true
  kd_write $e/auto-split-enabled true || true
  kd_write $e/tiling-mode-enabled true || true
  kd_write $k/window-focus-left "['<Super>Left']" || true
  kd_write $k/window-focus-right "['<Super>Right']" || true
  kd_write $k/window-focus-up "['<Super>Up']" || true
  kd_write $k/window-focus-down "['<Super>Down']" || true
  kd_write $k/window-swap-left "['<Super><Shift>Left']" || true
  kd_write $k/window-swap-right "['<Super><Shift>Right']" || true
  kd_write $k/window-swap-up "['<Super><Shift>Up']" || true
  kd_write $k/window-swap-down "['<Super><Shift>Down']" || true
  kd_write $k/window-toggle-float "['<Super>t']" || true              # Super+T float
  kd_write $k/con-split-layout-toggle "['<Super>j', '<Super>l']" || true # Omarchy Super+J: toggle split
  kd_write $k/con-tabbed-layout-toggle "['<Super>g', '<Super><Control>f']" || true # group (tabs), monocle
  kd_write $k/window-resize-right-increase "['<Super>plus']" || true # US "=" key, German "+" key (keys.tsv)
  kd_write $k/window-resize-right-decrease "['<Super>minus']" || true
  for name in focus-border-toggle window-gap-size-increase window-gap-size-decrease con-split-horizontal \
              con-split-vertical con-stacked-layout-toggle con-tabbed-showtab-decoration-toggle \
              window-move-left window-move-right window-move-up window-move-down window-toggle-always-float \
              workspace-active-tile-toggle prefs-open prefs-tiling-toggle window-swap-last-active \
              window-snap-one-third-right window-snap-two-third-right window-snap-one-third-left \
              window-snap-two-third-left window-snap-center window-resize-left-increase \
              window-resize-left-decrease window-resize-bottom-increase window-resize-bottom-decrease \
              window-resize-top-increase window-resize-top-decrease; do
    kd_write "$k/$name" '@as []' || true
  done
}

ext_enabled() { gv_items "$(kd_effective /org/gnome/shell/enabled-extensions)" | grep -qxF "$1"; }

configure_extensions() {
  local e=/org/gnome/shell/extensions
  if [ "$TILER_ACTIVE" = 1 ]; then
    case "$TILER" in
      tilingshell)
        kd_write $e/tilingshell/enable-autotiling true || true
        # no gap to the screen edge; between windows a gap of --border px shows where one ends
        kd_write $e/tilingshell/inner-gaps "uint32 $BORDER" || true
        kd_write $e/tilingshell/outer-gaps 'uint32 0' || true
        kd_write $e/tilingshell/enable-window-border "$([ "$BORDER" -gt 0 ] && echo true || echo false)" || true
        kd_write $e/tilingshell/window-use-custom-border-color true || true
        kd_write $e/tilingshell/window-border-width "uint32 $([ "$BORDER" -gt 0 ] && echo "$BORDER" || echo 1)" || true
        kd_write $e/tilingshell/top-edge-maximize false || true
        tilingshell_layouts ;;
      paperwm)
        for k in horizontal-margin vertical-margin vertical-margin-bottom; do kd_write "$e/paperwm/$k" 0 || true; done
        kd_write $e/paperwm/window-gap "$BORDER" || true
        paperwm_keys ;;
      tactile)
        kd_write $e/tactile/gap-size "$BORDER" || true ;;
      kit)
        # a border of --border px around every tiled window (inside its tile), the focused one in the
        # theme's accent colour (kit-desk theme sets the colours)
        kd_write $e/kit-tiling/border-width "$BORDER" || true ;;
      forge)
        forge_settings ;;
    esac
  fi
  if ext_enabled space-bar@luchrioh || [ "$DRY_RUN" = 1 ]; then
    kd_write $e/space-bar/shortcuts/enable-activate-workspace-shortcuts false || true
    kd_write $e/space-bar/shortcuts/enable-move-to-workspace-shortcuts false || true
    kd_write $e/space-bar/shortcuts/open-menu '@as []' || true
    # its previous-workspace key Super+grave has no key on German QWERTZ (only a dead key there):
    # Above_Tab is the same key on both; PaperWM has its own on that key
    if [ "$TILER_ACTIVE" = 1 ] && [ "$TILER" = paperwm ]; then
      kd_write $e/space-bar/shortcuts/activate-previous-key '@as []' || true
    else
      kd_write $e/space-bar/shortcuts/activate-previous-key "['<Super>Above_Tab']" || true
    fi
    kd_write $e/space-bar/behavior/smart-workspace-names false || true
    kd_write $e/space-bar/behavior/show-empty-workspaces true || true
    kd_write $e/space-bar/behavior/always-show-numbers true || true
    kd_write $e/space-bar/behavior/system-workspace-indicator false || true
    # a click on a workspace number switches to it (default: the overview opens, also for an empty one)
    kd_write $e/space-bar/behavior/toggle-overview false || true
  fi
  if ext_enabled "$CLIP_UUID" || [ "$DRY_RUN" = 1 ]; then
    # history lives in memory only (pinned items excepted), no images, wiped at boot; only
    # Super+Ctrl+V is bound (apply_keys), the extension's Ctrl+F8..F12 keys are cleared
    kd_write $e/clipboard-indicator/cache-only-favorites true || true
    kd_write $e/clipboard-indicator/cache-images false || true
    kd_write $e/clipboard-indicator/clear-on-boot true || true
    for k in clear-history prev-entry next-entry private-mode-binding; do
      kd_write "$e/clipboard-indicator/$k" '@as []' || true
    done
  fi
  if ext_enabled just-perfection-desktop@just-perfection || [ "$DRY_RUN" = 1 ]; then
    kd_write $e/just-perfection/panel-size 24 || true
    kd_write $e/just-perfection/workspace-popup false || true
    kd_write $e/just-perfection/startup-status 0 || true
    # Super+Space opens the overview as the launcher: without the dash and the workspace thumbnails it
    # is the search field over the open windows; typing searches at once, Enter starts the first hit
    kd_write $e/just-perfection/dash false || true
    kd_write $e/just-perfection/workspace false || true
    kd_write $e/just-perfection/workspace-peek false || true
  fi
}

# ---- 5. keybindings and settings -------------------------------------------------------------
accel() { # "SUPER + SHIFT + RETURN" -> "<Shift><Super>Return"
  local mods="" key="" tok
  local IFS='+'
  for tok in $1; do
    tok="$(printf '%s' "$tok" | sed 's/^ *//; s/ *$//')"
    case "$tok" in
      SUPER) mods="$mods<Super>" ;; SHIFT) mods="$mods<Shift>" ;;
      CTRL) mods="$mods<Control>" ;; ALT) mods="$mods<Alt>" ;;
      RETURN) key=Return ;; SPACE) key=space ;; TAB) key=Tab ;; ESCAPE) key=Escape ;;
      LEFT) key=Left ;; RIGHT) key=Right ;; UP) key=Up ;; DOWN) key=Down ;;
      PRINT) key=Print ;; BACKSPACE) key=BackSpace ;; SLASH) key=slash ;; COMMA) key=comma ;;
      *) key="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')" ;;
    esac
  done
  printf '%s%s' "$mods" "$key"
}

extra_accels() { # GNOME defaults kept next to the Omarchy key, so familiar keys keep working
  case "$1" in
    */toggle-overview) echo '<Super>s' ;;
    */wm/keybindings/close) echo '<Alt>F4' ;;
    */toggle-maximized) echo '<Alt>F10' ;;
    */media-keys/screensaver) [ "$TILER_ACTIVE" = 1 ] || echo '<Super>l' ;; # Super+L = next layout with a tiler
    */toggle-message-tray) printf '%s\n' '<Super>v' '<Super>m' ;;
    # without a tiler, Super+Shift+arrows stay GNOME's own "move to monitor" keys
    */move-to-monitor-left) [ "$TILER_ACTIVE" = 1 ] || echo '<Super><Shift>Left' ;;
    */move-to-monitor-right) [ "$TILER_ACTIVE" = 1 ] || echo '<Super><Shift>Right' ;;
    */move-to-monitor-up) [ "$TILER_ACTIVE" = 1 ] || echo '<Super><Shift>Up' ;;
    */move-to-monitor-down) [ "$TILER_ACTIVE" = 1 ] || echo '<Super><Shift>Down' ;;
    */switch-to-workspace-right) printf '%s\n' '<Super>Page_Down' '<Control><Alt>Right' ;;
    */switch-to-workspace-left) printf '%s\n' '<Super>Page_Up' '<Control><Alt>Left' ;;
    */switch-group) echo '<Alt>Above_Tab' ;;
    */switch-group-backward) echo '<Shift><Alt>Above_Tab' ;;
    */show-screen-recording-ui) echo '<Control><Shift><Alt>r' ;;
  esac
}

# keys.tsv expanded: "accel|kind|target" per line, DIGIT replaced by workspace numbers
expand_keys() {
  local key spec n k digit
  grep -v '^#' "$HERE/keys.tsv" | while IFS='|' read -r key _ spec; do
    [ -n "$key" ] || continue
    case "$key" in
      *" + DIGIT")
        n=1
        while [ "$n" -le "$WORKSPACES" ]; do
          digit=$n; [ "$n" = 10 ] && digit=0
          k="${key% + DIGIT} + $digit"
          printf '%s|%s\n' "$(accel "$k")" "${spec//-DIGIT/-$n}"
          n=$((n + 1))
        done ;;
      *) printf '%s|%s\n' "$(accel "$key")" "$spec" ;;
    esac
  done
}

CUSTOM_BASE=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
apply_keys() {
  local lines path acc cmd i=0 id paths target
  lines="$(expand_keys)"
  # set: one list per path
  paths="$(printf '%s\n' "$lines" | sed -n 's/^[^|]*|set:\(.*\)$/\1/p' | sort -u)"
  for path in $paths; do
    # the kit tiler moves windows between monitors itself (mutter 46 left a window at x = 0)
    case "$path" in */wm/keybindings/move-to-monitor-*)
      if [ "$TILER_ACTIVE" = 1 ] && [ "$TILER" = kit ]; then
        printf '%s\n' "$lines" | grep "|set:$path\$" | cut -d'|' -f1 | gv_list >"$TMP/v"
        # (named window-to-monitor-*: mutter's keybinding names are global, move-to-monitor-* is its own)
        kd_write "/org/gnome/shell/extensions/kit-tiling/window-to-monitor-${path##*-}" "$(cat "$TMP/v")" || true
        kd_write "$path" '@as []' || true
        continue
      fi ;;
    esac
    { printf '%s\n' "$lines" | grep "|set:$path\$" | cut -d'|' -f1; extra_accels "$path"; } | gv_list >"$TMP/v"
    kd_write "$path" "$(cat "$TMP/v")" || true
  done
  # tiler: rows name Tiling Shell's keys; the kit tiler uses the same key names in its own schema,
  # plus kit: rows (main area narrower / wider)
  if [ "$TILER_ACTIVE" = 1 ] && { [ "$TILER" = tilingshell ] || [ "$TILER" = kit ]; }; then
    paths="$(printf '%s\n' "$lines" | sed -n 's/^[^|]*|tiler:\(.*\)$/\1/p' | sort -u)"
    [ "$TILER" = kit ] && paths="$paths $(printf '%s\n' "$lines" | sed -n 's/^[^|]*|kit:\(.*\)$/\1/p' | sort -u)"
    for path in $paths; do
      printf '%s\n' "$lines" | grep -E "[|](tiler|kit):$path\$" | cut -d'|' -f1 | gv_list >"$TMP/v"
      target="$path"
      [ "$TILER" = kit ] && target="/org/gnome/shell/extensions/kit-tiling/${path##*/}"
      kd_write "$target" "$(cat "$TMP/v")" || true
    done
  fi
  if ext_enabled "$CLIP_UUID"; then
    paths="$(printf '%s\n' "$lines" | sed -n 's/^[^|]*|clip:\(.*\)$/\1/p' | sort -u)"
    for path in $paths; do
      printf '%s\n' "$lines" | grep "|clip:$path\$" | cut -d'|' -f1 | gv_list >"$TMP/v"
      kd_write "$path" "$(cat "$TMP/v")" || true
    done
  fi
  # custom shortcuts: /custom-keybindings/work-kit-desk-NN/
  printf '%s\n' "$lines" | grep '|custom:' >"$TMP/custom" || true
  while IFS='|' read -r acc cmd; do
    [ -n "$acc" ] || continue
    cmd="${cmd#custom:}"; cmd="${cmd//@BIN@/$BIN_DIR}"
    i=$((i + 1)); id="$(printf 'work-kit-desk-%02d' "$i")"
    kd_write "$CUSTOM_BASE/$id/name" "'kit-desk: ${cmd##*/}'" || continue
    kd_write "$CUSTOM_BASE/$id/command" "'$cmd'" || continue
    kd_write "$CUSTOM_BASE/$id/binding" "'$acc'" || continue
    kd_list_add "$CUSTOM_BASE" "$CUSTOM_BASE/$id/"
  done <"$TMP/custom"
  [ "${QUIET_KEYS:-0}" = 1 ] || report "keybindings: $(printf '%s\n' "$lines" | grep -cE '[|](set|custom):') GNOME shortcuts set (table: kit-desk keys)"
}

# ta_prejournal <dconf path>...: journal the value Ubuntu's Tiling Assistant saved for a key it
# took over (its overridden-settings: {'org.gnome.x.key': <value or @mb nothing>, ...}); the
# current value is only the assistant's own
TA_HELD=0
ta_prejournal() { # sets TA_HELD=1 when the assistant's record holds one of the keys
  local ov p k line v
  TA_HELD=0
  ov="$(kd_read /org/gnome/shell/extensions/tiling-assistant/overridden-settings)"
  [ -n "$ov" ] || return 0
  for p in "$@"; do
    k="$(printf '%s' "${p#/}" | tr '/' '.')"
    line="$(printf '%s\n' "$ov" | awk '{ gsub(/, \047org\./, "\n\047org."); print }' | grep -F "'$k': <" | head -n 1)" || true
    [ -n "$line" ] || continue
    TA_HELD=1
    { [ "$DRY_RUN" = 1 ] || grep -q "^$p$TAB" "$JOURNAL" 2>/dev/null; } && continue
    v="${line#*"'$k': <"}"; v="${v%\}*}"; v="${v%>}"
    case "$v" in
      '@mb nothing') printf '%s\tunset\t\n' "$p" >>"$JOURNAL" ;;
      *) printf '%s\tset\t%s\n' "$p" "${v#@mb }" >>"$JOURNAL" ;;
    esac
  done
}

clear_conflicts() { # GNOME defaults that would steal the Omarchy keys
  local wm=/org/gnome/desktop/wm/keybindings sh=/org/gnome/shell/keybindings n
  kd_write $wm/switch-applications '@as []' || true
  kd_write $wm/switch-applications-backward '@as []' || true
  kd_write $wm/switch-input-source "['XF86Keyboard', '<Super><Control>space']" || true
  kd_write $wm/switch-input-source-backward "['<Shift>XF86Keyboard']" || true
  n=1; while [ "$n" -le 9 ]; do kd_write "$sh/switch-to-application-$n" '@as []' || true; n=$((n + 1)); done
  kd_write /org/gnome/shell/extensions/dash-to-dock/hot-keys false || true
  kd_write /org/gnome/settings-daemon/plugins/media-keys/rotate-video-lock-static "['XF86RotationLockToggle']" || true
  kd_write /org/gnome/mutter/wayland/keybindings/restore-shortcuts '@as []' || true
  kd_write $sh/screenshot-window '@as []' || true
  # Super+Space is the launcher (overview with search); an earlier kit version put it on the app grid
  kd_list_remove $sh/toggle-application-view '<Super>space'
  # Ubuntu's show-desktop default holds Super+Ctrl+D (display settings here); GNOME's
  # move-to-workspace-left/right hold Super+Shift+Alt+Left/Right (move to monitor here).
  # Found in the GNOME 50 VM run (gsd-media-keys: "Failed to grab accelerator").
  kd_list_remove $wm/show-desktop '<Primary><Super>d'
  kd_list_remove $wm/show-desktop '<Control><Super>d'
  kd_list_remove $wm/move-to-workspace-left '<Super><Shift><Alt>Left'
  kd_list_remove $wm/move-to-workspace-right '<Super><Shift><Alt>Right'
  if [ "$TILER_ACTIVE" = 1 ] && [ "$TILER" != tactile ]; then
    # Ubuntu's Tiling Assistant holds these keys (empty) while it runs and puts its saved originals
    # back when it stops, after these writes: journal its originals, and write even if equal
    ta_prejournal $wm/maximize $wm/unmaximize /org/gnome/mutter/keybindings/toggle-tiled-left \
      /org/gnome/mutter/keybindings/toggle-tiled-right /org/gnome/mutter/edge-tiling
    KD_FORCE=$TA_HELD
    kd_write $wm/maximize '@as []' || true
    kd_write $wm/unmaximize "['<Alt>F5']" || true
    kd_write /org/gnome/mutter/keybindings/toggle-tiled-left '@as []' || true
    kd_write /org/gnome/mutter/keybindings/toggle-tiled-right '@as []' || true
    kd_write /org/gnome/mutter/edge-tiling false || true
    KD_FORCE=0
  elif [ "$TILER_ACTIVE" = 1 ]; then
    # Tactile places windows only on demand, so Super+arrows keep Ubuntu's Tiling Assistant (or
    # GNOME's own half tiling). Disabling the assistant and writing GNOME's keys back instead failed
    # on GNOME 50: the assistant, still running at the login step, emptied them again.
    report "Tactile: Super+T then two grid keys places a window; Super+arrows keep half-screen tiling and maximize"
  else
    [ "${QUIET_KEYS:-0}" = 1 ] || report "no tiling extension active: Super+Left/Right keep GNOME half-screen tiling, Super+Up maximizes"
  fi
}

apply_settings() {
  local p=/org/gnome/desktop
  kd_write /org/gnome/mutter/dynamic-workspaces false || true
  kd_write $p/wm/preferences/num-workspaces "$WORKSPACES" || true
  kd_write /org/gnome/mutter/center-new-windows true || true
  # mutter maximizes a new window that is about as large as the screen; with a tiler that turns the
  # first window into a maximized one, which the tiler leaves alone (GNOME 50 VM)
  [ "$TILER_ACTIVE" = 1 ] && { kd_write /org/gnome/mutter/auto-maximize false || true; }
  kd_write $p/wm/preferences/focus-mode "'sloppy'" || true
  kd_write $p/wm/preferences/button-layout "':'" || true
  kd_write $p/wm/preferences/mouse-button-modifier "'<Super>'" || true
  kd_write $p/wm/preferences/resize-with-right-button true || true
  kd_write $p/interface/enable-hot-corners false || true
  # Super alone does nothing, like Omarchy (Super+Space is the launcher); --skip superkey keeps GNOME's
  if want superkey; then kd_write /org/gnome/mutter/overlay-key "''" || true; fi
  if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/work-kit-JetBrainsMonoNerd" ] || [ "$DRY_RUN" = 1 ]; then
    kd_write $p/interface/monospace-font-name "'JetBrainsMono Nerd Font 10'" || true
  fi
  report "settings: $WORKSPACES fixed workspaces, focus follows mouse, no title bar buttons, no hot corner$(want superkey && echo ', Super alone does nothing')"
  if want input; then
    kd_write $p/peripherals/keyboard/repeat-interval 'uint32 25' || true
    kd_write $p/peripherals/keyboard/delay 'uint32 250' || true
    kd_write $p/peripherals/keyboard/numlock-state true || true
    kd_write $p/peripherals/touchpad/click-method "'fingers'" || true
    kd_write $p/peripherals/touchpad/natural-scroll false || true
    kd_list_add $p/input-sources/xkb-options 'compose:caps'
    report "input: repeat 40/s after 250 ms, Caps Lock = Compose, two-finger right click, natural scroll off (skip with --skip input)"
  fi
}

# ---- 6. share copy for kit-desk, theme ------------------------------------------------------
install_share() {
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: kit-desk -> $BIN_DIR/kit-desk, data -> $DESK_SHARE"; return 0; fi
  rm -rf "$DESK_SHARE"; mkdir -p "$DESK_SHARE"
  cp -R "$HERE/lib" "$HERE/themes" "$HERE/templates" "$HERE/keys.tsv" "$HERE/keys-kde.tsv" "$DESK_SHARE/"
  desk_put "$HERE/bin/kit-desk" "$BIN_DIR/kit-desk"; chmod 0755 "$BIN_DIR/kit-desk"
  rm -f "$DESK_STATE/ghostty-broken" "$DESK_STATE/ghostty-sw"
}

write_install_conf() { # read by kit-desk (keys, status); written after the extensions are known
  [ "$DRY_RUN" = 1 ] && return 0
  local clip=0
  [ "$DCONF_OK" = 1 ] && ext_enabled "$CLIP_UUID" && clip=1
  [ "$DESKTOP" = kde ] && { TILER=krohnkite; TILER_ACTIVE="${KDE_TILER_ACTIVE:-0}"; clip=1; }
  printf 'desktop=%s\nplasma=%s\ntiler=%s\ntiler_active=%s\nworkspaces=%s\ngnome=%s\nclipboard=%s\ndefer_anchor=%s\npending_login=%s\nborder=%s\nsuperkey=%s\n' \
    "$DESKTOP" "$PLASMA" "$TILER" "$TILER_ACTIVE" "$WORKSPACES" "$GNOME" "$clip" "$DEFER_ANCHOR" "$PENDING_LOGIN" "$BORDER" \
    "$(want superkey && echo off || echo overview)" >"$DESK_STATE/install.conf"
}

# First login after the install: one welcome window with the key table (later: Super+K).
install_welcome() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/work-kit-desktop-welcome.desktop"
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: welcome window on next login ($f)"; return 0; fi
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=work-kit desktop welcome' \
    'Comment=Shows the keyboard shortcuts once after the install' "Exec=$BIN_DIR/kit-desk welcome" \
    'X-GNOME-Autostart-Delay=3' 'NoDisplay=true' >"$TMP/welcome.desktop"
  desk_put "$TMP/welcome.desktop" "$f"
}

# Wayland: the queued changes (see should_defer) are applied by one login-time run of
# `kit-desk finish-login`, which then removes this entry.
PENDING_LOGIN=0
install_finish_login() {
  local n=0
  [ "$DRY_RUN" = 1 ] && return 0
  [ -s "$PENDING" ] && n="$(wc -l <"$PENDING" | tr -d ' ')"
  if [ "$n" = 0 ]; then rm -f "$PENDING" "$FINISH_AUTOSTART"; return 0; fi
  printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=work-kit desktop, finish setup' \
    'Comment=Applies the desktop changes that wait for the new GNOME extensions, once' \
    "Exec=$BIN_DIR/kit-desk finish-login --login" 'X-GNOME-Autostart-Delay=2' 'NoDisplay=true' >"$TMP/finish.desktop"
  desk_put "$TMP/finish.desktop" "$FINISH_AUTOSTART"
  PENDING_LOGIN=1
  report "PENDING until the next login: $n desktop change(s) that only make sense with the new extensions."
  if grep -q "ubuntu-dock@ubuntu.com" "$PENDING"; then
    report "  - Ubuntu Dock and desktop icons stay on until then, then they are turned off"; fi
  if grep -q "tiling-assistant@ubuntu.com\|tilingshell/" "$PENDING"; then
    report "  - GNOME's own half-screen tiling and keys keep working until then, then $TILER takes over"; fi
  report "  They are applied at the login by $FINISH_AUTOSTART (kit-desk finish-login), which removes itself once they hold."
  report "  Check with: kit-desk status. Still pending after the login? Run by hand in the desktop: kit-desk finish-login"
  report "  (log: $DESK_STATE/finish-login.log). Undo: bash $HERE/uninstall.sh (also removes the entry)."
}

# ---- main ------------------------------------------------------------------------------------
desk_init_state
[ "$DRY_RUN" = 1 ] || { : >"$REPORT"; rm -f "$PENDING"; } # a queue from an earlier run is rebuilt below
policy_check
set_tiler_uuid
if [ "$CHECK_ONLY" = 1 ]; then exit 0; fi
[ -d "$SRC" ] || report "offline directory $SRC missing: files are skipped, settings still apply"
backup_dconf
install_share
want fonts && install_fonts
want terminal && install_terminal
want tuis && install_tuis
want nvim && install_nvim
with zed && install_zed
if [ "$DESKTOP" = kde ]; then
  kde_backup
  want extensions && kde_tiler
  want settings && kde_settings "$WORKSPACES"
  want keys && kde_apply_keys files "$WORKSPACES"
  [ "$KEEP_DOCK" = 1 ] || kde_panel_autohide
  kde_reload
fi
if [ "$DCONF_OK" = 1 ]; then
  want extensions && setup_extensions
  configure_extensions
  if want keys; then
    if [ "$DEFER_ACTIVE" = 1 ] && [ "$TILER_ACTIVE" = 1 ]; then
      # now: GNOME's own tiling keys as they are; queued: the tiler's keys and the GNOME keys it replaces
      TILER_ACTIVE=0 QUIET_KEYS=1; clear_conflicts; apply_keys
      TILER_ACTIVE=1 QUIET_KEYS=0 KD_DEFER=1; clear_conflicts; apply_keys; KD_DEFER=0
    else
      clear_conflicts; apply_keys
    fi
  fi
  want settings && apply_settings
fi
if want theme; then
  targs="$THEME"; want wallpaper || targs="$targs --keep-wallpaper"
  # shellcheck disable=SC2086
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: kit-desk theme $targs"
  else DESK_NO_GNOME=$((1 - DCONF_OK)) DESK_KDE="$([ "$DESKTOP" = kde ] && echo "$PLASMA")" "$BIN_DIR/kit-desk" theme $targs || report "theme failed"; fi
fi
if [ "$DEFER_ACTIVE" = 1 ]; then install_finish_login; elif [ "$DRY_RUN" != 1 ]; then rm -f "$FINISH_AUTOSTART"; fi
write_install_conf
{ [ "$DCONF_OK" = 1 ] || [ "$DESKTOP" = kde ]; } && want welcome && install_welcome
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) report "$BIN_DIR is not on PATH (60-terminal adds it)";; esac
[ -z "$LOCKED_KEYS" ] || report "locked keys left unchanged:$LOCKED_KEYS"
# The dock is off, so app search must work by keyboard: warn loudly if no launcher key is bound.
if [ "$DCONF_OK" = 1 ]; then
  launch_keys="$(kd_read /org/gnome/shell/keybindings/toggle-overview) $(kd_read /org/gnome/shell/keybindings/toggle-application-view)"
  overlay="$(kd_read /org/gnome/mutter/overlay-key)"
  case "$overlay" in "''") overlay="Super alone does nothing" ;; *) overlay="Super alone opens the overview" ;; esac
  case "$launch_keys" in
    *"<Super>space"*) report "app search: Super+Space opens the launcher (type, Enter), Super+A the app grid; $overlay" ;;
    *) report "WARNING: no launcher key bound (toggle-overview = '${launch_keys}'). Fix with: gsettings set org.gnome.shell.keybindings toggle-overview \"['<Super>space']\"" ;;
  esac
fi
if [ "$DESKTOP" = kde ]; then report "done. Log out and back in now so KWin loads the keys and Krohnkite. Undo: bash $HERE/uninstall.sh"
elif [ "$PENDING_LOGIN" = 1 ]; then report "done. Log out and back in: the extensions load and the pending changes apply by themselves. Undo: bash $HERE/uninstall.sh"
else report "done. Log out and back in to load the extensions. Undo: bash $HERE/uninstall.sh"; fi
