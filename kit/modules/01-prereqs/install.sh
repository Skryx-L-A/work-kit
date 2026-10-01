#!/usr/bin/env bash
# Install base prerequisites (VS Code, git, tmux, curl, python3, ...) offline from the stick.
# Usage: install.sh [--sudo] [--force] [--ask] [--dry-run] [--list] [ITEM ...|all]
#   (default)  no sudo: unpack into ~/.local/share/work-kit, wrappers in ~/.local/bin
#   --sudo     install with apt from the offline repository on the stick (no network)
#   --force    also install items that are already present
#   --ask      ask yes/no per item
#   --list     show items, default selection and what is present
# Without ITEM the items marked default in items.conf are installed. Needs no python3.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh source-path=SCRIPTDIR
. "$HERE/common.sh"

MODE=user
FORCE=0
ASK=0
DRY=0
LIST=0
SEL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sudo) MODE=sudo ;;
    --user) MODE=user ;;
    --force) FORCE=1 ;;
    --ask) ASK=1 ;;
    --dry-run) DRY=1 ;;
    --list) LIST=1 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) pq_die "unknown option: $1" ;;
    *) IFS=', ' read -r -a more <<<"$1"; SEL+=("${more[@]}") ;;
  esac
  shift
done

# --- helpers --------------------------------------------------------------------------------
installed_pkg() { # dpkg knows the package as installed
  command -v dpkg-query >/dev/null 2>&1 || return 1
  [ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | cut -c1-2)" = ii ]
}

# present <item>: without --sudo every command of the item is on PATH and is not one of our
# wrappers; with --sudo every apt root package of the item is installed.
present() {
  local c p cmds pkgs
  pkgs="$(pq_field "$1" 4)"
  if [ "$MODE" = sudo ] && [ -n "$pkgs" ]; then
    for p in $pkgs; do installed_pkg "$p" || return 1; done
    return 0
  fi
  case "$1" in
    chrome) cmds=google-chrome-stable ;;
    edge) cmds=microsoft-edge-stable ;;
    zsh) cmds=zsh ;;
    *) cmds="$(pq_field "$1" 5)" ;;
  esac
  [ -n "$cmds" ] || return 1
  for c in $cmds; do
    p="$(command -v "$c" 2>/dev/null)" || return 1
    # A kit wrapper counts as present only when it still matches the recorded input fingerprint.
    if pq_is_ours "$p" && ! kit_user_present "$1"; then return 1; fi
  done
  return 0
}

item_commands() {
  case "$1" in
    chrome) echo google-chrome-stable ;;
    edge) echo microsoft-edge-stable ;;
    zsh) echo zsh ;;
    *) pq_field "$1" 5 ;;
  esac
}

item_fingerprint() {
  local item="$1" kind rel
  kind="$(pq_field "$item" 3)"
  case "$kind" in
    deb|ldso|toolchain) closure "$item" | awk '{ print $1, $2, $3 }' | pq_sha256 /dev/stdin ;;
    vscode) rel="$(awk '$2 ~ /^vscode\// { print $2; exit }' "$HERE/lock/files.lock")"
            awk -v p="$rel" '$2 == p { print $1; exit }' "$HERE/lock/files.lock" ;;
    cpython) rel="$(find "$KIT_OFFLINE/python" -name 'cpython-3.12*-x86_64-unknown-linux-gnu-install_only*.tar.gz' 2>/dev/null | sort | tail -n 1)"
             [ -n "$rel" ] && pq_sha256 "$rel" ;;
    node) rel="$(awk '$2 ~ /^node\// { print $2; exit }' "$HERE/lock/files.lock")"
          awk -v p="$rel" '$2 == p { print $1; exit }' "$HERE/lock/files.lock" ;;
    *) echo "$kind" ;;
  esac
}

