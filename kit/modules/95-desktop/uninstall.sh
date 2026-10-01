#!/usr/bin/env bash
# Undo 95-desktop: restore every journaled dconf key to its value before the first install,
# take our items out of GNOME lists (extensions, custom shortcuts, xkb options), remove the
# files the module created and move backed-up files back. Backups in
# ~/.local/share/work-kit/desktop/backup/ are kept.
#
# Usage: uninstall.sh [--dry-run] [--full-restore]
#   --full-restore   additionally load the complete dconf dump taken before the first install
#                    (dconf load /): also reverts unrelated settings changed since then
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/desk.sh
. "$HERE/lib/desk.sh"
# shellcheck source=lib/kde.sh
. "$HERE/lib/kde.sh"

FULL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --full-restore) FULL=1 ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

# a login-time step that never ran (Wayland install, no login since) must not survive the uninstall
if [ -e "$FINISH_AUTOSTART" ]; then
  if [ "$DRY_RUN" = 1 ]; then log "dry-run: remove pending login entry $FINISH_AUTOSTART"
  else rm -f "$FINISH_AUTOSTART"; log "removed pending login entry $FINISH_AUTOSTART"; fi
fi
[ -d "$DESK_STATE" ] || { log "nothing to undo (no state in $DESK_STATE)"; exit 0; }
reverse() { if have tac; then tac "$1"; else tail -r "$1"; fi; }

# KDE: KConfig keys back, panel, colour scheme, Krohnkite; then KWin reloads
PLASMA="$(sed -n 's/^plasma=//p' "$DESK_STATE/install.conf" 2>/dev/null | head -n 1)"
if [ -n "$PLASMA" ] && { [ -s "$KCJ" ] || [ -s "$DESK_STATE/kde-panels" ]; }; then
  kde_tools
  old_scheme="$(awk -F'\t' '$1=="kdeglobals" && $3=="ColorScheme" {print $4; exit}' "$KCJ" 2>/dev/null)"
  # the shortcut daemon would overwrite kglobalshortcutsrc now; restore it at the next login
  rdir="$KIT_DATA/desktop-restore"; hook="$KDE_ENV_DIR/work-kit-desktop-restore.sh"
  if { grep -q "^$SCF$TAB" "$KCJ" 2>/dev/null || [ -s "$DESK_STATE/kde-panels" ]; } && [ "$DRY_RUN" != 1 ]; then
    mkdir -p "$rdir" "$KDE_ENV_DIR"
    printf '#!/usr/bin/env bash\n# work-kit 95-desktop: put back the shortcuts from before the install\n' >"$rdir/restore.sh"
    kc_restore --script "$rdir/restore.sh"
    # Krohnkite entries the daemon added on its own (not in the backup from before the install)
    for k in $(sed -n 's/^\(Krohnkite[^=]*\)=.*/\1/p' "$KDE_CFG/$SCF" 2>/dev/null | tr ' ' '#'); do
      k="${k//#/ }"
      grep -qF "$k=" "$DESK_BACKUP/kde-original/$SCF" 2>/dev/null ||
        printf '%q ' "$KWC" --file "$SCF" --group kwin --key "$k" --delete >>"$rdir/restore.sh"
      printf '\n' >>"$rdir/restore.sh"
    done
    # panel visibility (0 none, 1 autohide, 2 windows can cover, 3 windows go below), before plasmashell starts
    # shellcheck disable=SC2013  # one line of "id=hiding" words
    for p in $(cat "$DESK_STATE/kde-panels" 2>/dev/null); do
      case "${p#*=}" in none) v=0 ;; autohide) v=1 ;; windowscover) v=2 ;; windowsbelow) v=3 ;; *) continue ;; esac
      printf '%q ' "$KWC" --file plasmashellrc --group PlasmaViews --group "Panel ${p%%=*}" --key panelVisibility "$v" >>"$rdir/restore.sh"
      printf '\n' >>"$rdir/restore.sh"
    done
    printf 'rm -f %q\nrm -rf %q\n' "$hook" "$rdir" >>"$rdir/restore.sh"
    printf '#!/bin/sh\n# work-kit 95-desktop: one-time shortcut restore at login\n[ -f %s ] && bash %s >/dev/null 2>&1 || true\n' \
      "\"$rdir/restore.sh\"" "\"$rdir/restore.sh\"" >"$hook"
    log "keyboard shortcuts are restored at the next login"
  else
    kc_restore --script /dev/null
  fi
  # the scheme's colours live in many kdeglobals groups: apply the old scheme again (unset = Plasma's BreezeLight)
  if [ -n "$old_scheme" ] && have plasma-apply-colorscheme && [ "$DRY_RUN" != 1 ]; then
    [ "$old_scheme" = "$UNSET" ] && old_scheme=BreezeLight
    # it refuses a scheme it believes is current (an unset key counts as BreezeLight)
    "$KWC" --file kdeglobals --group General --key ColorScheme kit-reset 2>/dev/null || true
    plasma-apply-colorscheme "$old_scheme" >/dev/null 2>&1 || true
  fi
  [ "$DRY_RUN" = 1 ] || kde_panel_restore
  if grep -qx krohnkite "$DESK_STATE/kwin-scripts" 2>/dev/null && [ "$DRY_RUN" != 1 ]; then
    kdir="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/krohnkite"
    if have "$KPT"; then "$KPT" --type=KWin/Script -r krohnkite >/dev/null 2>&1 || true; fi
    rm -rf "$kdir"
  fi
  kde_reload
  log "KDE settings restored (log out and in so the shortcuts reload)"
