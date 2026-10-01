"""Tests for kit-models: registry, targets, secrets, proxy. Temp HOMEs, fake servers, no network.

Run: python3 -m unittest discover -s tests   (from the module folder)
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

import kit_models as km  # noqa: E402
import kit_models_proxy as kp  # noqa: E402
from fake_servers import Fake  # noqa: E402

KEY = "sk-test-123"
LOCAL_TOKEN = "local-token-for-tests"


class Home:
    """A temp HOME with fake harness binaries on PATH and a clean environment."""

    def __init__(self, bins=("claude", "codex", "opencode", "gemini", "copilot", "aider", "pi",
                             "evalkit", "meeting", "llm-usage")):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.bin = self.home / "fakebin"
        self.bin.mkdir()
        for b in bins:
            p = self.bin / b
            p.write_text("#!/bin/sh\nexit 0\n")
            p.chmod(0o755)
        for d in (".claude", ".codex", ".config/opencode", ".pi/agent", ".continue", ".gemini",
                  ".config/Code/User"):
            (self.home / d).mkdir(parents=True, exist_ok=True)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("KIT_", "XDG_", "CODEX_", "CLAUDE_", "COPILOT_", "PI_", "WB_"))}
        env.update(HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin",
                   KIT_MODELS_NO_SECRET_TOOL="1")
        self.patch = mock.patch.dict(os.environ, env, clear=True)

    def __enter__(self):
        self.patch.start()
        return self

    def __exit__(self, *exc):
        self.patch.stop()
        self.tmp.cleanup()

    def run(self, *argv, stdin_tty=False, getpass_value=None) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out), \
                mock.patch("sys.stdin.isatty", return_value=stdin_tty), \
                mock.patch("getpass.getpass", return_value=getpass_value or ""):
            code = km.main(list(argv))
        if code:
            raise AssertionError(f"kit-models {' '.join(argv)} -> {code}\n{out.getvalue()}")
        return out.getvalue()

    def read(self, rel: str) -> str:
        return (self.home / rel).read_text()

    def json(self, rel: str):
        return json.loads(self.read(rel))

    def all_text(self, exclude=("secrets.env",)) -> str:
        out = []
        for p in self.home.rglob("*"):
            if p.is_file() and p.name not in exclude and "fakebin" not in p.parts:
                try:
                    out.append(p.read_text())
                except UnicodeDecodeError:
                    pass
        return "\n".join(out)


def add_args(name="corp", kind="openai", url="https://llm.example.test/v1", models=("m1",), *extra):
    a = ["add", "--name", name, "--kind", kind, "--base-url", url]
    for m in models:
        a += ["--model", m]
    return a + list(extra)


class RegistryAndSecrets(unittest.TestCase):
    def test_add_stores_key_only_in_0600_file(self):
        with Home() as h:
            h.run(*add_args(), stdin_tty=True, getpass_value=KEY)
            sec = h.home / ".config/work-kit/secrets.env"
            self.assertEqual(stat.S_IMODE(sec.stat().st_mode), 0o600)
            self.assertIn(KEY, sec.read_text())
            self.assertNotIn(KEY, h.all_text())  # no harness config, wrapper or registry has it
            reg = h.json(".config/work-kit/model-endpoints.json")
            self.assertEqual(reg["endpoints"]["corp"]["key_env"], "KIT_MODEL_CORP_KEY")
            self.assertEqual(stat.S_IMODE((h.home / ".config/work-kit/model-endpoints.json").stat().st_mode), 0o600)

    def test_rejects_literal_credential_header_and_reserved_names(self):
        with Home() as h:
            with self.assertRaises(SystemExit):
                h.run(*add_args("corp", "openai", "https://x.test/v1", ("m",),
                                "--header", "Authorization: Bearer abcdef1234567890xyz"))
            with self.assertRaises(SystemExit):
                h.run(*add_args("openai"))
            with self.assertRaises(SystemExit):
                h.run(*add_args("corp", "openai", "https://x.test/v1", ("m",), "--key-env", "sk-live-abc"))

    def test_env_snippet_exports_keys_without_values(self):
        with Home() as h:
            h.run(*add_args("corp", "openai", "https://x.test/v1", ("m",),
                            "--header", "X-Tenant: ${CORP_TENANT}"), stdin_tty=True, getpass_value=KEY)
            snippet = h.read(".config/work-kit/model-endpoints.sh")
            self.assertIn("export KIT_MODEL_CORP_KEY", snippet)
            self.assertIn("CORP_TENANT", snippet)
            self.assertNotIn(KEY, snippet)
            self.assertIn("model-endpoints.sh", h.read(".bashrc"))
            self.assertIn("model-endpoints.sh", h.read(".profile"))


class Targets(unittest.TestCase):
    def test_every_detected_target_is_written(self):
        with Home() as h:
            h.run(*add_args("corp", "openai", "https://llm.example.test/v1", ("m1", "m2"),
                            "--header", "X-Team: ai", "--context-window", "32768"))
            oc = h.json(".config/opencode/opencode.json")["provider"]["corp"]
            self.assertEqual(oc["options"]["apiKey"], "{env:KIT_MODEL_CORP_KEY}")
            self.assertEqual(oc["options"]["headers"], {"X-Team": "ai"})
            self.assertEqual(oc["models"]["m1"]["limit"]["context"], 32768)
            pi = h.json(".pi/agent/models.json")["providers"]["corp"]
            self.assertEqual(pi["apiKey"], "$KIT_MODEL_CORP_KEY")
            self.assertEqual(pi["api"], "openai-completions")
            codex = h.read(".codex/config.toml")
            self.assertIn("[model_providers.corp]", codex)
            self.assertIn('wire_api = "responses"', codex)
            self.assertIn("127.0.0.1:4020/e/corp/v1", codex)  # Codex speaks Responses only
            vs = h.json(".config/Code/User/chatLanguageModels.json")
            self.assertEqual(vs[0]["name"], "kit: corp")
            self.assertEqual(vs[0]["apiKey"], "${input:kit-corp-key}")
            self.assertIn("models:", h.read(".continue/config.yaml"))
            for w in ("claude-corp", "codex-corp", "gemini-corp", "copilot-corp", "aider-corp"):
                self.assertTrue((h.home / ".local/bin" / w).exists(), w)
            self.assertIn("CLAUDE_CODE_MAX_CONTEXT_TOKENS", h.read(".local/bin/claude-corp"))
            self.assertIn("kit-models-providers.yaml",
                          " ".join(p.name for p in (h.home / ".config/work-kit/evalkit").iterdir()))
            # harness defaults change only when asked
            self.assertNotIn("model", h.json(".config/opencode/opencode.json"))
            self.assertNotIn("model_provider =", codex)

    def test_default_and_takeover_and_undo(self):
        with Home() as h:
            (h.home / ".claude/settings.json").write_text('{"env": {"FOO": "bar"}}\n')
            h.run(*add_args("corp", "anthropic", "https://gw.example.test", ("c1",)))
            h.run("default", "corp", "--also", "claude,gemini,copilot")
            s = h.json(".claude/settings.json")
            self.assertEqual(s["env"]["ANTHROPIC_BASE_URL"], "https://gw.example.test")
            self.assertIn("key-helper KIT_MODEL_CORP_KEY", s["apiKeyHelper"])
            self.assertEqual(s["env"]["FOO"], "bar")
            self.assertIn("GOOGLE_GEMINI_BASE_URL", h.read(".gemini/.env"))
            self.assertIn("COPILOT_PROVIDER_TYPE", h.read(".config/work-kit/model-endpoints.sh"))
            self.assertEqual(h.json(".config/opencode/opencode.json")["model"], "corp/c1")
            self.assertIn('model_provider = "corp"', h.read(".codex/config.toml"))
            self.assertEqual(h.json(".pi/agent/settings.json")["defaultProvider"], "corp")
            h.run("default", "corp", "--no-also")
            s = h.json(".claude/settings.json")
            self.assertEqual(s, {"env": {"FOO": "bar"}})
            self.assertFalse((h.home / ".gemini/.env").exists())

    def test_sync_is_idempotent_and_user_values_win(self):
        with Home() as h:
            h.run(*add_args(), "--default")
            out = h.run("sync")
            changed = [ln for ln in out.splitlines() if ln.startswith(("[create", "[update", "[backup"))]
            self.assertEqual(changed, [], out)
            # the user edits the kit entry: kept, and remove leaves it alone
            p = h.home / ".config/opencode/opencode.json"
            d = json.loads(p.read_text())
            d["provider"]["corp"]["options"]["baseURL"] = "https://mine.test/v1"
            p.write_text(json.dumps(d))
            self.assertIn("is your value", h.run("sync"))
            h.run("remove", "corp")
            self.assertEqual(json.loads(p.read_text())["provider"]["corp"]["options"]["baseURL"],
                             "https://mine.test/v1")

    def test_remove_cleans_every_target_and_keeps_user_text(self):
        with Home() as h:
            (h.home / ".codex/config.toml").write_text('model = "gpt-5"\n[mcp_servers.x]\ncommand = "x"\n')
            (h.home / ".continue/config.yaml").write_text(
                "name: mine\nversion: 1.0.0\nschema: v1\nmodels:\n  - name: own\n    provider: ollama\n    model: a\n")
            (h.home / ".config/Code/User/chatLanguageModels.json").write_text('[{"name": "own", "vendor": "openai"}]')
            (h.home / ".bashrc").write_text("alias ll='ls -l'\n")
            h.run(*add_args(), "--default")
            self.assertIn("  - name: \"m1 (corp)\"", h.read(".continue/config.yaml"))
            self.assertIn("  - name: own", h.read(".continue/config.yaml"))
            h.run("remove", "corp")
            self.assertEqual(h.read(".codex/config.toml"), 'model = "gpt-5"\n[mcp_servers.x]\ncommand = "x"\n')
            self.assertNotIn("corp", h.read(".continue/config.yaml"))
            self.assertIn("- name: own", h.read(".continue/config.yaml"))
            self.assertEqual(h.json(".config/Code/User/chatLanguageModels.json"), [{"name": "own", "vendor": "openai"}])
            self.assertEqual(h.read(".bashrc"), "alias ll='ls -l'\n")
            beside = [str(p) for p in h.home.rglob("*.bak-*") if "work-kit/backups" not in str(p)]
            self.assertEqual(beside, [])  # backups live below the kit's data dir only
            self.assertTrue(list(h.home.glob(".local/share/work-kit/backups/33-model-endpoints/.bashrc.bak-*")))
            self.assertFalse((h.home / ".local/bin/claude-corp").exists())
            self.assertNotIn("corp", h.read(".pi/agent/models.json") if (h.home / ".pi/agent/models.json").exists() else "")
            self.assertFalse((h.home / ".config/opencode/opencode.json").exists())

    def test_workbench_uses_wb_state_and_pi_defers(self):
        with Home() as h:
            log = h.home / "wb.log"
            wb = h.bin / "wb-state"
            wb.write_text(f'#!/bin/sh\necho "$@" >> "{log}"\necho ok\n')
            wb.chmod(0o755)
            h.run(*add_args("corp", "openai", "https://llm.example.test/v1", ("m1",)))
            h.run(*add_args("hdr", "openai", "https://llm2.example.test/v1", ("m2",),
                            "--header", "X-A: b"))
            calls = log.read_text()
            self.assertIn("models add-provider --id corp --kind openai --base-url https://llm.example.test/v1", calls)
            self.assertIn("--owner 33-model-endpoints --key-env KIT_MODEL_CORP_KEY --model m1", calls)
            self.assertIn("--id hdr --kind openai --base-url http://127.0.0.1:4020/e/hdr/v1", calls)
            self.assertFalse((h.home / ".pi/agent/models.json").exists())
            h.run("remove", "corp")
            self.assertIn("models remove-provider --id corp --owner 33-model-endpoints", log.read_text())

    def test_vscode_workbench_registry(self):
        with Home() as h:
            (h.home / ".config/work-kit/workbench").mkdir(parents=True)
            (h.home / ".config/work-kit/workbench/models.json").write_text(json.dumps(
                {"version": 1, "providers": [{"id": "own", "label": "own", "kind": "local"}],
                 "harnesses": [], "models": []}))
            h.run(*add_args("corp", "azure", "https://res.openai.azure.test", ("dep1",)))
            reg = h.json(".config/work-kit/workbench/models.json")
            prov = {p["id"]: p for p in reg["providers"]}
            self.assertIn("own", prov)
            self.assertEqual(prov["corp"]["baseUrl"], "http://127.0.0.1:4020/e/corp/v1")  # azure via proxy
            self.assertEqual(prov["corp"]["apiKeyEnv"], "KIT_MODELS_PROXY_KEY")
            self.assertEqual(reg["models"][0]["harness"], "api")
            h.run("remove", "corp")
            reg = h.json(".config/work-kit/workbench/models.json")
            self.assertEqual([p["id"] for p in reg["providers"]], ["own"])
            self.assertEqual(reg["models"], [])

    def test_meeting_needs_internal_class(self):
        with Home() as h:
            h.run(*add_args())
            h.run("default", "corp", "--also", "meeting")
            conf = h.home / ".config/work-kit/meeting.conf"
            self.assertFalse(conf.exists() and "summary_url" in conf.read_text())
            h.run(*add_args("corp", "openai", "https://llm.example.test/v1", ("m1",),
                            "--data-classes", "PUBLIC,INTERNAL"))
            h.run("sync")
            self.assertIn("summary_url=http://127.0.0.1:4020/e/corp/v1", conf.read_text())
            tok = (h.home / ".local/share/work-kit/model-endpoints/proxy.token").read_text().strip()
            self.assertNotIn(tok, conf.read_text())  # meeting finds the token itself

    def test_local_token_replaces_the_placeholder_everywhere(self):
        with Home() as h:
            (h.home / ".config/Code/User/chatLanguageModels.json").write_text("[]")
            h.run(*add_args("corp", "azure", "https://res.openai.azure.test", ("dep1",),
                            "--all-targets"))
            h.run("default", "corp", "--also", "claude,gemini")
            tok_file = h.home / ".local/share/work-kit/model-endpoints/proxy.token"
            tok = tok_file.read_text().strip()
            self.assertGreaterEqual(len(tok), 32)
            self.assertEqual(stat.S_IMODE(tok_file.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(tok_file.parent.stat().st_mode), 0o700)
            before = tok
            h.run("sync")
            self.assertEqual(tok_file.read_text().strip(), before)  # stable across syncs
            text = h.all_text()
            self.assertNotIn("kit-proxy", text)
            for rel in (".config/opencode/opencode.json", ".pi/agent/models.json", ".gemini/.env",
                        ".continue/config.yaml"):
                p = h.home / rel
                self.assertTrue(p.exists(), rel)
                self.assertIn(tok, p.read_text(), rel)
                self.assertEqual(stat.S_IMODE(p.stat().st_mode) & 0o077, 0, rel)  # not readable by others
            # no world-readable script or snippet carries the token: they read the 0600 file
            for rel in (".local/bin/gemini-corp", ".local/bin/aider-corp", ".config/work-kit/model-endpoints.sh",
                        ".local/share/work-kit/model-endpoints/key-helper"):
                p = h.home / rel
                if p.exists():
                    self.assertNotIn(tok, p.read_text(), rel)
            self.assertIn('"${KIT_MODELS_PROXY_KEY}"', h.read(".local/bin/gemini-corp"))
            self.assertIn(str(tok_file), h.read(".config/work-kit/model-endpoints.sh"))
            helper = h.read(".local/share/work-kit/model-endpoints/key-helper")
            self.assertIn(f'cat "{tok_file}"', helper)
            # targets that read the token from the environment name the variable
            self.assertIn('env_key = "KIT_MODELS_PROXY_KEY"', h.read(".codex/config.toml"))
            self.assertIn("api_key_env: KIT_MODELS_PROXY_KEY",
                          h.read(".config/work-kit/evalkit/kit-models-providers.yaml"))
            state = h.home / ".local/share/work-kit/state/kit-models.json"
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)

    def test_dry_run_creates_no_token(self):
        with Home() as h:
            h.run(*add_args("corp", "azure", "https://res.openai.azure.test", ("dep1",), "--dry-run"))
            self.assertFalse((h.home / ".local/share/work-kit/model-endpoints/proxy.token").exists())

    def test_purge(self):
        with Home() as h:
            h.run(*add_args(), stdin_tty=True, getpass_value=KEY)
            h.run("purge")
            self.assertFalse((h.home / ".config/work-kit/model-endpoints.json").exists())
            self.assertFalse((h.home / ".config/work-kit/secrets.env").exists())
            self.assertFalse((h.home / ".local/bin/claude-corp").exists())
            self.assertFalse((h.home / ".bashrc").exists())  # held only the kit line


class Proxy(unittest.TestCase):
    """Every client protocol against every upstream kind, with tools and streams."""

    @classmethod
    def setUpClass(cls):
        cls.fakes = {k: Fake(k, models=["up-model"]).__enter__() for k in ("openai", "azure", "anthropic")}
        cls.env = mock.patch.dict(os.environ, {"FAKE_KEY": KEY, "TENANT": "t-42"})
        cls.env.start()
        eps = {
            "o": {"kind": "openai", "base_url": cls.fakes["openai"].url + "/v1", "models": ["up-model"],
                  "key_env": "FAKE_KEY", "headers": {"X-Tenant": "${TENANT}"}},
            "z": {"kind": "azure", "base_url": cls.fakes["azure"].url, "models": ["up-model"],
                  "key_env": "FAKE_KEY", "api_version": "2024-10-21"},
            "a": {"kind": "anthropic", "base_url": cls.fakes["anthropic"].url, "models": ["up-model"],
                  "key_env": "FAKE_KEY"},
        }
        kp.Handler.registry_loader = staticmethod(lambda: eps)
        kp.Handler.token_loader = staticmethod(lambda: LOCAL_TOKEN)
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), kp.Handler)
        cls.srv.daemon_threads = True
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.srv.server_address[1]}/e"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        for f in cls.fakes.values():
            f.__exit__()
        cls.env.stop()

    def post(self, url, body, raw=False):
        req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json",
                                              "Authorization": "Bearer " + LOCAL_TOKEN})
        with urllib.request.urlopen(req, timeout=10) as r:
            data = r.read()
        return data if raw else json.loads(data)

    def test_protocol_matrix(self):
        tools_oai = [{"type": "function", "function": {"name": "read", "parameters": {"type": "object"}}}]
        for e in ("o", "z", "a"):
            b = f"{self.base}/{e}"
            r = self.post(b + "/v1/chat/completions",
                          {"model": "x", "messages": [{"role": "user", "content": "hi"}]})
            self.assertTrue(r["choices"][0]["message"]["content"].startswith("OK"), (e, r))
            r = self.post(b + "/v1/chat/completions",
                          {"model": "x", "tools": tools_oai, "messages": [{"role": "user", "content": "hi"}]})
            self.assertEqual(r["choices"][0]["message"]["tool_calls"][0]["function"]["name"], "read", e)
            r = self.post(b + "/v1/messages", {"model": "claude-x", "max_tokens": 5, "system": "s",
                                               "messages": [{"role": "user", "content": "hi"},
                                                            {"role": "system", "content": "late"}]})
            self.assertEqual(r["content"][0]["type"], "text", e)
            r = self.post(b + "/v1/messages", {"model": "c", "max_tokens": 5,
                                               "tools": [{"name": "read", "input_schema": {"type": "object"}}],
                                               "messages": [{"role": "user", "content": "hi"}]})
            self.assertEqual((r["stop_reason"], r["content"][0]["name"]), ("tool_use", "read"), e)
            r = self.post(b + "/v1beta/models/gemini-9:generateContent",
                          {"contents": [{"role": "user", "parts": [{"text": "hi"}]}]})
            self.assertIn("OK", r["candidates"][0]["content"]["parts"][0]["text"], e)
            r = self.post(b + "/v1/responses", {"model": "x", "instructions": "be brief",
                                                "input": [{"type": "message", "role": "user",
                                                           "content": [{"type": "input_text", "text": "hi"}]}],
                                                "tools": [{"type": "function", "name": "read",
                                                           "parameters": {"type": "object"}}]})
            self.assertEqual(r["output"][0]["type"], "function_call", e)
            s = self.post(b + "/v1/messages", {"model": "c", "max_tokens": 5, "stream": True,
                                               "messages": [{"role": "user", "content": "hi"}]}, raw=True)
            self.assertIn(b"message_stop", s, e)
            s = self.post(b + "/v1/responses", {"model": "x", "stream": True, "input": "hi"}, raw=True)
            self.assertIn(b"response.completed", s, e)

    def test_auth_headers_and_client_key_not_forwarded(self):
        self.post(f"{self.base}/o/v1/chat/completions", {"model": "x", "messages": [{"role": "user", "content": "q"}]})
        h = {k.lower(): v for k, v in self.fakes["openai"].requests[-1]["headers"].items()}
        self.assertEqual(h["authorization"], f"Bearer {KEY}")
        self.assertEqual(h["x-tenant"], "t-42")
        self.post(f"{self.base}/z/v1/chat/completions", {"model": "x", "messages": [{"role": "user", "content": "q"}]})
        r = self.fakes["azure"].requests[-1]
        self.assertEqual(r["path"], "/openai/deployments/up-model/chat/completions?api-version=2024-10-21")
        self.assertEqual({k.lower(): v for k, v in r["headers"].items()}["api-key"], KEY)
        self.assertNotIn("authorization", {k.lower() for k in r["headers"]})

    def test_meeting_summary_request_passes_the_proxy_token_check(self):
        """17-meeting-capture against the real proxy handler: token from the token file, else 401."""
        import importlib.machinery
        import importlib.util
        path = str(HERE.parent.parent / "17-meeting-capture" / "meeting")
        loader = importlib.machinery.SourceFileLoader("meeting_under_test", path)
        spec = importlib.util.spec_from_loader("meeting_under_test", loader)
        meeting = importlib.util.module_from_spec(spec)
        loader.exec_module(meeting)
        settings = {"summary_url": f"{self.base}/o/v1", "summary_model": "up-model"}
        with tempfile.TemporaryDirectory() as d:
            env = {k: v for k, v in os.environ.items()
                   if k not in ("MEETING_SUMMARY_KEY", "KIT_MODELS_PROXY_KEY")}
            with mock.patch.dict(os.environ, dict(env, KIT_DATA_DIR=d), clear=True), \
                    contextlib.redirect_stderr(io.StringIO()) as err:
                self.assertIsNone(meeting.summarize("transcript", settings))  # no token: 401
                self.assertIn("MEETING_SUMMARY_KEY", err.getvalue())
                (Path(d) / "model-endpoints").mkdir()
                (Path(d) / "model-endpoints/proxy.token").write_text(LOCAL_TOKEN + "\n")
                self.assertTrue(meeting.summarize("transcript", settings).startswith("OK"))
            with mock.patch.dict(os.environ, dict(env, KIT_DATA_DIR=d, KIT_MODELS_PROXY_KEY=LOCAL_TOKEN), clear=True):
                (Path(d) / "model-endpoints/proxy.token").unlink()
                self.assertTrue(meeting.summarize("transcript", settings).startswith("OK"))

    def test_mid_conversation_system_messages_are_merged(self):
        self.post(f"{self.base}/o/v1/messages", {"model": "c", "max_tokens": 5, "system": "first",
                                                 "messages": [{"role": "user", "content": "hi"},
                                                              {"role": "system", "content": "second"}]})
        msgs = self.fakes["openai"].requests[-1]["body"]["messages"]
        self.assertEqual([m["role"] for m in msgs], ["system", "user"])
        self.assertIn("second", msgs[0]["content"])

    def test_unknown_endpoint(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.post(f"{self.base}/nope/v1/chat/completions", {"messages": []})
        self.assertEqual(cm.exception.code, 404)

    def status(self, path, headers=None, body=None, method=None):
        req = urllib.request.Request(self.base[:-2] + path, method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers=dict({"Content-Type": "application/json"}, **(headers or {})))
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    def test_requests_without_the_local_token_are_refused_before_routing(self):
        n = {k: len(f.requests) for k, f in self.fakes.items()}
        chat = {"model": "x", "messages": [{"role": "user", "content": "q"}]}
        posts = ["/e/o/v1/chat/completions", "/e/o/v1/messages", "/e/o/v1/responses",
                 "/e/o/v1beta/models/g:generateContent", "/e/nope/v1/chat/completions"]
        for bad in ({}, {"Authorization": "Bearer wrong"}, {"x-api-key": "wrong"},
                    {"Authorization": "Bearer "}, {"Authorization": LOCAL_TOKEN},
                    {"Authorization": "Bearer " + KEY}):
            for path in posts:
                code, obj = self.status(path, bad, chat)
                self.assertEqual(code, 401, (bad, path, obj))
            for path in ("/health", "/e/o/v1/models", "/e/o/v1beta/models"):
                self.assertEqual(self.status(path, bad)[0], 401, (bad, path))
        self.assertEqual(self.status("/e/o/v1/chat/completions", {}, chat, "PUT")[0], 401)
        self.assertEqual({k: len(f.requests) for k, f in self.fakes.items()}, n)  # nothing forwarded

    def test_token_is_accepted_in_every_header_a_client_may_use(self):
        chat = {"model": "x", "messages": [{"role": "user", "content": "q"}]}
        for headers in ({"Authorization": "Bearer " + LOCAL_TOKEN}, {"authorization": "bearer " + LOCAL_TOKEN},
                        {"x-api-key": LOCAL_TOKEN}, {"x-goog-api-key": LOCAL_TOKEN}):
            self.assertEqual(self.status("/e/o/v1/chat/completions", headers, chat)[0], 200, headers)
            self.assertEqual(self.status("/health", headers)[0], 200, headers)

    def test_proxy_without_a_token_source_refuses_everything(self):
        with mock.patch.object(kp.Handler, "token_loader", None):
            self.assertEqual(self.status("/health", {"Authorization": "Bearer " + LOCAL_TOKEN})[0], 401)
        with mock.patch.object(kp.Handler, "token_loader", staticmethod(lambda: None)):
            self.assertEqual(self.status("/health", {"Authorization": "Bearer "})[0], 401)


class CliTest(unittest.TestCase):
    def test_test_command_reports_latency(self):
        with Fake("openai", models=["m1"]) as f, Home() as h:
            h.run(*add_args("corp", "openai", f.url + "/v1", ("m1",)))
            with mock.patch.dict(os.environ, {"KIT_MODEL_CORP_KEY": KEY}):
                out = h.run("test", "corp")
            self.assertRegex(out, r"ok\s+corp/m1\s+\d+ ms")


if __name__ == "__main__":
    unittest.main()
