#!/usr/bin/env bash
# CLI argument handling and backups, in a scratch HOME. Needs no gitleaks.
# shellcheck disable=SC2016  # check() evaluates its quoted condition later
set -uo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config"
export KIT_BIN_DIR="$HOME/.local/bin" KIT_DATA_DIR="$HOME/.local/share/work-kit"
unset DATA_GUARD_HOME DATA_GUARD_CONFIG_DIR DATA_GUARD_DENY_FILE
export DATA_GUARD_ALLOW_UNSCANNED=1  # deny-list checks only: gitleaks may be absent here
mkdir -p "$KIT_BIN_DIR"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

echo "mine" >"$KIT_BIN_DIR/data-guard"                    # a foreign file at the link path
bash "$MOD/install.sh" >"$W/install.log" 2>&1 || { cat "$W/install.log"; exit 1; }
DG="$KIT_BIN_DIR/data-guard"
DENY="$XDG_CONFIG_HOME/work-kit/deny-patterns.txt"
BAK="$KIT_DATA_DIR/backups/40-data-guard"
check "foreign file backed up under backups/" 'grep -qx mine "$BAK"/data-guard.bak-*'
check "backup records the original path" 'grep -qx "$KIT_BIN_DIR/data-guard" "$BAK"/data-guard.bak-*.origin'
check "no backup beside the original" '[ -z "$(ls "$KIT_BIN_DIR" | grep "bak-" || true)" ]'

for args in "--help" "-h" "check --help" "scan -h" "staged --help" "status -h" "install-hook --help" \
            "remove-hook -h" "enable-global --help" "disable-global -h" "deny --help" "deny add --help" \
            "deny add -h" "deny remove --help" "deny list -h" "deny path --help" "prune --help"; do
  # shellcheck disable=SC2086
  out="$("$DG" $args 2>&1)"; rc=$?
  check "'$args' prints usage, exit 0" '[ "$rc" = 0 ] && grep -q "^  data-guard check" <<<"$out"'
done
check "help changed nothing" '! grep -qxF -e "--help" "$DENY" && ! grep -q -e "^-h$" "$DENY"'
check "no hooks-repo list created by help" '[ ! -e "$XDG_CONFIG_HOME/work-kit/hooked-repos.list" ]'

"$DG" deny add -- >/dev/null 2>&1; check "deny add -- refused (exit 2)" '[ $? = 2 ]'
"$DG" deny add '--help' >/dev/null 2>&1
check "deny add with a leading dash: help, not a pattern" '! grep -qxF -e "--help" "$DENY"'
out="$("$DG" deny add -foo 2>&1)"; rc=$?
check "pattern starting with '-' refused, exit 2" '[ "$rc" = 2 ] && grep -q "refusing" <<<"$out" && ! grep -qxF -e "-foo" "$DENY"'
out="$("$DG" deny add 'a(b' 2>&1)"; rc=$?
check "invalid regex refused" '[ "$rc" = 2 ] && ! grep -qxF "a(b" "$DENY"'
"$DG" check --bogus >/dev/null 2>&1; check "unknown option exit 2" '[ $? = 2 ]'
"$DG" nosuch >/dev/null 2>&1; check "unknown command exit 2" '[ $? = 2 ]'

"$DG" deny add 'acme-customer' >/dev/null
check "deny add appends" 'grep -qxF acme-customer "$DENY"'
out="$("$DG" deny add 'acme-customer')"; check "deny add twice is a no-op" '[ "$(grep -cxF acme-customer "$DENY")" = 1 ] && grep -q already <<<"$out"'
echo "text about ACME-CUSTOMER" | "$DG" check - >/dev/null 2>&1; check "pattern blocks matching text" '[ $? = 1 ]'
"$DG" deny remove 'acme-customer' >/dev/null; check "deny remove drops the line" '! grep -qxF acme-customer "$DENY"'
check "deny remove keeps the comments" 'grep -q "^#" "$DENY"'
echo "text about ACME-CUSTOMER" | "$DG" check - >/dev/null 2>&1; check "text passes again after remove" '[ $? = 0 ]'
"$DG" deny remove 'acme-customer' >/dev/null 2>&1; check "deny remove of an unknown pattern: exit 2" '[ $? = 2 ]'

# status: dispatcher line always there, plural, stale entries; prune; the list survives uninstall/install
LIST="$XDG_CONFIG_HOME/work-kit/hooked-repos.list"
rm -f "$LIST"
out="$("$DG" status 2>&1)"
check "status without a list: dispatcher line says no repositories registered" 'grep -q "^dispatcher:.*(no repositories registered)" <<<"$out"'
printf '# c\none-pattern\n' >"$W/one.txt"
out="$(DATA_GUARD_DENY_FILE="$W/one.txt" "$DG" status 2>&1)"
check "singular: 1 active pattern" 'grep -q "(1 active pattern)" <<<"$out"'
printf 'a\nb\n' >"$W/two.txt"
out="$(DATA_GUARD_DENY_FILE="$W/two.txt" "$DG" status 2>&1)"
check "plural: 2 active patterns" 'grep -q "(2 active patterns)" <<<"$out"'
GOOD="$W/good-repo"; git init -q "$GOOD"
printf '%s\n' "$GOOD" "$W/gone-repo" >"$LIST"
out="$("$DG" status 2>&1)"
check "status lists registered repositories" 'grep -q "^registered:  2" <<<"$out" && grep -qF "  $GOOD" <<<"$out"'
check "status flags a path that no longer exists" 'grep -qF "$W/gone-repo  (path no longer exists)" <<<"$out" && grep -q "data-guard prune" <<<"$out"'
check "status does not flag an existing repository" '! grep -qF "$GOOD  (path no longer" <<<"$out"'
out="$("$DG" prune 2>&1)"
check "prune forgets the missing path only" 'grep -qF "forgotten (path is gone): $W/gone-repo" <<<"$out" && [ "$(cat "$LIST")" = "$GOOD" ]'
out="$("$DG" prune 2>&1)"; check "prune with nothing stale is a no-op" 'grep -q "nothing to prune" <<<"$out" && [ "$(cat "$LIST")" = "$GOOD" ]'
"$DG" install-hook "$GOOD" >/dev/null 2>&1
check "install-hook registers the repository" 'grep -qxF "$(cd "$GOOD" && pwd)" "$LIST"'
bash "$MOD/uninstall.sh" >"$W/un.log" 2>&1
check "uninstall keeps hooked-repos.list" 'grep -qxF "$(cd "$GOOD" && pwd)" "$LIST"'
check "uninstall says so" 'grep -q "hooked-repos.list kept" "$W/un.log"'
check "uninstall removed the repository hook" '[ ! -e "$GOOD/.git/hooks/pre-commit" ]'
bash "$MOD/install.sh" >"$W/install2.log" 2>&1
check "reinstall puts the hook back for the listed repository" 'grep -q "work-kit data-guard hook" "$GOOD/.git/hooks/pre-commit"'
check "list intact after reinstall" 'grep -qxF "$(cd "$GOOD" && pwd)" "$LIST"'

echo "failures: $fails"
[ "$fails" = 0 ]