fi

# Extensions this module installed, with their dconf directories (cleared at the end)
ext_dconf_dir() {
  case "$1" in
    kit-tiling@work-kit) echo kit-tiling ;; tilingshell@ferrarodomenico.com) echo tilingshell ;; paperwm@paperwm.github.com) echo paperwm ;;
    tactile@lundal.io) echo tactile ;; forge@jmmaranan.com) echo forge ;; space-bar@luchrioh) echo space-bar ;;
    just-perfection-desktop@just-perfection) echo just-perfection ;; clipboard-indicator@tudmotu.com) echo clipboard-indicator ;;
  esac
}
OUR_EXT="$(cat "$DESK_STATE/ext-installed" 2>/dev/null || true)"
# Tiling Shell puts back the GNOME keys it overrode when it is disabled, which would be the kit's
# values; empty its record first so the journal below has the last word
if printf '%s\n' "$OUR_EXT" | grep -qx tilingshell@ferrarodomenico.com && [ "$DRY_RUN" != 1 ]; then
  kd_raw_write /org/gnome/shell/extensions/tilingshell/overridden-settings "'{}'" || true
fi

# Extensions keep running until the next login, and several write GNOME keys while they stop or when
# the keys below change under them: PaperWM writes back every GNOME key it emptied (as explicit
# values), Just Perfection enable-animations, Space Bar its styles; a live disable can also fail
# half-way (seen on GNOME 50). So besides the restore below, a one-time login script settles these
# keys once the extensions no longer run: the kit's journal wins, else the value in the dconf dump
# from before the first install, else the schema default.
ini_get() { # ini_get <dconf dump> <dir without leading slash> <key>
  awk -v sec="[$2]" -v k="$3=" '$0==sec {on=1; next} /^\[/ {on=0} on && index($0,k)==1 {print substr($0,length(k)+1); exit}' "$1" 2>/dev/null
}
settle_cmd() { # settle_cmd <dconf path> -> one shell line that puts the original back
  local path="$1" dir key line orig
  dir="${path%/*}"; dir="${dir#/}"; key="${path##*/}"
  line="$(awk -F'\t' -v p="$path" '$1==p {print $2 "\t" $3; exit}' "$JOURNAL" 2>/dev/null)"
  case "$line" in
    unset*) printf 'dconf reset %q\n' "$path"; return ;;
    set*) printf 'dconf write %q %q\n' "$path" "${line#set"$TAB"}"; return ;;
  esac
  orig="$(ini_get "$DESK_BACKUP/dconf-original.ini" "$dir" "$key")"
  if [ -n "$orig" ]; then printf 'dconf write %q %q\n' "$path" "$orig"; else printf 'dconf reset %q\n' "$path"; fi
}
SETTLE=""
if [ -n "$OUR_EXT" ]; then
  # Ubuntu's Tiling Assistant comes back during the uninstall and records the kit's key values as
  # the originals it puts back when it is disabled later
  SETTLE="/org/gnome/desktop/interface/enable-animations /org/gnome/mutter/attach-modal-dialogs /org/gnome/mutter/workspaces-only-on-primary /org/gnome/mutter/edge-tiling /org/gnome/shell/extensions/tiling-assistant/overridden-settings"
  if printf '%s\n' "$OUR_EXT" | grep -qx paperwm@paperwm.github.com; then
    # PaperWM's record: {"<key>":{"bind":"[...]","schema_id":"<schema>"},...}
    SETTLE="$SETTLE $(kd_read /org/gnome/shell/extensions/paperwm/restore-keybinds | sed 's/},"/}\n"/g' |
      sed -n 's/^[^"]*"\([a-z0-9-]*\)":{"bind":.*"schema_id":"\([a-z.-]*\)".*/\2 \1/p' |
      while read -r schema key; do printf '/%s/%s ' "$(printf '%s' "$schema" | tr '.' '/')" "$key"; done)"
  fi
fi

# 1. list items: remove what we added, put back what we removed (other entries stay)
if [ -s "$LISTJ" ]; then
  reverse "$LISTJ" | while IFS="$TAB" read -r path op item; do
    [ -n "$path" ] || continue
    cur="$(gv_items "$(kd_effective "$path")")"
    case "$op" in
      added) new="$(printf '%s\n' "$cur" | { grep -vxF "$item" || true; } | gv_list)" ;;
      removed) printf '%s\n' "$cur" | grep -qxF "$item" && continue
               new="$( { printf '%s\n' "$cur"; printf '%s\n' "$item"; } | gv_list)" ;;
      *) continue ;;
    esac
    if [ "$DRY_RUN" = 1 ]; then log "dry-run: $path -> $new"; else kd_raw_write "$path" "$new" || warn "could not write $path"; fi
  done
