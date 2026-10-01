"""Local translating proxy for kit-models (standard library only).

Listens on 127.0.0.1 and forwards every request to one registered endpoint, chosen by the path
prefix /e/<endpoint>/. It adds the key and the custom headers of the endpoint (read from the
environment at request time, so no key is ever written to a file by the proxy) and translates
between three client protocols and four upstream kinds:

  client side (what a harness speaks)           upstream kinds (what the company runs)
  OpenAI   POST /v1/chat/completions, /v1/models    openai     OpenAI-compatible /chat/completions
  Anthropic POST /v1/messages, /count_tokens        azure      Azure OpenAI deployments + api-version
  Gemini   POST /v1beta/models/M:generateContent     anthropic  Anthropic Messages /v1/messages
           (and :streamGenerateContent, :countTokens) ollama     Ollama (its OpenAI-compatible /v1)
  Responses POST /v1/responses (Codex; always translated to chat completions)

Every request must carry the per-install local token (Authorization: Bearer, x-api-key or
x-goog-api-key, whichever the client sends); without it the answer is 401 before any routing. The
token only opens this proxy; it is not an endpoint key.

Same protocol on both sides: the body is passed through, streams included. Translated requests
are sent upstream without streaming; a streaming client gets the full answer as one well-formed
event stream (with keep-alive pings while waiting). Tool calls are translated in all directions.
"""
from __future__ import annotations

import hmac
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ANTHROPIC_VERSION = "2023-06-01"
PING_SECONDS = 10.0
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers",
       "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}
# Client credentials never go upstream: the proxy sets the endpoint's own.
CLIENT_AUTH = {"authorization", "x-api-key", "api-key", "x-goog-api-key"}


# --- endpoint helpers -----------------------------------------------------------------------

def expand(value: str, env=None) -> str:
    """Replace ${VAR} with the environment value (empty when unset)."""
    env = os.environ if env is None else env
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", lambda m: env.get(m.group(1), ""), value)


def api_key(ep: dict, env=None) -> str:
    env = os.environ if env is None else env
    var = ep.get("key_env")
    return env.get(var, "") if var else ""


def upstream_request(ep: dict, protocol: str, model: str, stream: bool, env=None):
    """(url, headers) for one call in `protocol` (openai|anthropic) to endpoint ep."""
    base = ep["base_url"].rstrip("/")
    key = api_key(ep, env)
    headers = {"Content-Type": "application/json"}
    kind = ep["kind"]
    if kind == "azure":
        ver = ep.get("api_version") or "2024-10-21"
        if "/openai/v1" in base:  # the v1 API of Azure OpenAI takes the model in the body
            url = f"{base}/chat/completions"
        else:
            url = (f"{base}/openai/deployments/{urllib.parse.quote(model, safe='')}"
                   f"/chat/completions?api-version={urllib.parse.quote(ver)}")
        if key:
            headers["api-key"] = key
    elif kind == "anthropic":
        url = (base if base.endswith("/v1") else base + "/v1") + "/messages"
        headers["anthropic-version"] = ANTHROPIC_VERSION
        if key:
            headers["x-api-key"] = key
    else:  # openai, ollama
        if kind == "ollama" and not base.endswith("/v1"):
            base += "/v1"
        url = base + "/chat/completions"
        if key:
            headers["Authorization"] = f"Bearer {key}"
    for name, value in (ep.get("headers") or {}).items():
        headers[name] = expand(value, env)
    if stream:
        headers["Accept"] = "text/event-stream"
    return url, headers


def upstream_protocol(ep: dict) -> str:
    return "anthropic" if ep["kind"] == "anthropic" else "openai"


def models_url(ep: dict):
    base = ep["base_url"].rstrip("/")
    kind = ep["kind"]
    if kind == "anthropic":
        return (base if base.endswith("/v1") else base + "/v1") + "/models"
    if kind == "azure":
        return None  # deployments are not listed with a data-plane key
    if kind == "ollama" and not base.endswith("/v1"):
        base += "/v1"
    return base + "/models"


# --- text helpers ---------------------------------------------------------------------------

