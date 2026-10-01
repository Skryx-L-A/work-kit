# shellcheck shell=bash
# KDE Plasma 5/6 path of module 95-desktop (sourced after lib/desk.sh by install.sh, uninstall.sh
# and kit-desk). Every KConfig write goes through kc_write, which journals the original value
# (or "unset") once, so uninstall.sh can put back exactly what was there before.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

KCJ="$DESK_STATE/kconfig-journal.tsv"
KDE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
UNSET=__KIT_UNSET__
SCF=kglobalshortcutsrc

plasma_major() { # 5 or 6, empty when Plasma is not installed
  local v=""
  if have plasmashell; then v="$(QT_QPA_PLATFORM=offscreen plasmashell --version 2>/dev/null | sed -n 's/^plasmashell \([0-9][0-9]*\).*/\1/p')"; fi
  [ -n "$v" ] || { have kwriteconfig6 && v=6; } || { have kwriteconfig5 && v=5; } || true
  printf '%s' "$v"
}

kde_tools() { # sets KRC KWC KPT QDB for the Plasma version in $PLASMA
  KRC="kreadconfig$PLASMA"; KWC="kwriteconfig$PLASMA"; KPT="kpackagetool$PLASMA"; QDB=""
  local q
  for q in qdbus6 qdbus qdbus-qt5 /usr/lib/qt6/bin/qdbus /usr/lib/qt5/bin/qdbus /usr/lib/*/qt5/bin/qdbus; do
    if have "$q" || [ -x "$q" ]; then QDB="$q"; break; fi
  done
}

kde_group_args() { # "a>b" -> --group a --group b (one word per line)
  local IFS='>' g
  for g in $1; do printf -- '--group\n%s\n' "$g"; done
}

kc_read() { # kc_read <file> <groups a>b> <key> -> value or __KIT_UNSET__
  local args=() l
  while IFS= read -r l; do args+=("$l"); done < <(kde_group_args "$2")
  "$KRC" --file "$1" "${args[@]}" --key "$3" --default "$UNSET" 2>/dev/null || printf '%s' "$UNSET"
}

kc_write() { # kc_write <file> <groups> <key> <value>
  local f="$1" g="$2" k="$3" v="$4" old args=() l
  old="$(kc_read "$f" "$g" "$k")"
  [ "$old" = "$v" ] && return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: $f [$g] $k=$v"; return 0; fi
  if ! grep -qF "$f$TAB$g$TAB$k$TAB" "$KCJ" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\n' "$f" "$g" "$k" "$old" >>"$KCJ"
  fi
  while IFS= read -r l; do args+=("$l"); done < <(kde_group_args "$g")
  "$KWC" --file "$f" "${args[@]}" --key "$k" -- "$v" 2>/dev/null ||
    { report "could not write $f [$g] $k"; return 1; }
}

kc_restore() { # uninstall: journal lines in reverse order, back to the old value or deleted
  # kc_restore [--script OUT]: for kglobalshortcutsrc, write bash commands to OUT instead
  local f g k old args l out=""
  [ "${1:-}" = --script ] && out="$2"
  [ -s "$KCJ" ] || return 0
  { if have tac; then tac "$KCJ"; else tail -r "$KCJ"; fi; } | while IFS="$TAB" read -r f g k old; do
    [ -n "$f" ] || continue
    args=()
    if [ -n "$out" ] && [ "$f" = "$SCF" ]; then
      while IFS= read -r l; do args+=("$l"); done < <(kde_group_args "$g")
      if [ "$old" = "$UNSET" ]; then printf '%q ' "$KWC" --file "$f" "${args[@]}" --key "$k" --delete >>"$out"
      else printf '%q ' "$KWC" --file "$f" "${args[@]}" --key "$k" -- "$old" >>"$out"; fi
      printf '|| true\n' >>"$out"; continue
    fi
    while IFS= read -r l; do args+=("$l"); done < <(kde_group_args "$g")
    if [ "$DRY_RUN" = 1 ]; then log "dry-run: restore $f [$g] $k"; continue; fi
    if [ "$old" = "$UNSET" ]; then "$KWC" --file "$f" "${args[@]}" --key "$k" --delete 2>/dev/null || true
    else "$KWC" --file "$f" "${args[@]}" --key "$k" -- "$old" 2>/dev/null || warn "could not restore $f [$g] $k"; fi
  done
}

# ---- keys ------------------------------------------------------------------------------------
KDE_KB="${KDE_KB:-us}" # keyboard layout the keys are written for: us | de (kb_layout)

kde_accel() { # "SUPER + SHIFT + RETURN" -> "Meta+Shift+Return"
  local out="" tok k
  local IFS='+'
  for tok in $1; do
    tok="$(printf '%s' "$tok" | sed 's/^ *//; s/ *$//')"
    case "$tok" in
      SUPER) k=Meta ;; SHIFT) k=Shift ;; CTRL) k=Ctrl ;; ALT) k=Alt ;;
      RETURN) k=Return ;; SPACE) k=Space ;; TAB) k=Tab ;; ESCAPE) k=Esc ;; PRINT) k=Print ;;
      LEFT) k=Left ;; RIGHT) k=Right ;; UP) k=Up ;; DOWN) k=Down ;; MINUS) k='-' ;; EQUAL) k='=' ;;
      PLUS) if [ "$KDE_KB" = de ]; then k='+'; else k='='; fi ;;
      *) k="$tok" ;;
    esac
    out="$out${out:++}$k"
  done
  # KWin matches a shifted symbol key by the symbol it types, without Shift: US Shift+= is Meta++,
  # German Shift++ is Meta+*, Shift+- is Meta+_ on both (Meta+Shift+= / Meta+Shift+- never fired,
  # Plasma 6.6 VM with uinput keys, 2026-09-26)
  case "$KDE_KB:$out" in
    us:*Shift+=) out="${out%Shift+=}+" ;;
    de:*Shift++) out="${out%Shift++}*" ;;
    *:*Shift+-) out="${out%Shift+-}_" ;;
  esac
  printf '%s' "$out"
}