kit_user_present() { # item: own wrappers plus the exact source fingerprint recorded at install
  local item="$1" c p fp
  [ "$(pq_state_mode "$item")" = user ] || return 1
  fp="$(item_fingerprint "$item")"
  [ -n "$fp" ] && [ "$(pq_state_fingerprint "$item")" = "$fp" ] || return 1
  for c in $(item_commands "$item"); do
    p="$(command -v "$c" 2>/dev/null)" || return 1
    pq_is_ours "$p" || return 1
  done
}

cleanup_staging() {
  rm -rf "$PQ_VSCODE.new" "$PQ_DATA/python.new" "$PQ_DATA/node.new"
}

# closure <item>: lock lines (name version sha size file url items) of the item's packages
closure() { awk -v i="$1" '!/^#/ { n = split($7, a, ","); for (k = 1; k <= n; k++) if (a[k] == i) { print; break } }' "$LOCK"; }

verify_debs() { # item: every .deb of the item's closure exists and has the locked sha256
  local sum file bad=0 n=0
  while read -r _ _ sum _ file _; do
    n=$((n + 1))
    if [ ! -f "$PQ_OFF/apt/$file" ]; then pq_warn "missing $file"; bad=1
    elif [ "$(pq_sha256 "$PQ_OFF/apt/$file")" != "$sum" ]; then pq_warn "checksum mismatch: $file"; bad=1; fi
  done < <(closure "$1")
  [ "$n" -gt 0 ] || { pq_warn "$1: no packages for $CODENAME in lock/$CODENAME.lock"; return 1; }
  return "$bad"
}

verify_file() { # path under offline/prereqs: check against lock/files.lock
  local want
  want="$(awk -v p="$1" '$2 == p { print $1 }' "$HERE/lock/files.lock")"
  [ -n "$want" ] && [ -f "$PQ_OFF/$1" ] && [ "$(pq_sha256 "$PQ_OFF/$1")" = "$want" ]
}

extract_deb() { # deb dest
  if command -v dpkg-deb >/dev/null 2>&1; then dpkg-deb -x "$1" "$2"; return; fi
  local t
  t="$(mktemp -d)"
  (cd "$t" && ar x "$1") && tar -xf "$t"/data.tar.* -C "$2"
  local rc=$?
  rm -rf "$t"
  return "$rc"
}