fi

# the shell disables removed extensions right away, and several write keys while they stop
# (PaperWM, Just Perfection, Space Bar): wait until none of ours is active (at most 10 s)
if [ "$DRY_RUN" != 1 ] && [ -n "$OUR_EXT" ]; then
  n=0
  while [ "$n" -lt 20 ] && have gnome-extensions && pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1; do
    busy=0
    for u in $OUR_EXT; do gnome-extensions info "$u" 2>/dev/null | grep -q 'State: ACTIVE' && busy=1; done
    [ "$busy" = 0 ] && break
    sleep 0.5; n=$((n + 1))
  done
  sleep 1
fi

# 2. plain keys: back to the original value (list keys are handled above)
if [ -s "$JOURNAL" ]; then
  while IFS="$TAB" read -r path state value; do
    [ -n "$path" ] || continue
    if [ "$DRY_RUN" = 1 ]; then log "dry-run: restore $path ($state)"; continue; fi
    if grep -q "^$path$TAB" "$LISTJ" 2>/dev/null; then
      # list key: items were fixed above; when nothing else changed since the install, put
      # back the exact original (also "unset" and the original order)
      raw="$(kd_effective "$path")"; cur="$(gv_items "$raw" | sort)"
      if [ "$state" = unset ]; then
        # the original was the schema default: reset, and keep the reset only if it gives the
        # same items (a default list, e.g. show-desktop, had an item taken out and put back)
        kd_reset "$path"
        [ "$(gv_items "$(kd_effective "$path")" | sort)" = "$cur" ] || kd_raw_write "$path" "$raw" || true
        continue
      fi
      [ "$cur" = "$(gv_items "$value" | sort)" ] || continue
    fi
    if [ "$state" = unset ]; then kd_reset "$path"; else kd_raw_write "$path" "$value" || warn "could not restore $path"; fi
  done <"$JOURNAL"
  log "restored $(wc -l <"$JOURNAL" | tr -d ' ') dconf keys"
fi
if have dconf && [ "$DRY_RUN" != 1 ]; then
  for d in $(dconf list /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ 2>/dev/null | grep '^work-kit-desk-' || true); do
    dconf reset -f "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$d"
  done
  # settings of the extensions we installed (they also write their own keys at first start)
  for u in $OUR_EXT; do
    d="$(ext_dconf_dir "$u")"
    [ -n "$d" ] && dconf reset -f "/org/gnome/shell/extensions/$d/"
  done
  if [ -n "$OUR_EXT" ]; then
    gdir="$KIT_DATA/desktop-restore-gnome"; gauto="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/work-kit-desktop-restore.desktop"
    mkdir -p "$gdir" "$(dirname "$gauto")"
    {
      printf '#!/usr/bin/env bash\n# work-kit 95-desktop: settle GNOME keys once the removed extensions no longer run\n'
      for u in $OUR_EXT; do d="$(ext_dconf_dir "$u")"; [ -z "$d" ] || printf 'dconf reset -f %q\n' "/org/gnome/shell/extensions/$d/"; done
      for p in $SETTLE; do settle_cmd "$p"; done
      printf 'rm -f %q\nrm -rf %q\n' "$gauto" "$gdir"
    } >"$gdir/restore.sh"
    printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=work-kit desktop restore' \
      "Exec=bash \"$gdir/restore.sh\"" 'NoDisplay=true' 'X-GNOME-Autostart-Phase=Initialization' >"$gauto"
    log "GNOME: a one-time login script finishes the restore ($gauto)"
  fi
fi

# 3. files: newest first; a backup made at install time moves back into place
if [ -s "$FILES" ]; then
  reverse "$FILES" | while IFS="$TAB" read -r path bak; do
    [ -n "$path" ] || continue
    case "$path" in "$HOME"/*) ;; *) warn "skipping path outside HOME: $path"; continue ;; esac
    if [ "$DRY_RUN" = 1 ]; then log "dry-run: remove $path${bak:+ (restore $bak)}"; continue; fi
    rm -rf "$path"
    if [ "$bak" != "-" ] && { [ -e "$bak" ] || [ -L "$bak" ]; }; then
      mkdir -p "$(dirname "$path")"; mv "$bak" "$path"; rm -f "$bak.origin"; log "restored $path"
    fi
  done
  have fc-cache && [ "$DRY_RUN" != 1 ] && { fc-cache -f >/dev/null 2>&1 || true; }
fi

if [ "$FULL" = 1 ]; then
  f="$DESK_BACKUP/dconf-original.ini"
  if [ -f "$f" ] && have dconf; then
    if [ "$DRY_RUN" = 1 ]; then log "dry-run: dconf load / < $f"; else dconf load / <"$f"; log "loaded $f"; fi
  else warn "no full backup to load ($f)"; fi
fi

if [ "$DRY_RUN" != 1 ]; then
  rm -rf "$DESK_STATE" "$DESK_SHARE" "$DESK_DATA/apps"
  log "done. Backups kept in $DESK_BACKUP. Log out and back in to unload the extensions."
fi