kde_extra() { # KDE defaults kept next to the Omarchy key (tab separated)
  case "$1" in
    "Window Close") printf '\tAlt+F4' ;;
    "Window Maximize") printf '\tMeta+PgUp' ;;
    "Lock Session") printf '\tScreensaver' ;;
    org.kde.krunner.desktop) printf '\tAlt+Space\tAlt+F2\tSearch' ;;
    org.kde.plasma.emojier.desktop) printf '\tMeta+.' ;;
    show-on-mouse-pos) printf '\tMeta+V' ;;
    "Switch to Next Keyboard Layout") printf '\tMeta+Alt+K' ;;
  esac
}

# Values are "active keys,default keys,friendly name": a comma in a name would split the value,
# so names lose their commas, and an existing entry keeps its own name.
sc_set() { # sc_set <group> <action> <keys> [friendly name]: set the active keys of a shortcut
  local g="$1" a="$2" keys="$3" name="${4:-$2}" old
  old="$(kc_read "$SCF" "$g" "$a")"
  if [ "$old" != "$UNSET" ]; then name="${old##*,}"; fi
  kc_write "$SCF" "$g" "$a" "$keys,none,${name//,/}"
}

sc_service() { # sc_service <desktop file id> <keys> <name>: _launch key of an application
  local name="${3//,/}" old
  if [ "$PLASMA" -ge 6 ]; then kc_write "$SCF" "services>$1" _launch "$2"; return; fi
  old="$(kc_read "$SCF" "$1" _launch)"
  if [ "$old" != "$UNSET" ]; then name="${old##*,}"; fi
  [ "$(kc_read "$SCF" "$1" _k_friendly_name)" = "$UNSET" ] && kc_write "$SCF" "$1" _k_friendly_name "$name"
  kc_write "$SCF" "$1" _launch "$2,none,$name"
}

