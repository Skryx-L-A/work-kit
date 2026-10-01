#!/usr/bin/env python3
"""kit-net: make the laptop's tools work behind a company proxy and a TLS-inspecting firewall.

Nothing is changed until `kit-net proxy set` or `kit-net ca add` runs. Then one env file
(~/.config/work-kit/net.env) is written and hooked into terminals (marked block in
~/.bashrc and the login file), GUI apps and systemd user services
(~/.config/environment.d/60-work-kit-net.conf) and VS Code (marked block in settings.json).
Standard library only, Python 3.8 or newer, no network access except `kit-net test`.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile

VERSION = "1.0"
BEGIN = "# >>> work-kit company-network (managed, do not edit) >>>"
END = "# <<< work-kit company-network <<<"
DEFAULT_NO_PROXY = ["localhost", "127.0.0.1", "::1"]
SYSTEM_BUNDLES = [
    "/etc/ssl/certs/ca-certificates.crt",   # Debian, Ubuntu
    "/etc/pki/tls/certs/ca-bundle.crt",     # Fedora, RHEL
    "/etc/ssl/ca-bundle.pem",               # openSUSE
    "/etc/ssl/cert.pem",                    # macOS, Alpine
]


class NetError(Exception):
    pass


# --- paths ------------------------------------------------------------------------------------
def home():
    return os.path.expanduser("~")


def conf_root():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(home(), ".config")


def conf_dir():
    return os.path.join(conf_root(), "work-kit")


def ca_dir():
    return os.path.join(conf_dir(), "ca")


def p_state():
    return os.path.join(conf_dir(), "net.json")


def p_env():
    return os.path.join(conf_dir(), "net.env")


def p_bundle():
    return os.path.join(conf_dir(), "ca-bundle.pem")


def p_company():
    return os.path.join(conf_dir(), "ca-company.pem")


def p_envd():
    return os.path.join(conf_root(), "environment.d", "60-work-kit-net.conf")


def p_vscode():
    return os.path.join(conf_root(), "Code", "User", "settings.json")


def backup_dir():
    return os.path.join(os.environ.get("KIT_DATA_DIR") or os.path.join(home(), ".local", "share", "work-kit"),
                        "backups", "35-company-network")


def rc_targets():
    """(~/.bashrc, login file). The login file is the first of the three bash reads that exists."""
    login = os.path.join(home(), ".profile")
    for name in (".bash_profile", ".bash_login", ".profile"):
        if os.path.exists(os.path.join(home(), name)):
            login = os.path.join(home(), name)
            break
    return [os.path.join(home(), ".bashrc"), login]


def tilde(path):
    h = home()
    return "~" + path[len(h):] if path.startswith(h + os.sep) else path


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def say(msg):
    print(msg)


# --- files ------------------------------------------------------------------------------------
def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            return fh.read()
    except OSError:
        return None


def write_private(path, text, mode=0o600):
    """Atomic write with the given mode (proxy URLs may contain a password)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".kit-net.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def backup(path):
    """Copy PATH below the backup dir (name.bak-<timestamp>, original path in name.bak-<ts>.origin)."""
    os.makedirs(backup_dir(), exist_ok=True)
    b = os.path.join(backup_dir(), "%s.bak-%s" % (os.path.basename(path), datetime.datetime.now().strftime("%Y%m%d%H%M%S")))
    while os.path.exists(b):
        b += "-1"
    if os.path.isdir(path):
        shutil.copytree(path, b)
    else:
        shutil.copy2(path, b)
    with open(b + ".origin", "w") as fh:
        fh.write(path + "\n")
    return b


def strip_block(text, begin=None, end=None):
    """TEXT without the managed block(s); other lines untouched."""
    begin, end = begin or BEGIN, end or END
    out, skip = [], False
    for line in text.splitlines(True):
        bare = line.rstrip("\r\n")
        if bare.strip() == begin:
            skip = True
            continue
        if bare.strip() == end:
            skip = False
            continue
        if not skip:
            out.append(line)
    return "".join(out)


def set_block(path, body, present):
    """Put the managed block (BODY lines) at the top of PATH, or remove it. Returns a message or None.
    In-place rewrite keeps the file's mode and a symlinked dotfile; the block goes on top so
    interactive-only guards further down (Ubuntu's ~/.bashrc) cannot skip it."""
    old = read_text(path)
    if old is None and not present:
        return None
    base = strip_block(old or "")
    new = (BEGIN + "\n" + "\n".join(body) + "\n" + END + "\n" + base) if present else base
    if new == old:
        return None
    note = ""
    if old is not None:
        note = " (backup: %s)" % tilde(backup(path))
    if not present and new == "":
        os.unlink(path)
        return "removed empty %s%s" % (tilde(path), note)
    if old is None:
        write_private(path, new, 0o644)
    else:
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write(new)
    return "%s block in %s%s" % ("wrote" if present else "removed", tilde(path), note)


# --- certificates: a small X.509 reader (no third-party libraries) ----------------------------
def _tlv(buf, pos):
    tag = buf[pos]
    n = buf[pos + 1]
    pos += 2
    if n & 0x80:
        k = n & 0x7F
        n = int.from_bytes(buf[pos:pos + k], "big")
        pos += k
    if pos + n > len(buf):
        raise ValueError("truncated DER data")
    return tag, pos, pos + n


