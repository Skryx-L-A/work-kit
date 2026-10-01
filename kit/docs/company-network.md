# Company network (35-company-network, `kit-net`)

At a company the laptop usually reaches the internet through an HTTP(S) proxy, and a firewall may
re-sign HTTPS traffic with its own root CA. Every client then fails with a proxy or certificate error
until it is told about both. `kit-net` sets the standard variables once and hooks them into terminals,
GUI apps and VS Code. Nothing is set until `kit-net proxy set` or `kit-net ca add` runs; `kit-net proxy
unset`, `ca remove` or `uninstall.sh` take everything back (files are restored byte for byte, the CAs
are backed up first).

## What is written

| Where | What |
|---|---|
| `~/.config/work-kit/net.env` (0600) | `export` lines, sourced by terminals |
| `~/.config/environment.d/60-work-kit-net.conf` (0600) | same values for GUI apps and systemd user services, read at login |
| top of `~/.bashrc` and the login file (`.bash_profile`, `.bash_login` or `.profile`) | one marked block that sources `net.env`; on top, so Ubuntu's interactive-only guard cannot skip it |
| VS Code `~/.config/Code/User/settings.json` | marked block with `http.proxy` and `http.noProxy`, only with a proxy and when the folder exists; a file that sets `http.proxy` itself is left alone |
| `~/.config/work-kit/ca/*.pem` | the company CAs, one file each, named by subject and fingerprint |
| `ca-bundle.pem`, `ca-company.pem` | system bundle plus company CAs; company CAs only |

Every change to a file of yours is preceded by a backup below `~/.local/share/work-kit/backups/35-company-network/`.
`NO_PROXY` always holds `localhost,127.0.0.1,::1`, so the kit's local services (`kit-llm`, the
`kit-models` proxy, the brain MCP server) never go through the company proxy.

## Variables per client

Proxy (all clients): `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, each also in lower case. CA: `SSL_CERT_FILE`,
`REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `PIP_CERT`, `GIT_SSL_CAINFO`, `NPM_CONFIG_CAFILE`,
`CODEX_CA_CERTIFICATE`, `CARGO_HTTP_CAINFO`, `BUNDLE_SSL_CA_CERT` (all the combined bundle) and
`NODE_EXTRA_CA_CERTS` (the company CAs only, Node adds them to its own list). `kit-net status --clients` prints this.

| Client | Uses | Checked in |
|---|---|---|
| Claude Code | `HTTPS_PROXY`/`NO_PROXY` (URL with scheme, no SOCKS), `NODE_EXTRA_CA_CERTS`; `CLAUDE_CODE_CERT_STORE` selects bundled/system stores | 2.1.283 binary strings; https://code.claude.com/docs/en/network-config |
| Codex (Rust) | proxy variables; `CODEX_CA_CERTIFICATE`, else `SSL_CERT_FILE`; hands `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `GIT_SSL_CAINFO`, `CARGO_HTTP_CAINFO`, `BUNDLE_SSL_CA_CERT`, `npm_config_cafile` on to its commands | 0.157.1 binary strings |
| Gemini CLI | proxy variables; `NODE_EXTRA_CA_CERTS` (or `NODE_USE_SYSTEM_CA=1`) | https://geminicli.com/docs/resources/troubleshooting/ |
| opencode | proxy variables; `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` | 1.18.32 binary strings |
| pi | proxy variables (undici `EnvHttpProxyAgent`); `NODE_EXTRA_CA_CERTS` | 0.87 package |
| Aider | proxy variables (httpx); `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE` (litellm) | https://docs.litellm.ai/docs/guides/security_settings |
| Copilot CLI | proxy variables; `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` | 1.0.88 binary strings |
| VS Code | `http.proxy`/`http.noProxy` (block above), else the environment; `NODE_EXTRA_CA_CERTS`; `http.systemCertificates` stays at its default | https://code.visualstudio.com/docs/setup/network |
| uv | proxy variables; `SSL_CERT_FILE` (`UV_NATIVE_TLS` prints a deprecation warning in uv 0.11.28, so it is not set) | tested with uv 0.11.28 |
| python, pip, requests, curl, git, npm | the variables in the list above | tested |

## Test and status

`kit-net test <https-url>` requests the URL with python, node, curl, git and uv using the settings a new
terminal will have, says for each client whether TLS and the route work, and names what is missing
(no CA added, no proxy set, proxy needs credentials, host not tunnelled). `kit-net status` shows the
proxy (password hidden), the CAs, where the settings are applied, whether the system CA bundle changed
since the combined bundle was built (`kit-net refresh`), and whether the current shell has the values.

## Limits

- Proxy auto-config (PAC/WPAD) and NTLM/Kerberos-only proxies are not handled: ask IT for a fixed proxy
  host and port, or a local forwarder. Credentials in the URL are stored in 0600 files; percent-encode
  special characters.
- ssh remotes of git need a `ProxyCommand` in `~/.ssh/config`; `apt`, `snap` and the system trust store
  need root and are out of scope. Browsers use the system or NSS store, not these files.
- A root CA is trusted only in the tools above; intermediate CAs need their root next to them.
- Python builds linked against LibreSSL (Apple's macOS Python) ignore `SSL_CERT_FILE`; Ubuntu's do not.
- Values reach a shell only when it starts: open a new terminal, and log out and in for GUI apps.

## Verification (2026-09-26, macOS 26)

`tests/test-net.sh` (local HTTPS server signed by a throw-away CA, a CONNECT proxy that resolves every
name to loopback): python, node and curl fail with a certificate error before `ca add` and work after
it; through the proxy with `proxy set` (the proxy log shows python, node, curl and git connections,
`localhost` bypasses it); `kit-net test` output; idempotent rerun; `~/.bashrc` and `settings.json`
byte-identical after removal; help runs change nothing. Not run on Linux yet.