def _text_of(content) -> str:
    """Plain text of an OpenAI or Anthropic content value (string or list of parts)."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    out = []
    for part in content:
        if isinstance(part, str):
            out.append(part)
        elif isinstance(part, dict) and part.get("type") in ("text", "input_text", "output_text"):
            out.append(part.get("text", ""))
    return "".join(out)


def estimate_tokens(obj) -> int:
    return max(1, len(json.dumps(obj, ensure_ascii=False)) // 4)


def _new_id(prefix: str) -> str:
    return prefix + uuid.uuid4().hex[:24]


# --- Anthropic <-> OpenAI -------------------------------------------------------------------

def _anthropic_image_to_openai(block: dict):
    src = block.get("source") or {}
    if src.get("type") == "base64":
        url = f"data:{src.get('media_type', 'image/png')};base64,{src.get('data', '')}"
    else:
        url = src.get("url", "")
    return {"type": "image_url", "image_url": {"url": url}}


def anthropic_to_openai_request(body: dict, model: str) -> dict:
    msgs = []
    system = body.get("system")
    if system:
        msgs.append({"role": "system", "content": _text_of(system)})
    for m in body.get("messages", []):
        role, content = m.get("role"), m.get("content")
        if isinstance(content, str):
            msgs.append({"role": role, "content": content})
            continue
        parts, calls, results = [], [], []
        for b in content or []:
            t = b.get("type")
            if t == "text":
                parts.append({"type": "text", "text": b.get("text", "")})
            elif t == "image":
                parts.append(_anthropic_image_to_openai(b))
            elif t == "tool_use":
                calls.append({"id": b.get("id") or _new_id("call_"), "type": "function",
                              "function": {"name": b.get("name", ""),
                                           "arguments": json.dumps(b.get("input") or {})}})
            elif t == "tool_result":
                c = b.get("content")
                text = c if isinstance(c, str) else _text_of(c)
                if b.get("is_error"):
                    text = "ERROR: " + text
                results.append({"role": "tool", "tool_call_id": b.get("tool_use_id", ""),
                                "content": text})
            # thinking / redacted_thinking blocks are dropped: other models cannot use them
        msgs.extend(results)  # tool results answer the previous assistant turn first
        if role == "assistant":
            msg = {"role": "assistant",
                   "content": "".join(p.get("text", "") for p in parts if p["type"] == "text") or None}
            if calls:
                msg["tool_calls"] = calls
            if msg["content"] is not None or calls:
                msgs.append(msg)
        elif parts:
            only_text = all(p["type"] == "text" for p in parts)
            msgs.append({"role": role,
                         "content": "".join(p["text"] for p in parts) if only_text else parts})
    out = {"model": model, "messages": msgs}
    if body.get("max_tokens"):
        out["max_tokens"] = body["max_tokens"]
    for k in ("temperature", "top_p"):
        if k in body:
            out[k] = body[k]
    if body.get("stop_sequences"):
        out["stop"] = body["stop_sequences"]
    tools = [t for t in body.get("tools") or [] if t.get("name") and "input_schema" in t]
    if tools:
        out["tools"] = [{"type": "function", "function": {
            "name": t["name"], "description": t.get("description", ""),
            "parameters": t.get("input_schema") or {"type": "object"}}} for t in tools]
        tc = body.get("tool_choice") or {}
        if tc.get("type") == "any":
            out["tool_choice"] = "required"
        elif tc.get("type") == "tool":
            out["tool_choice"] = {"type": "function", "function": {"name": tc.get("name")}}
        elif tc.get("type") == "none":
            out["tool_choice"] = "none"
    return out


FINISH_TO_STOP = {"stop": "end_turn", "length": "max_tokens", "tool_calls": "tool_use",
                  "function_call": "tool_use", "content_filter": "end_turn"}
STOP_TO_FINISH = {"end_turn": "stop", "max_tokens": "length", "tool_use": "tool_calls",
                  "stop_sequence": "stop", "pause_turn": "stop", "refusal": "content_filter"}


def openai_to_anthropic_response(resp: dict, model: str) -> dict:
    choice = (resp.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    content = []
    text = msg.get("content")
    if isinstance(text, list):
        text = _text_of(text)
    if text:
        content.append({"type": "text", "text": text})
    for call in msg.get("tool_calls") or []:
        fn = call.get("function") or {}
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except ValueError:
            args = {"_raw": fn.get("arguments")}
        content.append({"type": "tool_use", "id": call.get("id") or _new_id("toolu_"),
                        "name": fn.get("name", ""), "input": args})
    usage = resp.get("usage") or {}
    stop = FINISH_TO_STOP.get(choice.get("finish_reason") or "stop", "end_turn")
    if any(b["type"] == "tool_use" for b in content):
        stop = "tool_use"
    return {"id": _new_id("msg_"), "type": "message", "role": "assistant", "model": model,
            "content": content or [{"type": "text", "text": ""}], "stop_reason": stop,
            "stop_sequence": None,
            "usage": {"input_tokens": usage.get("prompt_tokens", 0),
                      "output_tokens": usage.get("completion_tokens", 0)}}


def anthropic_sse(msg: dict):
    """Anthropic streaming events for a complete message."""
    def ev(name, data):
        return f"event: {name}\ndata: {json.dumps(data)}\n\n".encode()
    head = dict(msg, content=[], stop_reason=None,
                usage={"input_tokens": msg["usage"]["input_tokens"], "output_tokens": 0})
    yield ev("message_start", {"type": "message_start", "message": head})
    for i, block in enumerate(msg["content"]):
        if block["type"] == "text":
            yield ev("content_block_start", {"type": "content_block_start", "index": i,
                                             "content_block": {"type": "text", "text": ""}})
            yield ev("content_block_delta", {"type": "content_block_delta", "index": i,
                                             "delta": {"type": "text_delta", "text": block["text"]}})
        else:
            yield ev("content_block_start", {"type": "content_block_start", "index": i,
                                             "content_block": dict(block, input={})})
            yield ev("content_block_delta", {"type": "content_block_delta", "index": i,
                                             "delta": {"type": "input_json_delta",
                                                       "partial_json": json.dumps(block["input"])}})
        yield ev("content_block_stop", {"type": "content_block_stop", "index": i})
    yield ev("message_delta", {"type": "message_delta",
                               "delta": {"stop_reason": msg["stop_reason"], "stop_sequence": None},
                               "usage": {"output_tokens": msg["usage"]["output_tokens"]}})
    yield ev("message_stop", {"type": "message_stop"})


def openai_to_anthropic_request(body: dict, model: str) -> dict:
    system, msgs = [], []
    for m in body.get("messages", []):
        role, content = m.get("role"), m.get("content")
        if role in ("system", "developer"):
            system.append(_text_of(content))
            continue
        if role == "tool":
            block = {"type": "tool_result", "tool_use_id": m.get("tool_call_id", ""),
                     "content": _text_of(content)}
            if msgs and msgs[-1]["role"] == "user" and isinstance(msgs[-1]["content"], list):
                msgs[-1]["content"].append(block)
            else:
                msgs.append({"role": "user", "content": [block]})
            continue
        blocks = []
        if isinstance(content, str):
            if content:
                blocks.append({"type": "text", "text": content})
        else:
            for p in content or []:
                if p.get("type") == "text":
                    blocks.append({"type": "text", "text": p.get("text", "")})
                elif p.get("type") == "image_url":
                    url = (p.get("image_url") or {}).get("url", "")
                    mt = re.match(r"data:([^;]+);base64,(.*)", url, re.S)
                    src = ({"type": "base64", "media_type": mt.group(1), "data": mt.group(2)}
                           if mt else {"type": "url", "url": url})
                    blocks.append({"type": "image", "source": src})
        for call in m.get("tool_calls") or []:
            fn = call.get("function") or {}
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except ValueError:
                args = {}
            blocks.append({"type": "tool_use", "id": call.get("id") or _new_id("toolu_"),
                           "name": fn.get("name", ""), "input": args})
        if not blocks:
            continue
        if msgs and msgs[-1]["role"] == role and isinstance(msgs[-1]["content"], list):
            msgs[-1]["content"].extend(blocks)  # Anthropic wants alternating roles
        else:
            msgs.append({"role": role, "content": blocks})
    out = {"model": model, "messages": msgs,
           "max_tokens": body.get("max_tokens") or body.get("max_completion_tokens") or 4096}
    if system:
        out["system"] = "\n\n".join(system)
    for k in ("temperature", "top_p"):
        if k in body:
            out[k] = body[k]
    if body.get("stop"):
        out["stop_sequences"] = body["stop"] if isinstance(body["stop"], list) else [body["stop"]]
    tools = [t.get("function") or {} for t in body.get("tools") or [] if t.get("type") == "function"]
    if tools:
        out["tools"] = [{"name": f.get("name", ""), "description": f.get("description", ""),
                         "input_schema": f.get("parameters") or {"type": "object"}} for f in tools]
        tc = body.get("tool_choice")
        if tc == "required":
            out["tool_choice"] = {"type": "any"}
        elif tc == "none":
            out["tool_choice"] = {"type": "none"}
        elif isinstance(tc, dict) and tc.get("function"):
            out["tool_choice"] = {"type": "tool", "name": tc["function"].get("name")}
    return out


def anthropic_to_openai_response(resp: dict, model: str) -> dict:
    text, calls = [], []
    for b in resp.get("content") or []:
        if b.get("type") == "text":
            text.append(b.get("text", ""))
        elif b.get("type") == "tool_use":
            calls.append({"id": b.get("id"), "type": "function",
                          "function": {"name": b.get("name", ""),
                                       "arguments": json.dumps(b.get("input") or {})}})
    msg = {"role": "assistant", "content": "".join(text) or (None if calls else "")}
    if calls:
        msg["tool_calls"] = calls
    usage = resp.get("usage") or {}
    pin, pout = usage.get("input_tokens", 0), usage.get("output_tokens", 0)
    return {"id": _new_id("chatcmpl-"), "object": "chat.completion", "created": int(time.time()),
            "model": model,
            "choices": [{"index": 0, "message": msg,
                         "finish_reason": STOP_TO_FINISH.get(resp.get("stop_reason"), "stop")}],
            "usage": {"prompt_tokens": pin, "completion_tokens": pout, "total_tokens": pin + pout}}


def openai_sse(resp: dict):
    """OpenAI chat.completion.chunk events for a complete response."""
    choice = resp["choices"][0]
    msg = choice["message"]
    base = {"id": resp["id"], "object": "chat.completion.chunk", "created": resp["created"],
            "model": resp["model"]}

    def chunk(delta, finish=None, usage=None):
        d = dict(base, choices=[{"index": 0, "delta": delta, "finish_reason": finish}])
        if usage is not None:
            d["usage"] = usage
        return f"data: {json.dumps(d)}\n\n".encode()
    yield chunk({"role": "assistant", "content": ""})
    if msg.get("content"):
        yield chunk({"content": msg["content"]})
    for i, call in enumerate(msg.get("tool_calls") or []):
        yield chunk({"tool_calls": [dict(call, index=i)]})
    yield chunk({}, choice["finish_reason"], resp.get("usage"))
    yield b"data: [DONE]\n\n"


# --- Gemini <-> OpenAI ----------------------------------------------------------------------

def _schema_clean(schema):
    """Gemini schemas use upper-case types; OpenAI tools want JSON schema."""
    if isinstance(schema, dict):
        out = {}
        for k, v in schema.items():
            if k == "type" and isinstance(v, str):
                out[k] = v.lower()
            else:
                out[k] = _schema_clean(v)
        return out
    if isinstance(schema, list):
        return [_schema_clean(x) for x in schema]
    return schema


def gemini_to_openai_request(body: dict, model: str) -> dict:
    msgs = []
    si = body.get("systemInstruction") or body.get("system_instruction")
    if si:
        msgs.append({"role": "system",
                     "content": "".join(p.get("text", "") for p in si.get("parts", []))})
    pending = []  # ids of the model's function calls, answered in order
    for c in body.get("contents", []):
        role = "assistant" if c.get("role") == "model" else "user"
        texts, calls, results = [], [], []
        for p in c.get("parts", []):
            if p.get("thought"):
                continue
            if "text" in p:
                texts.append(p["text"])
            elif "functionCall" in p:
                fc = p["functionCall"]
                cid = fc.get("id") or _new_id("call_")
                pending.append((fc.get("name"), cid))
                calls.append({"id": cid, "type": "function",
                              "function": {"name": fc.get("name", ""),
                                           "arguments": json.dumps(fc.get("args") or {})}})
            elif "functionResponse" in p:
                fr = p["functionResponse"]
                cid = fr.get("id")
                if not cid:
                    match = next((x for x in pending if x[0] == fr.get("name")), None)
                    cid = match[1] if match else _new_id("call_")
                pending = [x for x in pending if x[1] != cid]
                results.append({"role": "tool", "tool_call_id": cid,
                                "content": json.dumps(fr.get("response") or {})})
        msgs.extend(results)
        if role == "assistant":
            if texts or calls:
                m = {"role": "assistant", "content": "".join(texts) or None}
                if calls:
                    m["tool_calls"] = calls
                msgs.append(m)
        elif texts:
            msgs.append({"role": "user", "content": "".join(texts)})
    out = {"model": model, "messages": msgs}
    gc = body.get("generationConfig") or {}
    if "temperature" in gc:
        out["temperature"] = gc["temperature"]
    if "topP" in gc:
        out["top_p"] = gc["topP"]
    if gc.get("maxOutputTokens"):
        out["max_tokens"] = gc["maxOutputTokens"]
    if gc.get("stopSequences"):
        out["stop"] = gc["stopSequences"]
    funcs = []
    for t in body.get("tools") or []:
        for f in t.get("functionDeclarations") or t.get("function_declarations") or []:
            params = f.get("parametersJsonSchema") or _schema_clean(f.get("parameters")) or {"type": "object"}
            funcs.append({"type": "function", "function": {
                "name": f.get("name", ""), "description": f.get("description", ""),
                "parameters": params}})
    if funcs:
        out["tools"] = funcs
    return out


def openai_to_gemini_response(resp: dict, model: str) -> dict:
    choice = (resp.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    parts = []
    text = _text_of(msg.get("content"))
    if text:
        parts.append({"text": text})
    for call in msg.get("tool_calls") or []:
        fn = call.get("function") or {}
        try:
            args = json.loads(fn.get("arguments") or "{}")
        except ValueError:
            args = {}
        parts.append({"functionCall": {"id": call.get("id"), "name": fn.get("name", ""), "args": args}})
    finish = {"length": "MAX_TOKENS", "content_filter": "SAFETY"}.get(choice.get("finish_reason"), "STOP")
    usage = resp.get("usage") or {}
    return {"candidates": [{"content": {"role": "model", "parts": parts or [{"text": ""}]},
                            "finishReason": finish, "index": 0}],
            "usageMetadata": {"promptTokenCount": usage.get("prompt_tokens", 0),
                              "candidatesTokenCount": usage.get("completion_tokens", 0),
                              "totalTokenCount": usage.get("total_tokens", 0)},
            "modelVersion": model}


# --- OpenAI Responses (Codex) <-> OpenAI chat -----------------------------------------------

def _output_text(value) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return _text_of(value)
    return json.dumps(value)


def responses_to_openai_request(body: dict, model: str):
    """Chat request for a Responses request, plus {tool name: kind} to map the answer back."""
    msgs, kinds = [], {}
    if body.get("instructions"):
        msgs.append({"role": "system", "content": body["instructions"]})
    items = body.get("input") or []
    if isinstance(items, str):
        items = [{"type": "message", "role": "user", "content": items}]
    for it in items:
        t = it.get("type") or ("message" if "role" in it else None)
        if t == "message":
            role = it.get("role", "user")
            role = "system" if role == "developer" else role
            text = _text_of(it.get("content"))
            if role == "assistant" and msgs and msgs[-1]["role"] == "assistant" and not msgs[-1].get("content"):
                msgs[-1]["content"] = text
            elif text or role != "assistant":
                msgs.append({"role": role, "content": text})
        elif t in ("function_call", "custom_tool_call", "local_shell_call"):
            if t == "function_call":
                name, args = it.get("name", ""), it.get("arguments") or "{}"
            elif t == "custom_tool_call":
                name, args = it.get("name", ""), json.dumps({"input": it.get("input", "")})
            else:
                name, args = "local_shell", json.dumps(it.get("action") or {})
            call_ = {"id": it.get("call_id") or _new_id("call_"), "type": "function",
                     "function": {"name": name, "arguments": args}}
            if msgs and msgs[-1]["role"] == "assistant" and "tool_calls" in msgs[-1]:
                msgs[-1]["tool_calls"].append(call_)
            elif msgs and msgs[-1]["role"] == "assistant" and msgs[-1].get("content") is not None:
                msgs[-1]["tool_calls"] = [call_]
            else:
                msgs.append({"role": "assistant", "content": None, "tool_calls": [call_]})
        elif t in ("function_call_output", "custom_tool_call_output", "local_shell_call_output"):
            out = it.get("output")
            if isinstance(out, dict) and "content" in out:
                out = out["content"]
            msgs.append({"role": "tool", "tool_call_id": it.get("call_id", ""),
                         "content": _output_text(out)})
        # reasoning items and anything else: dropped
    tools = []
    for tl in body.get("tools") or []:
        tt = tl.get("type")
        if tt == "function":
            f = tl.get("function") or tl
            tools.append({"type": "function", "function": {
                "name": f.get("name", ""), "description": f.get("description", ""),
                "parameters": f.get("parameters") or {"type": "object", "properties": {}}}})
            kinds[f.get("name", "")] = "function"
        elif tt == "custom":
            tools.append({"type": "function", "function": {
                "name": tl.get("name", ""),
                "description": (tl.get("description") or "") + " Pass the whole raw input as the string 'input'.",
                "parameters": {"type": "object", "properties": {"input": {"type": "string"}},
                               "required": ["input"]}}})
            kinds[tl.get("name", "")] = "custom"
        elif tt == "local_shell":
            tools.append({"type": "function", "function": {
                "name": "local_shell", "description": "Run a command on the user's machine.",
                "parameters": {"type": "object", "required": ["command"], "properties": {
                    "command": {"type": "array", "items": {"type": "string"}},
                    "workdir": {"type": "string"}, "timeout_ms": {"type": "integer"}}}}})
            kinds["local_shell"] = "local_shell"
        # web_search and other hosted tools cannot run on a company endpoint: dropped
    out = {"model": model, "messages": msgs}
    if tools:
        out["tools"] = tools
        tc = body.get("tool_choice")
        if tc in ("required", "none"):
            out["tool_choice"] = tc
    if body.get("max_output_tokens"):
        out["max_tokens"] = body["max_output_tokens"]
    for k in ("temperature", "top_p"):
        if body.get(k) is not None:
            out[k] = body[k]
    return out, kinds


def openai_to_responses_response(resp: dict, model: str, kinds: dict) -> dict:
    choice = (resp.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    output = []
    text = _text_of(msg.get("content"))
    if text:
        output.append({"type": "message", "id": _new_id("msg_"), "status": "completed",
                       "role": "assistant",
                       "content": [{"type": "output_text", "text": text, "annotations": []}]})
    for call_ in msg.get("tool_calls") or []:
        fn = call_.get("function") or {}
        name, args = fn.get("name", ""), fn.get("arguments") or "{}"
        cid = call_.get("id") or _new_id("call_")
        kind = kinds.get(name, "function")
        if kind == "custom":
            try:
                inp = json.loads(args).get("input", "")
            except (ValueError, AttributeError):
                inp = args
            output.append({"type": "custom_tool_call", "id": _new_id("ctc_"), "call_id": cid,
                           "name": name, "input": inp, "status": "completed"})
        elif kind == "local_shell":
            try:
                action = json.loads(args)
            except ValueError:
                action = {}
            action.setdefault("type", "exec")
            output.append({"type": "local_shell_call", "id": _new_id("lsh_"), "call_id": cid,
                           "action": action, "status": "completed"})
        else:
            output.append({"type": "function_call", "id": _new_id("fc_"), "call_id": cid,
                           "name": name, "arguments": args, "status": "completed"})
    usage = resp.get("usage") or {}
    pin, pout = usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0)
    return {"id": _new_id("resp_"), "object": "response", "created_at": int(time.time()),
            "status": "completed", "model": model, "output": output,
            "usage": {"input_tokens": pin, "output_tokens": pout, "total_tokens": pin + pout,
                      "input_tokens_details": {"cached_tokens": 0},
                      "output_tokens_details": {"reasoning_tokens": 0}}}


def responses_sse(resp: dict):
    seq = [0]

    def ev(name, data):
        data = dict(data, type=name, sequence_number=seq[0])
        seq[0] += 1
        return f"event: {name}\ndata: {json.dumps(data)}\n\n".encode()
    head = dict(resp, status="in_progress", output=[], usage=None)
    yield ev("response.created", {"response": head})
    yield ev("response.in_progress", {"response": head})
    for i, item in enumerate(resp["output"]):
        yield ev("response.output_item.added", {"output_index": i, "item": dict(item, status="in_progress")})
        if item["type"] == "message":
            part = item["content"][0]
            yield ev("response.content_part.added", {"item_id": item["id"], "output_index": i,
                                                     "content_index": 0,
                                                     "part": dict(part, text="")})
            yield ev("response.output_text.delta", {"item_id": item["id"], "output_index": i,
                                                    "content_index": 0, "delta": part["text"]})
            yield ev("response.output_text.done", {"item_id": item["id"], "output_index": i,
                                                   "content_index": 0, "text": part["text"]})
            yield ev("response.content_part.done", {"item_id": item["id"], "output_index": i,
                                                    "content_index": 0, "part": part})
        elif item["type"] == "function_call":
            yield ev("response.function_call_arguments.delta", {"item_id": item["id"], "output_index": i,
                                                                "delta": item["arguments"]})
            yield ev("response.function_call_arguments.done", {"item_id": item["id"], "output_index": i,
                                                               "arguments": item["arguments"]})
        yield ev("response.output_item.done", {"output_index": i, "item": item})
    yield ev("response.completed", {"response": resp})


# --- HTTP ------------------------------------------------------------------------------------

class UpstreamError(Exception):
    def __init__(self, status: int, body: bytes):
        super().__init__(f"upstream HTTP {status}")
        self.status, self.body = status, body


def _opener(url: str):
    # Loopback upstreams (local engines) bypass any HTTP(S)_PROXY of the environment.
    host = urllib.parse.urlsplit(url).hostname or ""
    if host in ("127.0.0.1", "localhost", "::1"):
        return urllib.request.build_opener(urllib.request.ProxyHandler({}))
    return urllib.request.build_opener()


def post_json(url: str, headers: dict, body: dict, timeout: float) -> dict:
    dump = os.environ.get("KIT_MODELS_PROXY_DUMP")  # debugging only: request bodies, no headers
    if dump:
        with open(dump, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"url": url, "body": body}) + "\n")
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="POST")
    try:
        with _opener(url).open(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise UpstreamError(e.code, e.read()) from None


def leading_system(body: dict) -> dict:
    """Merge every system message into one at the start. Claude Code and Codex put system or
    developer messages mid-conversation; many chat templates (Qwen, Llama) reject that."""
    msgs = body.get("messages") or []
    sys_parts = [_text_of(m.get("content")) for m in msgs if m.get("role") == "system"]
    if len(sys_parts) <= 1 and (not sys_parts or msgs[0].get("role") == "system"):
        return body
    rest = [m for m in msgs if m.get("role") != "system"]
    return dict(body, messages=[{"role": "system", "content": "\n\n".join(p for p in sys_parts if p)}] + rest)


def call(ep: dict, protocol: str, body: dict, timeout: float = 600.0, env=None) -> dict:
    """One non-streaming call in `protocol` (openai|anthropic); translated when needed."""
    model = body.get("model") or ep["models"][0]
    up = upstream_protocol(ep)
    if protocol == up:
        url, headers = upstream_request(ep, up, model, False, env)
        if up == "openai":
            body = leading_system(body)
        return post_json(url, headers, dict(body, stream=False), timeout)
    if protocol == "anthropic":  # client Anthropic, upstream OpenAI
        req = leading_system(anthropic_to_openai_request(body, model))
        url, headers = upstream_request(ep, "openai", model, False, env)
        return openai_to_anthropic_response(post_json(url, headers, req, timeout), model)
    req = openai_to_anthropic_request(body, model)  # client OpenAI, upstream Anthropic
    url, headers = upstream_request(ep, "anthropic", model, False, env)
    return anthropic_to_openai_response(post_json(url, headers, req, timeout), model)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "kit-models-proxy"
    registry_loader = None  # set by serve(): () -> {name: endpoint}
    token_loader = None  # set by serve(): () -> the local token; None means refuse everything
    timeout_s = 600.0

    def log_message(self, fmt, *args):  # no request log: paths may name models, never keys
        if os.environ.get("KIT_MODELS_PROXY_DEBUG"):
            sys.stderr.write("proxy: " + (fmt % args) + "\n")

    # local authentication
    def _presented_token(self) -> str:
        auth = self.headers.get("Authorization") or ""
        if auth[:7].lower() == "bearer ":
            return auth[7:].strip()
        return (self.headers.get("x-api-key") or self.headers.get("x-goog-api-key") or "").strip()

    def _authorized(self) -> bool:
        """True when the request carries the local token. Otherwise answers 401 and returns False."""
        want = self.token_loader() if self.token_loader else None
        got = self._presented_token()
        if want and got and hmac.compare_digest(got.encode(), want.encode()):
            return True
        self.close_connection = True  # the unread request body must not leak into the next request
        path = urllib.parse.urlsplit(self.path).path
        style = "anthropic" if "/messages" in path else "gemini" if "/v1beta/" in path else "openai"
        self._error(401, "missing or wrong local token (send it as Authorization: Bearer, "
                         "x-api-key or x-goog-api-key; see kit-models show)", style)
        return False

    # routing
    def _route(self):
        path = urllib.parse.urlsplit(self.path).path
        m = re.match(r"^/e/([A-Za-z0-9_.-]+)(/.*)?$", path)
        if not m:
            return None, None, path
        eps = self.registry_loader()
        return m.group(1), eps.get(m.group(1)), m.group(2) or "/"

    def _send(self, status: int, obj=None, raw: bytes = None, ctype="application/json"):
        data = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _error(self, status: int, message: str, style="openai"):
        if style == "anthropic":
            obj = {"type": "error", "error": {"type": "api_error", "message": message}}
        elif style == "gemini":
            obj = {"error": {"code": status, "message": message, "status": "UNAVAILABLE"}}
        else:
            obj = {"error": {"message": message, "type": "proxy_error", "code": status}}
        self._send(status, obj)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def do_GET(self):
        if not self._authorized():
            return None
        name, ep, rest = self._route()
        if rest in ("/health", "/"):
            return self._send(200, {"ok": True, "endpoints": sorted(self.registry_loader())})
        if ep is None:
            return self._error(404, f"unknown endpoint '{name}'")
        if rest.rstrip("/") in ("/v1/models", "/models"):
            data = [{"id": m, "object": "model", "owned_by": name,
                     "type": "model", "display_name": m} for m in ep["models"]]
            return self._send(200, {"object": "list", "data": data, "has_more": False})
        if rest.startswith("/v1beta/models"):
            return self._send(200, {"models": [{"name": f"models/{m}", "displayName": m,
                                                "supportedGenerationMethods": ["generateContent"]}
                                               for m in ep["models"]]})
        return self._error(404, f"not supported: GET {rest}")

    def do_POST(self):
        if not self._authorized():
            return None
        name, ep, rest = self._route()
        style = "anthropic" if "/messages" in rest else "gemini" if "/v1beta/" in rest else "openai"
        if ep is None:
            return self._error(404, f"unknown endpoint '{name}' (kit-models list)", style)
        try:
            body = self._body()
        except ValueError:
            return self._error(400, "request body is not JSON", style)
        try:
            if rest.rstrip("/") in ("/v1/chat/completions", "/chat/completions"):
                return self._openai(ep, body)
            if rest.rstrip("/") in ("/v1/messages", "/messages"):
                return self._anthropic(ep, body)
            if rest.rstrip("/") in ("/v1/responses", "/responses"):
                return self._responses(ep, body)
            if rest.rstrip("/").endswith("/messages/count_tokens"):
                return self._send(200, {"input_tokens": estimate_tokens(body.get("messages"))})
            m = re.match(r"^/v1beta/models/([^:]+):(generateContent|streamGenerateContent|countTokens)$", rest)
            if m:
                return self._gemini(ep, body, urllib.parse.unquote(m.group(1)), m.group(2))
            return self._error(404, f"not supported: POST {rest}", style)
        except UpstreamError as e:
            return self._send(e.status, raw=e.body or b"{}")
        except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
            if self._headers_sent():
                return None
            return self._error(502, f"upstream call failed: {e.__class__.__name__}: {e}", style)

    def _refuse_method(self):
        if self._authorized():
            self.close_connection = True
            self._error(405, f"not supported: {self.command}")

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = _refuse_method

    def _headers_sent(self) -> bool:
        return getattr(self, "_streaming", False)

    def _model(self, ep: dict, requested) -> str:
        # Harness aliases (claude-..., gemini-..., gpt-...) that the endpoint does not serve
        # map to its first model, so a harness works without knowing the company names.
        return requested if requested in ep["models"] else ep["models"][0]

    def _passthrough(self, ep: dict, protocol: str, body: dict):
        url, headers = upstream_request(ep, protocol, body["model"], bool(body.get("stream")))
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers,
                                     method="POST")
        try:
            r = _opener(url).open(req, timeout=self.timeout_s)
        except urllib.error.HTTPError as e:
            raise UpstreamError(e.code, e.read()) from None
        with r:
            self.send_response(r.status)
            ctype = r.headers.get("Content-Type", "application/json")
            self.send_header("Content-Type", ctype)
            if "event-stream" in ctype:
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.close_connection = True
                self.end_headers()
                self._streaming = True
                while True:
                    line = r.readline()
                    if not line:
                        break
                    self.wfile.write(line)
                    if line in (b"\n", b"\r\n"):
                        self.wfile.flush()
            else:
                data = r.read()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

    def _stream_with_pings(self, work, events, ping: bytes):
        """Start an SSE response, ping while `work()` runs, then write events(result)."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        self._streaming = True
        box = {}

        def run():
            try:
                box["result"] = work()
            except Exception as e:  # reported inside the stream below
                box["error"] = e
        t = threading.Thread(target=run, daemon=True)
        t.start()
        while t.is_alive():
            t.join(PING_SECONDS)
            if t.is_alive():
                self.wfile.write(ping)
                self.wfile.flush()
        if "error" in box:
            e = box["error"]
            detail = e.body.decode("utf-8", "replace")[:500] if isinstance(e, UpstreamError) else str(e)
            self.wfile.write(b"event: error\ndata: " + json.dumps(
                {"type": "error", "error": {"type": "api_error", "message": detail}}).encode() + b"\n\n")
            return
        for chunk in events(box["result"]):
            self.wfile.write(chunk)
        self.wfile.flush()

    def _openai(self, ep, body):
        body["model"] = self._model(ep, body.get("model"))
        if upstream_protocol(ep) == "openai":
            return self._passthrough(ep, "openai", leading_system(body))
        stream = bool(body.pop("stream", False))
        body.pop("stream_options", None)
        work = lambda: call(ep, "openai", body, self.timeout_s)  # noqa: E731
        if not stream:
            return self._send(200, work())
        self._stream_with_pings(work, openai_sse, b": keep-alive\n\n")

    def _anthropic(self, ep, body):
        body["model"] = self._model(ep, body.get("model"))
        if upstream_protocol(ep) == "anthropic":
            return self._passthrough(ep, "anthropic", body)
        stream = bool(body.pop("stream", False))
        work = lambda: call(ep, "anthropic", body, self.timeout_s)  # noqa: E731
        if not stream:
            return self._send(200, work())
        self._stream_with_pings(work, anthropic_sse,
                                b'event: ping\ndata: {"type": "ping"}\n\n')

    def _responses(self, ep, body):
        model = self._model(ep, body.get("model"))
        stream = bool(body.get("stream"))
        req, kinds = responses_to_openai_request(body, model)
        work = lambda: openai_to_responses_response(call(ep, "openai", req, self.timeout_s), model, kinds)  # noqa: E731
        if not stream:
            return self._send(200, work())
        self._stream_with_pings(work, responses_sse, b": keep-alive\n\n")

    def _gemini(self, ep, body, model, method):
        model = self._model(ep, model)
        if method == "countTokens":
            return self._send(200, {"totalTokens": estimate_tokens(body.get("contents"))})
        req = gemini_to_openai_request(body, model)
        work = lambda: openai_to_gemini_response(call(ep, "openai", req, self.timeout_s), model)  # noqa: E731
        if method == "generateContent":
            return self._send(200, work())
        self._stream_with_pings(work, lambda res: [f"data: {json.dumps(res)}\n\n".encode()],
                                b"\n")


def serve(port: int, loader, host: str = "127.0.0.1", ready=None, token_loader=None):
    """Run the proxy until interrupted. `loader()` returns {name: endpoint}; `token_loader()`
    returns the local token every request must carry (read per request, so a new token applies
    at once). Without a token_loader the proxy refuses every request."""
    Handler.registry_loader = staticmethod(loader)
    Handler.token_loader = staticmethod(token_loader) if token_loader else None
    srv = ThreadingHTTPServer((host, port), Handler)
    srv.daemon_threads = True
    if ready:
        ready(srv)
    try:
        srv.serve_forever()
    finally:
        srv.server_close()
    return srv


def port_free(port: int, host: str = "127.0.0.1") -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((host, port))
            return True
        except OSError:
            return False
