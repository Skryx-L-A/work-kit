"""kit-models: register company model endpoints for every harness and kit tool.

  kit-models add [--name N --kind openai|azure|anthropic|ollama --base-url URL
                  [--api-version V] --model M [--model M2 ...] [--header 'Name: value' ...]
                  [--key-env VAR] [--no-key] [--data-classes PUBLIC,INTERNAL] [--operator TEXT]
                  [--default] [--targets a,b | --all-targets] [--dry-run]]
                                      without flags: asks for every value
  kit-models list [--json]            endpoints, models, default, data classes
  kit-models test [NAME] [--model M]  tiny request to each model, reports latency
  kit-models remove NAME              removes the endpoint from every target
  kit-models default NAME [--model M] [--also claude,gemini]
                                      default model for harnesses that pick among providers;
                                      --also makes it the endpoint of Claude Code / Gemini CLI
  kit-models sync [--dry-run]         rewrite every target from the registry
  kit-models show NAME [--target T]   the settings for one target, to set by hand
  kit-models targets                  support matrix: target, detected, protocol, mechanism
  kit-models env                      shell lines that export the keys (eval "$(kit-models env)")
  kit-models ask [--name N] [--model M] "prompt"|-  one chat request (stdin with -)
  kit-models proxy start|stop|status|run [--port P]  local translating proxy (127.0.0.1)

Keys are asked once (hidden input) and stored only in the desktop secret store (secret-tool)
or in ~/.config/work-kit/secrets.env (mode 0600). Harness configs reference the env var.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit_models_files as kf  # noqa: E402
import kit_models_proxy as kp  # noqa: E402
import kit_models_targets as kt  # noqa: E402

VERSION = "1.0.0"
KINDS = ("openai", "azure", "anthropic", "ollama")
DATA_CLASSES = ("PUBLIC", "INTERNAL", "CONFIDENTIAL", "CUSTOMER")
DEFAULT_PORT = 4020
SECRET_SERVICE = "work-kit"
ENV_BEGIN = "# work-kit:begin model-endpoints - managed by kit-models"
ENV_END = "# work-kit:end model-endpoints"
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,30}$")


# --- paths and registry -------------------------------------------------------------------------

class App:
    def __init__(self, dry_run: bool = False, quiet: bool = False):
        self.home = Path(os.environ.get("HOME") or Path.home())
        self.ctx = kf.Ctx(self.home, dry_run, quiet)
        self.conf = self.ctx.conf_dir
        self.data = self.ctx.data_dir / "model-endpoints"
        self.registry_file = self.conf / "model-endpoints.json"
        self.secrets_file = self.conf / "secrets.env"
        self.env_file = self.conf / "model-endpoints.sh"
        self.module_dir = Path(__file__).resolve().parent

    # registry ----------------------------------------------------------------------------
    def load(self) -> dict:
        try:
            reg = json.loads(self.registry_file.read_text(encoding="utf-8"))
        except FileNotFoundError:
            reg = {}
        except ValueError as e:
            die(f"{self.registry_file} is not valid JSON ({e}); fix it or restore a copy from ~/.local/share/work-kit/backups/33-model-endpoints/")
        reg.setdefault("version", 1)
        reg.setdefault("endpoints", {})
        reg.setdefault("default", None)
        reg.setdefault("proxy_port", DEFAULT_PORT)
        return reg

    def save(self, reg: dict) -> None:
        text = json.dumps(reg, indent=2, sort_keys=True) + "\n"
        old = self.registry_file.read_text(encoding="utf-8") if self.registry_file.exists() else None
        if old == text:
            return
        # kit-models owns this file (no backup per change); purge keeps one copy
        self.ctx.write_text(self.registry_file, text, 0o600)
        self.ctx.say("update" if old is not None else "create", self.registry_file)

    def proxy_port(self, reg=None) -> int:
        env = os.environ.get("KIT_MODELS_PROXY_PORT")
        if env:
            return int(env)
        return int((reg or self.load()).get("proxy_port") or DEFAULT_PORT)

    def proxy_base(self, name: str, reg=None) -> str:
        return f"http://127.0.0.1:{self.proxy_port(reg)}/e/{name}"

    # local proxy token: random per install, 0600, opens only the local proxy (not an endpoint key)
    @property
    def token_file(self) -> Path:
        return self.data / "proxy.token"

    def proxy_token(self) -> str:
        """The token every request to the local proxy must carry; created on first use.
        A dry run never creates it and returns a stand-in."""
        try:
            tok = self.token_file.read_text(encoding="utf-8").strip()
            if tok:
                return tok
        except OSError:
            pass
        if self.ctx.dry_run:
            return "<new-local-proxy-token>"
        self.data.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.data, 0o700)
        tok = secrets.token_urlsafe(32)
        tmp = self.token_file.with_name(f".proxy.token.{os.getpid()}.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(tok + "\n")
        try:
            os.link(tmp, self.token_file)  # first writer wins, a parallel start reads that token
        except FileExistsError:
            pass
        finally:
            tmp.unlink(missing_ok=True)
        return self.token_file.read_text(encoding="utf-8").strip()


def die(msg: str, code: int = 1):
    print(f"kit-models: {msg}", file=sys.stderr)
    sys.exit(code)


# --- secrets ----------------------------------------------------------------------------------

def secret_tool_usable() -> bool:
    """secret-tool exists and a Secret Service answers (a desktop session, not SSH/CI)."""
    if os.environ.get("KIT_MODELS_NO_SECRET_TOOL") or not shutil.which("secret-tool"):
        return False
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return False
    try:
        r = subprocess.run(["secret-tool", "search", "service", SECRET_SERVICE],
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        return r.returncode in (0, 1)
    except (OSError, subprocess.TimeoutExpired):
        return False


def read_secrets_file(path: Path) -> dict:
    out = {}
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] == "'":
                v = v[1:-1].replace("'\"'\"'", "'")
            out[m.group(1)] = v
    return out


def shell_quote(v: str) -> str:
    return "'" + v.replace("'", "'\"'\"'") + "'"


def store_secret(app: App, var: str, value: str) -> str:
    """Store value under var. Returns where it went. Never prints the value."""
    if app.ctx.dry_run:
        return "nowhere (dry run)"
    if secret_tool_usable():
        r = subprocess.run(["secret-tool", "store", "--label", f"work-kit {var}",
                            "service", SECRET_SERVICE, "key", var],
                           input=value.encode(), capture_output=True, timeout=30)
        if r.returncode == 0:
            remove_secret_line(app, var)
            return "desktop secret store (secret-tool)"
    data = read_secrets_file(app.secrets_file)
    data[var] = value
    write_secrets_file(app, data)
    return str(app.secrets_file)


def write_secrets_file(app: App, data: dict) -> None:
    app.secrets_file.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# work-kit secrets: API keys for kit-models. Mode 0600. Never commit or share.",
             *[f"export {k}={shell_quote(v)}" for k, v in sorted(data.items())]]
    fd = os.open(str(app.secrets_file) + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(str(app.secrets_file) + ".tmp", 0o600)
    os.replace(str(app.secrets_file) + ".tmp", app.secrets_file)


def remove_secret_line(app: App, var: str) -> None:
    data = read_secrets_file(app.secrets_file)
    if var in data:
        del data[var]
        write_secrets_file(app, data)


def delete_secret(app: App, var: str) -> None:
    if app.ctx.dry_run:
        return
    remove_secret_line(app, var)
    if secret_tool_usable():
        subprocess.run(["secret-tool", "clear", "service", SECRET_SERVICE, "key", var],
                       capture_output=True, timeout=10)


def secret_value(app: App, var: str) -> str:
    """Current value: environment, then secrets file, then secret-tool."""
    if not var:
        return ""
    if os.environ.get(var):
        return os.environ[var]
    v = read_secrets_file(app.secrets_file).get(var)
    if v:
        return v
    if secret_tool_usable():
        r = subprocess.run(["secret-tool", "lookup", "service", SECRET_SERVICE, "key", var],
                           capture_output=True, timeout=10)
        if r.returncode == 0:
            return r.stdout.decode().strip()
    return ""


def secret_env(app: App, reg: dict) -> dict:
    """Environment with every endpoint key (for the proxy and `test`)."""
    env = dict(os.environ)
    for ep in reg["endpoints"].values():
        for var in [ep.get("key_env")] + header_vars(ep):
            if var and not env.get(var):
                v = secret_value(app, var)
                if v:
                    env[var] = v
    return env


def header_vars(ep: dict) -> list:
    return sorted({m for v in (ep.get("headers") or {}).values()
                   for m in re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", v)})


# --- env snippet ------------------------------------------------------------------------------

def env_snippet(app: App, reg: dict) -> str:
    """Shell code that exports every key variable; contains no secret values itself."""
    vars_ = sorted({v for ep in reg["endpoints"].values()
                    for v in [ep.get("key_env")] + header_vars(ep) if v})
    lines = ["# work-kit:managed - generated by kit-models, do not edit (no secrets inside)",
             "# Exports the API key variables of the endpoints registered with kit-models.",
             f'if [ -r "{app.secrets_file}" ]; then . "{app.secrets_file}"; fi']
    if vars_:
        lines.append("if command -v secret-tool >/dev/null 2>&1 && [ -n \"${DBUS_SESSION_BUS_ADDRESS:-}\" ]; then")
        for v in vars_:
            lines.append(f'  [ -n "${{{v}:-}}" ] || {v}="$(secret-tool lookup service {SECRET_SERVICE} '
                         f'key {v} 2>/dev/null)"')
        lines.append("fi")
        for v in vars_:
            lines.append(f'[ -n "${{{v}:-}}" ] && export {v}')
    lines.append(f"export KIT_MODELS_PROXY_URL=http://127.0.0.1:{app.proxy_port(reg)}")
    app.proxy_token()  # the token file exists before any shell reads it
    lines.append(f'KIT_MODELS_PROXY_KEY="$(cat "{app.token_file}" 2>/dev/null)"  # local proxy token, not an endpoint key')
    lines.append("export KIT_MODELS_PROXY_KEY")
    for k, v in sorted(getattr(app, "extra_env", {}).items()):
        lines.append(f"export {k}={kt.sh_dq(v)}")
    name = reg.get("default")
    if "copilot" in (reg.get("takeover") or []) and name in reg["endpoints"]:
        lines.append("# Copilot CLI uses the default endpoint (kit-models default --also copilot)")
        for k, v in kt.CopilotCli(app).env_for(name, reg["endpoints"][name], reg).items():
            lines.append(f"export {k}={kt.sh_dq(v)}")
    if reg.get("proxy_autostart", True) and kt.uses_proxy(app, reg):
        pidf = app.data / "proxy.pid"
        kit = app.ctx.bin_dir / "kit-models"
        lines += ["# start the local proxy once per login (kit-models proxy stop; KIT_MODELS_NO_AUTOSTART=1)",
                  f'if [ -z "${{KIT_MODELS_NO_AUTOSTART:-}}" ] && [ -x "{kit}" ]; then',
                  f'  _kp=$(cat "{pidf}" 2>/dev/null)',
                  '  if [ -z "$_kp" ] || ! kill -0 "$_kp" 2>/dev/null; then',
                  f'    ( "{kit}" proxy start >/dev/null 2>&1 & )',
                  "  fi",
                  "  unset _kp",
                  "fi"]
    return "\n".join(lines) + "\n"


def sync_env(app: App, reg: dict, shell_rc: bool = True) -> None:
    kf.write_managed_file(app.ctx, app.env_file, env_snippet(app, reg),
                          "# work-kit:managed - generated by kit-models, do not edit (no secrets inside)",
                          0o644)
    if not shell_rc:
        return
    line = f'[ -r "{app.env_file}" ] && . "{app.env_file}"'
    for rc in (app.home / ".bashrc", app.home / ".profile", app.home / ".zshrc"):
        if rc.name == ".zshrc" and not rc.exists():
            continue
        kf.set_region(app.ctx, rc, ENV_BEGIN, ENV_END, line if reg["endpoints"] else "")


# --- helpers ----------------------------------------------------------------------------------

def default_key_env(name: str) -> str:
    return "KIT_MODEL_" + re.sub(r"[^A-Z0-9]", "_", name.upper()) + "_KEY"


def parse_header(h: str):
    if ":" in h:
        k, v = h.split(":", 1)
    elif "=" in h:
        k, v = h.split("=", 1)
    else:
        die(f"header '{h}' must look like 'Name: value' (value may be ${{VAR}})")
    k, v = k.strip(), v.strip()
    if not re.fullmatch(r"[A-Za-z0-9-]+", k):
        die(f"bad header name '{k}'")
    return k, v


def looks_secret(value: str) -> bool:
    """A header value that looks like a credential must come from a variable."""
    if "${" in value:
        return False
    return bool(re.search(r"(?i)^(bearer|basic)\s+\S{8,}$", value)) or (
        len(value) >= 20 and re.fullmatch(r"[A-Za-z0-9_\-.=+/]+", value) is not None
        and re.search(r"\d", value) is not None and re.search(r"[A-Za-z]", value) is not None)


def ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    try:
        v = input(f"{prompt}{suffix}: ").strip()
    except EOFError:
        v = ""
    return v or default


def http_json(url: str, headers: dict = None, timeout: float = 10):
    req = urllib.request.Request(url, headers=headers or {})
    with kp._opener(url).open(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


# --- commands ---------------------------------------------------------------------------------

DATA_CLASS_REMINDER = """\
Data classes (40-data-guard, ~/.config/work-kit/data-classes.md):
  PUBLIC, INTERNAL, CONFIDENTIAL, CUSTOMER. Send a class to this endpoint only if IT
  confirmed that it may receive it. Who operates it? Where does it run? Are prompts logged
  or used for training? When unsure: PUBLIC only, and ask IT."""


def cmd_add(app: App, a) -> int:
    reg = app.load()
    interactive = a.name is None
    if interactive:
        if not sys.stdin.isatty():
            die("add without --name needs a terminal; pass --name, --kind, --base-url, --model")
        print("Register a company model endpoint. Ctrl-C cancels; nothing is written before the end.")
        a.name = ask("Short name (lowercase, e.g. company-llm)")
        a.kind = ask("Kind: openai (vLLM, LiteLLM, TGI, llama.cpp, gateways), azure, anthropic, ollama",
                     "openai")
        a.base_url = ask("Base URL (e.g. https://llm.example.internal/v1)")
        if a.kind == "azure":
            a.api_version = ask("Azure api-version", "2024-10-21")
        a.model = [m.strip() for m in ask("Model ids, comma separated").split(",") if m.strip()]
        hdr = ask("Extra headers, ';' separated ('Name: value', value may be ${VAR})", "")
        a.header = [h for h in hdr.split(";") if h.strip()]
        a.operator = ask("Who operates it (e.g. Work kit IT, on-premises)", "")
        print(DATA_CLASS_REMINDER)
        a.data_classes = ask("Data classes IT allowed for it", "PUBLIC")
    if not a.name or not NAME_RE.match(a.name):
        die("--name: lowercase letters, digits and '-', starting with a letter, max 31 chars")
    if a.name in kt.RESERVED:
        die(f"'{a.name}' is a built-in provider name of some harness; choose another (e.g. company-llm)")
    if a.kind not in KINDS:
        die(f"--kind must be one of {', '.join(KINDS)}")
    if not a.base_url or not re.match(r"^https?://", a.base_url):
        die("--base-url must start with http:// or https://")
    if not a.model:
        die("at least one --model is needed")
    classes = [c.strip().upper() for c in (a.data_classes or "PUBLIC").split(",") if c.strip()]
    bad = [c for c in classes if c not in DATA_CLASSES]
    if bad:
        die(f"unknown data class {', '.join(bad)} (use {', '.join(DATA_CLASSES)})")
    headers = dict(parse_header(h) for h in (a.header or []))
    for k, v in headers.items():
        if looks_secret(v):
            die(f"header {k} looks like a credential. Put it in a variable: "
                f"--header '{k}: ${{{default_key_env(a.name)[:-4]}_{k.upper().replace('-', '_')}}}' "
                "and run add interactively (it asks for the value), or export the variable")
    existed = a.name in reg["endpoints"]
    key_env = None if a.no_key else (a.key_env or default_key_env(a.name))
    if key_env and not re.fullmatch(r"[A-Z_][A-Z0-9_]*", key_env):
        die("--key-env must be an upper-case variable name (the variable holds the key, not the key)")
    ep = {"kind": a.kind, "base_url": a.base_url.rstrip("/"), "models": list(dict.fromkeys(a.model)),
          "headers": headers, "key_env": key_env, "data_classes": classes,
          "operator": a.operator or "", "added": time.strftime("%Y-%m-%d")}
    if a.kind == "azure":
        ep["api_version"] = a.api_version or "2024-10-21"
    if a.responses:
        ep["responses"] = True
    if a.context_window:
        ep["context_window"] = a.context_window
    if a.targets:
        ep["targets"] = [t.strip() for t in a.targets.split(",") if t.strip()]
        unknown = [t for t in ep["targets"] if t not in kt.BY_NAME]
        if unknown:
            die(f"unknown target(s) {', '.join(unknown)}; see kit-models targets")
    elif a.all_targets:
        ep["targets"] = ["all"]
    reg["endpoints"][a.name] = ep
    if a.default or not reg.get("default") or reg["default"] not in reg["endpoints"]:
        reg["default"] = a.name
        reg["default_model"] = ep["models"][0]
        # harness defaults (codex, opencode, pi, aider) change only on an explicit request
        reg["default_explicit"] = bool(a.default)

    if not interactive:
        print(DATA_CLASS_REMINDER)
    print(f"'{a.name}' may receive: {', '.join(classes)}"
          + (f"; operated by: {ep['operator']}" if ep["operator"] else ""))

    # key: asked once, hidden; never echoed or written into a harness config
    if key_env:
        have = secret_value(app, key_env)
        if have and not a.new_key:
            print(f"Key: {key_env} is already set (use --new-key to replace it).")
        elif sys.stdin.isatty() and not a.dry_run:
            v = getpass.getpass(f"API key for {a.name} (hidden; empty = set {key_env} yourself later): ")
            if v:
                print(f"Key stored in {store_secret(app, key_env, v.strip())} as {key_env}.")
        else:
            print(f"Key: set {key_env} (kit-models add --name {a.name} ... --new-key in a terminal, "
                  f"or add 'export {key_env}=...' to {app.secrets_file}, mode 0600).")
    for var in header_vars(ep):
        if not secret_value(app, var) and sys.stdin.isatty() and not a.dry_run:
            v = getpass.getpass(f"Value of {var} for a header (hidden, empty = later): ")
            if v:
                print(f"Stored in {store_secret(app, var, v.strip())} as {var}.")

    app.save(reg)
    kt.sync_all(app, reg, only=None)
    sync_env(app, reg, not a.no_shell_rc)
    app.ctx.save_state()
    print(f"{'Updated' if existed else 'Added'} endpoint '{a.name}'. Next: kit-models test {a.name}"
          + ("" if os.environ.get(key_env or "_", "") else
             f"  (new shells get {key_env}; this one: . {app.env_file})" if key_env else ""))
    return 0


def cmd_list(app: App, a) -> int:
    reg = app.load()
    if a.json:
        print(json.dumps(reg, indent=2, sort_keys=True))
        return 0
    if not reg["endpoints"]:
        print("No endpoints. Add one: kit-models add")
        return 0
    for name, ep in sorted(reg["endpoints"].items()):
        star = " (default)" if name == reg.get("default") else ""
        key = ep.get("key_env") or "none"
        state = "set" if ep.get("key_env") and secret_value(app, ep["key_env"]) else "MISSING"
        print(f"{name}{star}: {ep['kind']} {ep['base_url']}"
              + (f" api-version {ep['api_version']}" if ep.get("api_version") else ""))
        print(f"  models: {', '.join(ep['models'])}")
        print(f"  key: {key}" + (f" ({state})" if ep.get("key_env") else ""))
        if ep.get("headers"):
            print(f"  headers: {', '.join(ep['headers'])}")
        print(f"  data classes: {', '.join(ep.get('data_classes') or ['PUBLIC'])}"
              + (f"; operator: {ep['operator']}" if ep.get("operator") else ""))
    print(f"proxy: {app.proxy_base('<name>', reg)}  ({'running' if proxy_pid(app) else 'stopped'})")
    return 0


def tiny_request(app: App, ep: dict, model: str, env: dict, prompt: str = "Reply with the word OK.",
                 max_tokens: int = 16, timeout: float = 60):
    proto = kp.upstream_protocol(ep)
    body = {"model": model, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}]}
    if proto == "openai":
        body["temperature"] = 0
    res = kp.call(ep, proto, body, timeout, env)
    if proto == "anthropic":
        text = "".join(b.get("text", "") for b in res.get("content") or [] if b.get("type") == "text")
    else:
        msg = (res.get("choices") or [{}])[0].get("message") or {}
        text = kp._text_of(msg.get("content")) or msg.get("reasoning_content") or ""
    return text.strip()


def cmd_test(app: App, a) -> int:
    reg = app.load()
    names = [a.name] if a.name else sorted(reg["endpoints"])
    if not names:
        die("no endpoints registered")
    env = secret_env(app, reg)
    failed = 0
    for name in names:
        ep = reg["endpoints"].get(name) or die(f"unknown endpoint '{name}'")
        if ep.get("key_env") and not env.get(ep["key_env"]):
            print(f"{name}: key {ep['key_env']} is not set; the request will likely be refused")
        for model in ([a.model] if a.model else ep["models"]):
            t0 = time.time()
            try:
                text = tiny_request(app, ep, model, env, timeout=a.timeout)
                ms = (time.time() - t0) * 1000
                print(f"ok    {name}/{model}  {ms:.0f} ms  answer: {text[:60]!r}")
            except kp.UpstreamError as e:
                failed += 1
                detail = e.body.decode("utf-8", "replace").strip().replace("\n", " ")[:200]
                print(f"FAIL  {name}/{model}  HTTP {e.status}: {detail}")
            except (OSError, ValueError, KeyError, IndexError) as e:
                failed += 1
                print(f"FAIL  {name}/{model}  {e.__class__.__name__}: {e}")
        if a.proxy:
            failed += test_via_proxy(app, reg, name, ep, env, a.timeout)
    return 1 if failed else 0


def test_via_proxy(app: App, reg, name, ep, env, timeout) -> int:
    """The same tiny request in each client protocol, through the running proxy."""
    if not proxy_pid(app):
        print(f"proxy   {name}: not running (kit-models proxy start); skipped")
        return 0
    failed = 0
    base = app.proxy_base(name, reg)
    probes = {
        "openai": (base + "/v1/chat/completions",
                   {"model": ep["models"][0], "max_tokens": 16,
                    "messages": [{"role": "user", "content": "Reply with OK."}]}),
        "anthropic": (base + "/v1/messages",
                      {"model": ep["models"][0], "max_tokens": 16,
                       "messages": [{"role": "user", "content": "Reply with OK."}]}),
        "gemini": (base + f"/v1beta/models/{ep['models'][0]}:generateContent",
                   {"contents": [{"role": "user", "parts": [{"text": "Reply with OK."}]}],
                    "generationConfig": {"maxOutputTokens": 16}}),
    }
    for proto, (url, body) in probes.items():
        t0 = time.time()
        try:
            kp.post_json(url, {"Content-Type": "application/json",
                               "Authorization": "Bearer " + app.proxy_token()}, body, timeout)
            print(f"ok    proxy {proto:9} {name}  {(time.time() - t0) * 1000:.0f} ms")
        except kp.UpstreamError as e:
            failed += 1
            print(f"FAIL  proxy {proto:9} {name}  HTTP {e.status}: "
                  f"{e.body.decode('utf-8', 'replace')[:160]}")
        except OSError as e:
            failed += 1
            print(f"FAIL  proxy {proto:9} {name}  {e}")
    return failed


def cmd_remove(app: App, a) -> int:
    reg = app.load()
    ep = reg["endpoints"].get(a.name)
    if ep is None:
        die(f"unknown endpoint '{a.name}'")
    kt.remove_all(app, reg, a.name)
    del reg["endpoints"][a.name]
    if reg.get("default") == a.name:
        reg["default"] = next(iter(sorted(reg["endpoints"])), None)
        reg["default_model"] = reg["endpoints"][reg["default"]]["models"][0] if reg["default"] else None
        reg["default_explicit"] = False
    for var in [ep.get("key_env")] + header_vars(ep):
        if var and not a.keep_key and not any(
                var in [e.get("key_env")] + header_vars(e) for e in reg["endpoints"].values()):
            delete_secret(app, var)
            app.ctx.say("remove", f"secret {var}")
    if reg.get("default") != ep and not reg["endpoints"]:
        reg["takeover"] = []
    app.save(reg)
    kt.sync_all(app, reg, only=None)
    sync_env(app, reg, True)
    app.ctx.save_state()
    print(f"Removed '{a.name}'.")
    return 0


def cmd_default(app: App, a) -> int:
    reg = app.load()
    ep = reg["endpoints"].get(a.name) or die(f"unknown endpoint '{a.name}'")
    model = a.model or ep["models"][0]
    if model not in ep["models"]:
        die(f"'{model}' is not a model of {a.name} ({', '.join(ep['models'])})")
    reg["default"], reg["default_model"], reg["default_explicit"] = a.name, model, True
    also = [x.strip() for x in (a.also or "").split(",") if x.strip()]
    for x in also:
        if x not in kt.TAKEOVER:
            die(f"--also takes {', '.join(sorted(kt.TAKEOVER))}")
    reg["takeover"] = sorted(set(reg.get("takeover") or []) | set(also)) if also else reg.get("takeover", [])
    if a.no_also:
        reg["takeover"] = []
    app.save(reg)
    kt.sync_all(app, reg, only=None)
    sync_env(app, reg, True)
    app.ctx.save_state()
    for t in reg["takeover"]:
        print(f"{t}: now uses {a.name}/{model} (undo: kit-models default {a.name} --no-also)")
    print(f"Default: {a.name}/{model}.")
    return 0


def cmd_sync(app: App, a) -> int:
    reg = app.load()
    kt.sync_all(app, reg, only=a.targets.split(",") if a.targets else None)
    sync_env(app, reg, not a.no_shell_rc)
    app.ctx.save_state()
    return 0


def cmd_purge(app: App, a) -> int:
    """Remove every endpoint from every target, then registry, keys and snippet (uninstall --purge)."""
    reg = app.load()
    names = list(reg["endpoints"])
    for name in names:
        ep = reg["endpoints"].pop(name)
        for var in [ep.get("key_env")] + header_vars(ep):
            if var:
                delete_secret(app, var)
    reg["takeover"], reg["default"] = [], None
    kt.sync_all(app, reg, only=None)
    sync_env(app, reg, True)
    kf.remove_managed_file(app.ctx, app.env_file, "# work-kit:managed")
    kf.remove_managed_file(app.ctx, kt.key_helper_path(app), kt.WRAP_MARK)
    if app.registry_file.exists():
        app.ctx.backup(app.registry_file)
        app.registry_file.unlink()
        app.ctx.say("remove", app.registry_file, "backup kept (no keys inside)")
    if app.secrets_file.exists() and not read_secrets_file(app.secrets_file):
        app.secrets_file.unlink()
    app.ctx.state["targets"] = {}
    app.ctx.state_dirty = True
    app.ctx.save_state()
    print(f"Purged {len(names)} endpoint(s).")
    return 0


def cmd_show(app: App, a) -> int:
    reg = app.load()
    if a.name not in reg["endpoints"]:
        die(f"unknown endpoint '{a.name}'")
    print(kt.show(app, reg, a.name, a.target))
    return 0


def cmd_targets(app: App, a) -> int:
    print(kt.matrix(app))
    return 0


def cmd_env(app: App, a) -> int:
    reg = app.load()
    sys.stdout.write(env_snippet(app, reg))
    return 0


def cmd_ask(app: App, a) -> int:
    reg = app.load()
    name = a.name or reg.get("default")
    ep = reg["endpoints"].get(name or "") or die("no endpoint (kit-models add, or give a name)")
    model = a.model or (reg.get("default_model") if name == reg.get("default") else None) or ep["models"][0]
    prompt = sys.stdin.read() if a.prompt == "-" else a.prompt
    print(f"[kit-models] {name}/{model} may receive: {', '.join(ep.get('data_classes') or ['PUBLIC'])}",
          file=sys.stderr)
    try:
        print(tiny_request(app, ep, model, secret_env(app, reg), prompt, a.max_tokens, a.timeout))
    except kp.UpstreamError as e:
        die(f"HTTP {e.status}: {e.body.decode('utf-8', 'replace')[:300]}")
    return 0


# --- proxy process ----------------------------------------------------------------------------

def pid_file(app: App) -> Path:
    return app.data / "proxy.pid"


def proxy_pid(app: App):
    try:
        pid = int(pid_file(app).read_text().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return None
    try:  # the pid must still be our proxy, not a reused number
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
        return pid if "proxy" in cmd and "kit" in cmd else None
    except OSError:
        r = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
        return pid if "proxy" in r.stdout and "kit" in r.stdout else None


def proxy_health(port: int, token: str = None, timeout: float = 1.0) -> bool:
    """True when a proxy that knows `token` answers on the port."""
    try:
        h = {"Authorization": "Bearer " + token} if token else {}
        return bool(http_json(f"http://127.0.0.1:{port}/health", h, timeout=timeout).get("ok"))
    except (OSError, ValueError):
        return False


def proxy_requires_token(port: int, timeout: float = 1.0) -> bool:
    """False for a proxy from before local tokens (it answers /health without one)."""
    try:
        http_json(f"http://127.0.0.1:{port}/health", timeout=timeout)
        return False
    except urllib.error.HTTPError as e:
        return e.code == 401
    except (OSError, ValueError):
        return True


def cmd_proxy(app: App, a) -> int:
    reg = app.load()
    port = a.port or app.proxy_port(reg)
    if a.action == "run":
        def loader(cache={"m": None, "eps": {}}):
            try:
                m = app.registry_file.stat().st_mtime
            except OSError:
                return {}
            if m != cache["m"]:
                r = app.load()
                cache["eps"], cache["m"] = r["endpoints"], m
                refresh_keys(r)
            return cache["eps"]

        def refresh_keys(r):  # keys live only in this process's memory
            for ep in r["endpoints"].values():
                for var in [ep.get("key_env")] + header_vars(ep):
                    v = var and secret_value(app, var)
                    if v:
                        os.environ[var] = v
        def token_loader(cache={"m": None, "tok": None}):
            try:
                m = app.token_file.stat().st_mtime_ns
            except OSError:
                return None  # no token file: every request is refused
            if m != cache["m"]:
                cache["tok"], cache["m"] = app.token_file.read_text(encoding="utf-8").strip(), m
            return cache["tok"]
        app.proxy_token()
        refresh_keys(reg)
        print(f"kit-models proxy on http://127.0.0.1:{port}/e/<endpoint> (local token required)", flush=True)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        kp.serve(port, loader, token_loader=token_loader)
        return 0
    if a.action == "status":
        pid = proxy_pid(app)
        ok = proxy_health(port, app.proxy_token())
        print(f"proxy: {'running pid ' + str(pid) if pid else 'stopped'}, "
              f"http://127.0.0.1:{port} {'answers' if ok else 'does not answer'}")
        return 0 if pid and ok else 3
    if a.action == "stop":
        pid = proxy_pid(app)
        if not pid:
            print("proxy: not running")
            pid_file(app).unlink(missing_ok=True)
            return 0
        os.kill(pid, signal.SIGTERM)
        for _ in range(50):
            try:
                os.kill(pid, 0)
            except OSError:
                break
            time.sleep(0.1)
        else:
            os.kill(pid, signal.SIGKILL)
        pid_file(app).unlink(missing_ok=True)
        print(f"proxy: stopped pid {pid}")
        return 0
    # start
    token = app.proxy_token()
    if proxy_pid(app) and proxy_health(port, token):
        print(f"proxy: already running on http://127.0.0.1:{port}")
        return 0
    if proxy_pid(app) and not proxy_requires_token(port):
        print("proxy: running without local token (older version); restarting it")
        cmd_proxy(app, argparse.Namespace(action="stop", port=port))
    if not kp.port_free(port):
        die(f"port {port} is in use; choose another: kit-models proxy start --port N "
            "(then kit-models sync)")
    app.data.mkdir(parents=True, exist_ok=True)
    log = open(app.data / "proxy.log", "ab")
    cmd = [sys.executable, str(Path(__file__).resolve()), "proxy", "run", "--port", str(port)]
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                         start_new_session=True, close_fds=True)
    pid_file(app).write_text(str(p.pid))
    for _ in range(50):
        if proxy_health(port, token):
            print(f"proxy: started pid {p.pid} on http://127.0.0.1:{port} (log {app.data / 'proxy.log'})")
            return 0
        if p.poll() is not None:
            break
        time.sleep(0.1)
    die(f"proxy did not start; see {app.data / 'proxy.log'}")


# --- CLI --------------------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="kit-models", description=__doc__.split("\n\n")[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog=__doc__.split("\n\n", 1)[1])
    p.add_argument("--version", action="version", version=f"kit-models {VERSION}")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("add", help="register or update an endpoint (asks when no flags)")
    s.add_argument("--name")
    s.add_argument("--kind", choices=KINDS, default="openai")
    s.add_argument("--base-url")
    s.add_argument("--api-version")
    s.add_argument("--model", action="append")
    s.add_argument("--header", action="append", help="'Name: value'; value may be ${VAR}")
    s.add_argument("--key-env", help="variable that holds the key (default KIT_MODEL_<NAME>_KEY)")
    s.add_argument("--no-key", action="store_true", help="endpoint needs no key")
    s.add_argument("--new-key", action="store_true", help="ask for the key again")
    s.add_argument("--data-classes", help="comma list of PUBLIC,INTERNAL,CONFIDENTIAL,CUSTOMER")
    s.add_argument("--operator", help="who operates the endpoint")
    s.add_argument("--default", action="store_true", help="also the default of codex, opencode, pi, aider")
    s.add_argument("--responses", action="store_true",
                   help="the endpoint serves the OpenAI Responses API (Codex then talks to it directly)")
    s.add_argument("--context-window", type=int, help="context size of the models in tokens")
    s.add_argument("--targets", help="only these targets (see kit-models targets)")
    s.add_argument("--all-targets", action="store_true", help="also targets that are not detected")
    s.add_argument("--no-shell-rc", action="store_true", help="do not touch ~/.bashrc, ~/.profile")
    s.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("list")
    s.add_argument("--json", action="store_true")

    s = sub.add_parser("test")
    s.add_argument("name", nargs="?")
    s.add_argument("--model")
    s.add_argument("--timeout", type=float, default=60)
    s.add_argument("--proxy", action="store_true", help="also test the three proxy protocols")

    s = sub.add_parser("remove")
    s.add_argument("name")
    s.add_argument("--keep-key", action="store_true")
    s.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("default")
    s.add_argument("name")
    s.add_argument("--model")
    s.add_argument("--also", help=f"also switch {', '.join(sorted(kt.TAKEOVER))} to this endpoint")
    s.add_argument("--no-also", action="store_true", help="give Claude Code / Gemini CLI back their login")
    s.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("sync")
    s.add_argument("--targets")
    s.add_argument("--no-shell-rc", action="store_true")
    s.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("show")
    s.add_argument("name")
    s.add_argument("--target")

    sub.add_parser("targets")
    sub.add_parser("purge", help=argparse.SUPPRESS)
    sub.add_parser("env")

    s = sub.add_parser("ask")
    s.add_argument("prompt", help="the prompt, or - for stdin")
    s.add_argument("--name")
    s.add_argument("--model")
    s.add_argument("--max-tokens", type=int, default=1024)
    s.add_argument("--timeout", type=float, default=300)

    s = sub.add_parser("proxy")
    s.add_argument("action", choices=["start", "stop", "status", "run"])
    s.add_argument("--port", type=int)
    return p


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    app = App(dry_run=getattr(a, "dry_run", False))
    cmd = {"add": cmd_add, "list": cmd_list, "test": cmd_test, "remove": cmd_remove,
           "default": cmd_default, "sync": cmd_sync, "show": cmd_show, "targets": cmd_targets,
           "env": cmd_env, "ask": cmd_ask, "proxy": cmd_proxy, "purge": cmd_purge}[a.cmd]
    try:
        return cmd(app, a) or 0
    except KeyboardInterrupt:
        print("\ncancelled; nothing written", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
