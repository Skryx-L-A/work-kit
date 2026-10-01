#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# apt.sh must delegate to 01-prereqs --sudo (offline), never call apt-get itself.
set -euo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

out="$(bash "$MOD/apt.sh" --print)"
case "$out" in
  *"01-prereqs/install.sh --sudo git tmux build-essential zip shellcheck"*) ok "--print names the offline path" ;;
  *) bad "--print: $out" ;;
esac
grep -q 'apt-get' "$MOD/apt.sh" && bad "apt.sh still calls apt-get" || ok "no online apt-get"

# Run against a fake 01-prereqs that records its arguments.
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/modules/10-base-tools" "$W/modules/01-prereqs"
cp "$MOD/apt.sh" "$W/modules/10-base-tools/apt.sh"
printf '#!/usr/bin/env bash\necho "$*" >"%s/args"\n' "$W" >"$W/modules/01-prereqs/install.sh"
bash "$W/modules/10-base-tools/apt.sh"
[ "$(cat "$W/args")" = "--sudo git tmux build-essential zip shellcheck" ] && ok "delegates with --sudo and items" || bad "delegation args: $(cat "$W/args")"
rm "$W/modules/01-prereqs/install.sh"
if bash "$W/modules/10-base-tools/apt.sh" 2>"$W/err"; then bad "missing 01-prereqs must fail"; else grep -q 01-prereqs "$W/err" && ok "missing 01-prereqs is reported" || bad "no message"; fi
exit "$fail"