def _children(buf, start, end):
    pos, out = start, []
    while pos < end:
        tag, s, e = _tlv(buf, pos)
        out.append((tag, s, e))
        pos = e
    return out


def _oid(buf, s, e):
    b = buf[s:e]
    parts = [b[0] // 40, b[0] % 40]
    v = 0
    for x in b[1:]:
        v = (v << 7) | (x & 0x7F)
        if not x & 0x80:
            parts.append(v)
            v = 0
    return ".".join(str(p) for p in parts)


def _name(buf, s, e):
    labels = {"2.5.4.3": "CN", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST"}
    out = []
    for _t, rs, re_ in _children(buf, s, e):
        for _t2, as_, ae in _children(buf, rs, re_):
            kids = _children(buf, as_, ae)
            oid = _oid(buf, kids[0][1], kids[0][2])
            vt, vs, ve = kids[1]
            raw = buf[vs:ve]
            text = raw.decode("utf-16-be", "replace") if vt == 0x1E else raw.decode("utf-8", "replace")
            out.append("%s=%s" % (labels.get(oid, oid), text))
    return ", ".join(out)


def _time(buf, s, e, tag):
    t = buf[s:e].decode("ascii")
    if tag == 0x17:
        yy = int(t[:2])
        t = ("19" if yy >= 50 else "20") + t
    return datetime.datetime.strptime(t[:14], "%Y%m%d%H%M%S")


def parse_cert(der):
    """Fields of one DER certificate; raises ValueError when it is not a certificate."""
    try:
        tag, s, e = _tlv(der, 0)
        if tag != 0x30 or e != len(der):
            raise ValueError("not a DER certificate")
        tbs_tag, ts, te = _tlv(der, s)
        if tbs_tag != 0x30:
            raise ValueError("not a DER certificate")
        kids = _children(der, ts, te)
        i = 0
        version = 1
        if kids[0][0] == 0xA0:
            vt, vs, ve = _children(der, kids[0][1], kids[0][2])[0]
            version = der[vs] + 1
            i = 1
        issuer, validity, subject = kids[i + 2], kids[i + 3], kids[i + 4]
        nb_t, nb_s, nb_e = _children(der, validity[1], validity[2])[0]
        na_t, na_s, na_e = _children(der, validity[1], validity[2])[1]
        info = {
            "der": der, "version": version,
            "issuer": _name(der, issuer[1], issuer[2]), "subject": _name(der, subject[1], subject[2]),
            "issuer_raw": der[issuer[1]:issuer[2]], "subject_raw": der[subject[1]:subject[2]],
            "not_before": _time(der, nb_s, nb_e, nb_t), "not_after": _time(der, na_s, na_e, na_t),
            "ca": None, "key_cert_sign": None,
            "sha256": hashlib.sha256(der).hexdigest(),
        }
        for tg, xs, xe in kids[i + 6:]:
            if tg != 0xA3:
                continue
            ext_seq = _children(der, xs, xe)[0]
            for _t, es, ee in _children(der, ext_seq[1], ext_seq[2]):
                parts = _children(der, es, ee)
                oid = _oid(der, parts[0][1], parts[0][2])
                vt, vs, ve = parts[-1]
                if oid == "2.5.29.19":       # basicConstraints
                    seq = _children(der, vs, ve)[0]
                    flags = _children(der, seq[1], seq[2])
                    info["ca"] = bool(flags and flags[0][0] == 0x01 and der[flags[0][1]] != 0)
                elif oid == "2.5.29.15":     # keyUsage
                    bs = _children(der, vs, ve)[0]
                    bits = der[bs[1] + 1:bs[2]]
                    info["key_cert_sign"] = bool(bits and bits[0] & 0x04)
        return info
    except (IndexError, ValueError, UnicodeDecodeError) as exc:
        raise ValueError("not a valid X.509 certificate (%s)" % exc)


def to_pem(der):
    b = base64.b64encode(der).decode("ascii")
    return "-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n" % "\n".join(b[i:i + 64] for i in range(0, len(b), 64))


PEM_RE = re.compile(r"-----BEGIN (?:X509 |TRUSTED )?CERTIFICATE-----(.*?)-----END (?:X509 |TRUSTED )?CERTIFICATE-----", re.S)


def load_certs(path):
    """DER blobs of every certificate in PATH (PEM with one or more certificates, or one DER)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if b"PRIVATE KEY" in data:
        raise NetError("%s contains a private key. Never hand a private key to this tool; give it the certificate only." % path)
    text = data.decode("latin-1")
    if "-----BEGIN" in text:
        out = []
        for m in PEM_RE.finditer(text):
            try:
                out.append(base64.b64decode("".join(m.group(1).split()), validate=True))
            except ValueError:
                raise NetError("%s: a certificate block is not valid base64" % path)
        if not out:
            raise NetError("%s: no CERTIFICATE block found (is it a public key or request?)" % path)
        return out
    return [data]


def cert_label(info):
    return info["subject"] or info["sha256"][:12]


def slug(info):
    m = re.search(r"CN=([^,]+)", info["subject"]) or re.search(r"O=([^,]+)", info["subject"])
    s = re.sub(r"[^A-Za-z0-9]+", "-", m.group(1) if m else "ca").strip("-").lower()[:40] or "ca"
    return "%s-%s" % (s, info["sha256"][:8])


def stored_cas():
    """[(filename, info)] of the company CAs in ca_dir, sorted by name."""
    out = []
    if os.path.isdir(ca_dir()):
        for name in sorted(os.listdir(ca_dir())):
            if not name.endswith(".pem"):
                continue
            try:
                info = parse_cert(load_certs(os.path.join(ca_dir(), name))[0])
            except (NetError, ValueError, OSError):
                continue
            out.append((name, info))
    return out


# --- state, system bundle, env ---------------------------------------------------------------
def load_state():
    try:
        with open(p_state(), encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        st = {}
    st.setdefault("proxy", "")
    st.setdefault("no_proxy", [])
    st.setdefault("system_bundle", "")
    return st


def save_state(st):
    write_private(p_state(), json.dumps(st, indent=2, sort_keys=True) + "\n")


def mask(url):
    return re.sub(r"(//[^:/@]*):[^@]*@", r"\1:***@", url)


def find_system_bundle(st, override=None):
    cands = [override, os.environ.get("KIT_NET_SYSTEM_BUNDLE"), st.get("system_bundle")] + SYSTEM_BUNDLES
    try:
        cands.append(ssl.get_default_verify_paths().cafile)
    except Exception:
        pass
    try:
        import certifi  # type: ignore
        cands.append(certifi.where())
    except Exception:
        pass
    for c in cands:
        if c and os.path.isfile(c) and os.path.getsize(c) > 1000 and "BEGIN CERTIFICATE" in (read_text(c) or ""):
            return c
    raise NetError("no system CA bundle found (looked at %s). Pass --system-bundle FILE, "
                   "or set KIT_NET_SYSTEM_BUNDLE." % ", ".join(SYSTEM_BUNDLES))


def sha_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def valid_proxy(url):
    from urllib.parse import urlsplit
    if not re.match(r"^https?://", url or ""):
        raise NetError("proxy URL must be a complete URL with http:// or https://, e.g. http://proxy.example.com:8080 "
                       "(SOCKS is not supported by the harnesses)")
    if re.search(r"[\s\"'`$\\]", url):
        raise NetError("proxy URL contains a space, quote, backtick, dollar or backslash: percent-encode it "
                       "(a password with special characters becomes %XX)")
    sp = urlsplit(url)
    try:
        sp.port
    except ValueError:
        raise NetError("proxy URL has an invalid port")
    if not sp.hostname:
        raise NetError("proxy URL has no host name")
    return url.rstrip("/")


def split_list(text):
    return [x for x in re.split(r"[,\s]+", text or "") if x]


def effective_no_proxy(st):
    seen, out = set(), []
    for x in DEFAULT_NO_PROXY + list(st["no_proxy"]):
        if x not in seen:
            seen.add(x)
            out.append(x)
    return ",".join(out)


def build_env(st, has_ca):
    """Ordered (name, value) pairs of net.env."""
    env = []
    if st["proxy"]:
        env += [(k, st["proxy"]) for k in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")]
        env += [("NO_PROXY", effective_no_proxy(st)), ("no_proxy", effective_no_proxy(st))]
    if has_ca:
        b = p_bundle()
        env += [
            ("SSL_CERT_FILE", b),              # OpenSSL clients, Python ssl, Go, uv (0.12 reads SSL_CERT_FILE; UV_NATIVE_TLS is deprecated)
            ("REQUESTS_CA_BUNDLE", b),         # Python requests, aider, litellm
            ("CURL_CA_BUNDLE", b),             # curl
            ("PIP_CERT", b),                   # pip
            ("GIT_SSL_CAINFO", b),             # git over https
            ("NODE_EXTRA_CA_CERTS", p_company()),  # Node: Claude Code, Gemini CLI, Copilot CLI, opencode, pi, npm, VS Code
            ("NPM_CONFIG_CAFILE", b),          # npm
            ("CODEX_CA_CERTIFICATE", b),       # Codex (Rust; falls back to SSL_CERT_FILE)
            ("CARGO_HTTP_CAINFO", b),          # cargo
            ("BUNDLE_SSL_CA_CERT", b),         # ruby bundler
        ]
    return env


def sh_quote(v):
    return "'" + v.replace("'", "'\\''") + "'"


def envd_value(v):
    return v if re.match(r"^[A-Za-z0-9_@%+=:,./-]*$", v) else '"' + v.replace('"', '\\"') + '"'


CLIENTS = [
    ("Claude Code", "HTTPS_PROXY, NO_PROXY; NODE_EXTRA_CA_CERTS (CLAUDE_CODE_CERT_STORE picks bundled/system stores)"),
    ("Codex", "HTTPS_PROXY, NO_PROXY; CODEX_CA_CERTIFICATE, else SSL_CERT_FILE (also passes CURL/GIT/NODE/PIP/npm CA vars to sandboxed commands)"),
    ("Gemini CLI", "HTTPS_PROXY, NO_PROXY; NODE_EXTRA_CA_CERTS (or NODE_USE_SYSTEM_CA=1)"),
    ("opencode", "HTTPS_PROXY, NO_PROXY; NODE_EXTRA_CA_CERTS, SSL_CERT_FILE"),
    ("pi", "HTTPS_PROXY, NO_PROXY (EnvHttpProxyAgent); NODE_EXTRA_CA_CERTS"),
    ("Aider", "HTTPS_PROXY, NO_PROXY (httpx); SSL_CERT_FILE, REQUESTS_CA_BUNDLE (litellm)"),
    ("Copilot CLI", "HTTPS_PROXY, NO_PROXY; NODE_EXTRA_CA_CERTS, SSL_CERT_FILE"),
    ("VS Code", "http.proxy and http.noProxy in settings.json (block written when the file exists); NODE_EXTRA_CA_CERTS from the "
               "environment; system certificates stay on"),
    ("python / pip / requests", "HTTPS_PROXY, NO_PROXY; SSL_CERT_FILE, REQUESTS_CA_BUNDLE, PIP_CERT"),
    ("uv", "HTTPS_PROXY, NO_PROXY; SSL_CERT_FILE"),
    ("node / npm", "HTTPS_PROXY, NO_PROXY; NODE_EXTRA_CA_CERTS, NPM_CONFIG_CAFILE"),
    ("curl", "HTTPS_PROXY, NO_PROXY; CURL_CA_BUNDLE"),
    ("git (https remotes)", "HTTPS_PROXY, NO_PROXY; GIT_SSL_CAINFO. ssh remotes need a ProxyCommand in ~/.ssh/config"),
    ("kit-models, kit-llm", "as python/curl above (kit-llm and the kit-models proxy live on 127.0.0.1, which NO_PROXY skips)"),
]


# --- applying --------------------------------------------------------------------------------
def build_bundles(st, cas, override=None):
    """Write the combined bundle (system + company) and the company-only file."""
    sysb = find_system_bundle(st, override)
    text = read_text(sysb)
    if not text.endswith("\n"):
        text += "\n"
    parts = [text]
    company = []
    for name, info in cas:
        pem = "# %s (kit-net: %s)\n%s" % (cert_label(info), name, to_pem(info["der"]))
        company.append(pem)
    parts += company
    write_private(p_bundle(), "".join(parts), 0o644)
    write_private(p_company(), "".join(company), 0o644)
    st["system_bundle"] = sysb
    st["system_sha"] = sha_file(sysb)


VS_BEGIN = "// >>> work-kit company-network (managed, do not edit) >>>"
VS_END = "// <<< work-kit company-network <<<"


def vscode_body(st):
    lines = ["  " + VS_BEGIN]
    if st["proxy"]:
        lines.append('  "http.proxy": %s,' % json.dumps(st["proxy"]))
        lines.append('  "http.noProxy": %s,' % json.dumps(effective_no_proxy(st).split(",")))
    lines.append("  " + VS_END)
    return lines


def _skip_jsonc_prefix(text):
    """Index of the first '{' that is not inside a comment, or -1."""
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i)
            i = n if j < 0 else j + 2
        elif text[i] == "{":
            return i
        elif text[i].isspace():
            i += 1
        else:
            return -1
    return -1


def apply_vscode(st):
    """Managed http.proxy block in VS Code's user settings.json (only when VS Code has run once)."""
    path = p_vscode()
    if not os.path.isdir(os.path.dirname(path)):
        return "VS Code: no user settings folder yet; it reads the proxy and CA variables from the environment anyway"
    old = read_text(path)
    base = strip_block(old, VS_BEGIN, VS_END) if old else ""
    if not st["proxy"]:
        if old is None or base == old:
            return None
        new = base
        verb = "removed"
    else:
        if re.search(r'"http\.(proxy|noProxy)"', base):
            return "VS Code: settings.json already sets http.proxy or http.noProxy; left alone"
        block = "\n".join(vscode_body(st)) + "\n"
        if not base.strip():
            new = "{\n" + block + "}\n"
        else:
            k = _skip_jsonc_prefix(base)
            if k < 0:
                return "VS Code: settings.json is not a JSON object; left alone"
            rest = base[k + 1:]
            new = base[:k + 1] + "\n" + block + (rest[1:] if rest.startswith("\n") else rest)
        verb = "wrote"
        if new == old:
            return None
    note = " (backup: %s)" % tilde(backup(path)) if old is not None else ""
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(new)
    return "%s http.proxy block in %s%s" % (verb, tilde(path), note)


def remove_all(msgs):
    for path in (p_env(), p_envd(), p_bundle(), p_company()):
        if os.path.exists(path):
            os.unlink(path)
            msgs.append("removed %s" % tilde(path))
    try:
        os.rmdir(os.path.dirname(p_envd()))
    except OSError:
        pass
    for rc in rc_targets() + [os.path.join(home(), n) for n in (".profile", ".bash_profile", ".bash_login")]:
        m = set_block(rc, [], False)
        if m:
            msgs.append(m)
    m = apply_vscode({"proxy": "", "no_proxy": []})
    if m:
        msgs.append(m)


def apply(st, override=None):
    """Make the files match the state: nothing configured means nothing on disk."""
    cas = stored_cas()
    msgs = []
    if not st["proxy"] and not cas:
        remove_all(msgs)
        if os.path.exists(p_state()):
            os.unlink(p_state())
        return msgs or ["nothing configured, nothing on disk"]
    if cas:
        build_bundles(st, cas, override)
        msgs.append("wrote %s (system bundle + %d company CA%s)" % (tilde(p_bundle()), len(cas), "" if len(cas) == 1 else "s"))
    else:
        for p in (p_bundle(), p_company()):
            if os.path.exists(p):
                os.unlink(p)
        st["system_sha"] = ""
    env = build_env(st, bool(cas))
    header = "# Written by kit-net (work-kit 35-company-network). Change it with `kit-net`, not by hand.\n"
    write_private(p_env(), header + "".join("export %s=%s\n" % (k, sh_quote(v)) for k, v in env))
    write_private(p_envd(), header + "".join("%s=%s\n" % (k, envd_value(v)) for k, v in env))
    msgs.append("wrote %s and %s" % (tilde(p_env()), tilde(p_envd())))
    src = '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/net.env" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/net.env"'
    for rc in rc_targets():
        m = set_block(rc, [src], True)
        if m:
            msgs.append(m)
    m = apply_vscode(st)
    if m:
        msgs.append(m)
    save_state(st)
    return msgs


# --- commands --------------------------------------------------------------------------------
def cmd_proxy_set(a):
    st = load_state()
    st["proxy"] = valid_proxy(a.url)
    if a.no_proxy is not None:
        st["no_proxy"] = split_list(a.no_proxy)
    for m in apply(st):
        say(m)
    say("proxy: %s   no proxy for: %s" % (mask(st["proxy"]), effective_no_proxy(st)))
    say("Open a new terminal (GUI apps and services: log out and in). Check: kit-net test https://<a site you need>")


def cmd_proxy_unset(a):
    st = load_state()
    if not st["proxy"]:
        say("no proxy set")
    st["proxy"] = ""
    st["no_proxy"] = []
    for m in apply(st):
        say(m)


def cmd_ca_add(a):
    found = []
    for path in a.files:
        if not os.path.isfile(path):
            raise NetError("no such file: %s" % path)
        for der in load_certs(path):
            try:
                info = parse_cert(der)
            except ValueError as exc:
                raise NetError("%s: %s" % (path, exc))
            found.append((path, info))
    problems = []
    for path, info in found:
        selfsigned = info["issuer_raw"] == info["subject_raw"]
        if info["ca"] is False or (info["ca"] is None and (info["version"] >= 3 or not selfsigned)):
            problems.append("%s: %s is not a CA certificate (basicConstraints CA is not true). "
                            "This looks like a server certificate: ask IT for the root CA that signs it." % (path, cert_label(info)))
        elif info["key_cert_sign"] is False:
            problems.append("%s: %s may not sign certificates (keyUsage lacks keyCertSign)" % (path, cert_label(info)))
        elif info["not_after"] < utcnow():
            problems.append("%s: %s expired on %s" % (path, cert_label(info), info["not_after"].date()))
        elif info["not_before"] > utcnow():
            problems.append("%s: %s is not valid before %s (check the clock)" % (path, cert_label(info), info["not_before"].date()))
    if problems:
        raise NetError("nothing added:\n  " + "\n  ".join(problems))
    st = load_state()
    have = {i["sha256"] for _n, i in stored_cas()}
    added = []
    os.makedirs(ca_dir(), exist_ok=True)
    find_system_bundle(st, a.system_bundle)     # fail before anything is stored
    new = []
    for path, info in found:
        if info["sha256"] in have:
            say("already added: %s" % cert_label(info))
            continue
        name = slug(info) + ".pem"
        new.append((name, info))
        have.add(info["sha256"])
    for name, info in new:
        write_private(os.path.join(ca_dir(), name), to_pem(info["der"]), 0o644)
        added.append(name)
        say("added %s  (%s, valid until %s, sha256 %s)" % (name, cert_label(info), info["not_after"].date(), info["sha256"][:16]))
        if info["issuer_raw"] != info["subject_raw"]:
            say("  note: this is an intermediate CA, not a root. If checks still fail, add the root CA above it too.")
    if a.system_bundle:
        st["system_bundle"] = os.path.abspath(a.system_bundle)
    for m in apply(st, a.system_bundle):
        say(m)
    say("Open a new terminal (GUI apps and services: log out and in). Check: kit-net test https://<a site you need>")


def match_ca(key):
    hits = []
    for name, info in stored_cas():
        if key in (name, name[:-4]) or info["sha256"].startswith(key.lower()) or key.lower() == cert_label(info).lower():
            hits.append((name, info))
    if not hits:
        hits = [(n, i) for n, i in stored_cas() if key.lower() in cert_label(i).lower() or key.lower() in n.lower()]
    return hits


def cmd_ca_remove(a):
    hits = match_ca(a.name)
    if not hits:
        raise NetError("no company CA matches '%s' (see kit-net ca list)" % a.name)
    if len(hits) > 1:
        raise NetError("'%s' matches %d CAs, be more specific: %s" % (a.name, len(hits), ", ".join(n for n, _i in hits)))
    name, info = hits[0]
    os.unlink(os.path.join(ca_dir(), name))
    say("removed %s (%s)" % (name, cert_label(info)))
    try:
        os.rmdir(ca_dir())
    except OSError:
        pass
    for m in apply(load_state()):
        say(m)


def cmd_ca_list(a):
    cas = stored_cas()
    if not cas:
        say("no company CA added (kit-net ca add <file.pem|.crt|.der>)")
        return
    now = utcnow()
    for name, info in cas:
        flag = "  EXPIRED" if info["not_after"] < now else ""
        say("%s\n  subject: %s\n  issuer:  %s\n  valid:   %s to %s%s\n  sha256:  %s" % (
            name, info["subject"], info["issuer"], info["not_before"].date(), info["not_after"].date(), flag, info["sha256"]))


def cmd_refresh(a):
    st = load_state()
    if not st["proxy"] and not stored_cas():
        say("nothing configured")
        return
    for m in apply(st, a.system_bundle):
        say(m)


def read_env_file():
    out = {}
    for line in (read_text(p_env()) or "").splitlines():
        m = re.match(r"^export ([A-Za-z_][A-Za-z0-9_]*)='(.*)'$", line)
        if m:
            out[m.group(1)] = m.group(2).replace("'\\''", "'")
    return out


def has_block(path):
    return BEGIN in (read_text(path) or "").splitlines()


def cmd_status(a):
    st = load_state()
    cas = stored_cas()
    env = read_env_file()
    say("kit-net %s" % VERSION)
    say("proxy:      %s" % (mask(st["proxy"]) if st["proxy"] else "not set"))
    if st["proxy"]:
        say("no proxy:   %s" % effective_no_proxy(st))
    now = utcnow()
    say("company CAs: %s" % (len(cas) if cas else "none"))
    for name, info in cas:
        say("  %s  %s  until %s%s" % (name, cert_label(info), info["not_after"].date(), "  EXPIRED" if info["not_after"] < now else ""))
    if cas:
        sysb = st.get("system_bundle", "")
        if not sysb or not os.path.isfile(sysb):
            say("system bundle: %s is gone: run kit-net refresh" % (sysb or "(unknown)"))
        elif st.get("system_sha") and sha_file(sysb) != st["system_sha"]:
            say("system bundle: %s changed since the combined bundle was built: run kit-net refresh" % sysb)
        else:
            say("bundle:     %s (system bundle %s + company CAs)" % (tilde(p_bundle()), sysb))
    if not st["proxy"] and not cas:
        say("Nothing is set. Behind a proxy: kit-net proxy set <url>. TLS inspection: kit-net ca add <file>.")
        if a.clients:
            print_clients()
        return
    say("applied to:")
    say("  %s  %s" % (tilde(p_env()), "yes" if os.path.exists(p_env()) else "MISSING (kit-net refresh)"))
    for rc in rc_targets():
        say("  %s  %s" % (tilde(rc), "block present" if has_block(rc) else "block MISSING (kit-net refresh)"))
    say("  %s  %s" % (tilde(p_envd()), "yes (GUI apps and systemd user services, after the next login)" if os.path.exists(p_envd()) else "MISSING"))
    vs = p_vscode()
    if st["proxy"]:
        say("  %s  %s" % (tilde(vs), "block present" if has_block_jsonc(vs) else "no block (VS Code not run yet, or the file sets http.proxy itself)"))
    stale = [k for k, v in env.items() if os.environ.get(k) != v]
    if stale:
        say("this shell: %d of %d variables missing or different (%s). Open a new terminal, or run: . %s" % (
            len(stale), len(env), ", ".join(stale[:4]) + (", ..." if len(stale) > 4 else ""), tilde(p_env())))
    else:
        say("this shell: has all %d variables" % len(env))
    if a.clients:
        print_clients()


def print_clients():
    say("")
    for name, how in CLIENTS:
        say("%-22s %s" % (name, how))


def has_block_jsonc(path):
    return "// >>> work-kit company-network" in (read_text(path) or "")


# --- test: one HTTPS request per client -----------------------------------------------------
PY_CLIENT = r"""
import sys, urllib.request, urllib.error
try:
    r = urllib.request.urlopen(sys.argv[1], timeout=15)
    print("HTTP", r.status)
except urllib.error.HTTPError as e:
    print("HTTP", e.code)
except Exception as e:
    print("%s: %s" % (type(e).__name__, e)); sys.exit(1)
"""

NODE_CLIENT = r"""
const u = new URL(process.argv[1]), https = require('https'), http = require('http'), tls = require('tls');
const np = (process.env.NO_PROXY || process.env.no_proxy || '').split(',').map(s => s.trim().replace(/^\*?\./, '')).filter(Boolean);
const bypass = np.some(p => p === '*' || u.hostname === p || u.hostname.endsWith('.' + p));
const px = process.env.HTTPS_PROXY || process.env.https_proxy;
const fail = e => { console.error((e.code || e.name) + ': ' + e.message); process.exit(1); };
function get(extra) {
  https.get(u, Object.assign({ timeout: 15000 }, extra), r => { console.log('HTTP ' + r.statusCode); r.resume(); })
    .on('timeout', function () { this.destroy(new Error('timed out')); }).on('error', fail);
}
if (px && !bypass) {
  const p = new URL(px), headers = {};
  if (p.username) headers['Proxy-Authorization'] = 'Basic ' + Buffer.from(decodeURIComponent(p.username) + ':' + decodeURIComponent(p.password)).toString('base64');
  const req = (p.protocol === 'https:' ? https : http).request({ host: p.hostname, port: p.port || (p.protocol === 'https:' ? 443 : 80), method: 'CONNECT',
    path: u.hostname + ':' + (u.port || 443), headers, timeout: 15000 });
  req.on('connect', (res, sock) => {
    if (res.statusCode !== 200) { console.error('proxy CONNECT ' + res.statusCode); process.exit(1); }
    get({ createConnection: () => tls.connect({ socket: sock, servername: u.hostname }) });
  }).on('error', fail).on('timeout', () => fail(new Error('proxy timed out'))).end();
} else get({});
"""


def classify(text):
    t = text.lower()
    if re.search(r"certificate|self[- ]signed|issuer|cert_|unknownissuer|unable to verify|tls|ssl", t) and \
            not re.search(r"proxy connect|tunnel", t):
        return "cert"
    if re.search(r"\b407\b|proxy authentication", t):
        return "proxy-auth"
    if re.search(r"proxy|tunnel|connect tunnel", t):
        return "proxy"
    if re.search(r"could not resolve|name or service|nodename|getaddrinfo|enotfound|dns|failed to lookup", t):
        return "dns"
    if re.search(r"timed out|timeout|etimedout|unreachable|refused|econn", t):
        return "timeout"
    return "other"


def run(cmd, env, limit=30):
    try:
        p = subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=limit, universal_newlines=True)
        return p.returncode, p.stdout.strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out after %d s" % limit
    except OSError as exc:
        return 127, str(exc)


def client_checks(url, py, req_file):
    base = url.rstrip("/")
    node = shutil.which("node")
    curl = shutil.which("curl")
    git = shutil.which("git")
    uv = shutil.which("uv")
    checks = [("python", "SSL_CERT_FILE", [py, "-c", PY_CLIENT, url])]
    checks.append(("node", "NODE_EXTRA_CA_CERTS", [node, "-e", NODE_CLIENT, url] if node else None))
    checks.append(("curl", "CURL_CA_BUNDLE", [curl, "-sS", "-o", os.devnull, "-w", "HTTP %{http_code}", "--max-time", "20", url] if curl else None))
    checks.append(("git", "GIT_SSL_CAINFO", [git, "ls-remote", "--heads", base + "/kit-net-test.git"] if git else None))
    # resolving a package that does not exist fetches the index over TLS and needs no environment
    checks.append(("uv", "SSL_CERT_FILE", [uv, "pip", "compile", req_file, "--no-cache", "--quiet", "--index-url", base + "/simple/"] if uv else None))
    return checks


def cmd_test(a):
    from urllib.parse import urlsplit
    url = a.url
    if not url.startswith("https://") or not urlsplit(url).hostname:
        raise NetError("give an https URL, e.g. kit-net test https://pypi.org/")
    st = load_state()
    cas = stored_cas()
    env = dict(os.environ)
    env.update(read_env_file())          # what a new terminal will have
    env["GIT_TERMINAL_PROMPT"] = "0"
    py = sys.executable or shutil.which("python3")
    say("testing %s   proxy: %s   company CAs: %d" % (url, mask(st["proxy"]) if st["proxy"] else "none", len(cas)))
    bad = 0
    tmp = tempfile.mkdtemp(prefix="kit-net-")
    req_file = os.path.join(tmp, "requirements.in")
    with open(req_file, "w") as fh:
        fh.write("kit-net-probe-package\n")
    try:
        bad = run_checks(url, py, req_file, env, st, cas)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    stale = [k for k, v in read_env_file().items() if os.environ.get(k) != v]
    if stale:
        say("note: this shell does not have the kit-net variables yet; the checks above used them. Open a new terminal.")
    say("result: %s" % ("all clients work" if not bad else "%d client(s) failed" % bad))
    return 1 if bad else 0


def run_checks(url, py, req_file, env, st, cas):
    bad = 0
    for name, var, cmd in client_checks(url, py, req_file):
        if cmd is None:
            say("skip  %-7s not installed" % name)
            continue
        rc, out = run(cmd, env)
        last = out.splitlines()[-1] if out else ""
        if name == "git":
            # a URL that is not a repository still proves proxy and TLS work
            ok = rc == 0 or bool(re.search(r"not found|404|401|403|could not read Username|Authentication|repository", out, re.I)
                                 and classify(out) not in ("cert", "proxy", "proxy-auth", "dns", "timeout"))
        elif name == "uv":
            ok = rc == 0 or bool(re.search(r"not found in the package registry|unsatisfiable|404|No solution found", out, re.I)
                                 and classify(out) not in ("cert", "proxy", "proxy-auth", "dns", "timeout"))
        else:
            ok = rc == 0
        if ok:
            say("ok    %-7s TLS and network work%s" % (name, "" if name in ("git", "uv") else " (%s)" % last))
            continue
        bad += 1
        kind = classify(out)
        say("FAIL  %-7s %s" % (name, last[:160]))
        say("      -> " + hint(kind, name, var, st, cas))
    return bad


def hint(kind, name, var, st, cas):
    if kind == "cert":
        if not cas:
            return "the certificate is not trusted and no company CA is added. Get the firewall's root certificate from IT: kit-net ca add <file>"
        return ("a company CA is added, but this site's chain does not end in one of them. Check kit-net ca list; ask IT for the "
                "root and intermediate certificates (%s must point to the bundle: kit-net status)" % var)
    if kind == "proxy-auth":
        return "the proxy wants credentials: kit-net proxy set http://user:password@host:port (percent-encode special characters in the password)"
    if kind == "proxy":
        if not st["proxy"]:
            return "a proxy is in the way but none is set: kit-net proxy set http://host:port"
        return "the proxy %s does not tunnel this request. Check host and port with IT, and that the site is allowed" % mask(st["proxy"])
    if kind in ("dns", "timeout"):
        if not st["proxy"]:
            return "no direct connection and no proxy set. If the company network needs one: kit-net proxy set http://host:port"
        return "the proxy is set but the request did not get through: wrong proxy address, host blocked, or name is on the no-proxy list (kit-net status)"
    return "unexpected error; run the client by hand with -v to see more"


def cmd_purge(a):
    msgs = []
    if os.path.isdir(ca_dir()):
        say("backup of the company CAs: %s" % tilde(backup(ca_dir())))
        shutil.rmtree(ca_dir())
    remove_all(msgs)
    if os.path.exists(p_state()):
        os.unlink(p_state())
    for m in msgs:
        say(m)
    say("kit-net: all changes removed")


def build_parser():
    p = argparse.ArgumentParser(prog="kit-net", description="Company network readiness: HTTP(S) proxy and TLS-inspecting firewall. "
                                "Nothing is changed until 'proxy set' or 'ca add' runs; --help changes nothing.")
    p.add_argument("--version", action="version", version="kit-net " + VERSION)
    sub = p.add_subparsers(dest="cmd", metavar="COMMAND")
    sub.required = True

    pr = sub.add_parser("proxy", help="set or remove the HTTP(S) proxy").add_subparsers(dest="sub", metavar="set|unset")
    pr.required = True
    ps = pr.add_parser("set", help="set the proxy", description="Set the proxy for terminals, GUI apps and VS Code.")
    ps.add_argument("url", help="e.g. http://proxy.example.com:8080 (user:password@ allowed)")
    ps.add_argument("--no-proxy", metavar="LIST", help="hosts that skip the proxy, comma separated (localhost, 127.0.0.1 and ::1 always do)")
    ps.set_defaults(fn=cmd_proxy_set)
    pu = pr.add_parser("unset", help="remove the proxy")
    pu.set_defaults(fn=cmd_proxy_unset)

    ca = sub.add_parser("ca", help="add, remove, list company root certificates").add_subparsers(dest="sub", metavar="add|remove|list")
    ca.required = True
    ca_add = ca.add_parser("add", help="add a root CA (PEM, CRT or DER)", description="Validate and store a company CA, then rebuild the bundle.")
    ca_add.add_argument("files", nargs="+", metavar="FILE", help=".pem, .crt, .cer or .der; a PEM may hold several certificates")
    ca_add.add_argument("--system-bundle", metavar="FILE", help="system CA bundle to combine with (default: found automatically)")
    ca_add.set_defaults(fn=cmd_ca_add)
    ca_rm = ca.add_parser("remove", help="remove a company CA")
    ca_rm.add_argument("name", help="file name, part of the subject, or sha256 prefix (see ca list)")
    ca_rm.set_defaults(fn=cmd_ca_remove)
    ca.add_parser("list", help="list company CAs").set_defaults(fn=cmd_ca_list)

    st = sub.add_parser("status", help="show what is set and where")
    st.add_argument("--clients", action="store_true", help="also list how each client picks the settings up")
    st.set_defaults(fn=cmd_status)
    t = sub.add_parser("test", help="request an https URL with python, node, curl, git and uv and say what is missing")
    t.add_argument("url", help="e.g. https://pypi.org/")
    t.set_defaults(fn=cmd_test)
    rf = sub.add_parser("refresh", help="rebuild the combined bundle and all files (after a system CA update)")
    rf.add_argument("--system-bundle", metavar="FILE")
    rf.set_defaults(fn=cmd_refresh)
    sub.add_parser("purge", help="remove everything kit-net wrote (CAs are backed up first)").set_defaults(fn=cmd_purge)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args) or 0
    except NetError as exc:
        print("kit-net: %s" % exc, file=sys.stderr)
        return 1
    except OSError as exc:
        print("kit-net: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