kde_shift_digit() { # Meta+Shift+2 arrives as Meta+@ (US) or Meta+" (German) on X11: add both
  local d="${1##*+}" us de
  local usl=(')' '!' '@' '#' '$' '%' '^' '&' '*' '(') del=('=' '!' '"' '§' '$' '%' '&' '/' '(' ')')
  us="${usl[$d]}"; de="${del[$d]}"
  printf '%s' "$1"
  printf '\t%s' "${1%+Shift+*}+$us"
  # Meta+= is Super+= (wider window) with a US layout; with a German one that key is Meta++
  [ "$de" = "$us" ] || { [ "$de" = "=" ] && [ "$KDE_KB" != de ]; } || printf '\t%s' "${1%+Shift+*}+$de"
}

# Plasma defaults that would steal the Omarchy keys: group|action|friendly[|keys, default none].
# Journaled like our own keys, so uninstall.sh puts them back. Plasma 6 also puts Meta+Tab on
# Walk Through Windows; left there, the shortcut daemon strips it itself, unjournaled (found in the
# Plasma 6 VM: after uninstall Meta+Tab was gone).
kde_conflicts() {
  local n=1
  printf '%s\n' "kwin|Window Quick Tile Left|Quick Tile Window to the Left" \
    "kwin|Window Quick Tile Right|Quick Tile Window to the Right" \
    "kwin|Window Quick Tile Top|Quick Tile Window to the Top" \
    "kwin|Window Quick Tile Bottom|Quick Tile Window to the Bottom" \
    "kwin|Overview|Toggle Overview" "kwin|Edit Tiles|Toggle Tiles Editor" \
    "kwin|Walk Through Windows|Walk Through Windows|Alt+Tab" \
    "kwin|Walk Through Windows (Reverse)|Walk Through Windows (Reverse)|Alt+Shift+Tab" \
    "kwin|Activate Window Demanding Attention|Activate Window Demanding Attention" \
    "kwin|view_zoom_in|Zoom In" "kwin|view_zoom_out|Zoom Out" \
    "plasmashell|next activity|Walk through activities" \
    "plasmashell|previous activity|Walk through activities (Reverse)" \
    "kwin|Krohnkite: Set master|Krohnkite: Set master" "kwin|KrohnkiteSetMaster|Krohnkite: Set master" \
    "kwin|Krohnkite: Tile Layout|Krohnkite: Tile Layout" "kwin|KrohnkiteTileLayout|Krohnkite: Tile Layout" \
    "kwin|Krohnkite: Float All|Krohnkite: Float All" "kwin|KrohnkiteFloatAll|Krohnkite: Toggle Float All" \
    "kwin|Krohnkite: Increase|Krohnkite: Increase" "kwin|KrohnkiteIncrease|Krohnkite: Increase" \
    "kwin|Krohnkite: Decrease|Krohnkite: Decrease" "kwin|KrohnkiteDecrease|Krohnkite: Decrease" \
    "kwin|KrohnkiteFocusNext|Krohnkite: Focus Next" "kwin|KrohnkiteFocusPrev|Krohnkite: Focus Previous"
  while [ "$n" -le 10 ]; do printf 'plasmashell|activate task manager entry %s|Activate Task Manager Entry %s\n' "$n" "$n"; n=$((n + 1)); done
}

kde_launcher() { # kde_launcher files|keys <id> <command> <name> <keys>: desktop file or its shortcut
  local id="$2" cmd="$3" name="$4" keys="$5" f
  if [ "$1" = keys ]; then sc_service "$id.desktop" "$keys" "$name"; return; fi
  f="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$id.desktop"
  printf '%s\n' '[Desktop Entry]' 'Type=Application' "Name=$name" "Exec=$cmd" 'NoDisplay=true' \
    'X-KDE-GlobalAccel-CommandShortcut=true' >"$TMP/$id.desktop"
  desk_put "$TMP/$id.desktop" "$f"
}

# The shortcut daemon (kglobalaccel) keeps kglobalshortcutsrc in memory and writes it back over
# any change made while it runs. So install.sh only creates the launchers and a login hook in
# ~/.config/plasma-workspace/env/, which Plasma runs before the daemon starts; the hook calls
# `kit-desk kde-keys` once (kde_apply_keys keys). uninstall.sh restores the same way.
KDE_ENV_DIR="$KDE_CFG/plasma-workspace/env"
kde_login_hook() { # kde_login_hook <file name> <script body>
  printf '#!/bin/sh\n# work-kit 95-desktop (runs at Plasma login, before the shortcut daemon)\n%s\n' "$2" >"$TMP/$1"
  desk_put "$TMP/$1" "$KDE_ENV_DIR/$1"
}

