#!/usr/bin/env bash
# End-to-end test of kit-net on macOS and Linux, in a temp HOME. Starts a local HTTPS server signed
# by a throw-away test CA and a small CONNECT proxy (net_fixtures.py), on random loopback ports.
# Checks: help safety, install/rerun/uninstall, python/node/curl fail before `ca add` and work
# after it, the proxy path, `kit-net test`, and that every file is restored on removal.
# Needs python3, openssl, curl, node. git and uv are used when present.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
FIX=""
cleanup() {
  [ -n "$FIX" ] && kill "$FIX" 2>/dev/null && wait "$FIX" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR \
         REQUESTS_CA_BUNDLE CURL_CA_BUNDLE NODE_EXTRA_CA_CERTS GIT_SSL_CAINFO PIP_CERT UV_NATIVE_TLS UV_SYSTEM_CERTS NPM_CONFIG_CAFILE \
         CODEX_CA_CERTIFICATE CARGO_HTTP_CAINFO BUNDLE_SSL_CA_CERT XDG_CONFIG_HOME KIT_BIN_DIR KIT_DATA_DIR \
         KIT_NET_SYSTEM_BUNDLE NODE_USE_SYSTEM_CA; do unset "$v"; done

export HOME="$T/home"
mkdir -p "$HOME"
ORIG_PATH="$PATH"
export PATH="$HOME/.local/bin:$ORIG_PATH"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1 PYTHONDONTWRITEBYTECODE=1
CONF="$HOME/.config/work-kit"
BAK="$HOME/.local/share/work-kit/backups/35-company-network"

pass=0; fails=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fails=$((fails + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -n 8 | sed 's/^/     | /'; }
expect() { local d="$1"; shift; local o; if o="$("$@" 2>&1)"; then ok "$d"; else bad "$d" "$o"; fi; }
expect_not() { local d="$1"; shift; local o; if o="$("$@" 2>&1)"; then bad "$d (succeeded)" "$o"; else ok "$d"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1: expected '$2'" "$3" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1: unexpected '$2'" "$3" ;; *) ok "$1" ;; esac; }
mode_of() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
tree_sum() { (cd "$HOME" && find . -type f -exec shasum {} + 2>/dev/null | sort; find . -type d | sort); }

# The tool under test, from the source folder until it is installed.
kn() { python3 "$HERE/kit_net.py" "$@"; }
# A fresh terminal: only HOME and PATH, then ~/.bashrc (like a new interactive shell).
FUNCS=""
fresh() { env -i HOME="$HOME" PATH="$PATH" bash -c "$FUNCS"'; . "$HOME/.bashrc"; "$@"' _ "$@"; }
plain() { env -i HOME="$HOME" PATH="$PATH" bash --norc -c "$FUNCS"'; "$@"' _ "$@"; }
py_get() { python3 -c 'import sys,urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=15).status)' "$1"; }
node_get() { node -e "require('https').get(process.argv[1],r=>{console.log(r.statusCode);r.resume()}).on('error',e=>{console.error(e.code||e.message);process.exit(1)})" "$1"; }
curl_get() { curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$1"; }
FUNCS="$(declare -f py_get node_get curl_get)"

# --- PKI: test CA, server certificate (localhost and a name only the proxy can resolve), leaf, DER
P="$T/pki"; mkdir -p "$P"
cat >"$P/ca.cnf" <<'C'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Kit Net Test Root CA
O = Kit Net Test
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
C
cat >"$P/srv.cnf" <<'C'
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,DNS:intranet.test.example,IP:127.0.0.1
authorityKeyIdentifier = keyid
C
if ! { openssl req -x509 -newkey rsa:2048 -nodes -keyout "$P/ca.key" -out "$P/ca.pem" -days 30 -sha256 -config "$P/ca.cnf" -extensions v3_ca \
      && openssl req -newkey rsa:2048 -nodes -keyout "$P/srv.key" -out "$P/srv.csr" -subj "/CN=intranet.test.example" \
      && openssl x509 -req -in "$P/srv.csr" -CA "$P/ca.pem" -CAkey "$P/ca.key" -CAcreateserial -out "$P/srv.pem" -days 30 -sha256 -extfile "$P/srv.cnf" \
      && openssl x509 -in "$P/ca.pem" -outform DER -out "$P/ca.der"; } >/dev/null 2>&1; then
  echo "cannot create the test certificates with openssl"; exit 2
fi

# --- a python3 whose ssl reads SSL_CERT_FILE (Apple's LibreSSL Python does not; Ubuntu's does)
mkdir -p "$T/tools"
for c in python3 python3.14 python3.13 python3.12 python3.11 python3.10; do
  cp3="$(command -v "$c" 2>/dev/null)" || continue
  if SSL_CERT_FILE="$P/ca.pem" "$cp3" -c 'import ssl,sys; sys.exit(0 if any("Kit Net Test" in str(x.get("subject")) for x in ssl.create_default_context().get_ca_certs()) else 1)' 2>/dev/null; then
    ln -sf "$cp3" "$T/tools/python3"; break
  fi
done
[ -x "$T/tools/python3" ] || { echo "no python3 on this machine honors SSL_CERT_FILE; install python3 from python.org, Homebrew or apt"; exit 2; }
export PATH="$T/tools:$PATH"

# --- fixtures
mkdir -p "$T/fix"
python3 "$HERE/tests/net_fixtures.py" "$T/fix" "$P/srv.pem" "$P/srv.key" &
FIX=$!
for _ in $(seq 100); do [ -s "$T/fix/https.port" ] && [ -s "$T/fix/proxy.port" ] && break; kill -0 "$FIX" 2>/dev/null || break; sleep 0.1; done
[ -s "$T/fix/proxy.port" ] || { echo "fixture servers did not start"; exit 2; }
HP="$(cat "$T/fix/https.port")"; PP="$(cat "$T/fix/proxy.port")"
DIRECT="https://localhost:$HP/"; VIA="https://intranet.test.example:$HP/"
proxied() { [ -f "$T/fix/proxy.log" ] && wc -l <"$T/fix/proxy.log" | tr -d ' ' || echo 0; }

# --- a user's ~/.bashrc with Ubuntu's interactive guard, and its mode
printf '# ~/.bashrc: executed by bash for non-login shells.\ncase $- in\n    *i*) ;;\n      *) return;;\nesac\nHISTSIZE=1000\n' >"$HOME/.bashrc"
chmod 640 "$HOME/.bashrc"
cp -p "$HOME/.bashrc" "$T/bashrc.orig"

# --- 1. install changes no network behaviour
bash "$HERE/install.sh" >"$T/install.log" 2>&1 && ok "install.sh runs" || bad "install.sh" "$(cat "$T/install.log")"
expect "kit-net is on PATH after install" command -v kit-net
[ ! -e "$CONF" ] && ok "install alone writes no config" || bad "install wrote $CONF" "$(ls -R "$CONF")"
cmp -s "$HOME/.bashrc" "$T/bashrc.orig" && [ ! -e "$HOME/.profile" ] && ok "install alone leaves ~/.bashrc and ~/.profile alone" || bad "install touched the rc files"
out="$(bash "$HERE/install.sh" 2>&1)"; has "rerun keeps the launcher" "kit-net up to date" "$out"
[ ! -d "$BAK" ] && ok "rerun made no backup" || bad "rerun made a backup" "$(ls "$BAK")"
has "status with nothing set" "Nothing is set" "$(kit-net status)"

# --- 2. before `ca add`: the clients reject the test CA
o="$(plain python3 -c 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=15)' "$DIRECT" 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "python fails before ca add with a certificate error" "CERTIFICATE_VERIFY_FAILED" "$o" || bad "python trusted the test CA" "$o"
o="$(plain node_get "$DIRECT" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok "node fails before ca add ($o)" || bad "node trusted the test CA"
o="$(plain curl_get "$DIRECT" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok "curl fails before ca add" || bad "curl trusted the test CA" "$o"
out="$(kit-net test "$DIRECT" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "kit-net test exits 1 before ca add" || bad "kit-net test exit $rc" "$out"
has "test names python failing" "FAIL  python" "$out"
has "test names node failing" "FAIL  node" "$out"
has "test names curl failing" "FAIL  curl" "$out"
has "test says which setting is missing" "kit-net ca add <file>" "$out"

# --- 3. `ca add` refuses what is not a company CA
printf 'not a certificate\n' >"$T/junk.pem"
cat "$P/ca.pem" "$P/ca.key" >"$T/with-key.pem"
for f in "$P/srv.pem" "$T/junk.pem" "$T/with-key.pem" "$T/missing.pem"; do
  out="$(kit-net ca add "$f" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && ok "ca add refuses $(basename "$f")" || bad "ca add accepted $(basename "$f")" "$out"
done
has "server certificate is named as not a CA" "not a CA certificate" "$(kit-net ca add "$P/srv.pem" 2>&1)"
has "private key is refused by name" "private key" "$(kit-net ca add "$T/with-key.pem" 2>&1)"
[ ! -e "$CONF" ] && ok "refused files changed nothing" || bad "a refused ca add wrote files" "$(ls -R "$CONF")"

# --- 4. `ca add` with a DER file
out="$(kit-net ca add "$P/ca.der" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ca add accepts a DER CA" || bad "ca add ca.der" "$out"
has "ca add names the CA" "Kit Net Test Root CA" "$out"
ls "$CONF"/ca/*.pem >/dev/null 2>&1 && ok "PEM stored below ca/" || bad "no PEM below ca/"
head -n 1 "$CONF"/ca/*.pem | grep -q 'BEGIN CERTIFICATE' && ok "stored file is PEM" || bad "stored file is not PEM"
has "ca list shows subject and fingerprint" "sha256:" "$(kit-net ca list)"
has "second add is a no-op" "already added" "$(kit-net ca add "$P/ca.pem" 2>&1)"
[ "$(ls "$CONF"/ca | wc -l | tr -d ' ')" = 1 ] && ok "PEM and DER of one CA give one file" || bad "duplicate CA files" "$(ls "$CONF"/ca)"
env_txt="$(cat "$CONF/net.env")"
for v in SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE NODE_EXTRA_CA_CERTS GIT_SSL_CAINFO PIP_CERT NPM_CONFIG_CAFILE CODEX_CA_CERTIFICATE; do
  has "net.env sets $v" "export $v=" "$env_txt"
done
lacks "net.env sets no proxy yet" "PROXY" "$env_txt"
[ "$(mode_of "$CONF/net.env")" = 0o600 ] && ok "net.env is 0600" || bad "net.env mode $(mode_of "$CONF/net.env")"
has "environment.d file has the CA variables" "SSL_CERT_FILE=$CONF/ca-bundle.pem" "$(cat "$HOME/.config/environment.d/60-work-kit-net.conf")"
lacks "environment.d file is not shell syntax" "export " "$(cat "$HOME/.config/environment.d/60-work-kit-net.conf")"
grep -q 'Kit Net Test Root CA' "$CONF/ca-bundle.pem" && [ "$(grep -c 'BEGIN CERTIFICATE' "$CONF/ca-bundle.pem")" -gt 2 ] && ok "bundle = system bundle + company CA" || bad "bundle content"
[ "$(grep -c 'BEGIN CERTIFICATE' "$CONF/ca-company.pem")" = 1 ] && ok "company-only file has just the company CA" || bad "ca-company.pem"
[ "$(head -n 1 "$HOME/.bashrc")" = "# >>> work-kit company-network (managed, do not edit) >>>" ] && ok "block sits on top of ~/.bashrc (before the interactive guard)" || bad "bashrc block position" "$(head -n 4 "$HOME/.bashrc")"
[ "$(mode_of "$HOME/.bashrc")" = 0o640 ] && ok "~/.bashrc mode kept" || bad "~/.bashrc mode $(mode_of "$HOME/.bashrc")"
grep -q 'work-kit company-network' "$HOME/.profile" && ok "login file (~/.profile) has the block" || bad "no block in ~/.profile"
ls "$BAK"/.bashrc.bak-* >/dev/null 2>&1 && ok "backup of ~/.bashrc below backups/35-company-network" || bad "no ~/.bashrc backup" "$(ls -a "$BAK" 2>&1)"
cmp -s "$(ls "$BAK"/.bashrc.bak-* | grep -v origin | head -n 1)" "$T/bashrc.orig" && ok "backup equals the original" || bad "backup differs"

# --- 5. after `ca add` (fresh terminal): the clients trust the test CA
o="$(fresh py_get "$DIRECT" 2>&1)"; [ "$o" = 200 ] && ok "python works after ca add" || bad "python after ca add" "$o"
o="$(fresh node_get "$DIRECT" 2>&1)"; [ "$o" = 200 ] && ok "node works after ca add" || bad "node after ca add" "$o"
o="$(fresh curl_get "$DIRECT" 2>&1)"; [ "$o" = 200 ] && ok "curl works after ca add" || bad "curl after ca add" "$o"
out="$(kit-net test "$DIRECT" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "kit-net test exits 0 after ca add" || bad "kit-net test exit $rc" "$out"
for c in python node curl git; do has "test: $c ok" "ok    $c" "$out"; done
if command -v uv >/dev/null; then has "test: uv ok" "ok    uv" "$out"; fi
has "test lists its result" "all clients work" "$out"
o="$(kit-net status)"; has "status shows the CA" "Kit Net Test Root CA" "$o"; has "status shows the block in ~/.bashrc" "block present" "$o"

# --- 6. the proxy
out="$(kit-net proxy set proxy.example:8080 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "proxy URL without a scheme is refused" "http://" "$out" || bad "proxy without scheme accepted" "$out"
out="$(kit-net proxy set 'socks5://p:1080' 2>&1)"; [ "$?" = 1 ] && ok "socks proxy is refused" || bad "socks accepted" "$out"
out="$(kit-net proxy set 'http://h:8080/a b' 2>&1)"; [ "$?" = 1 ] && ok "proxy URL with a space is refused" || bad "space accepted" "$out"
mkdir -p "$HOME/.config/Code/User"
printf '// my settings\n{\n    // editor\n    "editor.fontSize": 14,\n    "files.autoSave": "afterDelay"\n}\n' >"$HOME/.config/Code/User/settings.json"
chmod 600 "$HOME/.config/Code/User/settings.json"; cp -p "$HOME/.config/Code/User/settings.json" "$T/settings.orig"
out="$(kit-net proxy set "http://127.0.0.1:$PP" --no-proxy '.corp.example,10.0.0.0/8' 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "proxy set" || bad "proxy set" "$out"
env_txt="$(cat "$CONF/net.env")"
for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy; do has "net.env sets $v" "export $v=" "$env_txt"; done
has "NO_PROXY keeps loopback and adds the list" "NO_PROXY='localhost,127.0.0.1,::1,.corp.example,10.0.0.0/8'" "$env_txt"
has "VS Code block written" "\"http.proxy\": \"http://127.0.0.1:$PP\"" "$(cat "$HOME/.config/Code/User/settings.json")"
python3 - "$HOME/.config/Code/User/settings.json" <<'PY' && ok "settings.json is still valid JSON (comments and trailing commas removed)" || bad "settings.json is not valid JSON"
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r"^\s*//.*$", "", t, flags=re.M)
t = re.sub(r",(\s*[}\]])", r"\1", t)
d = json.loads(t)
assert d["editor.fontSize"] == 14 and d["http.proxy"].startswith("http://127.0.0.1:") and "localhost" in d["http.noProxy"]
PY
[ "$(mode_of "$HOME/.config/Code/User/settings.json")" = 0o600 ] && ok "settings.json mode kept" || bad "settings.json mode"
before="$(proxied)"
o="$(plain py_get "$VIA" 2>&1)"; [ "$?" != 0 ] && ok "the proxy-only name does not resolve without the proxy" || bad "name resolved without proxy" "$o"
o="$(fresh py_get "$VIA" 2>&1)"; [ "$o" = 200 ] && ok "python through the proxy" || bad "python through the proxy" "$o"
o="$(fresh curl_get "$VIA" 2>&1)"; [ "$o" = 200 ] && ok "curl through the proxy" || bad "curl through the proxy" "$o"
[ "$(proxied)" -ge $((before + 2)) ] && ok "proxy saw the CONNECT requests" || bad "proxy log has no new CONNECT" "$(cat "$T/fix/proxy.log" 2>&1)"
before="$(proxied)"
o="$(fresh py_get "$DIRECT" 2>&1)"; [ "$o" = 200 ] && [ "$(proxied)" = "$before" ] && ok "localhost bypasses the proxy" || bad "localhost went through the proxy" "$o"
out="$(kit-net test "$VIA" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "kit-net test through the proxy exits 0" || bad "kit-net test via proxy exit $rc" "$out"
for c in python node curl git; do has "test via proxy: $c ok" "ok    $c" "$out"; done
[ "$(proxied)" -ge $((before + 4)) ] && ok "python, node, curl and git all used the proxy" || bad "proxy count" "$(cat "$T/fix/proxy.log")"
sum1="$(tree_sum)"
kit-net proxy set "http://127.0.0.1:$PP" --no-proxy '.corp.example,10.0.0.0/8' >/dev/null 2>&1
[ "$(tree_sum)" = "$sum1" ] && ok "proxy set twice: no file changes (idempotent)" || bad "second proxy set changed files" "$(diff <(echo "$sum1") <(tree_sum) | head -n 6)"
[ "$(grep -c 'work-kit company-network (managed' "$HOME/.bashrc")" = 1 ] && ok "still one block in ~/.bashrc" || bad "block count"
kit-net proxy set "http://user:s3cret@127.0.0.1:$PP" >/dev/null 2>&1
o="$(kit-net status)"; lacks "status hides the proxy password" "s3cret" "$o"; has "status masks it" "user:***@" "$o"
has "no-proxy list survives a proxy change" ".corp.example" "$(cat "$CONF/net.env")"
kit-net proxy set "http://127.0.0.1:$PP" --no-proxy '' >/dev/null 2>&1
lacks "--no-proxy '' clears the list" ".corp.example" "$(cat "$CONF/net.env")"
out="$(kit-net proxy set "http://127.0.0.1:$PP" 2>&1)"

# --- 7. help safety: with settings in place, help does not act
sum1="$(tree_sum)"; procs1="$(ps -A -o pid= | wc -l)"
for a in "--help" "-h" "--version" "proxy -h" "proxy set -h" "proxy unset --help" "ca -h" "ca add -h" "ca remove --help" "ca list -h" \
         "status -h" "test -h" "refresh --help" "purge --help" "purge -h"; do
  # shellcheck disable=SC2086
  out="$(kit-net $a 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && [ -n "$out" ]; then ok "kit-net $a prints and exits 0"; else bad "kit-net $a exit $rc" "$out"; fi
done
[ "$(tree_sum)" = "$sum1" ] && ok "no help run changed any file" || bad "help changed files" "$(diff <(echo "$sum1") <(tree_sum) | head -n 6)"

# --- 8. remove the proxy, then the CA: everything is restored
kit-net proxy unset >/dev/null 2>&1
lacks "proxy unset removes the proxy variables" "PROXY" "$(cat "$CONF/net.env")"
grep -q 'http.proxy' "$HOME/.config/Code/User/settings.json" && bad "VS Code block left" || ok "VS Code block removed"
cmp -s "$HOME/.config/Code/User/settings.json" "$T/settings.orig" && ok "settings.json is byte-identical to the original" || bad "settings.json differs" "$(diff "$T/settings.orig" "$HOME/.config/Code/User/settings.json")"
o="$(fresh py_get "$DIRECT" 2>&1)"; [ "$o" = 200 ] && ok "CA still trusted after proxy unset" || bad "CA lost after proxy unset" "$o"
out="$(kit-net ca remove nothing-like-this 2>&1)"; [ "$?" = 1 ] && ok "ca remove of an unknown name fails" || bad "ca remove unknown" "$out"
kit-net ca remove "kit-net-test" >/dev/null 2>&1 && ok "ca remove" || bad "ca remove"
for f in "$CONF/net.env" "$CONF/ca-bundle.pem" "$CONF/ca-company.pem" "$CONF/net.json" "$CONF/ca" "$HOME/.config/environment.d/60-work-kit-net.conf" "$HOME/.profile"; do
  [ ! -e "$f" ] && ok "removed: ${f#$HOME/}" || bad "left behind: ${f#$HOME/}"
done
cmp -s "$HOME/.bashrc" "$T/bashrc.orig" && ok "~/.bashrc is byte-identical to the original" || bad "~/.bashrc differs" "$(diff "$T/bashrc.orig" "$HOME/.bashrc")"
[ "$(mode_of "$HOME/.bashrc")" = 0o640 ] && ok "~/.bashrc mode still kept" || bad "~/.bashrc mode"
o="$(fresh py_get "$DIRECT" 2>&1)"; [ "$?" != 0 ] && ok "python fails again once the CA is removed" || bad "python still trusts it" "$o"

# --- 9. stale system bundle, own settings in VS Code, a foreign http.proxy
cp /etc/ssl/certs/ca-certificates.crt "$T/system.pem" 2>/dev/null || cp /etc/ssl/cert.pem "$T/system.pem"
KIT_NET_SYSTEM_BUNDLE="$T/system.pem" kit-net ca add "$P/ca.pem" >/dev/null 2>&1
has "status: bundle up to date" "bundle:" "$(kit-net status)"
printf '\n# changed\n' >>"$T/system.pem"
has "status notices a changed system bundle" "run kit-net refresh" "$(kit-net status)"
kit-net refresh >/dev/null 2>&1
lacks "refresh rebuilt it" "run kit-net refresh" "$(kit-net status)"
printf '{ "http.proxy": "http://mine:1" }\n' >"$HOME/.config/Code/User/settings.json"
has "own http.proxy in VS Code is left alone" "left alone" "$(kit-net proxy set "http://127.0.0.1:$PP" 2>&1)"
[ "$(cat "$HOME/.config/Code/User/settings.json")" = '{ "http.proxy": "http://mine:1" }' ] && ok "foreign settings.json untouched" || bad "foreign settings.json changed"

# --- 10. uninstall removes everything
bash "$HERE/uninstall.sh" >"$T/uninstall.log" 2>&1 && ok "uninstall.sh runs" || bad "uninstall.sh" "$(cat "$T/uninstall.log")"
[ ! -e "$HOME/.local/bin/kit-net" ] && ok "launcher removed" || bad "launcher left"
for f in "$CONF/net.env" "$CONF/ca-bundle.pem" "$CONF/net.json" "$CONF/ca" "$HOME/.config/environment.d/60-work-kit-net.conf" "$HOME/.profile" "$HOME/.local/share/work-kit/company-network"; do
  [ ! -e "$f" ] && ok "uninstall removed ${f#$HOME/}" || bad "uninstall left ${f#$HOME/}"
done
cmp -s "$HOME/.bashrc" "$T/bashrc.orig" && ok "uninstall restored ~/.bashrc" || bad "~/.bashrc differs after uninstall" "$(diff "$T/bashrc.orig" "$HOME/.bashrc")"
ls -d "$BAK"/ca.bak-* >/dev/null 2>&1 && ok "company CAs were backed up" || bad "no ca backup" "$(ls -a "$BAK")"
bash "$HERE/uninstall.sh" >/dev/null 2>&1 && ok "uninstall twice is harmless" || bad "second uninstall failed"
bash "$HERE/install.sh" >/dev/null 2>&1 && ok "install again after uninstall" || bad "reinstall"
[ ! -e "$CONF/net.env" ] && ok "reinstall sets nothing" || bad "reinstall wrote net.env"

kill "$FIX" 2>/dev/null; wait "$FIX" 2>/dev/null; kill -0 "$FIX" 2>/dev/null && bad "fixture still running" || { ok "fixture processes stopped"; FIX=""; }
echo "passed: $pass  failed: $fails"
[ "$fails" = 0 ]
