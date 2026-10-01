#!/usr/bin/env bash
# Tests for 01-prereqs install.sh / uninstall.sh with a temp HOME. Programs are not executed
# (the test also runs on a macOS build host); dpkg-query, apt-get and sudo are fakes.
# Needs the fetched offline tree: KIT_OFFLINE=<dir with prereqs/> (default: kit/offline).
# Usage: bash tests/test-install.sh
set -uo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_OFFLINE="${KIT_OFFLINE:-$(cd "$MOD/../.." && pwd)/offline}"
[ -d "$KIT_OFFLINE/prereqs/apt" ] || { echo "SKIP: no $KIT_OFFLINE/prereqs (run fetch.sh)"; exit 0; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /'; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing: $3)" "$2"; fi; }

# Fakes: dpkg-query reports libc6 and zlib as installed; sudo just runs the command;
# apt-get records its arguments.
FAKE="$T/fakebin"
mkdir -p "$FAKE"
cat >"$FAKE/dpkg-query" <<'EOF'
#!/bin/sh
for a; do p="$a"; done
case "$p" in libc6|zlib1g|libpcre2-8-0) printf 'ii ' ;; *) printf 'un ' ;; esac
EOF
cat >"$FAKE/sudo" <<'EOF'
#!/bin/sh
while [ "${1#*=}" != "$1" ]; do export "$1"; shift; done
exec "$@"
EOF
cat >"$FAKE/apt-get" <<EOF
#!/bin/sh
echo "\$*" >>"$T/apt.log"
for a; do case "\$a" in Dir::Etc::SourceList=*) cat "\${a#*=}" >>"$T/apt.log" ;; esac; done
EOF
chmod +x "$FAKE"/*

# A fake standalone CPython archive (00-python build output layout).
mkdir -p "$T/py/python/bin" "$T/offline-py/python/20260901"
printf '#!/bin/sh\necho fake\n' >"$T/py/python/bin/python3"; chmod +x "$T/py/python/bin/python3"
tar -czf "$T/offline-py/python/20260901/cpython-3.12.99+20260901-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz" -C "$T/py" python

# System tools only (plus zstd, which a macOS host keeps elsewhere); --force because the host
# may have git or curl itself.
SYSPATH="$FAKE:/usr/bin:/bin:/usr/sbin:/sbin"
if ! PATH="$SYSPATH" command -v zstd >/dev/null 2>&1 && command -v zstd >/dev/null 2>&1; then
  ln -s "$(command -v zstd)" "$FAKE/zstd"
fi
run() { # run <home> <args...>
  local h="$1"; shift
  HOME="$h" PATH="$h/.local/bin:$SYSPATH" KIT_OFFLINE="$KIT_OFFLINE" \
    PREREQS_ANY_HOST=1 PREREQS_CODENAME="${CODENAME:-noble}" KIT_DATA_DIR="$h/.local/share/work-kit" \
    bash "$MOD/install.sh" "$@" 2>&1
}
H="$T/home"; mkdir -p "$H"

# --- list / dry run / bad input ---------------------------------------------------------------
out="$(run "$H" --list)"
has "list shows tmux" "$out" "tmux"
has "list marks sudo-only items" "$out" "sudo only"
out="$(run "$H" --dry-run --force)"
has "dry-run default includes vscode" "$out" "would install vscode without sudo (vscode)"
has "dry-run default includes tmux (ldso)" "$out" "would install tmux without sudo (ldso)"
out="$(run "$H" --dry-run --sudo git chrome node)"
has "dry-run sudo uses apt for git" "$out" "would apt-install git: git"
has "dry-run sudo uses apt for chrome" "$out" "would apt-install chrome: google-chrome-stable"
has "dry-run sudo keeps node user-level" "$out" "would install node without sudo (node)"
out="$(run "$H" nope)"; has "unknown item rejected" "$out" "unknown item 'nope'"
out="$(CODENAME=bionic run "$H" git)"; has "unsupported release rejected" "$out" "no packages for Ubuntu 'bionic'"

# --- no-sudo install -------------------------------------------------------------------------
out="$(run "$H" --force git tmux curl vscode node)"; rc=$?
check "user install exits 0" test "$rc" = 0
[ "$rc" = 0 ] || printf '%s\n' "$out" | tail -20
B="$H/.local/bin"; D="$H/.local/share/work-kit"
for c in git curl tmux code node npm; do check "wrapper $c exists" test -x "$B/$c"; done
check "git wrapper sets GIT_EXEC_PATH" grep -q 'GIT_EXEC_PATH=.*/usr/lib/git-core' "$B/git"
check "git binary unpacked" test -x "$D/prereqs/root/usr/bin/git"
check "git-remote-https unpacked" test -x "$D/prereqs/root/usr/lib/git-core/git-remote-https"
check "tmux wrapper uses the loader, not LD_LIBRARY_PATH" grep -q 'ld-linux-x86-64.so.2 --library-path' "$B/tmux"
check "tmux wrapper exports nothing" sh -c "! grep -q LD_LIBRARY_PATH '$B/tmux'"
check "installed libc6 was not unpacked" sh -c "! grep -q '^libc6 ' '$D/prereqs/root.pkgs'"
check "missing libevent unpacked" grep -q '^libevent-core' "$D/prereqs/root.pkgs"
check "merged-usr symlink" test -L "$D/prereqs/root/lib"
check "vscode unpacked" test -x "$D/vscode/bin/code"
check "vscode wrapper handles the sandbox" grep -q -- '--no-sandbox' "$B/code"
AP="$H/.local/share/applications"
check "desktop entry is code.desktop (Wayland app_id 'code')" grep -q "Exec=$B/code" "$AP/code.desktop"
check "desktop entry keeps StartupWMClass=Code for X11" grep -qx "StartupWMClass=Code" "$AP/code.desktop"
check "desktop entry has no old work-kit-code name" test ! -e "$AP/work-kit-code.desktop"
check "node unpacked" test -x "$D/prereqs/node/bin/node"
check "state records items" grep -q '^tmux user ' "$D/prereqs/installed"
for f in "$B"/*; do
  p="$(sed -n 's/^exec "\([^"]*\)".*/\1/p; s/^exec \/lib64[^"]*"[^"]*" --argv0 "[^"]*" "\([^"]*\)".*/\1/p' "$f" | tail -n 1)"
  case "$p" in ""|*'$'*) continue ;; esac
  check "$(basename "$f") target exists" test -e "$p"
done

# A kit-owned install is present only while its recorded input fingerprint still matches.
out="$(run "$H" --list)"
has "list counts kit git as present" "$out" "git              yes"
out="$(run "$H" --dry-run git tmux curl vscode)"
has "dry-run skips matching kit installs" "$out" "git: already present, skipped"
has "dry-run skips matching kit vscode" "$out" "vscode: already present, skipped"
mkdir -p "$D/vscode.new" "$D/prereqs/node.new"
out="$(run "$H" git)"
check "stale vscode staging dir is removed" test ! -e "$D/vscode.new"
check "stale node staging dir is removed" test ! -e "$D/prereqs/node.new"

# --- rerun is idempotent, user files are kept -------------------------------------------------
printf '#!/bin/sh\necho mine\n' >"$B/jq"
out="$(run "$H" --force git jq)"
has "second run skips unpacked packages" "$out" "git: unpacked 0 package(s)"
check "foreign jq backed up under backups/" sh -c "grep -q mine '$D'/backups/01-prereqs/jq.bak-*"
check "backup records the original path" sh -c "grep -qx '$B/jq' '$D'/backups/01-prereqs/jq.bak-*.origin"
check "no backup beside the original" sh -c "! ls '$B' | grep -q 'bak-'"
check "jq replaced by wrapper" grep -q 'work-kit:01-prereqs item=jq' "$B/jq"

# Older installs recorded only name and Debian version.  Treat that legacy state as stale so a
# kit whose lock refreshes a package without changing its Debian version still replaces its files.
awk '{ print $1, $2 }' "$D/prereqs/root.pkgs" >"$D/prereqs/root.pkgs.new"
mv "$D/prereqs/root.pkgs.new" "$D/prereqs/root.pkgs"
out="$(run "$H" --force git)"
has "legacy package state triggers a refresh" "$out" "git: unpacked"
check "package state records the source hash" awk 'NF == 3 { found = 1 } END { exit !found }' "$D/prereqs/root.pkgs"

# --- python3 from the kit CPython ------------------------------------------------------------
out="$(HOME="$H" PATH="$SYSPATH" KIT_OFFLINE="$T/offline-py" PREREQS_ANY_HOST=1 PREREQS_CODENAME=noble \
  KIT_DATA_DIR="$H/.local/share/work-kit" bash -c 'mkdir -p "$KIT_OFFLINE/prereqs"; bash "$0" --force python3' "$MOD/install.sh" 2>&1)"
check "python3 wrapper" grep -q 'prereqs/python/bin/python3' "$B/python3"
check "python3 unpacked" test -x "$D/prereqs/python/bin/python3"

# --- sudo path (fake apt) --------------------------------------------------------------------
out="$(run "$H" --sudo --force git chrome)"; rc=$?
check "sudo install exits 0" test "$rc" = 0
log="$(cat "$T/apt.log" 2>/dev/null)"
has "apt sees only the stick repo" "$log" "deb [trusted=yes] file:$KIT_OFFLINE/prereqs/apt noble main"
has "apt uses private lists" "$log" "Dir::State::Lists="
has "apt installs git and chrome" "$log" "install -y git google-chrome-stable"
check "state records sudo mode" grep -q '^chrome sudo$' "$D/prereqs/installed"

# --- uninstall -------------------------------------------------------------------------------
out="$(HOME="$H" KIT_DATA_DIR="$D" bash "$MOD/uninstall.sh" tmux 2>&1)"
check "tmux wrapper removed" test ! -e "$B/tmux"
check "git wrapper kept" test -e "$B/git"
out="$(HOME="$H" KIT_DATA_DIR="$D" bash "$MOD/uninstall.sh" 2>&1)"
has "apt items only listed" "$out" "sudo apt-get remove"
has "apt removal lists chrome" "$out" "google-chrome-stable"
check "all wrappers removed" sh -c "! grep -l 'work-kit:01-prereqs' '$B'/* 2>/dev/null"
check "data dir removed" test ! -e "$D/prereqs"
check "vscode removed" test ! -e "$D/vscode"
check "desktop entry removed" test ! -e "$AP/code.desktop"
check "user jq backup kept" sh -c "ls '$D'/backups/01-prereqs/jq.bak-* >/dev/null"

echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