kde_key_lines() { # keys-kde.tsv expanded: "accel|action|kind:target", DIGIT replaced (bash 3.2 cannot parse this inside $(...))
  local key action spec n digit
  grep -v '^#' "${KEYS_KDE:-$HERE/keys-kde.tsv}" | while IFS='|' read -r key action spec; do
    [ -n "$key" ] || continue
    case "$spec" in none:*|kde:*|super:*) continue ;; esac
    case "$key" in
      *" + DIGIT")
        n=1
        while [ "$n" -le "$1" ]; do
          digit=$n; [ "$n" = 10 ] && digit=0
          printf '%s|%s|%s\n' "$(kde_accel "${key% + DIGIT} + $digit")" "${action//DIGIT/$n}" "${spec//DIGIT/$n}"
          n=$((n + 1))
        done ;;
      *) printf '%s|%s|%s\n' "$(kde_accel "$key")" "$action" "$spec" ;;
    esac
  done
}

kde_apply_keys() { # kde_apply_keys files|keys <workspaces>
  local mode="$1"; shift
  local lines line key action spec kind target k n digit acc p5 p6 i=0 cmd prev_cmd="" keys="" name=""
  KDE_KB="$(kb_layout kde)"
  lines="$(kde_key_lines "$1")"
  # conflicts first, so an Omarchy key that reuses one of them wins
  [ "$mode" = keys ] && while IFS='|' read -r k a name v; do
    [ -n "$k" ] && sc_set "$k" "$a" "${v:-none}" "$name"
  done < <(kde_conflicts)
  [ "$mode" = keys ] && while IFS='|' read -r acc action spec; do
    [ -n "$acc" ] || continue
    kind="${spec%%:*}"; target="${spec#*:}"
    case "$kind" in
      kwin) case "$acc" in *+Shift+[0-9]) acc="$(kde_shift_digit "$acc")" ;; esac
            sc_set kwin "$target" "$acc$(kde_extra "$target")" ;;
      tile) p5="${target%%;*}"; p6="${target#*;}"
            if [ "$PLASMA" -ge 6 ]; then sc_set kwin "$p6" "$acc" "$p5"; else sc_set kwin "$p5" "$acc"; fi ;;
      ksm) sc_set ksmserver "$target" "$acc$(kde_extra "$target")" ;;
      shell) sc_set plasmashell "$target" "$acc$(kde_extra "$target")" ;;
      layout) sc_set "KDE Keyboard Layout Switcher" "$target" "$acc$(kde_extra "$target")" ;;
      svc) sc_service "$target" "$acc$(kde_extra "$target")" "$action" ;;
    esac
  done <<<"$lines"
  # own launchers: one desktop file per command, all its keys on it
  printf '%s\n' "$lines" | grep '|custom:' | sed 's/^\([^|]*\)|\([^|]*\)|custom:\(.*\)$/\3|\1|\2/' >"$TMP/kcustom" || true
  sort -t'|' -k1,1 -s "$TMP/kcustom" >"$TMP/kcustom.s"
  while IFS='|' read -r cmd acc action; do
    if [ "$cmd" != "$prev_cmd" ] && [ -n "$prev_cmd" ]; then
      i=$((i + 1)); kde_launcher "$mode" "$(printf 'work-kit-desk-%02d' "$i")" "${prev_cmd//@BIN@/$BIN_DIR}" "kit-desk: $name" "$keys"; keys=""
    fi
    [ "$cmd" = "$prev_cmd" ] || name="$action"
    keys="$keys${keys:+$TAB}$acc"; prev_cmd="$cmd"
  done <"$TMP/kcustom.s"
  if [ -n "$prev_cmd" ]; then
    i=$((i + 1)); kde_launcher "$mode" "$(printf 'work-kit-desk-%02d' "$i")" "${prev_cmd//@BIN@/$BIN_DIR}" "kit-desk: $name" "$keys"
  fi
  if [ "$mode" = files ]; then
    # shellcheck disable=SC2016  # expanded at login, not now
    kde_login_hook work-kit-desktop-keys.sh '[ -x "$HOME/.local/bin/kit-desk" ] && "$HOME/.local/bin/kit-desk" kde-keys >/dev/null 2>&1 || true'
    report "keybindings: $i launchers created; the Omarchy keys are written at the next login (table: kit-desk keys)"
  else
    log "keybindings: Omarchy keys written to kglobalshortcutsrc"
  fi
  return 0
}