# fix_root <dir>: merged /usr (lib -> usr/lib, ...) and absolute symlinks that point into the tree.
fix_root() {
  local r="$1" d l t
  for d in bin sbin lib lib64; do
    if [ -d "$r/$d" ] && [ ! -L "$r/$d" ]; then
      mkdir -p "$r/usr/$d" && cp -a "$r/$d/." "$r/usr/$d/" && rm -rf "${r:?}/$d"
    fi
    [ -e "$r/$d" ] || [ -L "$r/$d" ] || ln -s "usr/$d" "$r/$d"
  done
  find "$r" -type l | while IFS= read -r l; do
    t="$(readlink "$l")"
    case "$t" in
      /*) if [ -e "$r$t" ] || [ -L "$r$t" ]; then ln -sfn "$r$t" "$l"; fi ;;
    esac
  done
}

# unpack_missing <item> <dest> [all]: unpack the packages of the closure that dpkg does not
# have (all: every package, for the toolchain sysroot). Records "name version sha256" in
# <dest>.pkgs, so a refreshed offline package with the same Debian version is unpacked again.
unpack_missing() {
  local item="$1" dest="$2" everything="${3:-}" name ver sum file n=0
  mkdir -p "$dest"
  touch "$dest.pkgs"
  while read -r name ver sum _ file _; do
    if [ -z "$everything" ] && installed_pkg "$name"; then continue; fi
    grep -qxF "$name $ver $sum" "$dest.pkgs" && continue
    extract_deb "$PQ_OFF/apt/$file" "$dest" || pq_die "cannot unpack $file"
    { grep -v "^$name " "$dest.pkgs" || true; echo "$name $ver $sum"; } >"$dest.pkgs.new"
    mv "$dest.pkgs.new" "$dest.pkgs"
    n=$((n + 1))
  done < <(closure "$item")
  fix_root "$dest"
  pq_log "$item: unpacked $n package(s) into $dest"
}

# write_wrapper <name> <body>: ~/.local/bin/<name>; a file we did not write is backed up first.
write_wrapper() {
  local t="$KIT_BIN_DIR/$1"
  if { [ -e "$t" ] || [ -L "$t" ]; } && ! pq_is_ours "$t"; then
    pq_backup "$t"
  fi
  mkdir -p "$KIT_BIN_DIR"
  printf '#!/bin/sh\n# %s item=%s (generated by install.sh; re-run it instead of editing)\n%s\n' \
    "$PQ_MARK" "$ITEM" "$2" >"$t.new"
  chmod 0755 "$t.new" && mv "$t.new" "$t"
}

libpath() { # library dirs that exist inside a root, colon separated
  local r="$1" d out=""
  for d in usr/lib/x86_64-linux-gnu usr/lib; do
    [ -d "$r/$d" ] && out="${out:+$out:}$r/$d"
  done
  echo "$out"
}

find_cmd() { # root cmd -> path of the program inside the root
  local d
  for d in usr/bin usr/sbin usr/games; do
    [ -x "$1/$d/$2" ] && { echo "$1/$d/$2"; return 0; }
  done
  return 1
}

item_env() { # export lines for programs that look for data at compiled-in paths
  local r="$PQ_ROOT" m="$PQ_ROOT/usr/lib/x86_64-linux-gnu"
  case "$1" in
    git)
      echo "export GIT_EXEC_PATH=\"$r/usr/lib/git-core\""
      echo "export GIT_TEMPLATE_DIR=\"$r/usr/share/git-core/templates\""
      echo "export PERL5LIB=\"$r/usr/share/perl5\${PERL5LIB:+:\$PERL5LIB}\"" ;;
    graphviz) echo "export GVBINDIR=\"$m/graphviz\"" ;;
    audio)
      if [ -d "$m/spa-0.2" ]; then echo "export SPA_PLUGIN_DIR=\"$m/spa-0.2\""; fi
      if [ -d "$m/pipewire-0.3" ]; then echo "export PIPEWIRE_MODULE_DIR=\"$m/pipewire-0.3\""; fi ;;
  esac
  return 0
}

ld_export() { echo "export LD_LIBRARY_PATH=\"$1\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""; }

# --- no-sudo path per kind ------------------------------------------------------------------
user_deb() { # item kind(deb|ldso)
  local item="$1" kind="$2" c p lp
  verify_debs "$item" || pq_die "$item: offline packages are incomplete (run fetch.sh --verify on the build host)"
  unpack_missing "$item" "$PQ_ROOT"
  lp="$(libpath "$PQ_ROOT")"
  for c in $(pq_field "$item" 5); do
    p="$(find_cmd "$PQ_ROOT" "$c")" || { pq_warn "$item: $c not found in the unpacked packages"; continue; }
    if [ "$kind" = ldso ]; then
      # The loader gets the library path; the program's children (shells in tmux panes) do not.
      write_wrapper "$c" "exec /lib64/ld-linux-x86-64.so.2 --library-path \"$lp\" --argv0 \"$c\" \"$p\" \"\$@\""
    else
      write_wrapper "$c" "$(ld_export "$lp")
$(item_env "$item")
exec \"$p\" \"\$@\""
    fi
  done
  if [ "$item" = graphviz ] && [ -x "$KIT_BIN_DIR/dot" ]; then
    "$KIT_BIN_DIR/dot" -c 2>/dev/null || pq_warn "graphviz: plugin registration (dot -c) failed"
  fi
}

user_toolchain() { # build-essential: runtime libraries in the root, compiler sysroot with everything
  local item="$1" lp s="$PQ_SYSROOT" c p
  verify_debs "$item" || pq_die "$item: offline packages are incomplete"
  unpack_missing "$item" "$PQ_ROOT"
  unpack_missing "$item" "$s" all
  lp="$(libpath "$PQ_ROOT")"
  for c in gcc g++ cpp cc c++ make; do
    case "$c" in cc) p=gcc ;; c++) p=g++ ;; *) p="$c" ;; esac
    [ -x "$s/usr/bin/$p" ] || { pq_warn "$item: $p not found in the sysroot"; continue; }
    if [ "$c" = make ]; then
      write_wrapper "$c" "$(ld_export "$lp")
exec \"$s/usr/bin/make\" \"\$@\""
    else
      write_wrapper "$c" "$(ld_export "$lp")
export PATH=\"$s/usr/bin:\$PATH\"
exec \"$s/usr/bin/$p\" --sysroot=\"$s\" \"\$@\""
    fi
  done
  pq_warn "$item without sudo is experimental; test: printf 'int main(void){return 0;}\\n' | gcc -x c - -o /tmp/t && /tmp/t"
}

# The menu entry of the kit's VS Code; also refreshed when VS Code itself is already current,
# so a kit update fixes an entry an older kit wrote.
vscode_menu_entry() {
  mkdir -p "$PQ_APPS"
  # Named code.desktop: on Wayland VS Code's app_id is "code" and GNOME matches window and launcher by
  # desktop file id (icon in dock and alt-tab). StartupWMClass=Code matches the X11 class (WM_CLASS
  # "code", "Code"). The old work-kit-code.desktop (no match on Wayland) is removed.
  rm -f "$PQ_APPS/work-kit-code.desktop"
  cat >"$PQ_APPS/code.desktop" <<EOF
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=$KIT_BIN_DIR/code %F
Icon=$PQ_VSCODE/resources/app/resources/linux/code.png
Type=Application
StartupNotify=false
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;
Keywords=vscode;
# $PQ_MARK
EOF
  if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$PQ_APPS" 2>/dev/null || true; fi
}

user_vscode() {
  local rel
  rel="$(awk '$2 ~ /^vscode\// { print $2; exit }' "$HERE/lock/files.lock")"
  verify_file "$rel" || pq_die "vscode: $PQ_OFF/$rel is missing or does not match lock/files.lock"
  rm -rf "$PQ_VSCODE.new" && mkdir -p "$PQ_VSCODE.new"
  tar -xzf "$PQ_OFF/$rel" -C "$PQ_VSCODE.new" --strip-components=1
  rm -rf "$PQ_VSCODE" && mv "$PQ_VSCODE.new" "$PQ_VSCODE"
  # Ubuntu 23.10+ blocks unprivileged user namespaces for programs without an AppArmor profile,
  # and chrome-sandbox under $HOME cannot be setuid root: then Electron only starts with --no-sandbox.
  write_wrapper code "d=\"$PQ_VSCODE\"
if [ ! -u \"\$d/chrome-sandbox\" ] && [ \"\$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)\" = 1 ]; then
  exec \"\$d/bin/code\" --no-sandbox \"\$@\"
fi
exec \"\$d/bin/code\" \"\$@\""
  vscode_menu_entry
  pq_log "vscode: $PQ_VSCODE, command 'code', menu entry 'Visual Studio Code'"
}

user_cpython() {
  local tb sums rel want
  tb="$(find "$KIT_OFFLINE/python" -name 'cpython-3.12*-x86_64-unknown-linux-gnu-install_only*.tar.gz' 2>/dev/null | sort | tail -n 1)"
  [ -n "$tb" ] || pq_die "python3: no CPython archive in $KIT_OFFLINE/python (00-python build step)"
  sums="$KIT_OFFLINE/SHA256SUMS"
  if [ -f "$sums" ]; then
    rel="${tb#"$KIT_OFFLINE"/}"
    want="$(awk -v p="$rel" '{ f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f) } f == p { print $1 }' "$sums")"
    [ -z "$want" ] || [ "$want" = "$(pq_sha256 "$tb")" ] || pq_die "python3: $rel does not match SHA256SUMS"
  fi
  rm -rf "$PQ_DATA/python.new" && mkdir -p "$PQ_DATA/python.new"
  tar -xzf "$tb" -C "$PQ_DATA/python.new" --strip-components=1
  rm -rf "$PQ_DATA/python" && mv "$PQ_DATA/python.new" "$PQ_DATA/python"
  write_wrapper python3 "exec \"$PQ_DATA/python/bin/python3\" \"\$@\""
  pq_log "python3: $(basename "$tb") (venv and pip included)"
}

install_node() { # user-level in both modes: Ubuntu's nodejs is older than the harness CLIs need
  local rel c
  rel="$(awk '$2 ~ /^node\// { print $2; exit }' "$HERE/lock/files.lock")"
  verify_file "$rel" || pq_die "node: $PQ_OFF/$rel is missing or does not match lock/files.lock"
  rm -rf "$PQ_DATA/node.new" && mkdir -p "$PQ_DATA/node.new"
  tar -xJf "$PQ_OFF/$rel" -C "$PQ_DATA/node.new" --strip-components=1
  rm -rf "$PQ_DATA/node" && mv "$PQ_DATA/node.new" "$PQ_DATA/node"
  for c in node npm npx corepack; do
    write_wrapper "$c" "export PATH=\"$PQ_DATA/node/bin:\$PATH\"
exec \"$PQ_DATA/node/bin/$c\" \"\$@\""
  done
  pq_log "node: $(basename "$rel" .tar.xz); global npm packages land in $PQ_DATA/node/bin"
}

# --- sudo path ------------------------------------------------------------------------------
apt_install() { # packages...
  command -v apt-get >/dev/null 2>&1 || pq_die "apt-get not found"
  local tmp rc=0
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/lists/partial" "$tmp/cache/archives/partial"
  echo "deb [trusted=yes] file:$PQ_OFF/apt $CODENAME main" >"$tmp/sources.list"
  # Only the stick's repository is visible to this apt run; system sources and lists stay as they are.
  local o=(-o "Dir::Etc::SourceList=$tmp/sources.list" -o "Dir::Etc::SourceParts=/dev/null"
           -o "Dir::State::Lists=$tmp/lists" -o "Dir::Cache=$tmp/cache" -o "Acquire::Languages=none"
           -o "APT::Install-Recommends=false")
  sudo apt-get "${o[@]}" update || rc=$?
  [ "$rc" != 0 ] || sudo DEBIAN_FRONTEND=noninteractive apt-get "${o[@]}" install -y "$@" || rc=$?
  sudo rm -rf "$tmp"
  return "$rc"
}

# --- list -----------------------------------------------------------------------------------
CODENAME="$(pq_codename)"
LOCK="$HERE/lock/$CODENAME.lock"
if [ "$LIST" = 1 ]; then
  printf '%-16s %-8s %-10s %-8s %s\n' ITEM DEFAULT NO-SUDO PRESENT DESCRIPTION
  pq_items | while IFS='|' read -r id def user _pkgs _cmds desc; do
    p=no; present "$id" && p=yes
    [ "$user" = none ] && user="sudo only"
    printf '%-16s %-8s %-10s %-8s %s\n' "$id" "$def" "$user" "$p" "$desc"
  done
  exit 0
fi

# --- selection ------------------------------------------------------------------------------
if [ "${#SEL[@]}" -eq 0 ]; then
  while IFS='|' read -r id def _rest; do if [ "$def" = yes ]; then SEL+=("$id"); fi; done < <(pq_items)
elif [ "${SEL[0]}" = all ]; then
  SEL=()
  while IFS='|' read -r id _rest; do SEL+=("$id"); done < <(pq_items)
fi
for i in "${SEL[@]}"; do pq_known "$i" || pq_die "unknown item '$i' (see --list)"; done
if [ "$ASK" = 1 ]; then
  keep=()
  for i in "${SEL[@]}"; do
    read -r -p "[prereqs] install $i ($(pq_field "$i" 6))? [y/N] " a </dev/tty || a=n
    case "$a" in y|Y|yes) keep+=("$i") ;; esac
  done
  SEL=(${keep[@]+"${keep[@]}"})
fi
[ "${#SEL[@]}" -gt 0 ] || { pq_log "nothing selected"; exit 0; }

# --- checks ---------------------------------------------------------------------------------
[ "$(id -u)" != 0 ] || pq_die "run as your normal user; --sudo asks for root only for apt"
if [ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ] && [ -z "${PREREQS_ANY_HOST:-}" ]; then
  pq_die "this module targets Ubuntu on x86_64"
fi
if [ -z "$CODENAME" ] || [ ! -f "$LOCK" ]; then
  have="$(find "$HERE/lock" -name '*.lock' ! -name files.lock -exec basename {} .lock \; | sort | tr '\n' ' ')"
  pq_die "no packages for Ubuntu '${CODENAME:-unknown}' (have: $have); PREREQS_CODENAME=<one of them> tries the closest"
fi
[ -d "$PQ_OFF" ] || pq_die "missing $PQ_OFF (run fetch.sh on the build host)"
cleanup_staging
trap cleanup_staging EXIT INT TERM
pq_log "Ubuntu $CODENAME, mode $MODE, items: ${SEL[*]}"

# --- run ------------------------------------------------------------------------------------
APT_PKGS=()
APT_ITEMS=()
failed=()
for ITEM in "${SEL[@]}"; do
  kind="$(pq_field "$ITEM" 3)"
  pkgs="$(pq_field "$ITEM" 4)"
  if [ "$FORCE" = 0 ] && present "$ITEM"; then
    pq_log "$ITEM: already present, skipped (--force installs anyway)"
    if [ "$ITEM" = vscode ] && [ "$MODE" = user ] && pq_is_ours "$(command -v code 2>/dev/null)" && [ "$DRY" = 0 ]; then
      vscode_menu_entry
    fi
    continue
  fi
  if [ "$DRY" = 1 ]; then
    if [ "$MODE" = sudo ] && [ -n "$pkgs" ]; then pq_log "would apt-install $ITEM: $pkgs"
    elif [ "$kind" = none ]; then pq_log "would skip $ITEM: sudo only"
    else pq_log "would install $ITEM without sudo ($kind)"; fi
    continue
  fi
  if [ "$MODE" = sudo ] && [ -n "$pkgs" ]; then
    verify_debs "$ITEM" || { failed+=("$ITEM"); continue; }
    # shellcheck disable=SC2206  # package list is a word list
    APT_PKGS+=($pkgs)
    APT_ITEMS+=("$ITEM")
    continue
  fi
  rc=0
  case "$kind" in
    none) pq_warn "$ITEM has no no-sudo path; run: bash $HERE/install.sh --sudo $ITEM"; rc=1 ;;
    deb|ldso) ( user_deb "$ITEM" "$kind" ) || rc=$? ;;
    toolchain) ( user_toolchain "$ITEM" ) || rc=$? ;;
    vscode) ( user_vscode ) || rc=$? ;;
    cpython) ( user_cpython ) || rc=$? ;;
    node) ( install_node ) || rc=$? ;;
    *) pq_warn "$ITEM: unknown user path '$kind'"; rc=1 ;;
  esac
  if [ "$rc" = 0 ]; then pq_state_set "$ITEM" user "$(item_fingerprint "$ITEM")"; else failed+=("$ITEM"); fi
done

if [ "${#APT_PKGS[@]}" -gt 0 ]; then
  pq_log "apt (offline repository, $CODENAME): ${APT_PKGS[*]}"
  if apt_install "${APT_PKGS[@]}"; then
    for ITEM in "${APT_ITEMS[@]}"; do pq_state_set "$ITEM" sudo; done
  else
    pq_warn "apt failed; the no-sudo path may still work: bash $HERE/install.sh ${APT_ITEMS[*]}"
    failed+=("${APT_ITEMS[@]}")
  fi
fi

case ":$PATH:" in
  *":$KIT_BIN_DIR:"*) ;;
  *) [ "$DRY" = 1 ] || pq_warn "$KIT_BIN_DIR is not on PATH (open a new login shell; 60-terminal also adds it)" ;;
esac
[ "${#failed[@]}" -eq 0 ] || pq_die "not installed: ${failed[*]}"
pq_log "done"
