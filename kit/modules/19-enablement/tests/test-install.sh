#!/usr/bin/env bash
# Install / re-install / edit / uninstall in a scratch HOME. Runs on any host.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export HOME="$W/home" KIT_DATA_DIR="$W/home/.local/share/work-kit"
unset ENABLEMENT_HOME
D="$HOME/work/enablement"
mkdir -p "$HOME"
n_src="$(cd "$MOD/content" && find . -type f ! -name '.*' | wc -l | tr -d ' ')"

bash "$MOD/install.sh" >/dev/null || bad "install exits 0"
check "all $n_src files copied" "[ \"\$(find '$D' -type f | wc -l | tr -d ' ')\" = '$n_src' ]"
check "README present" "[ -f '$D/README.md' ]"

# shellcheck disable=SC2034  # read inside eval
out="$(bash "$MOD/install.sh")"
check "rerun changes nothing" "grep -q '0 added, 0 updated, $n_src unchanged, 0 edited kept, 0 backups' <<<\"\$out\""

echo "my note" >>"$D/faq.md"
echo "my own file" >"$D/mine.md"
bash "$MOD/install.sh" >/dev/null
check "edit kept when kit unchanged" "grep -q 'my note' '$D/faq.md'"
check "no backup when kit unchanged" "[ -z \"\$(find '$W' -name '*.bak-*')\" ]"

# Simulate a new kit version of faq.md: copy the module, change the file, reinstall.
cp -R "$MOD" "$W/mod2"
echo "new kit line" >>"$W/mod2/content/faq.md"
bash "$W/mod2/install.sh" >/dev/null
BAKS="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/19-enablement"
check "edited file backed up under backups/" "ls '$BAKS' | grep -q '^faq.md.bak-'"
check "backup keeps edit" "grep -q 'my note' '$BAKS'/faq.md.bak-*"
check "backup records the original path" "grep -qx '$D/faq.md' '$BAKS'/faq.md.bak-*.origin"
check "no backup beside the edited file" "! ls '$D' | grep -q 'bak-'"
check "new kit version written" "cmp -s '$W/mod2/content/faq.md' '$D/faq.md'"

echo "second edit" >>"$D/curriculum.md"
bash "$MOD/uninstall.sh" >/dev/null
check "edited file kept by uninstall" "grep -q 'second edit' '$D/curriculum.md'"
check "own file kept" "[ -f '$D/mine.md' ]"
check "unedited file removed" "[ ! -e '$D/README.md' ]"
check "empty dirs removed" "[ ! -d '$D/handouts' ]"
check "state file removed" "[ ! -e '$KIT_DATA_DIR/state/19-enablement.sha256' ]"
check "uninstall twice is safe" "bash '$MOD/uninstall.sh' >/dev/null"

ENABLEMENT_HOME="$W/custom" bash "$MOD/install.sh" >/dev/null
check "ENABLEMENT_HOME honored" "[ -f '$W/custom/README.md' ]"

grep -rn 'TODO(ask IT)' "$MOD/content" >/dev/null && ok "placeholders present" || bad "placeholders present"
exit "$fail"