# ---- tiling, settings, panel, colours ---------------------------------------------------------
# Krohnkite 0.8.1 (Plasma 5) reads client.basicUnit, which KWin 5.27 has only for X11 windows: on a
# Plasma Wayland session every native Wayland window hit "TypeError: Cannot read property 'width' of
# undefined" (script.js adjustGeometry) and stayed untiled (Kubuntu 24.04 VM, KWin 5.27.11,
# 2026-09-26). One guard in the kit's own copy; a Krohnkite the user installed is not touched.
kde_krohnkite_wayland_fix() { # <script dir>
  local js="$1/contents/code/script.js"
  grep -qx krohnkite "$DESK_STATE/kwin-scripts" 2>/dev/null || return 0
  [ -f "$js" ] && grep -q 'if (!(this.client.basicUnit.width === 1' "$js" || return 0
  sed -i.kit-orig 's/if (!(this\.client\.basicUnit\.width === 1/if (this.client.basicUnit \&\& !(this.client.basicUnit.width === 1/' "$js" &&
    rm -f "$js.kit-orig" && log "Krohnkite: guard for Wayland windows added (client.basicUnit is X11 only)"
}

kde_tiler() { # install and configure Krohnkite; sets KDE_TILER_ACTIVE
  local file dir="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/krohnkite" s=Script-krohnkite
  KDE_TILER_ACTIVE=0
  if [ "$PLASMA" -ge 6 ]; then file="$SRC/kde/krohnkite-0.9.9.2.kwinscript"; else file="$SRC/kde/krohnkite-0.8.1.kwinscript"; fi
  if [ -d "$dir" ] && ! grep -qx krohnkite "$DESK_STATE/kwin-scripts" 2>/dev/null; then
    report "Krohnkite: already installed by you, kept"
  elif [ ! -f "$file" ]; then report "missing offline artifact $file: no tiling (KWin keeps its own quick tiling)"; return 0
  elif [ "$DRY_RUN" = 1 ]; then log "dry-run: install Krohnkite from $file"
  elif have "$KPT"; then
    if [ -d "$dir" ]; then "$KPT" --type=KWin/Script -u "$file" >/dev/null 2>&1 || true
    else "$KPT" --type=KWin/Script -i "$file" >/dev/null 2>&1 || { report "Krohnkite install failed"; return 0; }; fi
    grep -qx krohnkite "$DESK_STATE/kwin-scripts" 2>/dev/null || echo krohnkite >>"$DESK_STATE/kwin-scripts"
  else
    # kpackagetool is only a recommended package (missing on a minimal Plasma install, found in
    # the Plasma 6 VM); a .kwinscript is a zip that it would unpack into this directory
    rm -rf "$dir.new" && mkdir -p "$dir.new"
    if have unzip; then unzip -q -o "$file" -d "$dir.new" 2>/dev/null
    elif have python3; then python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$file" "$dir.new"
    fi
    if [ ! -f "$dir.new/metadata.json" ] && [ ! -f "$dir.new/metadata.desktop" ]; then
      rm -rf "$dir.new"; report "$KPT missing and the script could not be unpacked: no tiling script"; return 0
    fi
    rm -rf "$dir"; mv "$dir.new" "$dir"
    grep -qx krohnkite "$DESK_STATE/kwin-scripts" 2>/dev/null || echo krohnkite >>"$DESK_STATE/kwin-scripts"
    log "Krohnkite unpacked to $dir ($KPT missing)"
  fi
  [ "$DRY_RUN" = 1 ] || kde_krohnkite_wayland_fix "$dir"
  kc_write kwinrc Plugins krohnkiteEnabled true || return 0
  local k
  for k in screenGapLeft screenGapRight screenGapTop screenGapBottom; do kc_write kwinrc "$s" "$k" 0; done
  # between tiled windows a gap of --border px shows where one ends (no gap at the screen edge)
  for k in tileLayoutGap screenGapBetween; do kc_write kwinrc "$s" "$k" "${BORDER:-0}"; done
  kc_write kwinrc "$s" noTileBorder true   # tiled windows without title bar: no wasted space
  kc_write kwinrc "$s" directionalKeyFocus true  # Super+arrows move the focus (default: resize master)
  kc_write kwinrc "$s" directionalKeyDwm false
  KDE_TILER_ACTIVE=1
  report "tiling: Krohnkite (no gap at the screen edge, ${BORDER:-0} px between windows, no title bars on tiled windows)"
}

