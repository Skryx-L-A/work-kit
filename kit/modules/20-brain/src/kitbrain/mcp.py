"""Minimal MCP server over stdio (newline-delimited JSON-RPC 2.0).

Implemented by hand to keep the offline wheel set small; it covers what MCP
clients need for tools: initialize, tools/list, tools/call, ping.
"""

from __future__ import annotations

import json
import sys
import traceback

from . import __version__, service

PROTOCOL_VERSIONS = ("2025-06-18", "2025-03-26", "2024-11-05")

TOOLS = [
    {
        "name": "search",
        "description": "Hybrid search (BM25 + embeddings) over the work notes. Returns the best "
                       "matching notes with path, title and snippet. Use before non-trivial work.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "k": {"type": "integer", "minimum": 1, "maximum": 50, "default": 5},
                "project": {"type": "string"},
                "type": {"type": "string", "enum": list(service.notes.TYPES)},
            },
            "required": ["query"],
        },
    },
    {
        "name": "read",
        "description": "Read one note by path (relative to the brain) or exact title.",
        "inputSchema": {"type": "object", "properties": {"note": {"type": "string"}},
                        "required": ["note"]},
    },
    {
        "name": "new_note",
        "description": "Create a note and commit it. Types: " + ", ".join(service.notes.TYPES)
                       + ". 'session' and 'kern' need a project.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "type": {"type": "string", "enum": list(service.notes.TYPES)},
                "title": {"type": "string"},
                "project": {"type": "string"},
                "body": {"type": "string"},
            },
            "required": ["type", "title"],
        },
    },
    {
        "name": "append",
        "description": "Append Markdown text to an existing note and commit it.",
        "inputSchema": {"type": "object",
                        "properties": {"path": {"type": "string"}, "body": {"type": "string"}},
                        "required": ["path", "body"]},
    },
    {
        "name": "recent",
        "description": "List the most recently changed notes.",
        "inputSchema": {"type": "object",
                        "properties": {"n": {"type": "integer", "minimum": 1, "maximum": 100,
                                             "default": 10}}},
    },
]


def _call(name: str, args: dict) -> str:
    if name == "search":
        res = service.search(args["query"], k=int(args.get("k", 5)),
                             project=args.get("project"), ntype=args.get("type"))
        return json.dumps(res, ensure_ascii=False, indent=1)
    if name == "read":
        path, text = service.read(args["note"])
        return f"<!-- {path} -->\n{text}"
    if name == "new_note":
        res = service.new(args["type"], args["title"], project=args.get("project"),
                          body=args.get("body"))
        return json.dumps(res, ensure_ascii=False)
    if name == "append":
        return json.dumps(service.append(args["path"], args["body"]), ensure_ascii=False)
    if name == "recent":
        return json.dumps(service.recent(int(args.get("n", 10))), ensure_ascii=False, indent=1)
    raise KeyError(name)


def handle(msg: dict, tools: list | None = None, call=None, name: str = "brain") -> dict | None:
    tools = tools if tools is not None else TOOLS
    call = call or _call
    mid = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}
    if mid is None:  # notification
        return None

    def ok(result):
        return {"jsonrpc": "2.0", "id": mid, "result": result}

    def err(code, text):
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": text}}

    if method == "initialize":
        wanted = params.get("protocolVersion")
        version = wanted if wanted in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0]
        return ok({"protocolVersion": version,
                   "capabilities": {"tools": {"listChanged": False}},
                   "serverInfo": {"name": name, "version": __version__}})
    if method == "ping":
        return ok({})
    if method == "tools/list":
        return ok({"tools": tools})
    if method == "tools/call":
        tool = params.get("name")
        if tool not in {t["name"] for t in tools}:
            return err(-32602, f"unknown tool: {tool}")
        try:
            text = call(tool, params.get("arguments") or {})
            return ok({"content": [{"type": "text", "text": text}], "isError": False})
        except (*service.UserError, KeyError, ValueError, TypeError) as exc:
            return ok({"content": [{"type": "text", "text": f"error: {exc}"}], "isError": True})
    return err(-32601, f"method not found: {method}")


def serve(stdin=None, stdout=None, tools=None, call=None, name: str = "brain") -> int:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        else:
            try:
                reply = handle(msg, tools, call, name) if isinstance(msg, dict) else None
            except Exception as exc:  # never let one bad call kill the server
                traceback.print_exc(file=sys.stderr)
                reply = {"jsonrpc": "2.0", "id": msg.get("id"),
                         "error": {"code": -32603, "message": str(exc)}}
        if reply is not None:
            stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
            stdout.flush()
    return 0
