"""Providers: ways to obtain a model/agent response for a prompt."""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .shell import python_exe, render, run_shell


class ProviderError(ValueError):
    """Invalid provider configuration."""


@dataclass
class Response:
    text: str = ""
    error: str | None = None
    latency: float = 0.0
    tokens_in: int | None = None
    tokens_out: int | None = None
    cost: float | None = None


_ENV_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_ENV_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


def expand_env(value: str, what: str) -> str:
    """Expand ${VAR} and ${VAR:-default}; unset without default is a config error."""

    def sub(m: re.Match[str]) -> str:
        val = os.environ.get(m.group(1))
        if val:
            return val
        if m.group(2) is not None:
            return m.group(2)
        raise ProviderError(f"{what}: environment variable {m.group(1)} is not set")

    return _ENV_REF.sub(sub, value)


class Provider:
    id: str
    default: bool = True

    def prepare(self) -> None:
        """Resolve environment references; raise ProviderError when the provider cannot run."""

    def complete(self, prompt: str, timeout: float) -> Response:  # pragma: no cover
        raise NotImplementedError


@dataclass
class ShellProvider(Provider):
    id: str
    command: str
    input_mode: str = "auto"  # auto | arg | stdin
    cwd: Path | None = None
    default: bool = True

    def complete(self, prompt: str, timeout: float) -> Response:
        mode = self.input_mode
        if mode == "auto":
            mode = "arg" if "{input}" in self.command else "stdin"
        values = {"python": python_exe()}
        if mode == "arg":
            values["input"] = prompt
            cmd = render(self.command, values, quote=True)
            stdin = None
        else:
            cmd = render(self.command, values)
            stdin = prompt
        start = time.monotonic()
        res = run_shell(cmd, stdin=stdin, timeout=timeout, cwd=self.cwd)
        latency = time.monotonic() - start
        if res.timed_out:
            return Response(res.stdout, f"timeout after {timeout:g}s", latency)
        if res.returncode != 0:
            tail = (res.stderr.strip().splitlines() or [""])[-1]
            return Response(res.stdout, f"exit code {res.returncode}: {tail}"[:300], latency)
        return Response(res.stdout, None, latency)


@dataclass
class OpenAIProvider(Provider):
    """OpenAI-compatible /chat/completions endpoint (OpenAI, Ollama, vLLM, LM Studio, gateways)."""

    id: str
    base_url: str
    model: str
    api_key_env: str | None = None
    system: str | None = None
    temperature: float | None = None
    max_tokens: int | None = None
    price_in_per_1m: float | None = None
    price_out_per_1m: float | None = None
    retries: int = 2
    default: bool = True
    extra_body: dict[str, Any] = field(default_factory=dict)

    def prepare(self) -> None:
        self.base_url = expand_env(self.base_url, f"provider {self.id} base_url")
        self.model = expand_env(self.model, f"provider {self.id} model")

    def complete(self, prompt: str, timeout: float) -> Response:
        headers = {"Content-Type": "application/json"}
        if self.api_key_env:
            key = os.environ.get(self.api_key_env)
            if not key:
                return Response(error=f"environment variable {self.api_key_env} is not set")
            headers["Authorization"] = f"Bearer {key}"
        messages = []
        if self.system:
            messages.append({"role": "system", "content": self.system})
        messages.append({"role": "user", "content": prompt})
        body: dict[str, Any] = {"model": self.model, "messages": messages}
        if self.temperature is not None:
            body["temperature"] = self.temperature
        if self.max_tokens is not None:
            body["max_tokens"] = self.max_tokens
        body.update(self.extra_body)
        url = self.base_url.rstrip("/") + "/chat/completions"
        data = json.dumps(body).encode()

        start = time.monotonic()
        last_error = "unknown error"
        for attempt in range(self.retries + 1):
            req = urllib.request.Request(url, data=data, headers=headers, method="POST")
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    payload = json.loads(resp.read().decode("utf-8", "replace"))
                return self._parse(payload, time.monotonic() - start)
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")[:200].replace("\n", " ")
                last_error = f"HTTP {exc.code}: {detail}"
                if exc.code not in (408, 429, 500, 502, 503, 504):
                    break
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last_error = f"request failed: {getattr(exc, 'reason', exc)}"
            except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
                return Response(error=f"unexpected response: {exc!r}", latency=time.monotonic() - start)
            if attempt < self.retries:
                time.sleep(min(2**attempt, 8))
        return Response(error=last_error, latency=time.monotonic() - start)

    def _parse(self, payload: dict[str, Any], latency: float) -> Response:
        content = payload["choices"][0]["message"].get("content") or ""
        usage = payload.get("usage") or {}
        tin = usage.get("prompt_tokens")
        tout = usage.get("completion_tokens")
        cost = usage.get("cost") if isinstance(usage.get("cost"), (int, float)) else None
        if cost is None and tin is not None and tout is not None:
            if self.price_in_per_1m is not None and self.price_out_per_1m is not None:
                cost = (tin * self.price_in_per_1m + tout * self.price_out_per_1m) / 1e6
        return Response(content, None, latency, tin, tout, cost)


def build_provider(spec: Any, base_dir: Path, where: str) -> Provider:
    if not isinstance(spec, dict):
        raise ProviderError(f"{where}: provider must be a mapping")
    pid = spec.get("id")
    if not isinstance(pid, str) or not pid:
        raise ProviderError(f"{where}: provider needs a string 'id'")
    where = f"{where} ({pid})"
    if "api_key" in spec:
        raise ProviderError(f"{where}: literal API keys are not allowed; use api_key_env: NAME_OF_ENV_VAR")
    ptype = spec.get("type")
    default = spec.get("default", True)
    if not isinstance(default, bool):
        raise ProviderError(f"{where}: 'default' must be true or false")
    if ptype == "shell":
        command = spec.get("command")
        if not isinstance(command, str) or not command.strip():
            raise ProviderError(f"{where}: shell provider needs 'command'")
        mode = spec.get("input_mode", "auto")
        if mode not in ("auto", "arg", "stdin"):
            raise ProviderError(f"{where}: input_mode must be auto, arg or stdin")
        return ShellProvider(pid, command, mode, base_dir, default)
    if ptype == "openai":
        for key in ("base_url", "model"):
            if not isinstance(spec.get(key), str) or not spec[key]:
                raise ProviderError(f"{where}: openai provider needs '{key}'")
        env_name = spec.get("api_key_env")
        if env_name is not None and (not isinstance(env_name, str) or not _ENV_NAME.match(env_name)):
            raise ProviderError(
                f"{where}: api_key_env must be the NAME of an environment variable, not a key"
            )
        price = spec.get("price") or {}
        return OpenAIProvider(
            id=pid,
            base_url=spec["base_url"],
            model=spec["model"],
            api_key_env=env_name,
            system=spec.get("system"),
            temperature=spec.get("temperature"),
            max_tokens=spec.get("max_tokens"),
            price_in_per_1m=price.get("input_per_1m"),
            price_out_per_1m=price.get("output_per_1m"),
            retries=int(spec.get("retries", 2)),
            default=default,
            extra_body=spec.get("extra_body") or {},
        )
    raise ProviderError(f"{where}: type must be 'shell' or 'openai', got {ptype!r}")