kde_settings() { # $1 = workspaces
  kc_write kwinrc Desktops Number "$1"; kc_write kwinrc Desktops Rows 1
  kc_write kwinrc Windows FocusPolicy FocusFollowsMouse
  kc_write kwinrc org.kde.kdecoration2 BorderSize None
  kc_write kwinrc org.kde.kdecoration2 BorderSizeAuto false
  # Meta alone does nothing, like Omarchy (Meta+Space is the launcher); --skip superkey keeps the menu
  want superkey && kc_write kwinrc ModifierOnlyShortcuts Meta ""
  report "settings: $1 workspaces, focus follows mouse, no window borders$(want superkey && echo ', Meta alone does nothing')"
  if want input; then
    kc_write kcminputrc Keyboard RepeatDelay 250; kc_write kcminputrc Keyboard RepeatRate 40
    report "input: key repeat 40/s after 250 ms (skip with --skip input)"
  fi
}

kde_eval() { # run a Plasma shell script, print its output
  [ -n "$QDB" ] || return 1
  "$QDB" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1" 2>/dev/null
}

kde_panel_autohide() {
  local st="$DESK_STATE/kde-panels" out
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: panels auto-hide"; return 0; fi
  out="$(kde_eval 'var o=[];panels().forEach(function(p){o.push(p.id+"="+p.hiding);p.hiding="autohide";});print(o.join(" "));')" ||
    { report "panel: Plasma shell not reachable, panel left as it is"; return 0; }
  [ -s "$st" ] || printf '%s\n' "$out" >"$st"
  report "panel: auto-hide (it slides in at the screen edge)"
}

kde_panel_restore() {
  local st="$DESK_STATE/kde-panels" p js=""
  [ -s "$st" ] || return 0
  # shellcheck disable=SC2013  # one line of "id=hiding" words
  for p in $(cat "$st"); do js="$js var q=panelById(${p%%=*}); if(q) q.hiding=\"${p#*=}\";"; done
  kde_eval "$js" >/dev/null || warn "could not restore the panel; set it in its edit mode"
}

kde_colors() { # kde_colors dark|light: Breeze colour scheme matching the theme
  local want=BreezeDark
  [ "$1" = light ] && want=BreezeLight
  have plasma-apply-colorscheme || return 0
  [ "$(kc_read kdeglobals General ColorScheme)" = "$want" ] && return 0
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: plasma-apply-colorscheme $want"; return 0; fi
  grep -qF "kdeglobals${TAB}General${TAB}ColorScheme$TAB" "$KCJ" 2>/dev/null ||
    printf 'kdeglobals\tGeneral\tColorScheme\t%s\n' "$(kc_read kdeglobals General ColorScheme)" >>"$KCJ"
  plasma-apply-colorscheme "$want" >/dev/null 2>&1 || true
}

kde_reload() { # make KWin and the shortcut daemon pick up the files
  [ "$DRY_RUN" = 1 ] && return 0
  if [ -n "$QDB" ]; then "$QDB" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; fi
}
